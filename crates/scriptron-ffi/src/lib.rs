use once_cell::sync::OnceCell;
use parking_lot::Mutex;
use scriptron_core::ScriptronCore;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use tokio::runtime::Runtime;
use tron_parser::TronCell;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();
static CORE: OnceCell<ScriptronCore> = OnceCell::new();
static EVENTS: OnceCell<Mutex<VecDeque<Value>>> = OnceCell::new();

#[derive(Debug, Deserialize)]
struct RpcRequest {
    method: String,
    #[serde(default)]
    params: Value,
}

#[no_mangle]
pub extern "C" fn scriptron_init() -> *mut c_char {
    let result = runtime().block_on(async {
        if CORE.get().is_none() {
            let core = ScriptronCore::init().await.map_err(|e| e.to_string())?;
            let _ = CORE.set(core);
        }
        Ok::<Value, String>(json!({ "initialized": true }))
    });
    json_response(result)
}

#[no_mangle]
pub extern "C" fn scriptron_call(request_json: *const c_char) -> *mut c_char {
    let Some(request) = read_request(request_json) else {
        return json_response(Err("Invalid UTF-8 or null request".into()));
    };

    let parsed: Result<RpcRequest, _> = serde_json::from_str(&request);
    let Ok(request) = parsed else {
        return json_response(Err(parsed.unwrap_err().to_string()));
    };

    let result = runtime().block_on(dispatch(request));
    json_response(result)
}

#[no_mangle]
pub extern "C" fn scriptron_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

async fn dispatch(request: RpcRequest) -> Result<Value, String> {
    ensure_core().await?;
    let core = CORE
        .get()
        .ok_or_else(|| "ScripTron core is not initialized".to_string())?;

    match request.method.as_str() {
        "get_workspace_path" => Ok(json!(core.workspace_path())),
        "list_workspace_files" => {
            serde_json::to_value(core.list_workspace_files().await?).map_err(|e| e.to_string())
        }
        "list_projects" => {
            serde_json::to_value(core.list_projects().await?).map_err(|e| e.to_string())
        }
        "list_dir_files" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.list_dir_files(path).await?).map_err(|e| e.to_string())
        }
        "create_project" => {
            let name = required_string(&request.params, "name")?;
            core.create_project(name).await?;
            Ok(json!(null))
        }
        "archive_project" => {
            let path = required_string(&request.params, "path")?;
            core.archive_project(path).await?;
            Ok(json!(null))
        }
        "restore_project" => {
            let path = required_string(&request.params, "path")?;
            core.restore_project(path).await?;
            Ok(json!(null))
        }
        "delete_project" => {
            let path = required_string(&request.params, "path")?;
            core.delete_project(path).await?;
            Ok(json!(null))
        }
        "create_folder" => {
            let parent_path = required_string(&request.params, "parent_path")?;
            let name = required_string(&request.params, "name")?;
            serde_json::to_value(core.create_folder(parent_path, name).await?)
                .map_err(|e| e.to_string())
        }
        "create_file" => {
            let parent_path = required_string(&request.params, "parent_path")?;
            let name = required_string(&request.params, "name")?;
            serde_json::to_value(core.create_file(parent_path, name).await?)
                .map_err(|e| e.to_string())
        }
        "rename_entry" => {
            let path = required_string(&request.params, "path")?;
            let name = required_string(&request.params, "name")?;
            serde_json::to_value(core.rename_entry(path, name).await?).map_err(|e| e.to_string())
        }
        "copy_entry" => {
            let path = required_string(&request.params, "path")?;
            let target_directory_path = required_string(&request.params, "target_directory_path")?;
            serde_json::to_value(core.copy_entry(path, target_directory_path).await?)
                .map_err(|e| e.to_string())
        }
        "move_entry" => {
            let path = required_string(&request.params, "path")?;
            let target_directory_path = required_string(&request.params, "target_directory_path")?;
            serde_json::to_value(core.move_entry(path, target_directory_path).await?)
                .map_err(|e| e.to_string())
        }
        "import_zip_project" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.import_zip_project(path).await?).map_err(|e| e.to_string())
        }
        "delete_entry" => {
            let path = required_string(&request.params, "path")?;
            core.delete_entry(path).await?;
            Ok(json!(null))
        }
        "save_plain_file" => {
            let path = required_string(&request.params, "path")?;
            let content = required_string(&request.params, "content")?;
            core.save_plain_file(path, content).await?;
            Ok(json!(null))
        }
        "open_tron_file" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.open_tron_file(path).await?).map_err(|e| e.to_string())
        }
        "save_tron_file" => {
            let path = required_string(&request.params, "path")?;
            let cells: Vec<TronCell> =
                serde_json::from_value(required_value(&request.params, "cells")?)
                    .map_err(|e| e.to_string())?;
            let blackboard = request.params.get("blackboard").cloned();
            core.save_tron_file(path, cells, blackboard).await?;
            Ok(json!(null))
        }
        "create_tron_file" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.create_tron_file(path).await?).map_err(|e| e.to_string())
        }
        "list_tools" => serde_json::to_value(core.list_tools().await).map_err(|e| e.to_string()),
        "install_tool_from_json" => {
            let manifest_json = required_string(&request.params, "manifest_json")?;
            core.install_tool_from_json(manifest_json).await?;
            Ok(json!(null))
        }
        "remove_tool" => {
            let name = required_string(&request.params, "name")?;
            core.remove_tool(name).await?;
            Ok(json!(null))
        }
        "sync_tronhub" => {
            core.sync_tronhub().await?;
            Ok(json!(null))
        }
        "list_tronhub" => {
            let kind = required_string(&request.params, "kind")?;
            serde_json::to_value(core.list_tronhub(kind).await?).map_err(|e| e.to_string())
        }
        "install_tronhub" => {
            let kind = required_string(&request.params, "kind")?;
            let name = required_string(&request.params, "name")?;
            core.install_tronhub(kind, name).await?;
            Ok(json!(null))
        }
        "list_skills" => serde_json::to_value(core.list_skills().await?).map_err(|e| e.to_string()),
        "remove_skill" => {
            let name = required_string(&request.params, "name")?;
            core.remove_skill(name).await?;
            Ok(json!(null))
        }
        "run_plugin_login" => {
            let name = required_string(&request.params, "name")?;
            let output = core.run_plugin_login(name).await?;
            serde_json::to_value(output).map_err(|e| e.to_string())
        }
        "run_plugin_install_script" => {
            let kind = required_string(&request.params, "kind")?;
            let name = required_string(&request.params, "name")?;
            let output = core.run_plugin_install_script(kind, name).await?;
            serde_json::to_value(output).map_err(|e| e.to_string())
        }
        "get_auth_status" => {
            serde_json::to_value(core.get_auth_status().await).map_err(|e| e.to_string())
        }
        "hermes_status" => {
            serde_json::to_value(core.hermes_status().await?).map_err(|e| e.to_string())
        }
        "hermes_status_report" => {
            serde_json::to_value(core.hermes_status_report().await?).map_err(|e| e.to_string())
        }
        "hermes_doctor" => {
            serde_json::to_value(core.hermes_doctor().await?).map_err(|e| e.to_string())
        }
        "hermes_auth_status" => {
            let provider = required_string(&request.params, "provider")?;
            serde_json::to_value(core.hermes_auth_status(provider).await?)
                .map_err(|e| e.to_string())
        }
        "hermes_provider_link_status" => {
            let provider = required_string(&request.params, "provider")?;
            serde_json::to_value(core.hermes_provider_link_status(provider).await?)
                .map_err(|e| e.to_string())
        }
        "hermes_skills_browse" => {
            serde_json::to_value(core.hermes_skills_browse().await?).map_err(|e| e.to_string())
        }
        "hermes_skills_search" => {
            let query = required_string(&request.params, "query")?;
            serde_json::to_value(core.hermes_skills_search(query).await?).map_err(|e| e.to_string())
        }
        "hermes_skills_install" => {
            let install_ref = required_string(&request.params, "install_ref")?;
            core.hermes_skills_install(install_ref).await?;
            Ok(json!(null))
        }
        "sync_hermes_workspace_bridge" => {
            core.sync_hermes_workspace_bridge().await?;
            Ok(json!(null))
        }
        "get_active_config" => {
            serde_json::to_value(core.get_active_config().await).map_err(|e| e.to_string())
        }
        "set_active_config" => {
            let provider = required_string(&request.params, "provider")?;
            let model = required_string(&request.params, "model")?;
            core.set_active_config(provider, model).await?;
            Ok(json!(null))
        }
        "get_memory_snapshot" => {
            let project_path = request
                .params
                .get("project_path")
                .and_then(Value::as_str)
                .map(str::to_string);
            serde_json::to_value(core.get_memory_snapshot(project_path).await?)
                .map_err(|e| e.to_string())
        }
        "update_global_memory" => {
            let global_memory =
                serde_json::from_value(required_value(&request.params, "global_memory")?)
                    .map_err(|e| e.to_string())?;
            serde_json::to_value(core.update_global_memory(global_memory).await?)
                .map_err(|e| e.to_string())
        }
        "update_project_memory" => {
            let project_memory =
                serde_json::from_value(required_value(&request.params, "project_memory")?)
                    .map_err(|e| e.to_string())?;
            serde_json::to_value(core.update_project_memory(project_memory).await?)
                .map_err(|e| e.to_string())
        }
        "factory_reset_app_state" => {
            core.factory_reset_app_state().await?;
            Ok(json!(null))
        }
        "search_mentions" => {
            let query = request
                .params
                .get("query")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let project_path = request
                .params
                .get("project_path")
                .and_then(Value::as_str)
                .map(str::to_string);
            serde_json::to_value(core.search_mentions(query, project_path).await?)
                .map_err(|e| e.to_string())
        }
        "record_mention_reference" => {
            let reference = request
                .params
                .get("reference")
                .cloned()
                .unwrap_or_else(|| json!({}));
            core.record_mention_reference(reference).await?;
            Ok(json!(null))
        }
        "troner_agent_message" => {
            let message = required_string(&request.params, "message")?;
            let project_path = request
                .params
                .get("project_path")
                .and_then(Value::as_str)
                .map(str::to_string);
            serde_json::to_value(core.troner_agent_message(message, project_path).await?)
                .map_err(|e| e.to_string())
        }
        "build_task" => {
            let cells: Vec<TronCell> =
                serde_json::from_value(required_value(&request.params, "cells")?)
                    .map_err(|e| e.to_string())?;
            let project_path = required_string(&request.params, "project_path")?;
            let blackboard = request.params.get("blackboard").cloned();
            Ok(core.build_task(cells, project_path, blackboard).await)
        }
        "hermes_prompt_submit" => {
            let cells: Vec<TronCell> =
                serde_json::from_value(required_value(&request.params, "cells")?)
                    .map_err(|e| e.to_string())?;
            let project_path = required_string(&request.params, "project_path")?;
            let blackboard = request.params.get("blackboard").cloned();
            let tron_path = request
                .params
                .get("path")
                .and_then(Value::as_str)
                .map(str::to_string);
            let result = core
                .hermes_prompt_submit(cells, project_path, blackboard, tron_path)
                .await?;
            let queued = result.events.len();
            for event in result.events {
                enqueue_event(serde_json::to_value(event).map_err(|e| e.to_string())?);
            }
            Ok(json!({ "queued": queued, "blackboard": result.blackboard }))
        }
        "hermes_poll_events" => {
            let mut queue = event_queue().lock();
            let events: Vec<Value> = queue.drain(..).collect();
            Ok(json!(events))
        }
        other => Err(format!("Unknown ScripTron method: {other}")),
    }
}

async fn ensure_core() -> Result<(), String> {
    if CORE.get().is_some() {
        return Ok(());
    }
    let core = ScriptronCore::init().await.map_err(|e| e.to_string())?;
    let _ = CORE.set(core);
    Ok(())
}

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| Runtime::new().expect("failed to create ScripTron runtime"))
}

fn event_queue() -> &'static Mutex<VecDeque<Value>> {
    EVENTS.get_or_init(|| Mutex::new(VecDeque::new()))
}

fn enqueue_event(event: Value) {
    event_queue().lock().push_back(event);
}

fn read_request(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(str::to_string) }
}

fn required_value(params: &Value, key: &str) -> Result<Value, String> {
    params
        .get(key)
        .cloned()
        .ok_or_else(|| format!("Missing required param: {key}"))
}

fn required_string(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| format!("Missing or invalid string param: {key}"))
}

fn json_response(result: Result<Value, String>) -> *mut c_char {
    let value = match result {
        Ok(data) => json!({ "ok": true, "data": data }),
        Err(error) => json!({ "ok": false, "error": error }),
    };
    CString::new(value.to_string())
        .unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":\"Invalid response\"}").unwrap())
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        fs,
        path::{Path, PathBuf},
        sync::{Mutex, OnceLock},
        time::{SystemTime, UNIX_EPOCH},
    };

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn fixture_path(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("scriptron-core")
            .join("tests")
            .join("fixtures")
            .join(name)
    }

    fn unique_temp_home(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock before unix epoch")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "scriptron-ffi-{label}-{}-{nanos}",
            std::process::id()
        ))
    }

    #[test]
    fn dispatch_exposes_stage2_hermes_skill_methods() {
        let _guard = env_lock().lock().expect("lock env");
        let home = unique_temp_home("stage2-hermes-skills");
        fs::create_dir_all(&home).expect("create temp home");
        let command_log = home.join("fake-hermes-commands.log");
        std::env::set_var("HOME", &home);
        std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
        std::env::set_var("FAKE_HERMES_LOG", &command_log);

        let rt = Runtime::new().expect("runtime");
        let browsed = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_skills_browse".into(),
                params: json!({}),
            }))
            .expect("browse dispatch");
        let browsed_names = browsed
            .as_array()
            .expect("array")
            .iter()
            .map(|item| item["name"].as_str().expect("name"))
            .collect::<Vec<_>>();
        assert_eq!(
            browsed_names,
            vec!["claude-code", "github-pr-review", "research-brief"]
        );
        assert_eq!(browsed[0]["source"], "Hermes Official / Hub");
        assert_eq!(browsed[0]["tags"], json!(["official", "cli", "coding"]));
        assert_eq!(browsed[0]["icon"], "terminal");

        let searched = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_skills_search".into(),
                params: json!({ "query": "github" }),
            }))
            .expect("search dispatch");
        assert_eq!(searched.as_array().expect("array").len(), 1);

        rt.block_on(dispatch(RpcRequest {
            method: "hermes_skills_install".into(),
            params: json!({ "install_ref": "github-pr-review" }),
        }))
        .expect("install dispatch");

        let log = fs::read_to_string(command_log).expect("read fake hermes command log");
        assert!(log.contains("skills browse --size 100"));
        assert!(log.contains("skills search github --limit 20"));
        assert!(log.contains("skills install github-pr-review"));
    }

    #[test]
    fn dispatch_exposes_real_hermes_runtime_commands() {
        let _guard = env_lock().lock().expect("lock env");
        let home = unique_temp_home("stage2-hermes-runtime");
        fs::create_dir_all(&home).expect("create temp home");
        let command_log = home.join("fake-hermes-commands.log");
        std::env::set_var("HOME", &home);
        std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
        std::env::set_var("FAKE_HERMES_LOG", &command_log);

        let rt = Runtime::new().expect("runtime");
        let status = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_status_report".into(),
                params: json!({}),
            }))
            .expect("status dispatch");
        assert_eq!(status["success"], true);
        assert!(status["output"]
            .as_str()
            .expect("output")
            .contains("Hermes Agent Status"));

        let doctor = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_doctor".into(),
                params: json!({}),
            }))
            .expect("doctor dispatch");
        assert_eq!(doctor["success"], true);
        assert!(doctor["output"]
            .as_str()
            .expect("output")
            .contains("Hermes Doctor"));

        let auth = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_auth_status".into(),
                params: json!({ "provider": "codex" }),
            }))
            .expect("auth dispatch");
        assert_eq!(auth["success"], true);
        assert!(auth["output"]
            .as_str()
            .expect("output")
            .contains("codex: logged in"));

        let link = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_provider_link_status".into(),
                params: json!({ "provider": "codex" }),
            }))
            .expect("provider link dispatch");
        assert_eq!(link["success"], true);
        assert!(link["output"]
            .as_str()
            .expect("output")
            .contains("Hermes auth"));

        let secret = "sk-from-ffi";
        let saved = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_save_api_key".into(),
                params: json!({ "provider": "openrouter", "api_key": secret }),
            }))
            .expect("save key dispatch");
        assert_eq!(saved["success"], true);
        let save_output = saved["output"].as_str().expect("save output");
        assert!(save_output.contains("OPENROUTER_API_KEY"));
        assert!(!save_output.contains(secret));

        let env_contents =
            fs::read_to_string(home.join(".hermes").join(".env")).expect("read hermes env");
        assert!(env_contents.contains("OPENROUTER_API_KEY=sk-from-ffi"));

        let chat = rt
            .block_on(dispatch(RpcRequest {
                method: "hermes_test_chat".into(),
                params: json!({}),
            }))
            .expect("test chat dispatch");
        assert_eq!(chat["success"], true);
        assert!(chat["output"]
            .as_str()
            .expect("chat output")
            .contains("Fake Hermes response"));

        let log = fs::read_to_string(command_log).expect("read fake hermes command log");
        assert!(log.contains("status"));
        assert!(log.contains("doctor"));
        assert!(log.contains("auth status codex"));
        assert!(log.contains("chat -q"));
    }
}
