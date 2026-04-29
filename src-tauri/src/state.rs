use agent_loop::{AgentLoop, AnthropicProvider, GeminiProvider, OpenAiCompatProvider};
use auth::{AppConfig, AuthManager, Provider};
use cli_registry::CliRegistry;
use std::{path::PathBuf, sync::Arc};
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
        let registry_dir = data_dir.join("registry");
        let auth_dir = data_dir.join("credentials");
        let config_path = data_dir.join("config.json");
        let workspace_dir = home.join("ScripTron");

        tokio::fs::create_dir_all(&workspace_dir).await?;
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
        new_config.save(&self.config_path).map_err(|e| e.to_string())?;
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
            Provider::Gemini => {
                Arc::new(GeminiProvider::new(token).with_model(model.clone()))
            }
            Provider::OpenAi => {
                Arc::new(OpenAiCompatProvider::new_openai(token, model.clone()))
            }
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
