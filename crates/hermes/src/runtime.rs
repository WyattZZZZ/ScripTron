use crate::compression::{CompressionDecision, CompressionPolicy};
use crate::prompt::{build_system_prompt, build_user_prompt, PromptContext};
use crate::provider::ModelProvider;
use crate::tools::ToolRegistry;
use crate::types::{ContentBlock, HermesError, Message, RunEvent, RunRequest};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub max_turns: usize,
    pub max_tokens: u32,
    pub compression: CompressionPolicy,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            max_turns: 30,
            max_tokens: 4096,
            compression: CompressionPolicy::default(),
        }
    }
}

pub struct HermesRuntime {
    provider: Arc<dyn ModelProvider>,
    tools: ToolRegistry,
    config: RuntimeConfig,
}

impl HermesRuntime {
    pub fn new(provider: Arc<dyn ModelProvider>, tools: ToolRegistry) -> Self {
        Self {
            provider,
            tools,
            config: RuntimeConfig::default(),
        }
    }

    pub fn with_config(mut self, config: RuntimeConfig) -> Self {
        self.config = config;
        self
    }

    pub async fn run(&self, request: RunRequest) -> Result<Vec<RunEvent>, HermesError> {
        if request.instructions.is_empty() {
            return Err(HermesError::NoInstructions);
        }

        let tool_definitions = self.tools.definitions();
        let system = build_system_prompt(&PromptContext {
            project_path: request
                .project_path
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned()),
            memory: request.memory.clone(),
            tools: tool_definitions.clone(),
        });
        let user_prompt =
            build_user_prompt(&request.instructions, &request.context, &request.blackboard);
        let mut messages = vec![Message::user_text(user_prompt)];
        let mut events = vec![RunEvent::Started];

        for turn in 1..=self.config.max_turns {
            messages = self.maybe_compress(messages, &mut events);
            let response = self
                .provider
                .complete(
                    &system,
                    &messages,
                    &tool_definitions,
                    self.config.max_tokens,
                )
                .await?;

            let mut tool_results = Vec::new();
            let mut tool_calls = Vec::new();
            let mut response_text = Vec::new();

            for block in &response.content {
                match block {
                    ContentBlock::Text { text } => {
                        if !text.trim().is_empty() {
                            events.push(RunEvent::Thinking {
                                content: text.clone(),
                            });
                            response_text.push(text.clone());
                        }
                    }
                    ContentBlock::ToolUse { .. } => {
                        if let Some(call) = block.as_tool_call() {
                            events.push(RunEvent::ToolCall {
                                tool: call.name.clone(),
                                args: call.input.clone(),
                            });
                            tool_calls.push(call);
                        }
                    }
                    ContentBlock::ToolResult { .. } => {}
                }
            }

            messages.push(Message::assistant(response.content));

            for call in tool_calls {
                let output = self.tools.execute(call).await;
                events.push(RunEvent::ToolResult {
                    tool: output.tool_name.clone(),
                    output: output.output.clone(),
                    success: output.success,
                });
                tool_results.push(output.into_content_block());
            }

            if tool_results.is_empty() {
                let final_text = response_text.join("\n\n");
                if !final_text.trim().is_empty() {
                    events.push(RunEvent::Text {
                        content: final_text,
                    });
                }
                events.push(RunEvent::Complete);
                return Ok(events);
            }

            messages.push(Message::user_tool_results(tool_results));

            if turn == self.config.max_turns {
                events.push(RunEvent::Error {
                    message: format!("Exceeded maximum turns ({turn}). Stopping."),
                });
                events.push(RunEvent::Complete);
                return Ok(events);
            }
        }

        events.push(RunEvent::Complete);
        Ok(events)
    }

    fn maybe_compress(&self, messages: Vec<Message>, events: &mut Vec<RunEvent>) -> Vec<Message> {
        match self.config.compression.evaluate(&messages) {
            CompressionDecision::Keep => messages,
            CompressionDecision::Compress { summary, retained } => {
                events.push(RunEvent::Warning {
                    message: summary.clone(),
                });
                let mut compressed = vec![Message::user_text(summary)];
                compressed.extend(retained);
                compressed
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::{MockProvider, ModelResponse};
    use crate::tools::{object_tool, output_for, StaticTool};
    use crate::types::ToolCall;

    fn request(instruction: &str) -> RunRequest {
        RunRequest {
            instructions: vec![instruction.into()],
            context: Vec::new(),
            blackboard: serde_json::json!({}),
            project_path: None,
            memory: None,
        }
    }

    #[tokio::test]
    async fn runtime_returns_final_text_without_tools() {
        let provider = Arc::new(MockProvider::new([ModelResponse::text("done")]));
        let runtime = HermesRuntime::new(provider, ToolRegistry::new());

        let events = runtime.run(request("say done")).await.unwrap();

        assert_eq!(events.first(), Some(&RunEvent::Started));
        assert!(events.contains(&RunEvent::Thinking {
            content: "done".into()
        }));
        assert!(events.contains(&RunEvent::Text {
            content: "done".into()
        }));
        assert_eq!(events.last(), Some(&RunEvent::Complete));
    }

    #[tokio::test]
    async fn runtime_feeds_tool_result_back_to_model() {
        let provider = Arc::new(MockProvider::new([
            ModelResponse {
                content: vec![ContentBlock::ToolUse {
                    id: "call-1".into(),
                    name: "echo".into(),
                    input: serde_json::json!({ "message": "hi" }),
                }],
                stop_reason: "tool_use".into(),
            },
            ModelResponse::text("saw tool result"),
        ]));
        let mut registry = ToolRegistry::new();
        registry.register_fn(
            object_tool("echo", "Echo message"),
            |call: ToolCall| async move { Ok(output_for(&call, "hello from tool", true)) },
        );
        let runtime = HermesRuntime::new(provider.clone(), registry);

        let events = runtime.run(request("call echo")).await.unwrap();

        assert!(events.contains(&RunEvent::ToolCall {
            tool: "echo".into(),
            args: serde_json::json!({ "message": "hi" })
        }));
        assert!(events.contains(&RunEvent::ToolResult {
            tool: "echo".into(),
            output: "hello from tool".into(),
            success: true,
        }));

        let calls = provider.calls();
        assert_eq!(calls.len(), 2);
        assert!(matches!(
            calls[1].messages.last().unwrap().content[0],
            ContentBlock::ToolResult { .. }
        ));
    }

    #[tokio::test]
    async fn runtime_merges_registered_tool_definitions_into_provider_call() {
        let provider = Arc::new(MockProvider::new([ModelResponse::text("done")]));
        let mut registry = ToolRegistry::new();
        registry.register(StaticTool::new("echo", "hello"));
        let runtime = HermesRuntime::new(provider.clone(), registry);

        runtime.run(request("hello")).await.unwrap();

        let calls = provider.calls();
        assert_eq!(calls[0].tools.len(), 1);
        assert_eq!(calls[0].tools[0].name, "echo");
    }

    #[tokio::test]
    async fn runtime_reports_max_turns_as_event() {
        let provider = Arc::new(MockProvider::new([ModelResponse {
            content: vec![ContentBlock::ToolUse {
                id: "call-1".into(),
                name: "mock".into(),
                input: serde_json::json!({}),
            }],
            stop_reason: "tool_use".into(),
        }]));
        let mut registry = ToolRegistry::new();
        registry.register(StaticTool::new("mock", "ok"));
        let runtime = HermesRuntime::new(provider, registry).with_config(RuntimeConfig {
            max_turns: 1,
            ..RuntimeConfig::default()
        });

        let events = runtime.run(request("loop")).await.unwrap();

        assert!(matches!(
            events.as_slice(),
            [
                RunEvent::Started,
                RunEvent::ToolCall { .. },
                RunEvent::ToolResult { .. },
                RunEvent::Error { message },
                RunEvent::Complete,
            ] if message.contains("Exceeded maximum turns (1)")
        ));
    }

    #[tokio::test]
    async fn runtime_rejects_empty_instructions() {
        let runtime = HermesRuntime::new(
            Arc::new(MockProvider::new([ModelResponse::text("never")])),
            ToolRegistry::new(),
        );

        let error = runtime
            .run(RunRequest {
                instructions: Vec::new(),
                context: Vec::new(),
                blackboard: serde_json::json!({}),
                project_path: None,
                memory: None,
            })
            .await
            .unwrap_err();

        assert!(matches!(error, HermesError::NoInstructions));
    }

    #[tokio::test]
    async fn unknown_tool_result_is_fed_back_as_error() {
        let provider = Arc::new(MockProvider::new([
            ModelResponse {
                content: vec![ContentBlock::ToolUse {
                    id: "call-1".into(),
                    name: "missing".into(),
                    input: serde_json::json!({}),
                }],
                stop_reason: "tool_use".into(),
            },
            ModelResponse::text("handled missing tool"),
        ]));
        let runtime = HermesRuntime::new(provider.clone(), ToolRegistry::new());

        let events = runtime.run(request("call missing")).await.unwrap();

        assert!(events.contains(&RunEvent::ToolResult {
            tool: "missing".into(),
            output: "Error: unknown tool 'missing'".into(),
            success: false,
        }));
        assert!(matches!(
            provider.calls()[1].messages.last().unwrap().content[0],
            ContentBlock::ToolResult { is_error: true, .. }
        ));
    }
}
