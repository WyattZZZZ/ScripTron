use async_trait::async_trait;
use cli_registry::ToolManifest;
use process_runner::{ProcessConfig, ProcessRunner};
use serde::{Deserialize, Serialize};
use std::{
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

// ── Internal message format (Anthropic-style, provider-agnostic internally) ───
//
// User content blocks:
//   {"type":"text","text":"..."}
//   {"type":"tool_result","tool_use_id":"...","content":"..."}
//
// Assistant content blocks:
//   {"type":"text","text":"..."}
//   {"type":"tool_use","id":"...","name":"...","input":{...}}
//
// Tools (Anthropic format):
//   {"name":"...","description":"...","input_schema":{...}}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: serde_json::Value,
}

#[derive(Debug, Clone)]
pub struct LlmResponse {
    /// Content blocks in Anthropic-style format (text / tool_use).
    pub content: Vec<serde_json::Value>,
    pub stop_reason: String,
}

#[async_trait]
pub trait LlmProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        max_tokens: u32,
    ) -> Result<LlmResponse, String>;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// ── CLI model provider ────────────────────────────────────────────────────────

pub struct CliModelProvider {
    manifest: ToolManifest,
    project_path: PathBuf,
    runner: ProcessRunner,
}

impl CliModelProvider {
    pub fn new(manifest: ToolManifest, project_path: impl Into<PathBuf>) -> Self {
        Self {
            manifest,
            project_path: project_path.into(),
            runner: ProcessRunner::new(),
        }
    }
}

#[async_trait]
impl LlmProvider for CliModelProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        _max_tokens: u32,
    ) -> Result<LlmResponse, String> {
        let prompt = build_cli_model_prompt(system, messages, tools);
        let output =
            if self.manifest.name == "codex-cli" || self.manifest.command.ends_with("/codex") {
                run_codex_model_cli(
                    &self.manifest.command,
                    &self.project_path,
                    &prompt,
                    &self.runner,
                )
                .await?
            } else {
                run_generic_model_cli(
                    &self.manifest.command,
                    &self.project_path,
                    &prompt,
                    &self.runner,
                )
                .await?
            };

        Ok(LlmResponse {
            content: vec![serde_json::json!({"type": "text", "text": output})],
            stop_reason: "end_turn".into(),
        })
    }
}

async fn run_generic_model_cli(
    command: &str,
    project_path: &PathBuf,
    prompt: &str,
    runner: &ProcessRunner,
) -> Result<String, String> {
    let result = runner
        .run(
            ProcessConfig::new(command, vec![prompt.to_string()])
                .with_working_dir(project_path.clone())
                .with_timeout(180),
        )
        .await
        .map_err(|e| e.to_string())?;
    if !result.success() {
        return Err(result.combined_output());
    }
    Ok(result.combined_output())
}

async fn run_codex_model_cli(
    command: &str,
    project_path: &PathBuf,
    prompt: &str,
    runner: &ProcessRunner,
) -> Result<String, String> {
    let last_message_path = cli_last_message_path();
    let args = vec![
        "exec".to_string(),
        "--cd".to_string(),
        project_path.to_string_lossy().into_owned(),
        "--sandbox".to_string(),
        "workspace-write".to_string(),
        "-c".to_string(),
        "approval_policy=\"never\"".to_string(),
        "--skip-git-repo-check".to_string(),
        "--color".to_string(),
        "never".to_string(),
        "--output-last-message".to_string(),
        last_message_path.to_string_lossy().into_owned(),
        prompt.to_string(),
    ];
    let result = runner
        .run(
            ProcessConfig::new(command, args)
                .with_working_dir(project_path.clone())
                .with_timeout(240),
        )
        .await
        .map_err(|e| e.to_string())?;
    let final_message = tokio::fs::read_to_string(&last_message_path).await.ok();
    let _ = tokio::fs::remove_file(&last_message_path).await;
    if !result.success() {
        return Err(result.combined_output());
    }
    Ok(final_message
        .filter(|text| !text.trim().is_empty())
        .unwrap_or_else(|| result.combined_output()))
}

fn build_cli_model_prompt(
    system: &str,
    messages: &[ChatMessage],
    tools: &[serde_json::Value],
) -> String {
    let mut out = String::new();
    out.push_str("System instructions:\n");
    out.push_str(system);
    out.push_str("\n\nAvailable ScripTron tool schemas:\n");
    out.push_str(&serde_json::to_string_pretty(tools).unwrap_or_else(|_| "[]".into()));
    out.push_str("\n\nConversation:\n");
    for message in messages {
        out.push_str(&format!("{}:\n", message.role));
        out.push_str(&message_content_to_text(&message.content));
        out.push_str("\n\n");
    }
    out.push_str("Reply as Troner. If this CLI cannot emit structured tool calls, provide the best direct answer and say what local action is needed.");
    out
}

fn message_content_to_text(content: &serde_json::Value) -> String {
    let Some(blocks) = content.as_array() else {
        return content.to_string();
    };
    blocks
        .iter()
        .filter_map(|block| match block["type"].as_str().unwrap_or("") {
            "text" => block["text"].as_str().map(str::to_string),
            "tool_result" => Some(format!(
                "Tool result {}:\n{}",
                block["tool_use_id"].as_str().unwrap_or(""),
                block["content"].as_str().unwrap_or("")
            )),
            "tool_use" => Some(format!(
                "Tool call {} {}\n{}",
                block["id"].as_str().unwrap_or(""),
                block["name"].as_str().unwrap_or(""),
                block["input"].to_string()
            )),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn cli_last_message_path() -> PathBuf {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "scriptron-model-cli-{}-{}.txt",
        std::process::id(),
        millis
    ))
}

// ── Anthropic provider ────────────────────────────────────────────────────────

pub struct AnthropicProvider {
    client: reqwest::Client,
    access_token: String,
    model: String,
}

impl AnthropicProvider {
    pub fn new(access_token: impl Into<String>) -> Self {
        Self {
            client: reqwest::Client::new(),
            access_token: access_token.into(),
            model: "claude-opus-4-7".into(),
        }
    }

    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }
}

#[async_trait]
impl LlmProvider for AnthropicProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        max_tokens: u32,
    ) -> Result<LlmResponse, String> {
        let body = serde_json::json!({
            "model": self.model,
            "max_tokens": max_tokens,
            "system": system,
            "tools": tools,
            "messages": messages,
        });

        let resp = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.access_token)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Read response: {}", e))?;

        if !status.is_success() {
            return Err(format!("Anthropic API {}: {}", status, text));
        }

        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        Ok(LlmResponse {
            content: json["content"].as_array().cloned().unwrap_or_default(),
            stop_reason: json["stop_reason"].as_str().unwrap_or("end_turn").into(),
        })
    }
}

// ── Gemini provider ───────────────────────────────────────────────────────────
//
// Converts to/from Gemini's generateContent format:
//   request: { systemInstruction, contents, tools, generationConfig }
//   response: { candidates[0].content.parts, candidates[0].finishReason }

pub struct GeminiProvider {
    client: reqwest::Client,
    access_token: String,
    model: String,
}

impl GeminiProvider {
    pub fn new(access_token: impl Into<String>) -> Self {
        Self {
            client: reqwest::Client::new(),
            access_token: access_token.into(),
            model: "gemini-2.5-pro".into(),
        }
    }

    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }
}

#[async_trait]
impl LlmProvider for GeminiProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        max_tokens: u32,
    ) -> Result<LlmResponse, String> {
        let contents = convert_messages_to_gemini(messages);
        let gemini_tools = convert_tools_to_gemini(tools);

        let mut body = serde_json::json!({
            "contents": contents,
            "generationConfig": { "maxOutputTokens": max_tokens },
        });

        if !system.is_empty() {
            body["systemInstruction"] = serde_json::json!({
                "parts": [{"text": system}]
            });
        }
        if !gemini_tools.is_empty() {
            body["tools"] = serde_json::json!([{
                "functionDeclarations": gemini_tools
            }]);
        }

        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent",
            self.model
        );

        let resp = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.access_token))
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Gemini request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Read response: {}", e))?;

        if !status.is_success() {
            return Err(format!("Gemini API {}: {}", status, text));
        }

        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        parse_gemini_response(&json)
    }
}

fn convert_messages_to_gemini(messages: &[ChatMessage]) -> Vec<serde_json::Value> {
    let mut out = Vec::new();
    for msg in messages {
        let gemini_role = if msg.role == "assistant" {
            "model"
        } else {
            "user"
        };
        let blocks = msg.content.as_array().cloned().unwrap_or_default();
        let mut parts: Vec<serde_json::Value> = Vec::new();

        for block in &blocks {
            let t = block["type"].as_str().unwrap_or("");
            match t {
                "text" => {
                    let text = block["text"].as_str().unwrap_or("");
                    if !text.is_empty() {
                        parts.push(serde_json::json!({"text": text}));
                    }
                }
                "tool_use" => {
                    parts.push(serde_json::json!({
                        "functionCall": {
                            "name": block["name"],
                            "args": block["input"]
                        }
                    }));
                }
                "tool_result" => {
                    let tool_use_id = block["tool_use_id"].as_str().unwrap_or("");
                    let content = block["content"].as_str().unwrap_or("");
                    // Gemini needs the function name — look it up from history
                    let name = out
                        .iter()
                        .rev()
                        .find_map(|m: &serde_json::Value| {
                            if m["role"] == "model" {
                                m["parts"].as_array()?.iter().find_map(|p| {
                                    let fname = p["functionCall"]["name"].as_str()?;
                                    // Match by position if no ID (Gemini doesn't track IDs)
                                    // We stored the id hint in the block itself
                                    let _ = tool_use_id;
                                    Some(fname.to_string())
                                })
                            } else {
                                None
                            }
                        })
                        .unwrap_or_else(|| tool_use_id.to_string());

                    parts.push(serde_json::json!({
                        "functionResponse": {
                            "name": name,
                            "response": {"result": content}
                        }
                    }));
                }
                _ => {}
            }
        }

        if !parts.is_empty() {
            out.push(serde_json::json!({"role": gemini_role, "parts": parts}));
        }
    }
    out
}

fn convert_tools_to_gemini(tools: &[serde_json::Value]) -> Vec<serde_json::Value> {
    tools
        .iter()
        .map(|t| {
            serde_json::json!({
                "name": t["name"],
                "description": t["description"],
                "parameters": t["input_schema"],
            })
        })
        .collect()
}

fn parse_gemini_response(json: &serde_json::Value) -> Result<LlmResponse, String> {
    let candidate = json["candidates"]
        .as_array()
        .and_then(|a| a.first())
        .ok_or("Gemini returned no candidates")?;

    let parts = candidate["content"]["parts"]
        .as_array()
        .cloned()
        .unwrap_or_default();

    let mut content: Vec<serde_json::Value> = Vec::new();
    let mut tool_id_counter = 0u32;

    for part in &parts {
        if let Some(text) = part["text"].as_str() {
            if !text.is_empty() {
                content.push(serde_json::json!({"type": "text", "text": text}));
            }
        } else if part["functionCall"].is_object() {
            let fc = &part["functionCall"];
            tool_id_counter += 1;
            let id = format!("gemini_tool_{}", tool_id_counter);
            content.push(serde_json::json!({
                "type": "tool_use",
                "id": id,
                "name": fc["name"],
                "input": fc["args"],
            }));
        }
    }

    let stop_reason = if content.iter().any(|b| b["type"] == "tool_use") {
        "tool_use"
    } else {
        "end_turn"
    };

    Ok(LlmResponse {
        content,
        stop_reason: stop_reason.into(),
    })
}

// ── OpenAI-compatible provider ────────────────────────────────────────────────
//
// Handles: OpenAI, DeepSeek (OpenAI-compatible), OpenRouter (OpenAI-compatible).
// Each instance points at a different base_url.

pub struct OpenAiCompatProvider {
    client: reqwest::Client,
    access_token: String,
    model: String,
    base_url: String,
    /// Extra headers injected on every request (e.g. OpenRouter's referer).
    extra_headers: Vec<(String, String)>,
}

impl OpenAiCompatProvider {
    fn new_inner(
        access_token: impl Into<String>,
        model: impl Into<String>,
        base_url: impl Into<String>,
        extra_headers: Vec<(String, String)>,
    ) -> Self {
        Self {
            client: reqwest::Client::new(),
            access_token: access_token.into(),
            model: model.into(),
            base_url: base_url.into(),
            extra_headers,
        }
    }

    pub fn new_openai(access_token: impl Into<String>, model: impl Into<String>) -> Self {
        Self::new_inner(access_token, model, "https://api.openai.com/v1", vec![])
    }

    pub fn new_deepseek(access_token: impl Into<String>, model: impl Into<String>) -> Self {
        Self::new_inner(access_token, model, "https://api.deepseek.com/v1", vec![])
    }

    pub fn new_openrouter(access_token: impl Into<String>, model: impl Into<String>) -> Self {
        Self::new_inner(
            access_token,
            model,
            "https://openrouter.ai/api/v1",
            vec![
                ("HTTP-Referer".into(), "https://scriptron.app".into()),
                ("X-Title".into(), "ScripTron".into()),
            ],
        )
    }
}

#[async_trait]
impl LlmProvider for OpenAiCompatProvider {
    async fn complete(
        &self,
        system: &str,
        messages: &[ChatMessage],
        tools: &[serde_json::Value],
        max_tokens: u32,
    ) -> Result<LlmResponse, String> {
        let oai_messages = convert_messages_to_openai(system, messages);
        let oai_tools = convert_tools_to_openai(tools);

        let mut body = serde_json::json!({
            "model": self.model,
            "max_tokens": max_tokens,
            "messages": oai_messages,
        });

        if !oai_tools.is_empty() {
            body["tools"] = serde_json::Value::Array(oai_tools);
        }

        let url = format!("{}/chat/completions", self.base_url);

        let mut req = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.access_token))
            .header("content-type", "application/json");

        for (k, v) in &self.extra_headers {
            req = req.header(k.as_str(), v.as_str());
        }

        let resp = req
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Read response: {}", e))?;

        if !status.is_success() {
            return Err(format!("API {}: {}", status, text));
        }

        let json: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        parse_openai_response(&json)
    }
}

fn convert_messages_to_openai(system: &str, messages: &[ChatMessage]) -> Vec<serde_json::Value> {
    let mut out: Vec<serde_json::Value> = Vec::new();

    if !system.is_empty() {
        out.push(serde_json::json!({"role": "system", "content": system}));
    }

    for msg in messages {
        let blocks = msg.content.as_array().cloned().unwrap_or_default();

        if msg.role == "assistant" {
            // Collect text and tool_calls separately
            let mut text_parts: Vec<&str> = Vec::new();
            let mut tool_calls: Vec<serde_json::Value> = Vec::new();

            for block in &blocks {
                match block["type"].as_str().unwrap_or("") {
                    "text" => {
                        if let Some(t) = block["text"].as_str() {
                            text_parts.push(t);
                        }
                    }
                    "tool_use" => {
                        tool_calls.push(serde_json::json!({
                            "id": block["id"],
                            "type": "function",
                            "function": {
                                "name": block["name"],
                                "arguments": serde_json::to_string(&block["input"])
                                    .unwrap_or_else(|_| "{}".into()),
                            }
                        }));
                    }
                    _ => {}
                }
            }

            let text_content = text_parts.join("\n");
            let mut m = serde_json::json!({
                "role": "assistant",
                "content": if text_content.is_empty() { serde_json::Value::Null }
                           else { serde_json::Value::String(text_content) },
            });
            if !tool_calls.is_empty() {
                m["tool_calls"] = serde_json::Value::Array(tool_calls);
            }
            out.push(m);
        } else {
            // User role: text blocks → one user message; tool_result blocks → separate tool messages
            let mut text_parts: Vec<&str> = Vec::new();
            let mut tool_results: Vec<serde_json::Value> = Vec::new();

            for block in &blocks {
                match block["type"].as_str().unwrap_or("") {
                    "text" => {
                        if let Some(t) = block["text"].as_str() {
                            text_parts.push(t);
                        }
                    }
                    "tool_result" => {
                        tool_results.push(serde_json::json!({
                            "role": "tool",
                            "tool_call_id": block["tool_use_id"],
                            "content": block["content"].as_str().unwrap_or(""),
                        }));
                    }
                    _ => {}
                }
            }

            if !text_parts.is_empty() {
                out.push(serde_json::json!({
                    "role": "user",
                    "content": text_parts.join("\n"),
                }));
            }
            out.extend(tool_results);
        }
    }

    out
}

fn convert_tools_to_openai(tools: &[serde_json::Value]) -> Vec<serde_json::Value> {
    tools
        .iter()
        .map(|t| {
            serde_json::json!({
                "type": "function",
                "function": {
                    "name": t["name"],
                    "description": t["description"],
                    "parameters": t["input_schema"],
                }
            })
        })
        .collect()
}

fn parse_openai_response(json: &serde_json::Value) -> Result<LlmResponse, String> {
    let choice = json["choices"]
        .as_array()
        .and_then(|a| a.first())
        .ok_or("OpenAI-compat API returned no choices")?;

    let finish = choice["finish_reason"].as_str().unwrap_or("stop");
    let message = &choice["message"];

    let mut content: Vec<serde_json::Value> = Vec::new();

    if let Some(text) = message["content"].as_str() {
        if !text.is_empty() {
            content.push(serde_json::json!({"type": "text", "text": text}));
        }
    }

    if let Some(tool_calls) = message["tool_calls"].as_array() {
        for tc in tool_calls {
            let args_str = tc["function"]["arguments"].as_str().unwrap_or("{}");
            let input: serde_json::Value =
                serde_json::from_str(args_str).unwrap_or(serde_json::json!({}));
            content.push(serde_json::json!({
                "type": "tool_use",
                "id": tc["id"],
                "name": tc["function"]["name"],
                "input": input,
            }));
        }
    }

    let stop_reason = if finish == "tool_calls" {
        "tool_use"
    } else {
        "end_turn"
    };

    Ok(LlmResponse {
        content,
        stop_reason: stop_reason.into(),
    })
}
