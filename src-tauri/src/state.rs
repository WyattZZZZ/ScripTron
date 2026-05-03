use agent_loop::{AgentLoop, AnthropicProvider, GeminiProvider, OpenAiCompatProvider};
use auth::{AppConfig, AuthManager, Provider};
use cli_registry::CliRegistry;
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};
use tokio::sync::RwLock;

pub struct AppState {
    pub registry: Arc<RwLock<CliRegistry>>,
    pub auth: Arc<AuthManager>,
    pub registry_dir: PathBuf,
    pub workspace_dir: PathBuf,
    pub config: Arc<RwLock<AppConfig>>,
    pub config_path: PathBuf,
}

impl AppState {
    pub async fn init() -> anyhow::Result<Self> {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."));

        let data_dir = home.join(".scriptron");
        let legacy_registry_dir = data_dir.join("registry");
        let auth_dir = data_dir.join("credentials");
        let config_path = data_dir.join("config.json");
        let workspace_dir = home.join("ScripTron");
        let registry_dir = workspace_dir.join(".register");

        tokio::fs::create_dir_all(&workspace_dir).await?;
        ensure_workspace_layout(&workspace_dir).await?;
        migrate_legacy_registry(&legacy_registry_dir, &registry_dir).await?;
        tokio::fs::create_dir_all(&auth_dir).await?;

        let registry = CliRegistry::load(&registry_dir).await?;
        let auth = AuthManager::new(auth_dir);
        let config = AppConfig::load(&config_path);

        Ok(Self {
            registry: Arc::new(RwLock::new(registry)),
            auth: Arc::new(auth),
            registry_dir,
            workspace_dir,
            config: Arc::new(RwLock::new(config)),
            config_path,
        })
    }

    pub async fn get_config(&self) -> AppConfig {
        self.config.read().await.clone()
    }

    pub async fn set_config(&self, new_config: AppConfig) -> Result<(), String> {
        new_config
            .save(&self.config_path)
            .map_err(|e| e.to_string())?;
        *self.config.write().await = new_config;
        Ok(())
    }

    /// Build an AgentLoop for the currently active provider + model.
    pub async fn build_agent_loop(&self) -> Result<AgentLoop, String> {
        let cfg = self.config.read().await.clone();
        let provider = &cfg.active_provider;
        let model = &cfg.active_model;

        let token = self
            .auth
            .access_token(provider)
            .await
            .map_err(|e| e.to_string())?;

        let llm: Arc<dyn agent_loop::LlmProvider + Send + Sync> = match provider {
            Provider::Anthropic => {
                Arc::new(AnthropicProvider::new(token).with_model(model.clone()))
            }
            Provider::Gemini => Arc::new(GeminiProvider::new(token).with_model(model.clone())),
            Provider::OpenAi => Arc::new(OpenAiCompatProvider::new_openai(token, model.clone())),
            Provider::DeepSeek => {
                Arc::new(OpenAiCompatProvider::new_deepseek(token, model.clone()))
            }
            Provider::OpenRouter => {
                Arc::new(OpenAiCompatProvider::new_openrouter(token, model.clone()))
            }
        };

        Ok(AgentLoop::new(llm, Arc::clone(&self.registry)))
    }
}

async fn ensure_workspace_layout(workspace_dir: &Path) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(workspace_dir.join(".register")).await?;

    let troner_path = workspace_dir.join(".troner.json");
    if !troner_path.exists() {
        let default_memory = serde_json::json!({
            "schema_version": 1,
            "agent_memory": {
                "global": [],
                "projects": {},
                "notes": []
            },
            "register": {
                "path": ".register",
                "description": "Workspace-local registry for model CLIs and tool/software CLIs."
            }
        });
        tokio::fs::write(troner_path, serde_json::to_string_pretty(&default_memory)?).await?;
    }

    Ok(())
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
