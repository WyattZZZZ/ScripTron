mod builtin_tools;
mod llm;

pub use llm::{
    AnthropicProvider, CliModelProvider, GeminiProvider, LlmProvider, OpenAiCompatProvider,
};

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
    ToolCall {
        tool: String,
        args: serde_json::Value,
    },
    /// Result of a tool call.
    ToolResult {
        tool: String,
        output: String,
        success: bool,
    },
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

        // Combine run:true cells, static document context, and blackboard into one user turn.
        let mut user_sections = Vec::new();
        if !task.context.is_empty() {
            user_sections.push(format!(
                "Document context from non-run markdown:\n{}",
                task.context.join("\n\n---\n\n")
            ));
        }
        if !task.blackboard.is_null()
            && !(task.blackboard.is_object()
                && task
                    .blackboard
                    .as_object()
                    .map(|o| o.is_empty())
                    .unwrap_or(false))
        {
            user_sections.push(format!(
                "Hidden .tron blackboard state:\n{}",
                serde_json::to_string_pretty(&task.blackboard).unwrap_or_else(|_| "{}".into())
            ));
        }
        user_sections.push(format!(
            "Run instructions:\n{}",
            task.instructions.join("\n\n---\n\n")
        ));
        let user_content = user_sections.join("\n\n====\n\n");

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
            "create_file" => builtin_tools::write_file(input, project_path).await,
            "mkdir" => builtin_tools::create_dir(input, project_path).await,
            "delete_path" => builtin_tools::delete_path(input, project_path).await,
            "move_path" => builtin_tools::move_path(input, project_path).await,
            "exec" => builtin_tools::run_command(input, project_path, &self.runner).await,
            "run_command" => builtin_tools::run_command(input, project_path, &self.runner).await,
            "codex" => builtin_tools::run_codex(input, project_path, &self.runner).await,
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
        r#"You are Troner, the built-in autonomous agent assistant inside ScripTron.
ScripTron is a local-first automation studio, and you run inside the user's app with access to project files, installed skills, registered CLI tools, and local terminal execution.

Your purpose:
- Understand the user's real goal, not just the literal phrasing.
- Plan and complete the task with the tools available to you.
- Read relevant files, skills, manifests, and project context before making non-trivial changes.
- Use installed skills from the workspace `.skills` directory when they match the task.
- Use registered CLI tools from `.register` when they are more appropriate than raw shell commands.
- Use terminal execution through `exec` / `run_command` when needed, while keeping commands scoped and explainable.
- Prefer completing the task end-to-end over giving generic advice.

Project path: {project}
Workspace skill path: {project}/.skills when present, or the parent workspace `.skills` directory when working inside a project.
Workspace CLI registry: {project}/.register when present, or the parent workspace `.register` directory when working inside a project.

Rules:
- Work entirely within the project path unless explicitly instructed otherwise.
- Prefer reading before writing — verify the current state of files first.
- After each tool call, check the result before proceeding.
- If a step fails, report the error clearly and stop unless you can safely recover.
- Before using a skill, inspect its files enough to understand its expected workflow.
- Before using a registered CLI, inspect its manifest or the registry prompt block and pass arguments according to its schema.
- Do not invent installed capabilities. If a skill or CLI is missing, say what is missing and use the best available fallback.
- Do not claim you performed an action unless a tool result confirms it.
- Be concise in visible reasoning and focus on action, evidence, and outcome.

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
        serde_json::json!({
            "name": "exec",
            "description": "Run a shell command in the project directory. Alias for run_command.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "args": {"type": "array", "items": {"type": "string"}},
                    "working_dir": {"type": "string"}
                },
                "required": ["command", "args"]
            }
        }),
        serde_json::json!({
            "name": "mkdir",
            "description": "Create a directory relative to the project directory.",
            "input_schema": {
                "type": "object",
                "properties": {"path": {"type": "string"}},
                "required": ["path"]
            }
        }),
        serde_json::json!({
            "name": "delete_path",
            "description": "Delete a file or directory relative to the project directory.",
            "input_schema": {
                "type": "object",
                "properties": {"path": {"type": "string"}},
                "required": ["path"]
            }
        }),
        serde_json::json!({
            "name": "move_path",
            "description": "Move or rename a file/directory relative to the project directory.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "from": {"type": "string"},
                    "to": {"type": "string"}
                },
                "required": ["from", "to"]
            }
        }),
        serde_json::json!({
            "name": "codex",
            "description": "Delegate a bounded project task to Codex CLI in non-interactive mode.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "prompt": {"type": "string"},
                    "timeout_secs": {"type": "number"}
                },
                "required": ["prompt"]
            }
        }),
    ];

    // Add run_cli_tool only when tools are installed
    if !registry.list_tools().is_empty() {
        let tool_names: Vec<&str> = registry
            .list_tools()
            .iter()
            .map(|t| t.name.as_str())
            .collect();
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
