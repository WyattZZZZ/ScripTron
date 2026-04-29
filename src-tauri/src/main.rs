// Prevents a console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod state;

use state::AppState;

#[tokio::main]
async fn main() {
    let app_state = AppState::init()
        .await
        .expect("Failed to initialise app state");

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(app_state)
        .invoke_handler(tauri::generate_handler![
            commands::open_tron_file,
            commands::save_tron_file,
            commands::create_tron_file,
            commands::list_workspace_files,
            commands::list_dir_files,
            commands::get_workspace_path,
            commands::run_task,
            commands::list_tools,
            commands::install_tool_from_json,
            commands::install_tool_from_path,
            commands::remove_tool,
            commands::get_auth_status,
            commands::store_api_key,
            commands::disconnect_provider,
            commands::start_oauth_flow,
            commands::get_active_config,
            commands::set_active_config,
        ])
        .run(tauri::generate_context!())
        .expect("Failed to run ScripTron");
}
