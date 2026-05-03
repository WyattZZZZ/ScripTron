use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON parse error in {path}: {source}")]
    Json {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("Tool '{0}' not found")]
    NotFound(String),
    #[error("Tool '{0}' already installed")]
    AlreadyInstalled(String),
}

/// The type of a CLI argument.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ArgType {
    String,
    Number,
    Boolean,
    Array,
}

impl std::fmt::Display for ArgType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ArgType::String => write!(f, "string"),
            ArgType::Number => write!(f, "number"),
            ArgType::Boolean => write!(f, "boolean"),
            ArgType::Array => write!(f, "array"),
        }
    }
}

/// Describes a single argument accepted by a CLI tool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArgSchema {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub required: bool,
    #[serde(rename = "type")]
    pub arg_type: ArgType,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum CliKind {
    Tool,
    Model,
    Software,
}

impl Default for CliKind {
    fn default() -> Self {
        Self::Tool
    }
}

/// The manifest describing one CLI tool available in the registry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolManifest {
    /// Unique tool name (e.g. "excel-cli").
    pub name: String,
    /// Registry item category. Models are also CLI-backed entries.
    #[serde(default)]
    pub kind: CliKind,
    pub description: String,
    pub version: String,
    /// The binary / script entry-point to invoke.
    pub command: String,
    #[serde(default)]
    pub args_schema: Vec<ArgSchema>,
    /// Plain-language usage examples shown to the LLM and in the UI.
    #[serde(default)]
    pub examples: Vec<String>,
    /// Optional homepage / install URL shown in the marketplace.
    #[serde(default)]
    pub homepage: Option<String>,
    /// Optional author field.
    #[serde(default)]
    pub author: Option<String>,
}

impl ToolManifest {
    /// Format this manifest as a compact text block for inclusion in the LLM system prompt.
    pub fn to_prompt_block(&self) -> String {
        let mut s = format!("Tool: {}\nDescription: {}\n", self.name, self.description);
        if !self.args_schema.is_empty() {
            s.push_str("Arguments:\n");
            for arg in &self.args_schema {
                let req = if arg.required { " (required)" } else { "" };
                s.push_str(&format!(
                    "  - {} [{}]{}: {}\n",
                    arg.name, arg.arg_type, req, arg.description
                ));
            }
        }
        if !self.examples.is_empty() {
            s.push_str("Examples:\n");
            for ex in &self.examples {
                s.push_str(&format!("  {}\n", ex));
            }
        }
        s
    }
}

/// In-memory registry of installed CLI tools.
///
/// Tools are stored as individual `manifest.json` files under:
///   `<registry_dir>/<tool-name>/manifest.json`
#[derive(Debug, Default)]
pub struct CliRegistry {
    pub registry_dir: PathBuf,
    tools: Vec<ToolManifest>,
}

impl CliRegistry {
    /// Load registry from disk. Creates the directory if absent.
    pub async fn load(registry_dir: impl Into<PathBuf>) -> Result<Self, RegistryError> {
        let dir: PathBuf = registry_dir.into();
        if !dir.exists() {
            tokio::fs::create_dir_all(&dir).await?;
        }
        let mut tools = Vec::new();
        let mut rd = tokio::fs::read_dir(&dir).await?;
        while let Some(entry) = rd.next_entry().await? {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let manifest_path = path.join("manifest.json");
            if !manifest_path.exists() {
                continue;
            }
            let raw = tokio::fs::read_to_string(&manifest_path).await?;
            let manifest: ToolManifest =
                serde_json::from_str(&raw).map_err(|e| RegistryError::Json {
                    path: manifest_path,
                    source: e,
                })?;
            tools.push(manifest);
        }
        tools.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(Self {
            registry_dir: dir,
            tools,
        })
    }

    pub fn list_tools(&self) -> &[ToolManifest] {
        &self.tools
    }

    pub fn get_tool(&self, name: &str) -> Option<&ToolManifest> {
        self.tools.iter().find(|t| t.name == name)
    }

    pub async fn install_tool(&mut self, manifest: ToolManifest) -> Result<(), RegistryError> {
        if self.tools.iter().any(|t| t.name == manifest.name) {
            return Err(RegistryError::AlreadyInstalled(manifest.name.clone()));
        }
        let tool_dir = self.registry_dir.join(&manifest.name);
        tokio::fs::create_dir_all(&tool_dir).await?;
        let json = serde_json::to_string_pretty(&manifest).map_err(|e| RegistryError::Json {
            path: tool_dir.clone(),
            source: e,
        })?;
        tokio::fs::write(tool_dir.join("manifest.json"), json).await?;
        self.tools.push(manifest);
        self.tools.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(())
    }

    pub async fn remove_tool(&mut self, name: &str) -> Result<(), RegistryError> {
        let idx = self
            .tools
            .iter()
            .position(|t| t.name == name)
            .ok_or_else(|| RegistryError::NotFound(name.to_string()))?;
        let tool_dir = self.registry_dir.join(name);
        if tool_dir.exists() {
            tokio::fs::remove_dir_all(tool_dir).await?;
        }
        self.tools.remove(idx);
        Ok(())
    }

    /// Build the tools section of the system prompt for the LLM.
    pub fn to_system_prompt_section(&self) -> String {
        if self.tools.is_empty() {
            return "No CLI tools are currently installed.\n".to_string();
        }
        let mut s = "Installed CLI tools (call via the run_cli_tool function):\n\n".to_string();
        for tool in &self.tools {
            s.push_str(&tool.to_prompt_block());
            s.push('\n');
        }
        s
    }

    /// Reload tools from disk (e.g. after external install).
    pub async fn reload(&mut self) -> Result<(), RegistryError> {
        let reloaded = CliRegistry::load(self.registry_dir.clone()).await?;
        self.tools = reloaded.tools;
        Ok(())
    }
}

/// Install a manifest from a local JSON file path (used by the marketplace).
pub async fn install_from_path(
    registry: &mut CliRegistry,
    manifest_path: impl AsRef<Path>,
) -> Result<(), RegistryError> {
    let raw = tokio::fs::read_to_string(manifest_path.as_ref()).await?;
    let manifest: ToolManifest = serde_json::from_str(&raw).map_err(|e| RegistryError::Json {
        path: manifest_path.as_ref().to_path_buf(),
        source: e,
    })?;
    registry.install_tool(manifest).await
}
