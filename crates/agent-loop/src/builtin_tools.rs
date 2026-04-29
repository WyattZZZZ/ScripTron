use process_runner::{ProcessConfig, ProcessRunner};
use std::path::PathBuf;

pub async fn list_files(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let rel = input["path"].as_str().unwrap_or(".");
    let target = project_path.join(rel);

    let mut rd = match tokio::fs::read_dir(&target).await {
        Ok(r) => r,
        Err(e) => return format!("Error: {}", e),
    };

    let mut entries: Vec<String> = Vec::new();
    while let Ok(Some(entry)) = rd.next_entry().await {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        let kind = if path.is_dir() { "dir" } else { "file" };
        entries.push(format!("[{}] {}", kind, name));
    }
    entries.sort();
    if entries.is_empty() {
        "(empty directory)".to_string()
    } else {
        entries.join("\n")
    }
}

pub async fn read_file(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let rel = match input["path"].as_str() {
        Some(p) => p,
        None => return "Error: 'path' is required".into(),
    };
    let target = project_path.join(rel);
    match tokio::fs::read_to_string(&target).await {
        Ok(content) => content,
        Err(e) => format!("Error: {}", e),
    }
}

pub async fn write_file(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let rel = match input["path"].as_str() {
        Some(p) => p,
        None => return "Error: 'path' is required".into(),
    };
    let content = match input["content"].as_str() {
        Some(c) => c,
        None => return "Error: 'content' is required".into(),
    };
    let target = project_path.join(rel);
    if let Some(parent) = target.parent() {
        if let Err(e) = tokio::fs::create_dir_all(parent).await {
            return format!("Error creating directories: {}", e);
        }
    }
    match tokio::fs::write(&target, content).await {
        Ok(()) => format!("Written {} bytes to {}", content.len(), rel),
        Err(e) => format!("Error: {}", e),
    }
}

pub async fn run_command(
    input: &serde_json::Value,
    project_path: &PathBuf,
    runner: &ProcessRunner,
) -> String {
    let command = match input["command"].as_str() {
        Some(c) => c.to_string(),
        None => return "Error: 'command' is required".into(),
    };
    let args: Vec<String> = input["args"]
        .as_array()
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();

    let working_dir = input["working_dir"]
        .as_str()
        .map(|d| project_path.join(d))
        .unwrap_or_else(|| project_path.clone());

    let cfg = ProcessConfig::new(command, args).with_working_dir(working_dir);
    match runner.run(cfg).await {
        Ok(result) => result.combined_output(),
        Err(e) => format!("Error: {}", e),
    }
}
