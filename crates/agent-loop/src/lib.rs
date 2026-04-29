mod builtin_tools;
mod llm;

pub use llm::{AnthropicProvider, GeminiProvider, OpenAiCompatProvider, LlmProvider};

use cli_registry::CliRegistry;
use process_runner::{ProcessConfig, ProcessRunner};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::mpsc;
use tron_parser::TronTask;

// ── Errors ────────────────────────────────────────────────────────────────────

#[derive(Debug, Error)]
pub enum AgentError {
    #[error("LLM error: {0}")]
    Llm(String),
    #[error("Tool execution error: {0}")]
    ToolExec(String),
    #[error("No instructions to run")]
    NoInstructions,
    #[error("Serialisation error: {0}")]
    Serde(#[from] serde_json::Error),
}

// ── Execution events streamed to the UI ───────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ExecutionEvent {
    /// The model is reasoning / generating text.
    Thinking { content: String },
    /// The model requested a tool call.
    ToolCall { tool: String, args: serde_json::Value },
    /// Result of a tool call.
    ToolResult { tool: String, output: String, success: bool },
    /// Final answer text from the model.
    Text { content: String },
    /// A non-fatal warning.
    Warning { message: String },
    /// Fatal error — loop aborted.
    Error { message: String },
    /// All cells have been processed.
    Complete,
}

// ── Agent loop ────────────────────────────────────────────────────────────────

pub struct AgentLoop {
    provider: Arc<dyn LlmProvider + Send + Sync>,
    registry: Arc<tokio::sync::RwLock<CliRegistry>>,
    runner: ProcessRunner,
}

impl AgentLoop {
    pub fn new(
        provider: Arc<dyn LlmProvider + Send + Sync>,
        registry: Arc<tokio::sync::RwLock<CliRegistry>>,
    ) -> Self {
        Self {
            provider,
            registry,
            runner: ProcessRunner::new(),
        }
    }

    /// Execute a full `TronTask`, streaming `ExecutionEvent`s via `tx`.
    pub async fn run(
        &self,
        task: TronTask,
        tx: mpsc::Sender<ExecutionEvent>,
    ) -> Result<(), AgentError> {
        if task.instructions.is_empty() {
            return Err(AgentError::NoInstructions);
        }

        let registry = self.registry.read().await;
        let system = build_system_prompt(&registry, &task.project_path);
        let tools = build_tools(&registry);
        drop(registry);

        // Combine all run:true cells into a single user turn
        let user_content = task.instructions.join("\n\n---\n\n");

        // Conversation history
        let mut messages: Vec<llm::ChatMessage> = vec![llm::ChatMessage {
            role: "user".into(),
            content: serde_json::json!([{"type": "text", "text": user_content}]),
        }];

        const MAX_TURNS: usize = 30;
        let mut turn = 0;

        loop {
            turn += 1;
            if turn > MAX_TURNS {
                let _ = tx
                    .send(ExecutionEvent::Error {
                        message: "Exceeded maximum turns (30). Stopping.".into(),
                    })
                    .await;
                break;
            }

            let response = self
                .provider
                .complete(&system, &messages, &tools, 4096)
                .await
                .map_err(|e| AgentError::Llm(e))?;

            // Emit text blocks as Thinking / Text events
            let mut has_tool_use = false;
            let mut tool_results: Vec<serde_json::Value> = Vec::new();

            for block in &response.content {
                let block_type = block["type"].as_str().unwrap_or("");
                match block_type {
                    "text" => {
                        let text = block["text"].as_str().unwrap_or("").to_string();
                        if !text.trim().is_empty() {
                            let _ = tx.send(ExecutionEvent::Thinking { content: text }).await;
                        }
                    }
                    "tool_use" => {
                        has_tool_use = true;
                        let tool_name = block["name"].as_str().unwrap_or("").to_string();
                        let tool_id = block["id"].as_str().unwrap_or("").to_string();
                        let input = block["input"].clone();

                        let _ = tx
                            .send(ExecutionEvent::ToolCall {
                                tool: tool_name.clone(),
                                args: input.clone(),
                            })
                            .await;

                        let output = self
                            .dispatch_tool(&tool_name, &input, &task.project_path)
                            .await;

                        let success = !output.starts_with("Error:");
                        let _ = tx
                            .send(ExecutionEvent::ToolResult {
                                tool: tool_name.clone(),
                                output: output.clone(),
                                success,
                            })
                            .await;

                        tool_results.push(serde_json::json!({
                            "type": "tool_result",
                            "tool_use_id": tool_id,
                            "content": output,
                        }));
                    }
                    _ => {}
                }
            }

            // Append the assistant turn to history
            messages.push(llm::ChatMessage {
                role: "assistant".into(),
                content: serde_json::Value::Array(response.content.clone()),
            });

            if has_tool_use && !tool_results.is_empty() {
                // Feed tool results back and continue
                messages.push(llm::ChatMessage {
                    role: "user".into(),
                    content: serde_json::Value::Array(tool_results),
                });
            } else {
                // No tool use → we're done
                // Emit any remaining text as the final answer
                for block in &response.content {
                    if block["type"] == "text" {
                        let text = block["text"].as_str().unwrap_or("").to_string();
                        if !text.trim().is_empty() {
                            let _ = tx.send(ExecutionEvent::Text { content: text }).await;
                        }
                    }
                }
                break;
            }
        }

        let _ = tx.send(ExecutionEvent::Complete).await;
        Ok(())
    }

    async fn dispatch_tool(
        &self,
        name: &str,
        input: &serde_json::Value,
        project_path: &PathBuf,
    ) -> String {
        match name {
            "list_files" => builtin_tools::list_files(input, project_path).await,
            "read_file" => builtin_tools::read_file(input, project_path).await,
            "write_file" => builtin_tools::write_file(input, project_path).await,
            "run_command" => {
                builtin_tools::run_command(input, project_path, &self.runner).await
            }
            "run_cli_tool" => {
                let registry = self.registry.read().await;
                self.run_cli_tool(input, project_path, &registry).await
            }
            _ => format!("Error: unknown tool '{}'", name),
        }
    }

    async fn run_cli_tool(
        &self,
        input: &serde_json::Value,
        project_path: &PathBuf,
        registry: &CliRegistry,
    ) -> String {
        let tool_name = match input["tool"].as_str() {
            Some(n) => n,
            None => return "Error: 'tool' field is required".into(),
        };
        let manifest = match registry.get_tool(tool_name) {
            Some(m) => m.clone(),
            None => return format!("Error: CLI tool '{}' is not installed", tool_name),
        };

        let args: Vec<String> = input["args"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();

        let working_dir = input["working_dir"]
            .as_str()
            .map(PathBuf::from)
            .unwrap_or_else(|| project_path.clone());

        let cfg = ProcessConfig::new(manifest.command, args).with_working_dir(working_dir);

        match self.runner.run(cfg).await {
            Ok(result) => result.combined_output(),
            Err(e) => format!("Error: {}", e),
        }
    }
}

// ── Prompt + tool schema builders ─────────────────────────────────────────────

fn build_system_prompt(registry: &CliRegistry, project_path: &PathBuf) -> String {
    format!(
        r#"You are ScripTron, an automation agent running on the user's local machine.
You execute tasks described in natural language using the tools available to you.

Project path: {project}

Rules:
- Work entirely within the project path unless explicitly instructed otherwise.
- Prefer reading before writing — verify the current state of files first.
- After each tool call, check the result before proceeding.
- If a step fails, report the error clearly and stop unless you can safely recover.
- Be concise in your reasoning — focus on action.

{tools_section}"#,
        project = project_path.display(),
        tools_section = registry.to_system_prompt_section(),
    )
}

fn build_tools(registry: &CliRegistry) -> Vec<serde_json::Value> {
    let mut tools = vec![
        serde_json::json!({
            "name": "list_files",
            "description": "List files and directories at a path relative to the project directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative path to list (use '.' for the project root)."
                    }
                },
                "required": ["path"]
            }
        }),
        serde_json::json!({
            "name": "read_file",
            "description": "Read the contents of a file at a path relative to the project directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative path to the file."
                    }
                },
                "required": ["path"]
            }
        }),
        serde_json::json!({
            "name": "write_file",
            "description": "Write content to a file at a path relative to the project directory. Creates the file if it does not exist.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Relative path to the file."
                    },
                    "content": {
                        "type": "string",
                        "description": "Content to write."
                    }
                },
                "required": ["path", "content"]
            }
        }),
        serde_json::json!({
            "name": "run_command",
            "description": "Run an arbitrary shell command. Use sparingly and only when no CLI tool covers the need.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "The executable to run."},
                    "args": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Arguments to pass."
                    },
                    "working_dir": {
                        "type": "string",
                        "description": "Optional working directory (relative to project path)."
                    }
                },
                "required": ["command", "args"]
            }
        }),
    ];

    // Add run_cli_tool only when tools are installed
    if !registry.list_tools().is_empty() {
        let tool_names: Vec<&str> = registry.list_tools().iter().map(|t| t.name.as_str()).collect();
        tools.push(serde_json::json!({
            "name": "run_cli_tool",
            "description": format!(
                "Run an installed CLI tool. Available tools: {}.",
                tool_names.join(", ")
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "tool": {
                        "type": "string",
                        "description": "Name of the CLI tool to run."
                    },
                    "args": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Arguments to pass to the tool."
                    },
                    "working_dir": {
                        "type": "string",
                        "description": "Optional working directory relative to project path."
                    }
                },
                "required": ["tool", "args"]
            }
        }));
    }

    tools
}
