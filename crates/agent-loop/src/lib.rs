mod builtin_tools;
mod llm;

pub use llm::{
    AnthropicProvider, CliModelProvider, GeminiProvider, LlmProvider, OpenAiCompatProvider,
};

use cli_registry::CliRegistry;
use process_runner::{ProcessConfig, ProcessRunner};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
};
use thiserror::Error;
use tokio::sync::mpsc;
use tokio::time::{sleep, Duration};
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
    /// Planner output before execution begins.
    Plan { content: String },
    /// The executor is starting a concrete tool step.
    StepStarted {
        step_id: String,
        tool: String,
        args: serde_json::Value,
    },
    /// A failed step is being retried with a model-selected strategy.
    StepRetried {
        step_id: String,
        tool: String,
        attempt: u32,
        decision: String,
        reason: String,
    },
    /// A concrete tool step completed.
    StepCompleted {
        step_id: String,
        tool: String,
        output: String,
    },
    /// A concrete tool step failed after retry handling.
    StepFailed {
        step_id: String,
        tool: String,
        error: String,
    },
    /// Skills selected as likely relevant for the current task.
    SkillSelected { skills: Vec<String> },
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RetryDecision {
    decision: String,
    reason: String,
    #[serde(default)]
    delay_ms: Option<u64>,
    #[serde(default)]
    patched_args: Option<serde_json::Value>,
    #[serde(default)]
    patched_prompt: Option<String>,
    #[serde(default)]
    confidence: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SkillCard {
    name: String,
    description: String,
    path: String,
    #[serde(default)]
    required_clis: Vec<String>,
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    document: String,
    #[serde(default)]
    tokens: Vec<String>,
    #[serde(default)]
    score: f64,
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
        let tools = build_tools(&registry);
        let skill_cards = recall_skill_cards(&task.project_path, &task).await;
        let planner_system =
            build_planner_system_prompt(&registry, &task.project_path, &tools, &skill_cards);
        let executor_system =
            build_executor_system_prompt(&registry, &task.project_path, &tools, &skill_cards);
        drop(registry);
        if !skill_cards.is_empty() {
            let _ = tx
                .send(ExecutionEvent::SkillSelected {
                    skills: skill_cards.iter().map(|skill| skill.name.clone()).collect(),
                })
                .await;
        }

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

        // Phase 1: planner. The planner receives the full first-step context and the
        // full deterministic tool inventory, but it does not receive callable tools.
        let planner_messages: Vec<llm::ChatMessage> = vec![llm::ChatMessage {
            role: "user".into(),
            content: serde_json::json!([{"type": "text", "text": user_content}]),
        }];

        let plan_response = self
            .provider
            .complete(&planner_system, &planner_messages, &[], 512)
            .await
            .map_err(|e| AgentError::Llm(e))?;
        let plan = response_text(&plan_response.content);
        let mut execution_trace = Vec::<String>::new();
        if !plan.trim().is_empty() {
            execution_trace.push(format!("Plan:\n{}", plan.trim()));
            let _ = tx
                .send(ExecutionEvent::Plan {
                    content: plan.clone(),
                })
                .await;
        }

        // Phase 2: executor. The executor receives the plan, the original context,
        // and the callable tools.
        let executor_user_content = format!(
            "Execution plan from planner:\n{}\n\n====\n\nOriginal request and context:\n{}",
            if plan.trim().is_empty() {
                "(Planner returned no explicit plan. Execute directly.)"
            } else {
                plan.trim()
            },
            user_content
        );
        let mut messages: Vec<llm::ChatMessage> = vec![llm::ChatMessage {
            role: "user".into(),
            content: serde_json::json!([{"type": "text", "text": executor_user_content}]),
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
                .complete(&executor_system, &messages, &tools, 4096)
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
                        execution_trace.push(format!(
                            "Tool call: {}\nArgs: {}",
                            tool_name,
                            compact_json(&input)
                        ));

                        let output = self
                            .dispatch_tool_with_retry(
                                &tool_name,
                                &input,
                                &task.project_path,
                                &executor_system,
                                &tools,
                                &messages,
                                &tx,
                            )
                            .await;

                        let success = !output.starts_with("Error:");
                        execution_trace.push(format!(
                            "Tool result: {}\nSuccess: {}\nOutput:\n{}",
                            tool_name, success, output
                        ));
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
                let executor_text = response_text(&response.content);
                if !executor_text.trim().is_empty() {
                    execution_trace.push(format!("Executor final text:\n{}", executor_text.trim()));
                }
                let final_text = self
                    .synthesize_final_response(
                        &task,
                        &plan,
                        &user_content,
                        &execution_trace,
                        &executor_text,
                    )
                    .await
                    .unwrap_or_else(|_| concise_fallback_response(&executor_text));
                if !final_text.trim().is_empty() {
                    let _ = tx
                        .send(ExecutionEvent::Text {
                            content: final_text,
                        })
                        .await;
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
            "run_cli_tool" => {
                let registry = self.registry.read().await;
                self.run_cli_tool(input, project_path, &registry).await
            }
            _ => format!("Error: unknown tool '{}'", name),
        }
    }

    async fn dispatch_tool_with_retry(
        &self,
        name: &str,
        input: &serde_json::Value,
        project_path: &PathBuf,
        system: &str,
        tools: &[serde_json::Value],
        messages: &[llm::ChatMessage],
        tx: &mpsc::Sender<ExecutionEvent>,
    ) -> String {
        const MAX_RETRIES: u32 = 3;
        let step_id = format!("{}-{}", safe_step_name(name), chrono_like_millis());
        let mut attempt = 0u32;
        let mut current_input = input.clone();

        loop {
            attempt += 1;
            let _ = tx
                .send(ExecutionEvent::StepStarted {
                    step_id: step_id.clone(),
                    tool: name.to_string(),
                    args: current_input.clone(),
                })
                .await;

            let output = self.dispatch_tool(name, &current_input, project_path).await;
            let success = !output.starts_with("Error:");
            if success {
                let _ = tx
                    .send(ExecutionEvent::StepCompleted {
                        step_id,
                        tool: name.to_string(),
                        output: output.clone(),
                    })
                    .await;
                return output;
            }

            if attempt > MAX_RETRIES {
                let _ = tx
                    .send(ExecutionEvent::StepFailed {
                        step_id,
                        tool: name.to_string(),
                        error: output.clone(),
                    })
                    .await;
                return output;
            }

            let decision = self
                .plan_retry(
                    name,
                    &current_input,
                    &output,
                    attempt,
                    system,
                    tools,
                    messages,
                )
                .await;

            match decision.decision.as_str() {
                "modify_and_retry" => {
                    let _ = tx
                        .send(ExecutionEvent::StepRetried {
                            step_id: step_id.clone(),
                            tool: name.to_string(),
                            attempt,
                            decision: decision.decision.clone(),
                            reason: decision.reason.clone(),
                        })
                        .await;
                    current_input = decision
                        .patched_args
                        .filter(|value| value.is_object())
                        .unwrap_or(current_input);
                }
                "wait_and_retry" => {
                    let _ = tx
                        .send(ExecutionEvent::StepRetried {
                            step_id: step_id.clone(),
                            tool: name.to_string(),
                            attempt,
                            decision: decision.decision.clone(),
                            reason: decision.reason.clone(),
                        })
                        .await;
                    let delay_ms = decision.delay_ms.unwrap_or(5000).clamp(0, 30000);
                    sleep(Duration::from_millis(delay_ms)).await;
                }
                _ => {
                    let _ = tx
                        .send(ExecutionEvent::StepFailed {
                            step_id,
                            tool: name.to_string(),
                            error: format!("{}\n\nRetry decision: {}", output, decision.reason),
                        })
                        .await;
                    return output;
                }
            }
        }
    }

    async fn plan_retry(
        &self,
        tool: &str,
        args: &serde_json::Value,
        error: &str,
        attempt: u32,
        system: &str,
        tools: &[serde_json::Value],
        messages: &[llm::ChatMessage],
    ) -> RetryDecision {
        let retry_system = format!(
            r#"You are Troner's retry planner.
Choose one retry strategy for a failed tool call.

Allowed decisions:
- no_retry
- modify_and_retry
- wait_and_retry

Rules:
- Return only JSON.
- Use no_retry when the failure is permanent or needs user input.
- Use modify_and_retry when arguments can be corrected.
- Use wait_and_retry for temporary lock, network, rate-limit, or timing failures.
- At most 3 retry attempts are allowed by runtime.

Executor system context:
{system}

Available tools:
{tools}"#,
            tools = format_tool_inventory(tools)
        );

        let prompt = serde_json::json!({
            "tool": tool,
            "attempt": attempt,
            "args": args,
            "error": error,
            "recent_messages": messages.iter().rev().take(4).collect::<Vec<_>>(),
            "required_output_schema": {
                "decision": "no_retry | modify_and_retry | wait_and_retry",
                "reason": "short explanation",
                "delay_ms": 5000,
                "patched_args": {},
                "patched_prompt": "",
                "confidence": 0.0
            }
        });

        let retry_messages = vec![llm::ChatMessage {
            role: "user".into(),
            content: serde_json::json!([{"type": "text", "text": prompt.to_string()}]),
        }];

        let response = match self
            .provider
            .complete(&retry_system, &retry_messages, &[], 512)
            .await
        {
            Ok(response) => response,
            Err(error) => {
                return RetryDecision {
                    decision: "no_retry".into(),
                    reason: format!("Retry planner failed: {error}"),
                    delay_ms: None,
                    patched_args: None,
                    patched_prompt: None,
                    confidence: Some(0.0),
                };
            }
        };

        parse_retry_decision(&response_text(&response.content)).unwrap_or_else(|error| {
            RetryDecision {
                decision: "no_retry".into(),
                reason: format!("Retry planner returned invalid JSON: {error}"),
                delay_ms: None,
                patched_args: None,
                patched_prompt: None,
                confidence: Some(0.0),
            }
        })
    }

    async fn synthesize_final_response(
        &self,
        task: &TronTask,
        plan: &str,
        user_content: &str,
        execution_trace: &[String],
        executor_text: &str,
    ) -> Result<String, String> {
        let system = r#"You are Troner's final response writer.
Write the final user-facing response in concise Markdown.
Do not paste raw command output.
Use the execution trace only as evidence.
If a command listed files, return clean names or a short summary.
If project files were changed, mention the changed paths.
Be brief and fast: prefer 1-6 bullets or one short paragraph."#;
        let prompt = serde_json::json!({
            "run_instructions": task.instructions,
            "blackboard": task.blackboard,
            "planner_output": plan,
            "original_context": user_content,
            "execution_trace": execution_trace,
            "executor_text": executor_text
        });
        let messages = vec![llm::ChatMessage {
            role: "user".into(),
            content: serde_json::json!([{"type": "text", "text": prompt.to_string()}]),
        }];
        let response = self.provider.complete(system, &messages, &[], 768).await?;
        Ok(response_text(&response.content))
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

        let working_dir = match input["working_dir"].as_str() {
            Some(dir) => match project_relative_path(project_path, dir) {
                Some(path) => path,
                None => return "Error: working_dir must stay inside the project directory".into(),
            },
            None => project_path.clone(),
        };

        let cfg = ProcessConfig::new(manifest.command, args)
            .with_working_dir(working_dir)
            .with_env(
                "PATH",
                "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            );

        match self.runner.run(cfg).await {
            Ok(result) => result.combined_output(),
            Err(e) => format!("Error: {}", e),
        }
    }
}

// ── Prompt + tool schema builders ─────────────────────────────────────────────

fn parse_retry_decision(text: &str) -> Result<RetryDecision, String> {
    let trimmed = text.trim();
    let json_text = if trimmed.starts_with('{') {
        trimmed.to_string()
    } else {
        let start = trimmed
            .find('{')
            .ok_or_else(|| "missing JSON object".to_string())?;
        let end = trimmed
            .rfind('}')
            .ok_or_else(|| "missing JSON object end".to_string())?;
        trimmed[start..=end].to_string()
    };
    let mut decision: RetryDecision =
        serde_json::from_str(&json_text).map_err(|e| e.to_string())?;
    decision.decision = match decision.decision.as_str() {
        "modify_and_retry" => "modify_and_retry".into(),
        "wait_and_retry" => "wait_and_retry".into(),
        _ => "no_retry".into(),
    };
    if decision.reason.trim().is_empty() {
        decision.reason = "No retry reason provided.".into();
    }
    Ok(decision)
}

fn concise_fallback_response(text: &str) -> String {
    let compact = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .take(8)
        .collect::<Vec<_>>()
        .join("\n");
    if compact.is_empty() {
        "(completed without a final response)".into()
    } else {
        compact.chars().take(1000).collect()
    }
}

fn compact_json(value: &serde_json::Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".into())
}

async fn recall_skill_cards(project_path: &Path, task: &TronTask) -> Vec<SkillCard> {
    let query = task_query(task);
    let mut cards = Vec::new();
    for dir in skill_dirs(project_path) {
        cards.extend(read_skill_cards_from_dir(&dir, &query));
    }
    cards.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.name.cmp(&b.name))
    });
    cards.truncate(15);
    cards
}

fn skill_dirs(project_path: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![project_path.join(".skills")];
    if let Some(parent) = project_path.parent() {
        dirs.push(parent.join(".skills"));
    }
    dirs.sort();
    dirs.dedup();
    dirs
}

fn read_skill_cards_from_dir(dir: &Path, query: &str) -> Vec<SkillCard> {
    let index_path = dir.join("index.json");
    if let Ok(raw) = std::fs::read_to_string(&index_path) {
        if let Ok(items) = serde_json::from_str::<Vec<SkillCard>>(&raw) {
            return score_skill_cards(items, query);
        }
    }

    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let cards = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .filter_map(|path| read_skill_card(&path))
        .collect::<Vec<_>>();
    score_skill_cards(cards, query)
}

fn read_skill_card(path: &Path) -> Option<SkillCard> {
    let manifest_path = path.join("skill.json");
    let raw = std::fs::read_to_string(&manifest_path).ok()?;
    let json: serde_json::Value = serde_json::from_str(&raw).ok()?;
    let name = json
        .get("name")
        .and_then(|v| v.as_str())
        .or_else(|| path.file_name().and_then(|v| v.to_str()))?
        .to_string();
    let description = json
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let required_clis = json
        .pointer("/requires/clis")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    item.get("name")
                        .and_then(|v| v.as_str())
                        .map(str::to_string)
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let capabilities = json
        .get("capabilities")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let tags = json
        .get("tags")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let document = skill_document(&name, &description, &required_clis, &capabilities, &tags);
    let tokens = tokenize_for_bm25(&document);
    Some(SkillCard {
        name,
        description,
        path: path.to_string_lossy().into_owned(),
        required_clis,
        capabilities,
        tags,
        document,
        tokens,
        score: 0.0,
    })
}

fn task_query(task: &TronTask) -> String {
    task.instructions
        .iter()
        .chain(task.context.iter())
        .cloned()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn skill_document(
    name: &str,
    description: &str,
    required_clis: &[String],
    capabilities: &[String],
    tags: &[String],
) -> String {
    format!(
        "{} {} {} {} {}",
        name,
        description,
        tags.join(" "),
        capabilities.join(" "),
        required_clis.join(" ")
    )
    .to_lowercase()
}

fn score_skill_cards(mut cards: Vec<SkillCard>, query: &str) -> Vec<SkillCard> {
    let query_tokens = tokenize_for_bm25(query);
    if query_tokens.is_empty() {
        cards.sort_by(|a, b| a.name.cmp(&b.name));
        return cards;
    }

    let avgdl = cards
        .iter()
        .map(|card| card.tokens.len() as f64)
        .sum::<f64>()
        / cards.len().max(1) as f64;
    let mut document_frequency = HashMap::<String, usize>::new();
    for card in &cards {
        let unique = card.tokens.iter().cloned().collect::<HashSet<_>>();
        for token in unique {
            *document_frequency.entry(token).or_default() += 1;
        }
    }
    let total_docs = cards.len() as f64;
    for card in &mut cards {
        card.score = bm25_score(
            &query_tokens,
            &card.tokens,
            avgdl,
            total_docs,
            &document_frequency,
        ) + skill_boost(&query_tokens, card);
    }
    cards.into_iter().filter(|card| card.score > 0.0).collect()
}

fn bm25_score(
    query_tokens: &[String],
    doc_tokens: &[String],
    avgdl: f64,
    total_docs: f64,
    document_frequency: &HashMap<String, usize>,
) -> f64 {
    const K1: f64 = 1.2;
    const B: f64 = 0.75;
    let mut term_frequency = HashMap::<&str, usize>::new();
    for token in doc_tokens {
        *term_frequency.entry(token.as_str()).or_default() += 1;
    }
    let doc_len = doc_tokens.len().max(1) as f64;
    let mut score = 0.0;
    for token in query_tokens {
        let Some(tf) = term_frequency.get(token.as_str()).copied() else {
            continue;
        };
        let df = document_frequency.get(token).copied().unwrap_or(0) as f64;
        let idf = ((total_docs - df + 0.5) / (df + 0.5) + 1.0).ln();
        let tf = tf as f64;
        let denom = tf + K1 * (1.0 - B + B * doc_len / avgdl.max(1.0));
        score += idf * (tf * (K1 + 1.0)) / denom;
    }
    score
}

fn skill_boost(query_tokens: &[String], card: &SkillCard) -> f64 {
    let joined_query = query_tokens.join(" ");
    let mut boost = 0.0;
    let name = card.name.to_lowercase();
    if !joined_query.is_empty() && name.contains(&joined_query) {
        boost += 3.0;
    }
    for token in query_tokens {
        if name.contains(token) {
            boost += 1.2;
        }
        if card
            .required_clis
            .iter()
            .any(|cli| cli.to_lowercase().contains(token))
        {
            boost += 0.8;
        }
        if card
            .capabilities
            .iter()
            .any(|cap| cap.to_lowercase().contains(token))
        {
            boost += 0.6;
        }
        if card
            .tags
            .iter()
            .any(|tag| tag.to_lowercase().contains(token))
        {
            boost += 0.5;
        }
    }
    boost
}

fn tokenize_for_bm25(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut tokens = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|term| term.len() >= 2)
        .map(str::to_string)
        .collect::<Vec<_>>();
    let chars = lower.chars().filter(|ch| is_cjk(*ch)).collect::<Vec<_>>();
    for window in chars.windows(2) {
        tokens.push(window.iter().collect());
    }
    for window in chars.windows(3) {
        tokens.push(window.iter().collect());
    }
    tokens
}

fn is_cjk(ch: char) -> bool {
    ('\u{4e00}'..='\u{9fff}').contains(&ch)
        || ('\u{3400}'..='\u{4dbf}').contains(&ch)
        || ('\u{3040}'..='\u{30ff}').contains(&ch)
}

fn format_skill_cards(skill_cards: &[SkillCard]) -> String {
    if skill_cards.is_empty() {
        return "[]".into();
    }
    serde_json::to_string_pretty(skill_cards).unwrap_or_else(|_| "[]".into())
}

fn safe_step_name(name: &str) -> String {
    name.chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect()
}

fn chrono_like_millis() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn project_relative_path(project_path: &Path, rel: &str) -> Option<PathBuf> {
    let candidate = Path::new(rel);
    if candidate.is_absolute()
        || candidate
            .components()
            .any(|component| matches!(component, std::path::Component::ParentDir))
    {
        return None;
    }
    Some(project_path.join(candidate))
}

fn build_planner_system_prompt(
    registry: &CliRegistry,
    project_path: &PathBuf,
    tools: &[serde_json::Value],
    skill_cards: &[SkillCard],
) -> String {
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

Architecture:
- You are in the Plan phase.
- Produce a concise execution plan for the Executor.
- Do not call tools in this phase.
- You can select one or more tools or skills when useful.
- Mention exact tool names from the inventory.
- Keep the plan short: at most 3 numbered steps.

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

Installed CLI registry:
{tools_section}

Available deterministic tools:
{tool_inventory}

Recalled skill candidates:
{skill_cards}

Return only:
Plan:
1. ...
"#,
        project = project_path.display(),
        tools_section = registry.to_system_prompt_section(),
        tool_inventory = format_tool_inventory(tools),
        skill_cards = format_skill_cards(skill_cards),
    )
}

fn build_executor_system_prompt(
    registry: &CliRegistry,
    project_path: &PathBuf,
    tools: &[serde_json::Value],
    skill_cards: &[SkillCard],
) -> String {
    format!(
        r#"You are Troner, the built-in autonomous agent executor inside ScripTron.
ScripTron is a local-first automation studio, and you run inside the user's app with access to project files, installed skills, registered CLI tools, and local terminal execution.

Your purpose:
- Execute the supplied plan and satisfy the user's request end-to-end.
- Use the available deterministic tools directly when they help.
- `exec` and `run_command` are normal tools for local command execution.
- When results are best presented inside project files, update or create files with `write_file`.
- Do not paste long raw command output as the final answer; final response synthesis will handle presentation.
- Read relevant files, skills, manifests, and project context before making non-trivial changes.
- Use installed skills from the workspace `.skills` directory when they match the task.
- Use registered CLI tools from `.register` when they are appropriate.

Project path: {project}
Workspace skill path: {project}/.skills when present, or the parent workspace `.skills` directory when working inside a project.
Workspace CLI registry: {project}/.register when present, or the parent workspace `.register` directory when working inside a project.

Rules:
- Work entirely within the project path unless explicitly instructed otherwise.
- Follow the planner's plan, but adapt if tool results prove the plan wrong.
- After each tool call, check the result before proceeding.
- If a step fails, report the error clearly and stop unless you can safely recover.
- Before using a skill, inspect its files enough to understand its expected workflow.
- Before using a registered CLI, inspect its manifest or the registry prompt block and pass arguments according to its schema.
- Do not invent installed capabilities. If a skill or CLI is missing, say what is missing and use the best available fallback.
- Do not claim you performed an action unless a tool result confirms it.
- Be concise in visible reasoning and focus on action, evidence, and outcome.

Installed CLI registry:
{tools_section}

Available deterministic tools:
{tool_inventory}

Recalled skill candidates:
{skill_cards}"#,
        project = project_path.display(),
        tools_section = registry.to_system_prompt_section(),
        tool_inventory = format_tool_inventory(tools),
        skill_cards = format_skill_cards(skill_cards),
    )
}

fn response_text(blocks: &[serde_json::Value]) -> String {
    blocks
        .iter()
        .filter_map(|block| {
            if block["type"] == "text" {
                block["text"].as_str().map(str::to_string)
            } else {
                None
            }
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn format_tool_inventory(tools: &[serde_json::Value]) -> String {
    serde_json::to_string_pretty(tools).unwrap_or_else(|_| "[]".into())
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
            "description": "Run a shell command in the project directory.",
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
