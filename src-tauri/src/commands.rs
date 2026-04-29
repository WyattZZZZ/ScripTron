use crate::state::AppState;
use agent_loop::ExecutionEvent;
use auth::{all_provider_statuses, AppConfig, Credentials, Provider, ProviderStatus};
use cli_registry::ToolManifest;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tauri::State;
use tokio::sync::mpsc;
use tron_parser::{TronCell, TronFile};

// ── File operations ───────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct TronFileDto {
    pub path: String,
    pub cells: Vec<TronCell>,
}

#[tauri::command]
pub async fn open_tron_file(path: String) -> Result<TronFileDto, String> {
    tron_parser::parse_file(&path)
        .map(|f| TronFileDto {
            path: f.path.to_string_lossy().into_owned(),
            cells: f.cells,
        })
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn save_tron_file(path: String, cells: Vec<TronCell>) -> Result<(), String> {
    let content = tron_parser::serialize(&cells);
    tokio::fs::write(&path, content).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn create_tron_file(path: String) -> Result<TronFileDto, String> {
    let cells = vec![TronCell { run: true, content: String::new() }];
    let content = tron_parser::serialize(&cells);
    tokio::fs::write(&path, &content).await.map_err(|e| e.to_string())?;
    Ok(TronFileDto { path, cells })
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_tron: bool,
}

#[tauri::command]
pub async fn list_workspace_files(state: State<'_, AppState>) -> Result<Vec<FileEntry>, String> {
    list_dir(&state.workspace_dir).await
}

#[tauri::command]
pub async fn list_dir_files(path: String) -> Result<Vec<FileEntry>, String> {
    list_dir(PathBuf::from(path)).await
}

async fn list_dir(dir: impl AsRef<std::path::Path>) -> Result<Vec<FileEntry>, String> {
    let mut rd = tokio::fs::read_dir(dir).await.map_err(|e| e.to_string())?;
    let mut entries = Vec::new();
    while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') { continue; }
        let is_dir = path.is_dir();
        let is_tron = path.extension().map(|e| e == "tron").unwrap_or(false);
        entries.push(FileEntry { name, path: path.to_string_lossy().into_owned(), is_dir, is_tron });
    }
    entries.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));
    Ok(entries)
}

#[tauri::command]
pub async fn get_workspace_path(state: State<'_, AppState>) -> Result<String, String> {
    Ok(state.workspace_dir.to_string_lossy().into_owned())
}

// ── Agent execution ───────────────────────────────────────────────────────────

#[tauri::command]
pub async fn run_task(
    window: tauri::Window,
    state: State<'_, AppState>,
    cells: Vec<TronCell>,
    project_path: String,
) -> Result<(), String> {
    let agent = state.build_agent_loop().await?;

    let fake_file = TronFile {
        path: PathBuf::from("task.tron"),
        cells,
    };
    let task = fake_file.build_task(PathBuf::from(&project_path));

    let (tx, mut rx) = mpsc::channel::<ExecutionEvent>(64);

    let win = window.clone();
    tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            let _ = win.emit("execution-event", &event);
        }
    });

    agent.run(task, tx).await.map_err(|e| e.to_string())
}

// ── CLI Registry ──────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn list_tools(state: State<'_, AppState>) -> Result<Vec<ToolManifest>, String> {
    let reg = state.registry.read().await;
    Ok(reg.list_tools().to_vec())
}

#[tauri::command]
pub async fn install_tool_from_json(
    state: State<'_, AppState>,
    manifest_json: String,
) -> Result<(), String> {
    let manifest: ToolManifest = serde_json::from_str(&manifest_json).map_err(|e| e.to_string())?;
    let mut reg = state.registry.write().await;
    reg.install_tool(manifest).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn remove_tool(state: State<'_, AppState>, name: String) -> Result<(), String> {
    let mut reg = state.registry.write().await;
    reg.remove_tool(&name).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn install_tool_from_path(
    state: State<'_, AppState>,
    manifest_path: String,
) -> Result<(), String> {
    let mut reg = state.registry.write().await;
    cli_registry::install_from_path(&mut reg, &manifest_path)
        .await
        .map_err(|e| e.to_string())
}

// ── Authentication ────────────────────────────────────────────────────────────

#[tauri::command]
pub async fn get_auth_status(state: State<'_, AppState>) -> Result<Vec<ProviderStatus>, String> {
    Ok(all_provider_statuses(&state.auth).await)
}

#[tauri::command]
pub async fn store_api_key(
    state: State<'_, AppState>,
    provider: String,
    api_key: String,
) -> Result<(), String> {
    let p = parse_provider(&provider)?;
    let creds = Credentials::from_api_key(api_key);
    state.auth.store(&p, &creds).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn disconnect_provider(
    state: State<'_, AppState>,
    provider: String,
) -> Result<(), String> {
    let p = parse_provider(&provider)?;
    state.auth.delete(&p).await.map_err(|e| e.to_string())
}

/// Start a PKCE OAuth flow for providers that support it (Gemini).
/// Opens the browser and waits for the redirect — may take 30-120 seconds.
#[tauri::command]
pub async fn start_oauth_flow(
    state: State<'_, AppState>,
    provider: String,
) -> Result<(), String> {
    let p = parse_provider(&provider)?;

    match p.auth_method() {
        auth::AuthMethod::Oauth(cfg) => {
            let flow = auth::PkceFlow {
                auth_url: cfg.auth_url.to_string(),
                token_url: cfg.token_url.to_string(),
                client_id: cfg.client_id.to_string(),
                client_secret: cfg.client_secret.map(str::to_string),
                scopes: cfg.scopes.iter().map(|s| s.to_string()).collect(),
            };
            let creds = flow.run().await.map_err(|e| e.to_string())?;
            state.auth.store(&p, &creds).await.map_err(|e| e.to_string())
        }
        auth::AuthMethod::OpenRouterOAuth => {
            let creds = state.auth.openrouter_oauth().await.map_err(|e| e.to_string())?;
            state.auth.store(&p, &creds).await.map_err(|e| e.to_string())
        }
        auth::AuthMethod::ApiKey => {
            Err(format!("{} uses API key auth — use store_api_key instead", provider))
        }
    }
}

// ── Active provider / model ───────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct ActiveConfig {
    pub provider: String,
    pub model: String,
}

#[tauri::command]
pub async fn get_active_config(state: State<'_, AppState>) -> Result<ActiveConfig, String> {
    let cfg = state.get_config().await;
    Ok(ActiveConfig {
        provider: cfg.active_provider.id().into(),
        model: cfg.active_model,
    })
}

#[tauri::command]
pub async fn set_active_config(
    state: State<'_, AppState>,
    provider: String,
    model: String,
) -> Result<(), String> {
    let p = parse_provider(&provider)?;
    let cfg = AppConfig { active_provider: p, active_model: model };
    state.set_config(cfg).await
}

fn parse_provider(s: &str) -> Result<Provider, String> {
    Provider::from_id(s).ok_or_else(|| format!("Unknown provider: {}", s))
}
