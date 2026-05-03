mod keychain;
mod pkce;

pub use pkce::PkceFlow;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Keychain error: {0}")]
    Keychain(String),
    #[error("Network error: {0}")]
    Network(String),
    #[error("OAuth error: {code} — {description}")]
    OAuth { code: String, description: String },
    #[error("No credentials found for provider '{0}'")]
    NoCreds(String),
}

// ── Provider enum ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Anthropic,
    Gemini,
    OpenAi,
    DeepSeek,
    OpenRouter,
}

/// How a provider authenticates.
#[derive(Debug, Clone, PartialEq)]
pub enum AuthMethod {
    /// Full PKCE browser flow.
    Oauth(OAuthConfig),
    /// User pastes an API key.
    ApiKey,
    /// OpenRouter's simplified callback flow (not standard PKCE).
    OpenRouterOAuth,
}

/// OAuth parameters for PKCE providers.
#[derive(Debug, Clone, PartialEq)]
pub struct OAuthConfig {
    pub auth_url: &'static str,
    pub token_url: &'static str,
    /// Bundled client_id (non-confidential for desktop PKCE apps).
    pub client_id: &'static str,
    pub client_secret: Option<&'static str>,
    pub scopes: &'static [&'static str],
}

impl Provider {
    pub fn id(&self) -> &'static str {
        match self {
            Provider::Anthropic => "anthropic",
            Provider::Gemini => "gemini",
            Provider::OpenAi => "openai",
            Provider::DeepSeek => "deepseek",
            Provider::OpenRouter => "openrouter",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Provider::Anthropic => "Claude (Anthropic)",
            Provider::Gemini => "Gemini (Google)",
            Provider::OpenAi => "GPT / Codex (OpenAI)",
            Provider::DeepSeek => "DeepSeek",
            Provider::OpenRouter => "OpenRouter",
        }
    }

    pub fn auth_method(&self) -> AuthMethod {
        match self {
            Provider::Gemini => AuthMethod::Oauth(OAuthConfig {
                auth_url: "https://accounts.google.com/o/oauth2/v2/auth",
                token_url: "https://oauth2.googleapis.com/token",
                // Replace with a real desktop OAuth client_id registered in Google Cloud Console.
                // Desktop OAuth client_ids are non-confidential per Google's documentation.
                client_id: "REPLACE_WITH_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
                client_secret: None,
                scopes: &["https://www.googleapis.com/auth/generative-language"],
            }),
            Provider::OpenRouter => AuthMethod::OpenRouterOAuth,
            _ => AuthMethod::ApiKey,
        }
    }

    pub fn available_models(&self) -> Vec<&'static str> {
        match self {
            Provider::Anthropic => vec![
                "claude-opus-4-7",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001",
            ],
            Provider::Gemini => vec![
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "gemini-1.5-pro",
            ],
            Provider::OpenAi => vec!["gpt-4o", "gpt-4.1", "o3", "o4-mini"],
            Provider::DeepSeek => vec!["deepseek-chat", "deepseek-reasoner"],
            Provider::OpenRouter => vec![
                "anthropic/claude-opus-4-7",
                "google/gemini-2.5-pro",
                "openai/gpt-4o",
                "deepseek/deepseek-chat",
                "meta-llama/llama-3.3-70b-instruct",
                "mistralai/mistral-large",
            ],
        }
    }

    pub fn default_model(&self) -> &'static str {
        self.available_models()[0]
    }

    pub fn from_id(id: &str) -> Option<Self> {
        match id {
            "anthropic" => Some(Provider::Anthropic),
            "gemini" => Some(Provider::Gemini),
            "openai" => Some(Provider::OpenAi),
            "deepseek" => Some(Provider::DeepSeek),
            "openrouter" => Some(Provider::OpenRouter),
            _ => None,
        }
    }

    pub fn all() -> &'static [Provider] {
        &[
            Provider::Anthropic,
            Provider::Gemini,
            Provider::OpenAi,
            Provider::DeepSeek,
            Provider::OpenRouter,
        ]
    }
}

// ── Credentials ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Credentials {
    pub access_token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    /// Unix ms when the access_token expires (None = never / API key).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<i64>,
}

impl Credentials {
    pub fn is_expired(&self) -> bool {
        if let Some(exp) = self.expires_at {
            Utc::now().timestamp_millis() >= exp - 60_000
        } else {
            false
        }
    }

    pub fn from_api_key(key: String) -> Self {
        Self {
            access_token: key,
            refresh_token: None,
            expires_at: None,
        }
    }
}

// ── Persistent app config ─────────────────────────────────────────────────────

/// User-selected active provider + model, persisted to ~/.scriptron/config.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub active_provider: Provider,
    pub active_model: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            active_provider: Provider::Anthropic,
            active_model: Provider::Anthropic.default_model().into(),
        }
    }
}

impl AppConfig {
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> Result<(), AuthError> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(self)?;
        std::fs::write(path, json)?;
        Ok(())
    }
}

// ── Claude Code credential reuse ──────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ClaudeCodeFile {
    #[serde(rename = "claudeAiOauth")]
    claude_ai_oauth: Option<ClaudeCodeOauth>,
}

#[derive(Debug, Deserialize)]
struct ClaudeCodeOauth {
    #[serde(rename = "accessToken")]
    access_token: String,
    #[serde(rename = "refreshToken")]
    refresh_token: Option<String>,
    #[serde(rename = "expiresAt")]
    expires_at: Option<i64>,
}

// ── AuthManager ───────────────────────────────────────────────────────────────

pub struct AuthManager {
    storage_dir: PathBuf,
}

impl AuthManager {
    pub fn new(storage_dir: impl Into<PathBuf>) -> Self {
        Self {
            storage_dir: storage_dir.into(),
        }
    }

    /// Read Claude Code tokens from ~/.claude/.credentials.json (zero-friction reuse).
    pub fn load_claude_code_credentials() -> Option<Credentials> {
        let home = std::env::var("HOME").ok().map(PathBuf::from)?;
        let path = home.join(".claude").join(".credentials.json");
        let raw = std::fs::read_to_string(path).ok()?;
        let parsed: ClaudeCodeFile = serde_json::from_str(&raw).ok()?;
        let oauth = parsed.claude_ai_oauth?;
        Some(Credentials {
            access_token: oauth.access_token,
            refresh_token: oauth.refresh_token,
            expires_at: oauth.expires_at,
        })
    }

    pub async fn load(&self, provider: &Provider) -> Option<Credentials> {
        if *provider == Provider::Anthropic {
            if let Some(c) = Self::load_claude_code_credentials() {
                return Some(c);
            }
        }
        keychain::load(provider, &self.storage_dir).ok().flatten()
    }

    pub async fn store(&self, provider: &Provider, creds: &Credentials) -> Result<(), AuthError> {
        keychain::store(provider, creds, &self.storage_dir)
    }

    pub async fn delete(&self, provider: &Provider) -> Result<(), AuthError> {
        keychain::delete(provider, &self.storage_dir)
    }

    pub async fn access_token(&self, provider: &Provider) -> Result<String, AuthError> {
        let creds = self
            .load(provider)
            .await
            .ok_or_else(|| AuthError::NoCreds(provider.id().into()))?;
        Ok(creds.access_token)
    }

    /// Run the OpenRouter simplified OAuth flow.
    /// Opens browser → catches redirect → GET /api/v1/auth/keys?code=CODE → returns API key.
    pub async fn openrouter_oauth(&self) -> Result<Credentials, AuthError> {
        use std::net::TcpListener;
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        use tokio::net::TcpListener as TokioListener;

        let port = {
            let l = TcpListener::bind("127.0.0.1:0").map_err(AuthError::Io)?;
            l.local_addr().map_err(AuthError::Io)?.port()
        };

        let callback = format!("http://127.0.0.1:{}/callback", port);
        let auth_url = format!(
            "https://openrouter.ai/auth?callback_url={}",
            urlencoding_encode(&callback)
        );

        let open_cmd = if cfg!(target_os = "macos") {
            "open"
        } else {
            "xdg-open"
        };
        tokio::process::Command::new(open_cmd)
            .arg(&auth_url)
            .spawn()
            .map_err(AuthError::Io)?;

        // Wait for the redirect
        let listener = TokioListener::bind(format!("127.0.0.1:{}", port))
            .await
            .map_err(AuthError::Io)?;
        let (mut stream, _) = listener.accept().await.map_err(AuthError::Io)?;

        let mut req = String::new();
        let mut buf = [0u8; 4096];
        loop {
            let n = stream.read(&mut buf).await.map_err(AuthError::Io)?;
            if n == 0 {
                break;
            }
            req.push_str(&String::from_utf8_lossy(&buf[..n]));
            if req.contains("\r\n\r\n") {
                break;
            }
        }

        let query = req
            .lines()
            .next()
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|p| p.split_once('?').map(|(_, q)| q))
            .unwrap_or("");

        let code = url::form_urlencoded::parse(query.as_bytes())
            .find(|(k, _)| k == "code")
            .map(|(_, v)| v.into_owned())
            .ok_or_else(|| AuthError::OAuth {
                code: "no_code".into(),
                description: "OpenRouter did not return a code".into(),
            })?;

        let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\
            <html><body style='font-family:sans-serif;text-align:center;padding:60px;background:#1a1a1a;color:#e0e0e0'>\
            <h2>Connected to OpenRouter!</h2><p>You can close this tab.</p></body></html>";
        let _ = stream.write_all(html.as_bytes()).await;

        // Exchange code for API key
        let client = reqwest::Client::new();
        let resp = client
            .get(format!(
                "https://openrouter.ai/api/v1/auth/keys?code={}",
                code
            ))
            .header("content-type", "application/json")
            .send()
            .await
            .map_err(|e| AuthError::Network(e.to_string()))?;

        let json: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| AuthError::Network(e.to_string()))?;

        let key = json["key"]
            .as_str()
            .ok_or_else(|| AuthError::OAuth {
                code: "no_key".into(),
                description: json.to_string(),
            })?
            .to_string();

        Ok(Credentials::from_api_key(key))
    }
}

fn urlencoding_encode(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

// ── Provider status (for UI) ──────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderStatus {
    pub provider: String,
    pub display_name: String,
    pub connected: bool,
    pub auth_method: String,
    pub available_models: Vec<String>,
    pub default_model: String,
}

pub async fn all_provider_statuses(manager: &AuthManager) -> Vec<ProviderStatus> {
    let mut out = Vec::new();
    for p in Provider::all() {
        let connected = manager.load(p).await.is_some();
        let method = match p.auth_method() {
            AuthMethod::Oauth(_) => "oauth",
            AuthMethod::OpenRouterOAuth => "openrouter_oauth",
            AuthMethod::ApiKey => "api_key",
        };
        out.push(ProviderStatus {
            provider: p.id().into(),
            display_name: p.display_name().into(),
            connected,
            auth_method: method.into(),
            available_models: p.available_models().iter().map(|s| s.to_string()).collect(),
            default_model: p.default_model().into(),
        });
    }
    out
}
