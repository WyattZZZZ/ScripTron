use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum HermesError {
    #[error("model error: {0}")]
    Model(String),
    #[error("tool error: {0}")]
    Tool(String),
    #[error("request has no instructions")]
    NoInstructions,
    #[error("maximum turns exceeded: {0}")]
    MaxTurnsExceeded(usize),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RunRequest {
    pub instructions: Vec<String>,
    #[serde(default)]
    pub context: Vec<String>,
    #[serde(default)]
    pub blackboard: serde_json::Value,
    #[serde(default)]
    pub project_path: Option<PathBuf>,
    #[serde(default)]
    pub memory: Option<crate::memory::MemorySnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RunEvent {
    Started,
    Thinking {
        content: String,
    },
    ToolCall {
        tool: String,
        args: serde_json::Value,
    },
    ToolResult {
        tool: String,
        output: String,
        success: bool,
    },
    Text {
        content: String,
    },
    Warning {
        message: String,
    },
    Error {
        message: String,
    },
    Complete,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Message {
    pub role: String,
    pub content: Vec<ContentBlock>,
}

impl Message {
    pub fn user_text(text: impl Into<String>) -> Self {
        Self {
            role: "user".into(),
            content: vec![ContentBlock::Text { text: text.into() }],
        }
    }

    pub fn assistant(content: Vec<ContentBlock>) -> Self {
        Self {
            role: "assistant".into(),
            content,
        }
    }

    pub fn user_tool_results(results: Vec<ContentBlock>) -> Self {
        Self {
            role: "user".into(),
            content: results,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    Text {
        text: String,
    },
    ToolUse {
        id: String,
        name: String,
        #[serde(default)]
        input: serde_json::Value,
    },
    ToolResult {
        tool_use_id: String,
        content: String,
        #[serde(default)]
        is_error: bool,
    },
}

impl ContentBlock {
    pub fn as_tool_call(&self) -> Option<ToolCall> {
        match self {
            ContentBlock::ToolUse { id, name, input } => Some(ToolCall {
                id: id.clone(),
                name: name.clone(),
                input: input.clone(),
            }),
            ContentBlock::Text { .. } | ContentBlock::ToolResult { .. } => None,
        }
    }

    pub fn text(&self) -> Option<&str> {
        match self {
            ContentBlock::Text { text } => Some(text),
            ContentBlock::ToolUse { .. } | ContentBlock::ToolResult { .. } => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolDefinition {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub input: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolOutput {
    pub tool_call_id: String,
    pub tool_name: String,
    pub output: String,
    pub success: bool,
}

impl ToolOutput {
    pub fn into_content_block(self) -> ContentBlock {
        ContentBlock::ToolResult {
            tool_use_id: self.tool_call_id,
            content: self.output,
            is_error: !self.success,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_block_uses_anthropic_style_tags() {
        let block = ContentBlock::ToolUse {
            id: "call-1".into(),
            name: "read_file".into(),
            input: serde_json::json!({"path": "README.md"}),
        };

        let json = serde_json::to_value(&block).unwrap();

        assert_eq!(json["type"], "tool_use");
        assert_eq!(json["id"], "call-1");
        assert_eq!(json["name"], "read_file");
        assert_eq!(json["input"]["path"], "README.md");
    }

    #[test]
    fn tool_output_converts_to_tool_result_block() {
        let output = ToolOutput {
            tool_call_id: "call-2".into(),
            tool_name: "exec".into(),
            output: "ok".into(),
            success: true,
        };

        assert_eq!(
            output.into_content_block(),
            ContentBlock::ToolResult {
                tool_use_id: "call-2".into(),
                content: "ok".into(),
                is_error: false,
            }
        );
    }

    #[test]
    fn run_request_roundtrips() {
        let request = RunRequest {
            instructions: vec!["do it".into()],
            context: vec!["context".into()],
            blackboard: serde_json::json!({"done": false}),
            project_path: Some(PathBuf::from("/tmp/project")),
            memory: None,
        };

        let encoded = serde_json::to_string(&request).unwrap();
        let decoded: RunRequest = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded, request);
    }
}
