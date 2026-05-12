use crate::memory::MemorySnapshot;
use crate::types::ToolDefinition;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SystemIdentity {
    pub name: String,
    pub role: String,
    #[serde(default)]
    pub instructions: Vec<String>,
}

impl SystemIdentity {
    pub fn new(name: impl Into<String>, role: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            role: role.into(),
            instructions: Vec::new(),
        }
    }

    pub fn with_instruction(mut self, instruction: impl Into<String>) -> Self {
        self.instructions.push(instruction.into());
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SkillPrompt {
    pub name: String,
    pub description: String,
}

impl SkillPrompt {
    pub fn new(name: impl Into<String>, description: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            description: description.into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PromptInputs {
    pub identity: SystemIdentity,
    #[serde(default)]
    pub context: Vec<String>,
    #[serde(default)]
    pub blackboard: Option<String>,
    #[serde(default)]
    pub memory: MemorySnapshot,
    #[serde(default)]
    pub skills: Vec<SkillPrompt>,
    #[serde(default)]
    pub tool_names: Vec<String>,
}

impl PromptInputs {
    pub fn new(identity: SystemIdentity) -> Self {
        Self {
            identity,
            context: Vec::new(),
            blackboard: None,
            memory: MemorySnapshot::default(),
            skills: Vec::new(),
            tool_names: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PromptBuilder;

impl PromptBuilder {
    pub fn new() -> Self {
        Self
    }

    pub fn build(&self, inputs: &PromptInputs) -> String {
        let mut sections = Vec::new();
        sections.push(("System Identity", render_identity(&inputs.identity)));
        sections.push(("Context", render_context(&inputs.context)));
        sections.push((
            "Blackboard",
            inputs
                .blackboard
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("(none)")
                .to_string(),
        ));
        sections.push(("Memory", inputs.memory.to_prompt_section()));
        sections.push(("Skills", render_skill_prompts(&inputs.skills)));
        sections.push(("Tools", render_tool_names(&inputs.tool_names)));

        sections
            .into_iter()
            .map(|(title, body)| format!("## {title}\n{body}"))
            .collect::<Vec<_>>()
            .join("\n\n")
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct PromptContext {
    pub project_path: Option<String>,
    #[serde(default)]
    pub memory: Option<MemorySnapshot>,
    #[serde(default)]
    pub tools: Vec<ToolDefinition>,
}

pub fn build_system_prompt(context: &PromptContext) -> String {
    let mut sections = Vec::new();
    sections.push(
        r#"You are Hermes, ScripTron's local-first agent runtime.
You execute user goals inside the current project using deterministic tools, remembered context, and concise final responses.
Gateway, ACP, voice, remote sandbox, and training/batch surfaces are intentionally unavailable in this Rust runtime."#
            .to_string(),
    );

    if let Some(project_path) = context
        .project_path
        .as_deref()
        .filter(|path| !path.is_empty())
    {
        sections.push(format!(
            "Project path:\n{}",
            Path::new(project_path).display()
        ));
    }

    if let Some(memory) = context.memory.as_ref().filter(|memory| !memory.is_empty()) {
        sections.push(format_memory(memory));
    }

    if !context.tools.is_empty() {
        sections.push(format_tools(&context.tools));
    }

    sections.push(
        r#"Runtime rules:
- Read before writing when the task is non-trivial.
- Use tool calls for filesystem, command, or registry work.
- After tool results, adapt to the evidence.
- Never claim an action happened unless a tool result confirms it."#
            .to_string(),
    );

    sections.join("\n\n---\n\n")
}

pub fn build_user_prompt(
    instructions: &[String],
    context: &[String],
    blackboard: &serde_json::Value,
) -> String {
    let mut sections = Vec::new();
    if !context.is_empty() {
        sections.push(format!(
            "Document context from non-run cells:\n{}",
            context.join("\n\n---\n\n")
        ));
    }
    if !blackboard_is_empty(blackboard) {
        sections.push(format!(
            "Hidden .tron blackboard state:\n{}",
            serde_json::to_string_pretty(blackboard).unwrap_or_else(|_| "{}".into())
        ));
    }
    sections.push(format!(
        "Run instructions:\n{}",
        instructions.join("\n\n---\n\n")
    ));
    sections.join("\n\n====\n\n")
}

fn render_identity(identity: &SystemIdentity) -> String {
    let mut lines = vec![
        format!("Name: {}", identity.name.trim()),
        format!("Role: {}", identity.role.trim()),
        "Instructions:".to_string(),
    ];
    if identity.instructions.is_empty() {
        lines.push("(none)".to_string());
    } else {
        lines.extend(
            identity
                .instructions
                .iter()
                .map(|instruction| format!("- {}", instruction.trim())),
        );
    }
    lines.join("\n")
}

fn render_context(context: &[String]) -> String {
    if context.is_empty() {
        return "(none)".to_string();
    }

    context
        .iter()
        .enumerate()
        .map(|(index, value)| format!("Context {}:\n{}", index + 1, value.trim()))
        .collect::<Vec<_>>()
        .join("\n\n----\n\n")
}

fn render_skill_prompts(skills: &[SkillPrompt]) -> String {
    if skills.is_empty() {
        return "(none)".to_string();
    }

    skills
        .iter()
        .map(|skill| {
            if skill.description.trim().is_empty() {
                format!("- {}", skill.name.trim())
            } else {
                format!("- {}: {}", skill.name.trim(), skill.description.trim())
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn render_tool_names(tool_names: &[String]) -> String {
    let mut names = tool_names
        .iter()
        .map(|name| name.trim())
        .filter(|name| !name.is_empty())
        .collect::<Vec<_>>();
    names.sort_unstable();
    names.dedup();

    if names.is_empty() {
        return "(none)".to_string();
    }

    names
        .into_iter()
        .map(|name| format!("- {name}"))
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_memory(memory: &MemorySnapshot) -> String {
    let mut lines = Vec::new();
    if !memory.global.trim().is_empty() {
        lines.push(format!("Global memory:\n{}", memory.global.trim()));
    }
    if let Some(project) = &memory.project {
        if !project.notes.trim().is_empty() {
            lines.push(format!("Project memory:\n{}", project.notes.trim()));
        }
    }
    if !memory.skills.is_empty() {
        let skills = memory
            .skills
            .iter()
            .map(|skill| format!("- {}: {}", skill.name, skill.description))
            .collect::<Vec<_>>()
            .join("\n");
        lines.push(format!("Recalled skills:\n{skills}"));
    }
    format!("Memory:\n{}", lines.join("\n\n"))
}

fn format_tools(tools: &[ToolDefinition]) -> String {
    let inventory = tools
        .iter()
        .map(|tool| format!("- {}: {}", tool.name, tool.description))
        .collect::<Vec<_>>()
        .join("\n");
    format!("Available tools:\n{inventory}")
}

fn blackboard_is_empty(value: &serde_json::Value) -> bool {
    value.is_null()
        || value
            .as_object()
            .map(|object| object.is_empty())
            .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::{MemorySnapshot, SkillMemory};

    #[test]
    fn system_prompt_includes_selected_context_in_stable_order() {
        let prompt = build_system_prompt(&PromptContext {
            project_path: Some("/tmp/project".into()),
            memory: Some(MemorySnapshot {
                global: "Use Chinese.".into(),
                project: None,
                skills: vec![SkillMemory {
                    name: "rust".into(),
                    description: "Rust edits".into(),
                    path: "skills/rust".into(),
                }],
                ..Default::default()
            }),
            tools: vec![ToolDefinition {
                name: "read_file".into(),
                description: "Read a file".into(),
                input_schema: serde_json::json!({"type": "object"}),
            }],
        });

        assert!(prompt.contains("Project path:\n/tmp/project"));
        assert!(prompt.contains("Global memory:\nUse Chinese."));
        assert!(prompt.contains("- rust: Rust edits"));
        assert!(prompt.contains("- read_file: Read a file"));
        assert!(prompt.contains("Gateway, ACP"));
    }

    #[test]
    fn user_prompt_combines_context_blackboard_and_instructions() {
        let prompt = build_user_prompt(
            &["run".into()],
            &["doc".into()],
            &serde_json::json!({"cell": 1}),
        );

        assert!(prompt.contains("Document context"));
        assert!(prompt.contains("Hidden .tron blackboard"));
        assert!(prompt.contains("Run instructions"));
    }

    #[test]
    fn prompt_builder_renders_stable_sections() {
        let prompt = PromptBuilder::new().build(&PromptInputs {
            identity: SystemIdentity::new("Hermes", "agent runtime")
                .with_instruction("Prefer deterministic prompts"),
            context: vec!["Document context".into()],
            blackboard: Some("{\"phase\":\"bootstrap\"}".into()),
            memory: MemorySnapshot {
                global: "Remember project constraints.".into(),
                ..Default::default()
            },
            skills: vec![SkillPrompt::new("rust", "Rust implementation work")],
            tool_names: vec!["write_file".into(), "read_file".into(), "read_file".into()],
        });

        assert_eq!(
            prompt,
            "## System Identity\nName: Hermes\nRole: agent runtime\nInstructions:\n- Prefer deterministic prompts\n\n## Context\nContext 1:\nDocument context\n\n## Blackboard\n{\"phase\":\"bootstrap\"}\n\n## Memory\nGlobal:\nRemember project constraints.\n\n## Skills\n- rust: Rust implementation work\n\n## Tools\n- read_file\n- write_file"
        );
    }
}
