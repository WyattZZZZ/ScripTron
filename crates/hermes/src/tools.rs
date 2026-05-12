use crate::types::{HermesError, ToolCall, ToolDefinition, ToolOutput};
use async_trait::async_trait;
use serde_json::Value;
use std::collections::BTreeMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

type ToolFuture = Pin<Box<dyn Future<Output = Result<ToolOutput, HermesError>> + Send>>;
type BoxedToolFn = Arc<dyn Fn(ToolCall) -> ToolFuture + Send + Sync>;

#[async_trait]
pub trait ToolExecutor: Send + Sync {
    fn definition(&self) -> ToolDefinition;

    async fn execute(&self, call: ToolCall) -> Result<ToolOutput, HermesError>;
}

#[derive(Clone, Default)]
pub struct ToolRegistry {
    tools: BTreeMap<String, Arc<dyn ToolExecutor>>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register<E>(&mut self, executor: E)
    where
        E: ToolExecutor + 'static,
    {
        let definition = executor.definition();
        self.tools.insert(definition.name, Arc::new(executor));
    }

    pub fn register_arc(&mut self, executor: Arc<dyn ToolExecutor>) {
        let definition = executor.definition();
        self.tools.insert(definition.name, executor);
    }

    pub fn register_fn<F, Fut>(&mut self, definition: ToolDefinition, handler: F)
    where
        F: Fn(ToolCall) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<ToolOutput, HermesError>> + Send + 'static,
    {
        self.register(FunctionToolExecutor::new(definition, handler));
    }

    pub fn definitions(&self) -> Vec<ToolDefinition> {
        self.tools
            .values()
            .map(|executor| executor.definition())
            .collect()
    }

    pub async fn execute(&self, call: ToolCall) -> ToolOutput {
        let Some(executor) = self.tools.get(&call.name).cloned() else {
            return ToolOutput {
                tool_call_id: call.id,
                tool_name: call.name.clone(),
                output: format!("Error: unknown tool '{}'", call.name),
                success: false,
            };
        };

        match executor.execute(call.clone()).await {
            Ok(output) => output,
            Err(error) => ToolOutput {
                tool_call_id: call.id,
                tool_name: call.name,
                output: format!("Error: {error}"),
                success: false,
            },
        }
    }

    pub fn is_empty(&self) -> bool {
        self.tools.is_empty()
    }
}

pub struct FunctionToolExecutor {
    definition: ToolDefinition,
    handler: BoxedToolFn,
}

impl FunctionToolExecutor {
    pub fn new<F, Fut>(definition: ToolDefinition, handler: F) -> Self
    where
        F: Fn(ToolCall) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<ToolOutput, HermesError>> + Send + 'static,
    {
        Self {
            definition,
            handler: Arc::new(move |call| Box::pin(handler(call))),
        }
    }
}

#[async_trait]
impl ToolExecutor for FunctionToolExecutor {
    fn definition(&self) -> ToolDefinition {
        self.definition.clone()
    }

    async fn execute(&self, call: ToolCall) -> Result<ToolOutput, HermesError> {
        (self.handler)(call).await
    }
}

#[derive(Clone)]
pub struct MockToolExecutor {
    definition: ToolDefinition,
    output: String,
    success: bool,
}

impl MockToolExecutor {
    pub fn new(name: impl Into<String>, output: impl Into<String>) -> Self {
        let name = name.into();
        Self {
            definition: object_tool(name.clone(), format!("Mock executor for {name}.")),
            output: output.into(),
            success: true,
        }
    }

    pub fn failing(name: impl Into<String>, output: impl Into<String>) -> Self {
        Self {
            success: false,
            ..Self::new(name, output)
        }
    }
}

#[async_trait]
impl ToolExecutor for MockToolExecutor {
    fn definition(&self) -> ToolDefinition {
        self.definition.clone()
    }

    async fn execute(&self, call: ToolCall) -> Result<ToolOutput, HermesError> {
        Ok(ToolOutput {
            tool_call_id: call.id,
            tool_name: call.name,
            output: self.output.clone(),
            success: self.success,
        })
    }
}

pub type StaticTool = MockToolExecutor;

pub fn object_tool(name: impl Into<String>, description: impl Into<String>) -> ToolDefinition {
    ToolDefinition {
        name: name.into(),
        description: description.into(),
        input_schema: serde_json::json!({ "type": "object" }),
    }
}

pub fn output_for(call: &ToolCall, output: impl Into<String>, success: bool) -> ToolOutput {
    ToolOutput {
        tool_call_id: call.id.clone(),
        tool_name: call.name.clone(),
        output: output.into(),
        success,
    }
}

pub fn string_arg(input: &Value, name: &str) -> Option<String> {
    input
        .get(name)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn registry_executes_registered_tool() {
        let mut registry = ToolRegistry::new();
        registry.register(StaticTool::new("echo", "hello"));

        let output = registry
            .execute(ToolCall {
                id: "call-1".into(),
                name: "echo".into(),
                input: serde_json::json!({}),
            })
            .await;

        assert!(output.success);
        assert_eq!(output.output, "hello");
        assert_eq!(output.tool_name, "echo");
        assert_eq!(registry.definitions()[0].name, "echo");
    }

    #[tokio::test]
    async fn registry_executes_function_tool() {
        let mut registry = ToolRegistry::new();
        registry.register_fn(object_tool("echo", "Echo message"), |call| async move {
            Ok(output_for(
                &call,
                string_arg(&call.input, "message").unwrap_or_default(),
                true,
            ))
        });

        let output = registry
            .execute(ToolCall {
                id: "call-1".into(),
                name: "echo".into(),
                input: serde_json::json!({ "message": "hi" }),
            })
            .await;

        assert_eq!(output.output, "hi");
        assert!(output.success);
    }

    #[tokio::test]
    async fn registry_wraps_unknown_tool_as_failed_output() {
        let output = ToolRegistry::new()
            .execute(ToolCall {
                id: "call-1".into(),
                name: "missing".into(),
                input: serde_json::json!({}),
            })
            .await;

        assert!(!output.success);
        assert_eq!(output.tool_name, "missing");
        assert!(output.output.contains("unknown tool"));
    }
}
