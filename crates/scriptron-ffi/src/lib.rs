use once_cell::sync::OnceCell;
use scriptron_core::ScriptronCore;
use serde::Deserialize;
use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use tokio::runtime::Runtime;
use tron_parser::TronCell;

static RUNTIME: OnceCell<Runtime> = OnceCell::new();
static CORE: OnceCell<ScriptronCore> = OnceCell::new();

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
    let core = CORE.get().ok_or_else(|| "ScripTron core is not initialized".to_string())?;

    match request.method.as_str() {
        "get_workspace_path" => Ok(json!(core.workspace_path())),
        "list_workspace_files" => serde_json::to_value(core.list_workspace_files().await?).map_err(|e| e.to_string()),
        "list_dir_files" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.list_dir_files(path).await?).map_err(|e| e.to_string())
        }
        "open_tron_file" => {
            let path = required_string(&request.params, "path")?;
            serde_json::to_value(core.open_tron_file(path).await?).map_err(|e| e.to_string())
        }
        "save_tron_file" => {
            let path = required_string(&request.params, "path")?;
            let cells: Vec<TronCell> = serde_json::from_value(required_value(&request.params, "cells")?)
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
        "get_auth_status" => serde_json::to_value(core.get_auth_status().await).map_err(|e| e.to_string()),
        "store_api_key" => {
            let provider = required_string(&request.params, "provider")?;
            let api_key = required_string(&request.params, "api_key")?;
            core.store_api_key(provider, api_key).await?;
            Ok(json!(null))
        }
        "disconnect_provider" => {
            let provider = required_string(&request.params, "provider")?;
            core.disconnect_provider(provider).await?;
            Ok(json!(null))
        }
        "get_active_config" => serde_json::to_value(core.get_active_config().await).map_err(|e| e.to_string()),
        "set_active_config" => {
            let provider = required_string(&request.params, "provider")?;
            let model = required_string(&request.params, "model")?;
            core.set_active_config(provider, model).await?;
            Ok(json!(null))
        }
        "build_task" => {
            let cells: Vec<TronCell> = serde_json::from_value(required_value(&request.params, "cells")?)
                .map_err(|e| e.to_string())?;
            let project_path = required_string(&request.params, "project_path")?;
            Ok(core.build_task(cells, project_path).await)
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
