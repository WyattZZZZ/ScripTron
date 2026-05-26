use chrono::Utc;
use process_runner::{ProcessConfig, ProcessRunner};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Stdio,
    sync::Arc,
};
use tokio::sync::RwLock;
use tron_parser::{TronCell, TronFile};

#[derive(Debug, Serialize, Deserialize)]
pub struct TronFileDto {
    pub path: String,
    pub cells: Vec<TronCell>,
    pub blackboard: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_tron: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectEntry {
    pub name: String,
    pub path: String,
    pub status: String,
    pub archived: bool,
    pub packaged: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ActiveConfig {
    pub provider: String,
    pub model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderStatus {
    pub provider: String,
    pub display_name: String,
    pub connected: bool,
    pub auth_method: String,
    pub available_models: Vec<String>,
    pub default_model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ArgType {
    String,
    Number,
    Boolean,
    Array,
}

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolManifest {
    pub name: String,
    #[serde(default)]
    pub kind: CliKind,
    pub description: String,
    pub version: String,
    pub command: String,
    #[serde(default)]
    pub args_schema: Vec<ArgSchema>,
    #[serde(default)]
    pub examples: Vec<String>,
    #[serde(default)]
    pub homepage: Option<String>,
    #[serde(default)]
    pub author: Option<String>,
}

#[derive(Debug, Default)]
struct CliRegistry {
    registry_dir: PathBuf,
    tools: Vec<ToolManifest>,
}

impl CliRegistry {
    async fn load(registry_dir: impl Into<PathBuf>) -> Result<Self, String> {
        let dir = registry_dir.into();
        if !dir.exists() {
            tokio::fs::create_dir_all(&dir)
                .await
                .map_err(|e| e.to_string())?;
        }

        let mut tools = Vec::new();
        let mut entries = tokio::fs::read_dir(&dir).await.map_err(|e| e.to_string())?;
        while let Some(entry) = entries.next_entry().await.map_err(|e| e.to_string())? {
            let manifest_path = entry.path().join("manifest.json");
            if !manifest_path.exists() {
                continue;
            }
            let raw = tokio::fs::read_to_string(&manifest_path)
                .await
                .map_err(|e| e.to_string())?;
            let manifest = serde_json::from_str(&raw)
                .map_err(|e| format!("JSON parse error in {}: {e}", manifest_path.display()))?;
            tools.push(manifest);
        }
        tools.sort_by(|a: &ToolManifest, b| a.name.cmp(&b.name));
        Ok(Self {
            registry_dir: dir,
            tools,
        })
    }

    fn list_tools(&self) -> &[ToolManifest] {
        &self.tools
    }

    fn get_tool(&self, name: &str) -> Option<&ToolManifest> {
        self.tools.iter().find(|tool| tool.name == name)
    }

    async fn install_tool(&mut self, manifest: ToolManifest) -> Result<(), String> {
        if self.tools.iter().any(|tool| tool.name == manifest.name) {
            return Err(format!("Tool '{}' already installed", manifest.name));
        }
        let tool_dir = self.registry_dir.join(&manifest.name);
        tokio::fs::create_dir_all(&tool_dir)
            .await
            .map_err(|e| e.to_string())?;
        let json = serde_json::to_string_pretty(&manifest).map_err(|e| e.to_string())?;
        tokio::fs::write(tool_dir.join("manifest.json"), json)
            .await
            .map_err(|e| e.to_string())?;
        self.tools.push(manifest);
        self.tools.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(())
    }

    async fn remove_tool(&mut self, name: &str) -> Result<(), String> {
        let index = self
            .tools
            .iter()
            .position(|tool| tool.name == name)
            .ok_or_else(|| format!("Tool '{name}' not found"))?;
        let tool_dir = self.registry_dir.join(name);
        if tool_dir.exists() {
            tokio::fs::remove_dir_all(tool_dir)
                .await
                .map_err(|e| e.to_string())?;
        }
        self.tools.remove(index);
        Ok(())
    }

    async fn reload(&mut self) -> Result<(), String> {
        let reloaded = Self::load(self.registry_dir.clone()).await?;
        self.tools = reloaded.tools;
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionEvent {
    #[serde(rename = "type")]
    pub event_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

impl ExecutionEvent {
    fn warning(message: impl Into<String>) -> Self {
        Self {
            event_type: "warning".into(),
            content: None,
            message: Some(message.into()),
        }
    }

    fn text(content: impl Into<String>) -> Self {
        Self {
            event_type: "text".into(),
            content: Some(content.into()),
            message: None,
        }
    }

    fn complete() -> Self {
        Self {
            event_type: "complete".into(),
            content: None,
            message: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryNote {
    pub id: String,
    pub scope: String,
    pub content: String,
    pub source: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalMemory {
    pub user_name_preference: String,
    pub agent_style_preference: String,
    pub execution_rules: Vec<String>,
    pub notes: Vec<MemoryNote>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMemory {
    pub project_path: String,
    pub project_name: String,
    pub archived: bool,
    pub format_rules: Vec<String>,
    pub task_constraints: Vec<String>,
    pub glossary: BTreeMap<String, String>,
    pub long_context: Vec<MemoryNote>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterInfo {
    pub path: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronerMemory {
    pub schema_version: u32,
    pub global_memory: GlobalMemory,
    pub projects: BTreeMap<String, ProjectMemory>,
    pub register: RegisterInfo,
    pub audit_log: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySnapshot {
    pub global_memory: GlobalMemory,
    pub project_memory: ProjectMemory,
    pub effective_prompt: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronMentionModule {
    pub name: String,
    pub kind: String,
    pub injection: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MentionItem {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub path: String,
    pub detail: String,
    pub installed: bool,
    pub modules: Vec<TronMentionModule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MentionSearchResult {
    pub tools: Vec<MentionItem>,
    pub files: Vec<MentionItem>,
    pub cloud_suggestions: Vec<MentionItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronhubEntry {
    pub name: String,
    pub kind: String,
    pub description: String,
    pub source_path: String,
    pub installed: bool,
    pub manifest_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillEntry {
    pub name: String,
    pub description: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillIndexEntry {
    pub name: String,
    pub description: String,
    pub path: String,
    pub required_clis: Vec<String>,
    pub capabilities: Vec<String>,
    pub tags: Vec<String>,
    pub document: String,
    pub tokens: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesStatus {
    pub installed: bool,
    pub running: bool,
    pub version: Option<String>,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesSkillCatalogItem {
    pub name: String,
    pub description: String,
    #[serde(default = "default_hermes_source")]
    pub source: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub trust_level: String,
    #[serde(default)]
    pub installed: bool,
    #[serde(default)]
    pub install_ref: Option<String>,
    #[serde(default)]
    pub wraps_external_cli: bool,
}

fn default_hermes_source() -> String {
    "Hermes Official / Hub".into()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesPromptSubmitResult {
    pub events: Vec<ExecutionEvent>,
    pub blackboard: serde_json::Value,
    pub log_path: String,
}

pub struct ScriptronCore {
    registry: Arc<RwLock<CliRegistry>>,
    workspace_dir: PathBuf,
    config_path: PathBuf,
    runner: ProcessRunner,
}

impl ScriptronCore {
    pub async fn init() -> anyhow::Result<Self> {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."));

        let data_dir = home.join(".scriptron");
        let legacy_registry_dir = data_dir.join("registry");
        let config_path = data_dir.join("config.json");
        let workspace_dir = home.join("ScripTron");
        let registry_dir = workspace_dir.join(".register");

        tokio::fs::create_dir_all(&workspace_dir).await?;
        ensure_workspace_layout(&workspace_dir).await?;
        migrate_legacy_registry(&legacy_registry_dir, &registry_dir).await?;
        let bootstrap_runner = ProcessRunner::new();
        let _ = sync_tronhub_cache(&workspace_dir, &bootstrap_runner).await;

        Ok(Self {
            registry: Arc::new(RwLock::new(
                CliRegistry::load(&registry_dir)
                    .await
                    .map_err(anyhow::Error::msg)?,
            )),
            workspace_dir,
            config_path,
            runner: ProcessRunner::new(),
        })
    }

    pub fn workspace_path(&self) -> String {
        self.workspace_dir.to_string_lossy().into_owned()
    }

    pub async fn list_workspace_files(&self) -> Result<Vec<FileEntry>, String> {
        list_dir(self.workspace_dir.clone()).await
    }

    pub async fn list_dir_files(&self, path: String) -> Result<Vec<FileEntry>, String> {
        list_dir(PathBuf::from(path)).await
    }

    pub async fn list_projects(&self) -> Result<Vec<ProjectEntry>, String> {
        let memory = self.load_troner_memory().await?;
        let mut projects = Vec::new();
        let mut entries = tokio::fs::read_dir(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?;
        while let Some(entry) = entries.next_entry().await.map_err(|e| e.to_string())? {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') || !path.is_dir() {
                continue;
            }
            let path_text = path.to_string_lossy().into_owned();
            let archived = memory
                .projects
                .get(&path_text)
                .map(|project| project.archived)
                .unwrap_or(false);
            projects.push(ProjectEntry {
                name,
                path: path_text,
                status: if archived { "Archived" } else { "Ready" }.into(),
                archived,
                packaged: false,
            });
        }
        projects.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(projects)
    }

    pub async fn create_project(&self, name: String) -> Result<(), String> {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Err("Project name cannot be empty.".into());
        }
        let directory_name = sanitized_project_directory_name(trimmed);
        if directory_name.is_empty() {
            return Err("Project name cannot be empty.".into());
        }
        let project_dir = unique_child_path(&self.workspace_dir, &directory_name);
        tokio::fs::create_dir_all(&project_dir)
            .await
            .map_err(|e| e.to_string())?;
        let starter_path = project_dir.join("main.tron");
        let mut file = tokio::fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&starter_path)
            .await
            .map_err(|e| e.to_string())?;
        use tokio::io::AsyncWriteExt;
        file.write_all(starter_tron_content(trimmed).as_bytes())
            .await
            .map_err(|e| e.to_string())?;
        let mut memory = self.load_troner_memory().await?;
        ensure_project_memory(&mut memory, &project_dir.to_string_lossy());
        self.save_troner_memory(&memory).await?;
        Ok(())
    }

    pub async fn archive_project(&self, path: String) -> Result<(), String> {
        self.set_project_archived(path, true).await
    }

    pub async fn restore_project(&self, path: String) -> Result<(), String> {
        self.set_project_archived(path, false).await
    }

    pub async fn delete_project(&self, path: String) -> Result<(), String> {
        let project_path = PathBuf::from(&path);
        if !project_path.starts_with(&self.workspace_dir) || project_path == self.workspace_dir {
            return Err(format!("Refusing to delete outside workspace: {path}"));
        }
        if !project_path.is_dir() {
            return Err(format!("Project path is not a directory: {path}"));
        }
        tokio::fs::remove_dir_all(&project_path)
            .await
            .map_err(|e| e.to_string())?;
        let mut memory = self.load_troner_memory().await?;
        memory.projects.remove(&path);
        memory.audit_log.push(audit_event(
            "project.delete",
            serde_json::json!({ "path": path }),
        ));
        self.save_troner_memory(&memory).await
    }

    pub async fn create_folder(
        &self,
        parent_path: String,
        name: String,
    ) -> Result<FileEntry, String> {
        let parent = self.workspace_child_dir(&parent_path)?;
        let folder_name =
            sanitized_file_name(&name).ok_or_else(|| "Folder name cannot be empty.".to_string())?;
        let target = unique_child_path(&parent, &folder_name);
        tokio::fs::create_dir_all(&target)
            .await
            .map_err(|e| e.to_string())?;
        Ok(file_entry(target))
    }

    pub async fn create_file(
        &self,
        parent_path: String,
        name: String,
    ) -> Result<FileEntry, String> {
        let parent = self.workspace_child_dir(&parent_path)?;
        let file_name =
            sanitized_file_name(&name).ok_or_else(|| "File name cannot be empty.".to_string())?;
        let target = unique_child_path(&parent, &file_name);
        tokio::fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&target)
            .await
            .map_err(|e| e.to_string())?;
        Ok(file_entry(target))
    }

    pub async fn rename_entry(&self, path: String, name: String) -> Result<FileEntry, String> {
        let source = self.workspace_child_path(&path)?;
        if !source.exists() {
            return Err(format!("Path does not exist: {path}"));
        }
        let target_name =
            sanitized_file_name(&name).ok_or_else(|| "Name cannot be empty.".to_string())?;
        let parent = source
            .parent()
            .ok_or_else(|| "Cannot rename workspace root".to_string())?;
        let target = unique_child_path(parent, &target_name);
        tokio::fs::rename(&source, &target)
            .await
            .map_err(|e| e.to_string())?;
        Ok(file_entry(target))
    }

    pub async fn delete_entry(&self, path: String) -> Result<(), String> {
        let target = self.workspace_child_path(&path)?;
        if target.is_dir() {
            tokio::fs::remove_dir_all(&target)
                .await
                .map_err(|e| e.to_string())
        } else if target.is_file() {
            tokio::fs::remove_file(&target)
                .await
                .map_err(|e| e.to_string())
        } else {
            Err(format!("Path does not exist: {path}"))
        }
    }

    pub async fn save_plain_file(&self, path: String, content: String) -> Result<(), String> {
        let target = self.workspace_child_path(&path)?;
        if target.is_dir() {
            return Err(format!("Path is a directory: {path}"));
        }
        tokio::fs::write(target, content)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn import_zip_project(&self, source_path: String) -> Result<ProjectEntry, String> {
        let source = PathBuf::from(&source_path);
        if source.extension().and_then(|ext| ext.to_str()) != Some("zip") {
            return Err("Only .zip files can be imported as projects.".into());
        }
        if !source.is_file() {
            return Err(format!("Zip file does not exist: {source_path}"));
        }

        let raw_name = source
            .file_stem()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Imported Project".into());
        let directory_name = {
            let sanitized = sanitized_project_directory_name(&raw_name);
            if sanitized.is_empty() {
                "Imported Project".to_string()
            } else {
                sanitized
            }
        };
        let project_dir = unique_child_path(&self.workspace_dir, &directory_name);
        tokio::fs::create_dir_all(&project_dir)
            .await
            .map_err(|e| e.to_string())?;

        let source_clone = source.clone();
        let project_clone = project_dir.clone();
        let extraction = tokio::task::spawn_blocking(move || {
            let source_arg = source_clone.to_string_lossy().into_owned();
            let project_arg = project_clone.to_string_lossy().into_owned();
            let status = std::process::Command::new("/usr/bin/ditto")
                .args(["-x", "-k", source_arg.as_str(), project_arg.as_str()])
                .status()
                .map_err(|e| e.to_string())?;
            if status.success() {
                Ok(())
            } else {
                Err(format!("Could not unzip {}.", source_clone.display()))
            }
        })
        .await
        .map_err(|e| e.to_string())?;

        if let Err(error) = extraction {
            let _ = tokio::fs::remove_dir_all(&project_dir).await;
            return Err(error);
        }

        Ok(ProjectEntry {
            name: project_dir
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or(directory_name),
            path: project_dir.to_string_lossy().into_owned(),
            status: "Ready".into(),
            archived: false,
            packaged: false,
        })
    }

    pub async fn copy_entry(
        &self,
        path: String,
        target_directory_path: String,
    ) -> Result<FileEntry, String> {
        let source = self.workspace_child_path(&path)?;
        if !source.exists() {
            return Err(format!("Path does not exist: {path}"));
        }
        let target_directory = self.workspace_child_dir(&target_directory_path)?;
        if source.is_dir() && target_directory.starts_with(&source) {
            return Err("A folder cannot be copied into itself.".into());
        }
        let name = source
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .ok_or_else(|| "Path cannot be copied".to_string())?;
        let destination = unique_child_path(&target_directory, &name);
        let source_clone = source.clone();
        let destination_clone = destination.clone();
        tokio::task::spawn_blocking(move || copy_path_recursive(&source_clone, &destination_clone))
            .await
            .map_err(|e| e.to_string())??;
        Ok(file_entry(destination))
    }

    pub async fn move_entry(
        &self,
        path: String,
        target_directory_path: String,
    ) -> Result<FileEntry, String> {
        let source = self.workspace_child_path(&path)?;
        if !source.exists() {
            return Err(format!("Path does not exist: {path}"));
        }
        let target_directory = self.workspace_child_dir(&target_directory_path)?;
        if source.is_dir() && target_directory.starts_with(&source) {
            return Err("A folder cannot be moved into itself.".into());
        }
        let name = source
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .ok_or_else(|| "Path cannot be moved".to_string())?;
        let destination = unique_child_path(&target_directory, &name);
        tokio::fs::rename(&source, &destination)
            .await
            .map_err(|e| e.to_string())?;
        Ok(file_entry(destination))
    }

    pub async fn open_tron_file(&self, path: String) -> Result<TronFileDto, String> {
        tron_parser::parse_file(&path)
            .map(|f| TronFileDto {
                path: f.path.to_string_lossy().into_owned(),
                cells: f.cells,
                blackboard: f.blackboard,
            })
            .map_err(|e| e.to_string())
    }

    pub async fn save_tron_file(
        &self,
        path: String,
        cells: Vec<TronCell>,
        blackboard: Option<serde_json::Value>,
    ) -> Result<(), String> {
        let content = tron_parser::serialize_with_blackboard(
            &cells,
            &blackboard.unwrap_or_else(|| serde_json::json!({})),
        );
        tokio::fs::write(path, content)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_tron_file(&self, path: String) -> Result<TronFileDto, String> {
        let cells = Vec::<TronCell>::new();
        let blackboard = serde_json::json!({ "entries": [], "notes": [] });
        let content = tron_parser::serialize_with_blackboard(&cells, &blackboard);
        tokio::fs::write(&path, &content)
            .await
            .map_err(|e| e.to_string())?;
        Ok(TronFileDto {
            path,
            cells,
            blackboard,
        })
    }

    pub async fn list_tools(&self) -> Vec<ToolManifest> {
        self.registry.read().await.list_tools().to_vec()
    }

    pub async fn install_tool_from_json(&self, manifest_json: String) -> Result<(), String> {
        let manifest: ToolManifest =
            serde_json::from_str(&manifest_json).map_err(|e| e.to_string())?;
        self.registry
            .write()
            .await
            .install_tool(manifest)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn remove_tool(&self, name: String) -> Result<(), String> {
        self.registry
            .write()
            .await
            .remove_tool(&name)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn sync_tronhub(&self) -> Result<(), String> {
        sync_tronhub_cache(&self.workspace_dir, &self.runner)
            .await
            .map_err(|e| e.to_string())?;
        self.registry
            .write()
            .await
            .reload()
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn list_tronhub(&self, kind: String) -> Result<Vec<TronhubEntry>, String> {
        list_tronhub_entries(&self.workspace_dir, &kind)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn install_tronhub(&self, kind: String, name: String) -> Result<(), String> {
        install_tronhub_entry(&self.workspace_dir, &kind, &name)
            .await
            .map_err(|e| e.to_string())?;
        if kind == "skill" || kind == "skills" {
            install_skill_tool_adapters(&self.workspace_dir, &name)
                .await
                .map_err(|e| e.to_string())?;
            rebuild_skill_index(&self.workspace_dir)
                .await
                .map_err(|e| e.to_string())?;
        }
        if kind == "cli" || kind == "model" || kind == "skill" || kind == "skills" {
            self.registry
                .write()
                .await
                .reload()
                .await
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    pub async fn list_skills(&self) -> Result<Vec<SkillEntry>, String> {
        list_installed_skills(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn remove_skill(&self, name: String) -> Result<(), String> {
        let path = self.workspace_dir.join(".skills").join(safe_name(&name));
        if path.exists() {
            tokio::fs::remove_dir_all(path)
                .await
                .map_err(|e| e.to_string())?;
        }
        rebuild_skill_index(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn hermes_status(&self) -> Result<HermesStatus, String> {
        let bin = hermes_binary();
        let output = tokio::process::Command::new(&bin)
            .arg("--version")
            .stdin(Stdio::null())
            .output()
            .await;

        match output {
            Ok(output) if output.status.success() => {
                let version = String::from_utf8_lossy(&output.stdout).trim().to_string();
                Ok(HermesStatus {
                    installed: true,
                    running: false,
                    version: if version.is_empty() {
                        None
                    } else {
                        Some(version)
                    },
                    diagnostic: None,
                })
            }
            Ok(output) => Ok(HermesStatus {
                installed: false,
                running: false,
                version: None,
                diagnostic: Some(String::from_utf8_lossy(&output.stderr).trim().to_string()),
            }),
            Err(error) => Ok(HermesStatus {
                installed: false,
                running: false,
                version: None,
                diagnostic: Some(error.to_string()),
            }),
        }
    }

    pub async fn hermes_skills_browse(&self) -> Result<Vec<HermesSkillCatalogItem>, String> {
        run_hermes_skill_catalog_command(&["skills", "browse", "--size", "100"]).await
    }

    pub async fn hermes_skills_search(
        &self,
        query: String,
    ) -> Result<Vec<HermesSkillCatalogItem>, String> {
        run_hermes_skill_catalog_command(&["skills", "search", &query, "--limit", "20"]).await
    }

    pub async fn hermes_skills_install(&self, install_ref: String) -> Result<(), String> {
        let output = tokio::process::Command::new(hermes_binary())
            .args(["skills", "install", &install_ref])
            .stdin(Stdio::null())
            .output()
            .await
            .map_err(|e| e.to_string())?;
        if output.status.success() {
            Ok(())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
        }
    }

    pub async fn get_auth_status(&self) -> Vec<ProviderStatus> {
        vec![ProviderStatus {
            provider: "hermes".into(),
            display_name: "Hermes Agent".into(),
            connected: false,
            auth_method: "hermes_managed".into(),
            available_models: vec!["Hermes managed".into()],
            default_model: "Hermes managed".into(),
        }]
    }

    /// Run a TronHub plugin's `install.sh` to install the underlying tool/CLI.
    /// `kind` is "model" or "cli". Returns the script's combined output.
    /// On success, writes a `.installed` marker file inside the plugin directory.
    pub async fn run_plugin_install_script(
        &self,
        kind: String,
        name: String,
    ) -> Result<String, String> {
        let target_dir = installed_kind_dir(&self.workspace_dir, &kind).join(safe_name(&name));
        if !target_dir.exists() {
            return Err(format!("Plugin '{}' is not installed", name));
        }
        let script_path = target_dir.join("install.sh");
        if !script_path.exists() {
            // No install.sh: treat as already installed.
            let _ = tokio::fs::write(target_dir.join(".installed"), b"").await;
            return Ok(format!("No install.sh for '{}', skipping.", name));
        }
        let result = self
            .runner
            .run(
                ProcessConfig::new("bash", vec![script_path.to_string_lossy().into_owned()])
                    .with_working_dir(target_dir.clone())
                    .with_timeout(600)
                    .with_env("PATH", plugin_runtime_path()),
            )
            .await
            .map_err(|e| e.to_string())?;
        if !result.success() {
            return Err(result.combined_output());
        }
        let _ = tokio::fs::write(target_dir.join(".installed"), b"").await;
        Ok(result.combined_output())
    }

    /// Returns names of installed plugins whose dependencies have been installed
    /// (i.e. `.installed` marker exists in the plugin directory).
    pub async fn list_installed_dependencies(&self) -> Vec<String> {
        let mut out = Vec::new();
        for kind in ["model", "cli"] {
            let dir = installed_kind_dir(&self.workspace_dir, kind);
            let mut rd = match tokio::fs::read_dir(&dir).await {
                Ok(rd) => rd,
                Err(_) => continue,
            };
            while let Ok(Some(entry)) = rd.next_entry().await {
                let path = entry.path();
                if path.is_dir() && path.join(".installed").exists() {
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        out.push(name.to_string());
                    }
                }
            }
        }
        out
    }

    /// Run a TronHub plugin's `--action login` flow (OAuth or device code).
    pub async fn run_plugin_login(&self, name: String) -> Result<String, String> {
        let manifest = {
            let registry = self.registry.read().await;
            registry
                .get_tool(&name)
                .cloned()
                .ok_or_else(|| format!("Plugin '{}' not found", name))?
        };
        let working_dir = std::path::Path::new(&manifest.command)
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| self.workspace_dir.clone());
        let result = self
            .runner
            .run(
                ProcessConfig::new(
                    &manifest.command,
                    vec!["--action".to_string(), "login".to_string()],
                )
                .with_working_dir(working_dir)
                .with_timeout(300)
                .with_env("PATH", plugin_runtime_path()),
            )
            .await
            .map_err(|e| e.to_string())?;
        if !result.success() {
            return Err(result.combined_output());
        }
        Ok(result.combined_output())
    }

    pub async fn get_active_config(&self) -> ActiveConfig {
        std::fs::read_to_string(&self.config_path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_else(default_active_config)
    }

    pub async fn set_active_config(&self, provider: String, model: String) -> Result<(), String> {
        let cfg = ActiveConfig { provider, model };
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let json = serde_json::to_string_pretty(&cfg).map_err(|e| e.to_string())?;
        std::fs::write(&self.config_path, json).map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn build_task(
        &self,
        cells: Vec<TronCell>,
        project_path: String,
        blackboard: Option<serde_json::Value>,
    ) -> serde_json::Value {
        let file = TronFile {
            path: PathBuf::from("task.tron"),
            cells,
            blackboard: blackboard.unwrap_or_else(|| serde_json::json!({})),
        };
        serde_json::to_value(file.build_task(PathBuf::from(project_path)))
            .unwrap_or_else(|_| serde_json::json!({}))
    }

    pub async fn hermes_prompt_submit(
        &self,
        cells: Vec<TronCell>,
        project_path: String,
        blackboard: Option<serde_json::Value>,
        tron_path: Option<String>,
    ) -> Result<HermesPromptSubmitResult, String> {
        let mut blackboard = blackboard.unwrap_or_else(|| serde_json::json!({}));
        let log_path = run_log_path(tron_path.as_deref(), &project_path);
        let prompt_text = build_hermes_prompt_text(&cells, &project_path)?;
        let events = vec![
            ExecutionEvent::warning(format!(
                "Hermes prompt submitted. Log file: {}",
                log_path.display()
            )),
            ExecutionEvent::text(prompt_text.clone()),
            ExecutionEvent::complete(),
        ];
        let response = events
            .iter()
            .filter_map(|event| match event {
                ExecutionEvent {
                    event_type,
                    content: Some(content),
                    ..
                } if event_type == "text" => Some(content.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        update_blackboard_notes(
            &mut blackboard,
            &response,
            tron_path.as_deref().unwrap_or("run"),
        );
        if let Some(path) = tron_path {
            self.save_tron_file(path, cells, Some(blackboard.clone()))
                .await?;
        }
        write_run_log(&log_path, &events).await?;
        Ok(HermesPromptSubmitResult {
            events,
            blackboard,
            log_path: log_path.to_string_lossy().into_owned(),
        })
    }

    pub async fn get_memory_snapshot(
        &self,
        project_path: Option<String>,
    ) -> Result<MemorySnapshot, String> {
        let mut memory = self.load_troner_memory().await?;
        let project_path = project_path.unwrap_or_default();
        let project_memory = ensure_project_memory(&mut memory, &project_path);
        self.save_troner_memory(&memory).await?;
        let effective_prompt =
            build_effective_memory_prompt(&memory.global_memory, &project_memory);
        Ok(MemorySnapshot {
            global_memory: memory.global_memory,
            project_memory,
            effective_prompt,
        })
    }

    pub async fn update_global_memory(
        &self,
        global_memory: GlobalMemory,
    ) -> Result<TronerMemory, String> {
        let mut memory = self.load_troner_memory().await?;
        memory.global_memory = global_memory;
        memory
            .audit_log
            .push(audit_event("memory.global.update", serde_json::json!({})));
        self.save_troner_memory(&memory).await?;
        Ok(memory)
    }

    pub async fn factory_reset_app_state(&self) -> Result<(), String> {
        let hidden_dirs = [".register", ".skills", ".tronhub"];
        for dir in hidden_dirs {
            let path = self.workspace_dir.join(dir);
            if path.exists() {
                tokio::fs::remove_dir_all(&path)
                    .await
                    .map_err(|e| e.to_string())?;
            }
        }

        let memory_path = self.workspace_dir.join(".troner.json");
        if memory_path.exists() {
            tokio::fs::remove_file(&memory_path)
                .await
                .map_err(|e| e.to_string())?;
        }

        let default_config = default_active_config();
        let json = serde_json::to_string_pretty(&default_config).map_err(|e| e.to_string())?;
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(&self.config_path, json).map_err(|e| e.to_string())?;

        ensure_workspace_layout(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?;
        let _ = sync_tronhub_cache(&self.workspace_dir, &self.runner).await;
        self.registry
            .write()
            .await
            .reload()
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn update_project_memory(
        &self,
        project_memory: ProjectMemory,
    ) -> Result<TronerMemory, String> {
        let mut memory = self.load_troner_memory().await?;
        memory
            .projects
            .insert(project_memory.project_path.clone(), project_memory);
        memory
            .audit_log
            .push(audit_event("memory.project.update", serde_json::json!({})));
        self.save_troner_memory(&memory).await?;
        Ok(memory)
    }

    pub async fn search_mentions(
        &self,
        query: String,
        project_path: Option<String>,
    ) -> Result<MentionSearchResult, String> {
        let query = query.trim().to_lowercase();
        let mut tools = list_installed_skills(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?
            .iter()
            .filter(|skill| {
                query.is_empty()
                    || skill.name.to_lowercase().contains(&query)
                    || skill.description.to_lowercase().contains(&query)
            })
            .map(|skill| MentionItem {
                id: format!("skill:{}", skill.name),
                label: skill.name.clone(),
                kind: "skill".into(),
                path: skill.path.clone(),
                detail: skill.description.clone(),
                installed: true,
                modules: Vec::new(),
            })
            .collect::<Vec<_>>();
        tools.sort_by(|a, b| a.label.cmp(&b.label));

        let root = project_path
            .filter(|path| !path.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.workspace_dir.clone());
        let files = search_files(&root, &query).await?;
        let cloud_suggestions = marketplace_suggestions(&query);

        Ok(MentionSearchResult {
            tools,
            files,
            cloud_suggestions,
        })
    }

    pub async fn record_mention_reference(
        &self,
        reference: serde_json::Value,
    ) -> Result<(), String> {
        let mut memory = self.load_troner_memory().await?;
        memory
            .audit_log
            .push(audit_event("mention.reference", reference));
        self.save_troner_memory(&memory).await
    }

    pub async fn troner_agent_message(
        &self,
        message: String,
        project_path: Option<String>,
    ) -> Result<String, String> {
        let cwd = project_path
            .filter(|path| !path.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.workspace_dir.clone());
        let memory = self
            .get_memory_snapshot(Some(cwd.to_string_lossy().into_owned()))
            .await?;
        let prompt = format!(
            "Memory context:\n{}\n\nUser request:\n{}",
            memory.effective_prompt, message
        );
        let mut troner = self.load_troner_memory().await?;
        troner.audit_log.push(audit_event(
            "agent.hermes.pending",
            serde_json::json!({
                "message": message,
                "project_path": cwd,
            }),
        ));
        self.save_troner_memory(&troner).await?;
        Ok(format!(
            "Hermes Agent integration is pending. The prompt has been prepared for the upcoming gateway layer:\n\n{}",
            prompt
        ))
    }

    async fn load_troner_memory(&self) -> Result<TronerMemory, String> {
        let path = self.workspace_dir.join(".troner.json");
        let raw = tokio::fs::read_to_string(&path)
            .await
            .map_err(|e| e.to_string())?;
        serde_json::from_str(&raw).map_err(|e| e.to_string())
    }

    async fn save_troner_memory(&self, memory: &TronerMemory) -> Result<(), String> {
        let path = self.workspace_dir.join(".troner.json");
        let json = serde_json::to_string_pretty(memory).map_err(|e| e.to_string())?;
        tokio::fs::write(path, json)
            .await
            .map_err(|e| e.to_string())
    }

    async fn set_project_archived(&self, path: String, archived: bool) -> Result<(), String> {
        let project_path = PathBuf::from(&path);
        if !project_path.is_dir() {
            return Err(format!("Project path is not a directory: {path}"));
        }
        let mut memory = self.load_troner_memory().await?;
        let mut project = ensure_project_memory(&mut memory, &path);
        project.archived = archived;
        memory.projects.insert(path.clone(), project);
        memory.audit_log.push(audit_event(
            if archived {
                "project.archive"
            } else {
                "project.restore"
            },
            serde_json::json!({ "path": path }),
        ));
        self.save_troner_memory(&memory).await
    }

    fn workspace_child_dir(&self, path: &str) -> Result<PathBuf, String> {
        let path = self.workspace_child_path(path)?;
        if path.is_dir() {
            Ok(path)
        } else {
            Err(format!("Path is not a directory: {}", path.display()))
        }
    }

    fn workspace_child_path(&self, path: &str) -> Result<PathBuf, String> {
        let path = PathBuf::from(path);
        if path.starts_with(&self.workspace_dir) && path != self.workspace_dir {
            Ok(path)
        } else {
            Err(format!(
                "Refusing to access outside workspace: {}",
                path.display()
            ))
        }
    }
}

fn hermes_binary() -> String {
    std::env::var("SCRIPTRON_HERMES_BIN").unwrap_or_else(|_| "hermes".into())
}

async fn run_hermes_skill_catalog_command(
    args: &[&str],
) -> Result<Vec<HermesSkillCatalogItem>, String> {
    let output = tokio::process::Command::new(hermes_binary())
        .args(args)
        .stdin(Stdio::null())
        .output()
        .await
        .map_err(|e| e.to_string())?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    let mut items: Vec<HermesSkillCatalogItem> = serde_json::from_slice(&output.stdout)
        .or_else(|_| parse_hermes_skill_catalog_text(&String::from_utf8_lossy(&output.stdout)))?;
    for item in &mut items {
        item.source = default_hermes_source();
        if item.install_ref.is_none() {
            item.install_ref = Some(item.name.clone());
        }
    }
    items.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(items)
}

fn parse_hermes_skill_catalog_text(output: &str) -> Result<Vec<HermesSkillCatalogItem>, String> {
    let mut items = Vec::new();
    for line in output.lines() {
        let trimmed = line.trim_start();
        if !trimmed.starts_with('│') {
            continue;
        }
        let columns = trimmed
            .split('│')
            .skip(1)
            .map(|part| part.trim())
            .collect::<Vec<_>>();
        if columns.len() < 4 {
            continue;
        }

        let (name, description, source, trust, install_ref) = if columns
            .first()
            .and_then(|value| value.parse::<usize>().ok())
            .is_some()
        {
            if columns.len() < 5 {
                continue;
            }
            (columns[1], columns[2], columns[3], columns[4], None)
        } else {
            (columns[0], columns[1], columns[2], columns[3], columns.get(4).copied())
        };

        if name.is_empty() || name == "Name" || source.is_empty() {
            continue;
        }

        let trust_level = trust
            .trim_start_matches('★')
            .trim()
            .to_string();
        items.push(HermesSkillCatalogItem {
            name: name.to_string(),
            description: description.to_string(),
            source: default_hermes_source(),
            category: String::new(),
            trust_level,
            installed: false,
            install_ref: Some(
                install_ref
                    .filter(|value| !value.is_empty())
                    .unwrap_or(name)
                    .to_string(),
            ),
            wraps_external_cli: false,
        });
    }

    if items.is_empty() {
        Err("Hermes skill catalog output did not contain parseable items".into())
    } else {
        Ok(items)
    }
}

const RUN_NAME_PREFIX: &str = "[[scriptron:run-name]]";

fn build_hermes_prompt_text(cells: &[TronCell], project_path: &str) -> Result<String, String> {
    let context = cells
        .iter()
        .filter(|cell| !cell.run)
        .map(|cell| cell.content.trim().to_string())
        .filter(|content| !content.is_empty())
        .collect::<Vec<_>>();
    let prompts = cells
        .iter()
        .enumerate()
        .filter(|(_, cell)| cell.run)
        .map(|(index, cell)| parse_run_prompt(&cell.content, index))
        .filter(|(_, body)| !body.trim().is_empty())
        .collect::<Vec<_>>();
    if prompts.is_empty() {
        return Err("No run cells to submit to Hermes.".into());
    }

    let mut out = vec![
        "Hermes Gateway submission prepared.".to_string(),
        format!("Project: {}", project_path),
    ];
    if !context.is_empty() {
        out.push(format!("Context cells:\n{}", context.join("\n\n---\n\n")));
    }
    for (name, body) in prompts {
        out.push(format!("Prompt [{}]:\n{}", name, body));
    }
    Ok(out.join("\n\n"))
}

fn parse_run_prompt(content: &str, index: usize) -> (String, String) {
    let mut lines = content.lines().collect::<Vec<_>>();
    if let Some(first) = lines.first() {
        if first.starts_with(RUN_NAME_PREFIX) {
            let name = first.trim_start_matches(RUN_NAME_PREFIX).trim().to_string();
            lines.remove(0);
            let body = strip_scriptron_metadata(&lines.join("\n"));
            if !name.is_empty() {
                return (name, body);
            }
        }
    }
    (
        content
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .map(|line| line.chars().take(40).collect::<String>())
            .unwrap_or_else(|| format!("run_{}", index + 1)),
        strip_scriptron_metadata(content),
    )
}

fn strip_scriptron_metadata(content: &str) -> String {
    content
        .lines()
        .filter(|line| {
            let trimmed = line.trim_start();
            !trimmed.starts_with("[[scriptron:")
        })
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

fn update_blackboard_notes(blackboard: &mut serde_json::Value, response: &str, source: &str) {
    let summary = summarize_run_note(response);
    if summary.is_empty() {
        return;
    }
    if !blackboard.is_object() {
        *blackboard = serde_json::json!({});
    }
    let Some(obj) = blackboard.as_object_mut() else {
        return;
    };
    let notes = obj
        .entry("notes")
        .or_insert_with(|| serde_json::Value::Array(Vec::new()));
    if !notes.is_array() {
        *notes = serde_json::Value::Array(Vec::new());
    }
    let Some(items) = notes.as_array_mut() else {
        return;
    };
    items.insert(
        0,
        serde_json::json!({
            "id": format!("note-{}", Utc::now().timestamp_millis()),
            "source": source,
            "summary": summary,
            "created_at": now(),
            "tags": ["run"]
        }),
    );
    items.truncate(10);
}

fn run_log_path(tron_path: Option<&str>, project_path: &str) -> PathBuf {
    let root = PathBuf::from(project_path);
    let stem = tron_path
        .and_then(|path| Path::new(path).file_stem())
        .and_then(|stem| stem.to_str())
        .unwrap_or("run");
    root.join(".scriptron").join("run-logs").join(format!(
        "{}-{}.jsonl",
        safe_name(stem),
        Utc::now().timestamp_millis()
    ))
}

async fn write_run_log(path: &Path, events: &[ExecutionEvent]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let mut lines = String::new();
    for event in events {
        let value = serde_json::to_value(event).map_err(|e| e.to_string())?;
        lines.push_str(&serde_json::to_string(&value).map_err(|e| e.to_string())?);
        lines.push('\n');
    }
    tokio::fs::write(path, lines)
        .await
        .map_err(|e| e.to_string())
}

fn summarize_run_note(response: &str) -> String {
    let compact = response
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    compact.chars().take(500).collect::<String>()
}

async fn ensure_workspace_layout(workspace_dir: &Path) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(workspace_dir.join(".register")).await?;
    tokio::fs::create_dir_all(workspace_dir.join(".skills")).await?;
    tokio::fs::create_dir_all(workspace_dir.join(".tronhub")).await?;
    rebuild_skill_index(workspace_dir).await?;

    let troner_path = workspace_dir.join(".troner.json");
    if !troner_path.exists() {
        let default_memory = default_troner_memory();
        tokio::fs::write(troner_path, serde_json::to_string_pretty(&default_memory)?).await?;
    } else {
        let raw = tokio::fs::read_to_string(&troner_path).await?;
        if serde_json::from_str::<TronerMemory>(&raw).is_err() {
            let legacy: serde_json::Value =
                serde_json::from_str(&raw).unwrap_or_else(|_| serde_json::json!({}));
            let mut migrated = default_troner_memory();
            if let Some(notes) = legacy
                .pointer("/agent_memory/notes")
                .and_then(|v| v.as_array())
            {
                migrated.global_memory.notes = notes
                    .iter()
                    .filter_map(|value| value.as_str())
                    .map(|content| MemoryNote {
                        id: format!("note-{}", Utc::now().timestamp_millis()),
                        scope: "global".into(),
                        content: content.into(),
                        source: "legacy-migration".into(),
                        created_at: now(),
                    })
                    .collect();
            }
            tokio::fs::write(troner_path, serde_json::to_string_pretty(&migrated)?).await?;
        }
    }

    Ok(())
}

async fn sync_tronhub_cache(workspace_dir: &Path, runner: &ProcessRunner) -> anyhow::Result<()> {
    let hub_dir = workspace_dir.join(".tronhub");
    let repo_dir = hub_dir.join("ScripTron_Extension");
    tokio::fs::create_dir_all(&hub_dir).await?;
    let args = if repo_dir.join(".git").exists() {
        vec![
            "-C".to_string(),
            repo_dir.to_string_lossy().into_owned(),
            "pull".to_string(),
            "--ff-only".to_string(),
        ]
    } else {
        if repo_dir.exists() {
            tokio::fs::remove_dir_all(&repo_dir).await?;
        }
        vec![
            "clone".to_string(),
            "--depth".to_string(),
            "1".to_string(),
            "https://github.com/WyattZZZZ/ScripTron_Extension".to_string(),
            repo_dir.to_string_lossy().into_owned(),
        ]
    };
    runner
        .run(
            ProcessConfig::new("git", args)
                .with_working_dir(hub_dir)
                .with_timeout(60),
        )
        .await
        .map(|_| ())
        .map_err(|e| anyhow::anyhow!(e.to_string()))
}

async fn list_tronhub_entries(
    workspace_dir: &Path,
    kind: &str,
) -> anyhow::Result<Vec<TronhubEntry>> {
    let source_dir = tronhub_kind_dir(workspace_dir, kind);
    let install_dir = installed_kind_dir(workspace_dir, kind);
    let mut entries = Vec::new();
    if !source_dir.exists() {
        return Ok(entries);
    }
    let mut rd = tokio::fs::read_dir(&source_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        let manifest_json = read_manifest_json(&path).await?;
        let description = manifest_json
            .as_deref()
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(raw).ok())
            .and_then(|json| {
                json.get("description")
                    .and_then(|v| v.as_str())
                    .map(str::to_string)
            })
            .unwrap_or_else(|| format!("TronHub {} package '{}'.", kind, name));
        entries.push(TronhubEntry {
            name: name.clone(),
            kind: normalized_kind(kind).into(),
            description,
            source_path: path.to_string_lossy().into_owned(),
            installed: install_dir.join(&name).exists(),
            manifest_json,
        });
    }
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(entries)
}

async fn install_tronhub_entry(workspace_dir: &Path, kind: &str, name: &str) -> anyhow::Result<()> {
    let source_dir = tronhub_kind_dir(workspace_dir, kind).join(safe_name(name));
    if !source_dir.exists() {
        anyhow::bail!(
            "TronHub {} '{}' was not found. Try syncing TronHub first.",
            kind,
            name
        );
    }
    let target_dir = installed_kind_dir(workspace_dir, kind).join(safe_name(name));
    if target_dir.exists() {
        tokio::fs::remove_dir_all(&target_dir).await?;
    }
    copy_dir_all(&source_dir, &target_dir).await?;
    if kind == "cli" || kind == "model" {
        let manifest = target_dir.join("manifest.json");
        let needs_generate = if manifest.exists() {
            // Regenerate if the stored command is not an executable file.
            let raw = tokio::fs::read_to_string(&manifest)
                .await
                .unwrap_or_default();
            serde_json::from_str::<serde_json::Value>(&raw)
                .ok()
                .and_then(|j| {
                    j.get("command")
                        .and_then(|v| v.as_str())
                        .map(str::to_string)
                })
                .map(|cmd| {
                    let p = std::path::Path::new(&cmd);
                    !p.exists()
                        || p.metadata()
                            .map(|m| {
                                use std::os::unix::fs::PermissionsExt;
                                m.permissions().mode() & 0o111 == 0
                            })
                            .unwrap_or(true)
                })
                .unwrap_or(true)
        } else {
            true
        };
        if needs_generate {
            let generated = generated_cli_manifest(kind, name, &target_dir);
            tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
        }
    } else if kind == "skill" {
        let manifest = target_dir.join("skill.json");
        if !manifest.exists() {
            let generated = serde_json::json!({
                "name": name,
                "description": format!("TronHub skill '{}'.", name),
                "version": "0.1.0"
            });
            tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
        }
    }
    Ok(())
}

async fn list_installed_skills(workspace_dir: &Path) -> anyhow::Result<Vec<SkillEntry>> {
    let skill_dir = workspace_dir.join(".skills");
    let mut skills = Vec::new();
    tokio::fs::create_dir_all(&skill_dir).await?;
    let mut rd = tokio::fs::read_dir(&skill_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        let description = read_skill_description(&path)
            .await?
            .unwrap_or_else(|| format!("Installed TronHub skill '{}'.", name));
        skills.push(SkillEntry {
            name,
            description,
            path: path.to_string_lossy().into_owned(),
        });
    }
    skills.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(skills)
}

async fn rebuild_skill_index(workspace_dir: &Path) -> anyhow::Result<Vec<SkillIndexEntry>> {
    let skill_dir = workspace_dir.join(".skills");
    tokio::fs::create_dir_all(&skill_dir).await?;
    let mut index = Vec::new();
    let mut rd = tokio::fs::read_dir(&skill_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        if let Some(card) = read_skill_index_entry(&path).await? {
            index.push(card);
        }
    }
    index.sort_by(|a, b| a.name.cmp(&b.name));
    tokio::fs::write(
        skill_dir.join("index.json"),
        serde_json::to_string_pretty(&index)?,
    )
    .await?;
    Ok(index)
}

async fn read_skill_index_entry(path: &Path) -> anyhow::Result<Option<SkillIndexEntry>> {
    let manifest = path.join("skill.json");
    if !manifest.exists() {
        return Ok(None);
    }
    let raw = tokio::fs::read_to_string(&manifest).await?;
    let json: serde_json::Value = serde_json::from_str(&raw)?;
    let name = json
        .get("name")
        .and_then(|v| v.as_str())
        .or_else(|| path.file_name().and_then(|v| v.to_str()))
        .unwrap_or_default()
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
    let document = skill_index_document(&name, &description, &required_clis, &capabilities, &tags);
    let tokens = tokenize_skill_index_document(&document);
    Ok(Some(SkillIndexEntry {
        name,
        description,
        path: path.to_string_lossy().into_owned(),
        required_clis,
        capabilities,
        tags,
        document,
        tokens,
    }))
}

async fn install_skill_tool_adapters(workspace_dir: &Path, skill_name: &str) -> anyhow::Result<()> {
    let skill_dir = workspace_dir.join(".skills").join(safe_name(skill_name));
    for folder in ["tools", "clis"] {
        let adapter_root = skill_dir.join(folder);
        if !adapter_root.exists() {
            continue;
        }
        let mut rd = tokio::fs::read_dir(&adapter_root).await?;
        while let Some(entry) = rd.next_entry().await? {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let adapter_name = entry.file_name().to_string_lossy().into_owned();
            let target = workspace_dir
                .join(".register")
                .join(safe_name(&adapter_name));
            if target.exists() {
                tokio::fs::remove_dir_all(&target).await?;
            }
            copy_dir_all(&path, &target).await?;
            let manifest = target.join("manifest.json");
            if !manifest.exists() {
                let generated = generated_cli_manifest("cli", &adapter_name, &target);
                tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
            }
        }
    }
    Ok(())
}

fn skill_index_document(
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

fn tokenize_skill_index_document(text: &str) -> Vec<String> {
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

async fn read_manifest_json(path: &Path) -> anyhow::Result<Option<String>> {
    let manifest = path.join("manifest.json");
    if manifest.exists() {
        Ok(Some(tokio::fs::read_to_string(manifest).await?))
    } else {
        Ok(None)
    }
}

async fn read_skill_description(path: &Path) -> anyhow::Result<Option<String>> {
    let manifest = path.join("skill.json");
    if manifest.exists() {
        let raw = tokio::fs::read_to_string(manifest).await?;
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&raw) {
            return Ok(json
                .get("description")
                .and_then(|v| v.as_str())
                .map(str::to_string));
        }
    }
    Ok(None)
}

fn generated_cli_manifest(kind: &str, name: &str, installed_dir: &Path) -> serde_json::Value {
    // Read the plugin's own metadata file (model.json or cli.json) for the declared command.
    let meta_command = ["model.json", "cli.json"]
        .iter()
        .filter_map(|fname| std::fs::read_to_string(installed_dir.join(fname)).ok())
        .filter_map(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
        .filter_map(|json| {
            json.get("command")
                .and_then(|v| v.as_str())
                .map(str::to_string)
        })
        .next();

    let command = if let Some(rel) = meta_command {
        // Resolve relative paths (e.g. "./run.sh") against the installed directory.
        if rel.starts_with("./") || rel.starts_with("../") {
            installed_dir
                .join(&rel)
                .canonicalize()
                .unwrap_or_else(|_| installed_dir.join(&rel))
                .to_string_lossy()
                .into_owned()
        } else {
            rel
        }
    } else {
        first_child_path(installed_dir)
            .unwrap_or_else(|| installed_dir.join(name))
            .to_string_lossy()
            .into_owned()
    };

    serde_json::json!({
        "name": name,
        "kind": if kind == "model" { "model" } else { "tool" },
        "description": format!("TronHub {} '{}'.", kind, name),
        "version": "0.1.0",
        "command": command,
        "args_schema": [
            { "name": "input", "description": "Input prompt, path, or task payload.", "required": false, "type": "string" }
        ],
        "examples": [
            format!("{} --help", name)
        ]
    })
}

fn first_child_path(dir: &Path) -> Option<PathBuf> {
    std::fs::read_dir(dir)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| path.file_name().and_then(|n| n.to_str()) != Some("manifest.json"))
}

fn tronhub_kind_dir(workspace_dir: &Path, kind: &str) -> PathBuf {
    let folder = match kind {
        "skill" | "skills" => "skills",
        "model" | "models" => "models",
        _ => "clis",
    };
    workspace_dir
        .join(".tronhub")
        .join("ScripTron_Extension")
        .join(folder)
}

fn installed_kind_dir(workspace_dir: &Path, kind: &str) -> PathBuf {
    match kind {
        "skill" | "skills" => workspace_dir.join(".skills"),
        _ => workspace_dir.join(".register"),
    }
}

fn plugin_runtime_path() -> String {
    let base = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    match std::env::var("PATH") {
        Ok(existing) if !existing.is_empty() => format!("{base}:{existing}"),
        _ => base.to_string(),
    }
}

fn normalized_kind(kind: &str) -> &'static str {
    match kind {
        "skill" | "skills" => "skill",
        "model" | "models" => "model",
        _ => "cli",
    }
}

fn safe_name(name: &str) -> String {
    name.trim().replace(['/', ':', '\\'], "-")
}

fn default_troner_memory() -> TronerMemory {
    TronerMemory {
        schema_version: 1,
        global_memory: GlobalMemory {
            user_name_preference: String::new(),
            agent_style_preference:
                "Concise, direct, Chinese by default unless the user asks otherwise.".into(),
            execution_rules: vec![
                "Preview risky writes before execution.".into(),
                "Prefer project-local changes and avoid touching unrelated files.".into(),
            ],
            notes: Vec::new(),
        },
        projects: BTreeMap::new(),
        register: RegisterInfo {
            path: ".register".into(),
            description: "Workspace-local registry for model CLIs and tool/software CLIs.".into(),
        },
        audit_log: Vec::new(),
    }
}

fn ensure_project_memory(memory: &mut TronerMemory, project_path: &str) -> ProjectMemory {
    let key = project_path.to_string();
    memory
        .projects
        .entry(key.clone())
        .or_insert_with(|| ProjectMemory {
            project_name: Path::new(project_path)
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default(),
            project_path: key.clone(),
            archived: false,
            format_rules: Vec::new(),
            task_constraints: Vec::new(),
            glossary: BTreeMap::new(),
            long_context: Vec::new(),
        })
        .clone()
}

fn build_effective_memory_prompt(global: &GlobalMemory, project: &ProjectMemory) -> String {
    format!(
        "Global style: {}\nUser name preference: {}\nExecution rules:\n{}\nProject: {}\nFormat rules:\n{}\nTask constraints:\n{}",
        global.agent_style_preference,
        empty_dash(&global.user_name_preference),
        bullet_lines(&global.execution_rules),
        empty_dash(&project.project_name),
        bullet_lines(&project.format_rules),
        bullet_lines(&project.task_constraints),
    )
}

fn bullet_lines(items: &[String]) -> String {
    if items.is_empty() {
        "  -".into()
    } else {
        items
            .iter()
            .map(|item| format!("  - {item}"))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

fn empty_dash(value: &str) -> String {
    if value.trim().is_empty() {
        "-".into()
    } else {
        value.into()
    }
}

fn audit_event(event: &str, payload: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "event": event,
        "payload": payload,
        "created_at": now(),
    })
}

fn now() -> String {
    Utc::now().to_rfc3339()
}

async fn migrate_legacy_registry(
    legacy_registry_dir: &Path,
    registry_dir: &Path,
) -> anyhow::Result<()> {
    if !legacy_registry_dir.exists() || registry_has_entries(registry_dir).await? {
        return Ok(());
    }

    tokio::fs::create_dir_all(registry_dir).await?;
    let mut entries = tokio::fs::read_dir(legacy_registry_dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        let source = entry.path();
        if !source.is_dir() {
            continue;
        }
        let target = registry_dir.join(entry.file_name());
        if !target.exists() {
            copy_dir_all(&source, &target).await?;
        }
    }

    Ok(())
}

async fn registry_has_entries(registry_dir: &Path) -> anyhow::Result<bool> {
    if !registry_dir.exists() {
        return Ok(false);
    }
    let mut entries = tokio::fs::read_dir(registry_dir).await?;
    Ok(entries.next_entry().await?.is_some())
}

async fn copy_dir_all(source: &Path, target: &Path) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(target).await?;
    let mut entries = tokio::fs::read_dir(source).await?;
    while let Some(entry) = entries.next_entry().await? {
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        if source_path.is_dir() {
            Box::pin(copy_dir_all(&source_path, &target_path)).await?;
        } else {
            tokio::fs::copy(&source_path, &target_path).await?;
        }
    }
    Ok(())
}

async fn search_files(root: &Path, query: &str) -> Result<Vec<MentionItem>, String> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];

    while let Some(dir) = stack.pop() {
        let mut rd = match tokio::fs::read_dir(&dir).await {
            Ok(rd) => rd,
            Err(_) => continue,
        };
        while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            let path_text = path.to_string_lossy().into_owned();
            if !query.is_empty()
                && !name.to_lowercase().contains(query)
                && !path_text.to_lowercase().contains(query)
            {
                continue;
            }
            let is_tron = path.extension().map(|ext| ext == "tron").unwrap_or(false);
            let modules = if is_tron {
                tron_modules(&path).unwrap_or_default()
            } else {
                Vec::new()
            };
            out.push(MentionItem {
                id: format!("file:{path_text}"),
                label: name,
                kind: if is_tron {
                    "tron".into()
                } else {
                    "file".into()
                },
                path: path_text,
                detail: path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .into_owned(),
                installed: true,
                modules,
            });
            if out.len() >= 80 {
                return Ok(out);
            }
        }
    }
    out.sort_by(|a, b| a.label.cmp(&b.label));
    Ok(out)
}

fn tron_modules(path: &Path) -> Result<Vec<TronMentionModule>, String> {
    let parsed = tron_parser::parse_file(path).map_err(|e| e.to_string())?;
    let mut modules = Vec::new();
    for (index, cell) in parsed.cells.iter().enumerate() {
        if cell.run {
            let name = first_nonempty_line(&cell.content)
                .map(clean_heading)
                .filter(|line| !line.is_empty())
                .unwrap_or_else(|| format!("run_{}", index + 1));
            modules.push(TronMentionModule {
                name,
                kind: "executable".into(),
                injection: "function_call".into(),
            });
        } else {
            for line in cell.content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') {
                    let name = clean_heading(trimmed);
                    if !name.is_empty() {
                        modules.push(TronMentionModule {
                            name,
                            kind: "text".into(),
                            injection: "prompt_injection".into(),
                        });
                    }
                }
            }
        }
    }
    Ok(modules)
}

fn first_nonempty_line(content: &str) -> Option<&str> {
    content.lines().map(str::trim).find(|line| !line.is_empty())
}

fn clean_heading(line: &str) -> String {
    line.trim_start_matches('#')
        .trim()
        .trim_matches(':')
        .to_string()
}

fn marketplace_suggestions(query: &str) -> Vec<MentionItem> {
    if query.len() < 2 {
        return Vec::new();
    }
    ["pdf-cli", "excel-cli", "archive-cli", "hr-report-cli"]
        .iter()
        .filter(|name| name.contains(query))
        .map(|name| MentionItem {
            id: format!("cloud:{name}"),
            label: (*name).into(),
            kind: "cloud".into(),
            path: format!("marketplace://{name}"),
            detail: "Available from cloud plugin registry".into(),
            installed: false,
            modules: Vec::new(),
        })
        .collect()
}

async fn list_dir(dir: PathBuf) -> Result<Vec<FileEntry>, String> {
    let mut rd = tokio::fs::read_dir(dir).await.map_err(|e| e.to_string())?;
    let mut entries = Vec::new();
    while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let is_dir = path.is_dir();
        let is_tron = path.extension().map(|e| e == "tron").unwrap_or(false);
        entries.push(FileEntry {
            name,
            path: path.to_string_lossy().into_owned(),
            is_dir,
            is_tron,
        });
    }
    entries.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));
    Ok(entries)
}

fn file_entry(path: PathBuf) -> FileEntry {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let is_dir = path.is_dir();
    let is_tron = path.extension().map(|e| e == "tron").unwrap_or(false);
    FileEntry {
        name,
        path: path.to_string_lossy().into_owned(),
        is_dir,
        is_tron,
    }
}

fn copy_path_recursive(source: &Path, destination: &Path) -> Result<(), String> {
    if source.is_dir() {
        std::fs::create_dir_all(destination).map_err(|e| e.to_string())?;
        for entry in std::fs::read_dir(source).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let child_source = entry.path();
            let child_destination = destination.join(entry.file_name());
            copy_path_recursive(&child_source, &child_destination)?;
        }
        return Ok(());
    }

    if source.is_file() {
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::copy(source, destination).map_err(|e| e.to_string())?;
        return Ok(());
    }

    Err(format!("Path does not exist: {}", source.display()))
}

fn default_active_config() -> ActiveConfig {
    ActiveConfig {
        provider: "hermes".into(),
        model: "Hermes managed".into(),
    }
}

fn sanitized_project_directory_name(name: &str) -> String {
    let lower = name.trim().replace(' ', "-").to_lowercase();
    let mut out = String::with_capacity(lower.len());
    let mut last_dash = false;
    for ch in lower.chars() {
        let safe = if ch.is_ascii_alphanumeric() || ch == '_' {
            Some(ch)
        } else if ch == '-' || ch == '/' || ch == ':' || ch == '\\' {
            Some('-')
        } else {
            None
        };
        match safe {
            Some('-') if !last_dash => {
                out.push('-');
                last_dash = true;
            }
            Some('-') => {}
            Some(ch) => {
                out.push(ch);
                last_dash = false;
            }
            None => {}
        }
    }
    out.trim_matches('-').to_string()
}

fn sanitized_file_name(name: &str) -> Option<String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return None;
    }
    let mut out = String::with_capacity(trimmed.len());
    let mut last_dash = false;
    for ch in trimmed.chars() {
        let safe = if ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' {
            Some(ch)
        } else if ch == '-' || ch == ' ' || ch == '/' || ch == ':' || ch == '\\' {
            Some('-')
        } else {
            None
        };
        match safe {
            Some('-') if !last_dash => {
                out.push('-');
                last_dash = true;
            }
            Some('-') => {}
            Some(ch) => {
                out.push(ch);
                last_dash = false;
            }
            None => {}
        }
    }
    let cleaned = out.trim_matches('-').to_string();
    if cleaned.is_empty() {
        None
    } else {
        Some(cleaned)
    }
}

fn unique_child_path(parent: &Path, child_name: &str) -> PathBuf {
    let original = parent.join(child_name);
    if !original.exists() {
        return original;
    }
    for suffix in 2..=999 {
        let candidate = parent.join(format!("{child_name}-{suffix}"));
        if !candidate.exists() {
            return candidate;
        }
    }
    parent.join(format!("{}-{}", child_name, Utc::now().timestamp_millis()))
}

fn starter_tron_content(project_name: &str) -> String {
    format!(
        r#"---blackboard---
{{
  "entries": [],
  "notes": []
}}
---

---run: false---
# {project_name}

Describe the project context, source material, and constraints here.
---

---run: true---
[[scriptron:run-name]] first-run

Summarize the project goal and suggest the next concrete step.
---
"#
    )
}
