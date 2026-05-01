use auth::{all_provider_statuses, AppConfig, AuthManager, Credentials, Provider, ProviderStatus};
use cli_registry::{CliRegistry, ToolManifest};
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, sync::Arc};
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

#[derive(Debug, Serialize, Deserialize)]
pub struct ActiveConfig {
    pub provider: String,
    pub model: String,
}

pub struct ScriptronCore {
    registry: Arc<RwLock<CliRegistry>>,
    auth: Arc<AuthManager>,
    workspace_dir: PathBuf,
    config: Arc<RwLock<AppConfig>>,
    config_path: PathBuf,
}

impl ScriptronCore {
    pub async fn init() -> anyhow::Result<Self> {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."));

        let data_dir = home.join(".scriptron");
        let registry_dir = data_dir.join("registry");
        let auth_dir = data_dir.join("credentials");
        let config_path = data_dir.join("config.json");
        let workspace_dir = home.join("ScripTron");

        tokio::fs::create_dir_all(&workspace_dir).await?;
        tokio::fs::create_dir_all(&auth_dir).await?;

        Ok(Self {
            registry: Arc::new(RwLock::new(CliRegistry::load(&registry_dir).await?)),
            auth: Arc::new(AuthManager::new(auth_dir)),
            workspace_dir,
            config: Arc::new(RwLock::new(AppConfig::load(&config_path))),
            config_path,
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
        tokio::fs::write(path, content).await.map_err(|e| e.to_string())
    }

    pub async fn create_tron_file(&self, path: String) -> Result<TronFileDto, String> {
        let cells = vec![TronCell { run: true, content: String::new() }];
        let blackboard = serde_json::json!({ "entries": [], "notes": [] });
        let content = tron_parser::serialize_with_blackboard(&cells, &blackboard);
        tokio::fs::write(&path, &content).await.map_err(|e| e.to_string())?;
        Ok(TronFileDto { path, cells, blackboard })
    }

    pub async fn list_tools(&self) -> Vec<ToolManifest> {
        self.registry.read().await.list_tools().to_vec()
    }

    pub async fn install_tool_from_json(&self, manifest_json: String) -> Result<(), String> {
        let manifest: ToolManifest = serde_json::from_str(&manifest_json).map_err(|e| e.to_string())?;
        self.registry.write().await.install_tool(manifest).await.map_err(|e| e.to_string())
    }

    pub async fn remove_tool(&self, name: String) -> Result<(), String> {
        self.registry.write().await.remove_tool(&name).await.map_err(|e| e.to_string())
    }

    pub async fn get_auth_status(&self) -> Vec<ProviderStatus> {
        all_provider_statuses(&self.auth).await
    }

    pub async fn store_api_key(&self, provider: String, api_key: String) -> Result<(), String> {
        let p = parse_provider(&provider)?;
        self.auth
            .store(&p, &Credentials::from_api_key(api_key))
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn disconnect_provider(&self, provider: String) -> Result<(), String> {
        let p = parse_provider(&provider)?;
        self.auth.delete(&p).await.map_err(|e| e.to_string())
    }

    pub async fn get_active_config(&self) -> ActiveConfig {
        let cfg = self.config.read().await.clone();
        ActiveConfig {
            provider: cfg.active_provider.id().into(),
            model: cfg.active_model,
        }
    }

    pub async fn set_active_config(&self, provider: String, model: String) -> Result<(), String> {
        let active_provider = parse_provider(&provider)?;
        let cfg = AppConfig { active_provider, active_model: model };
        cfg.save(&self.config_path).map_err(|e| e.to_string())?;
        *self.config.write().await = cfg;
        Ok(())
    }

    pub async fn build_task(&self, cells: Vec<TronCell>, project_path: String) -> serde_json::Value {
        let file = TronFile {
            path: PathBuf::from("task.tron"),
            cells,
            blackboard: serde_json::json!({}),
        };
        serde_json::to_value(file.build_task(PathBuf::from(project_path))).unwrap_or_else(|_| serde_json::json!({}))
    }
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

fn parse_provider(s: &str) -> Result<Provider, String> {
    Provider::from_id(s).ok_or_else(|| format!("Unknown provider: {}", s))
}

