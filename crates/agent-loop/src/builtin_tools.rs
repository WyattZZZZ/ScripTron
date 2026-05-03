use process_runner::{ProcessConfig, ProcessRunner};
use std::{
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

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

pub async fn create_dir(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let rel = match input["path"].as_str() {
        Some(p) => p,
        None => return "Error: 'path' is required".into(),
    };
    let target = project_path.join(rel);
    match tokio::fs::create_dir_all(&target).await {
        Ok(()) => format!("Created directory {}", rel),
        Err(e) => format!("Error: {}", e),
    }
}

pub async fn delete_path(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let rel = match input["path"].as_str() {
        Some(p) => p,
        None => return "Error: 'path' is required".into(),
    };
    let target = project_path.join(rel);
    let result = if target.is_dir() {
        tokio::fs::remove_dir_all(&target).await
    } else {
        tokio::fs::remove_file(&target).await
    };
    match result {
        Ok(()) => format!("Deleted {}", rel),
        Err(e) => format!("Error: {}", e),
    }
}

pub async fn move_path(input: &serde_json::Value, project_path: &PathBuf) -> String {
    let from = match input["from"].as_str() {
        Some(p) => p,
        None => return "Error: 'from' is required".into(),
    };
    let to = match input["to"].as_str() {
        Some(p) => p,
        None => return "Error: 'to' is required".into(),
    };
    let source = project_path.join(from);
    let target = project_path.join(to);
    if let Some(parent) = target.parent() {
        if let Err(e) = tokio::fs::create_dir_all(parent).await {
            return format!("Error creating parent directory: {}", e);
        }
    }
    match tokio::fs::rename(&source, &target).await {
        Ok(()) => format!("Moved {} to {}", from, to),
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
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
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

pub async fn run_codex(
    input: &serde_json::Value,
    project_path: &PathBuf,
    runner: &ProcessRunner,
) -> String {
    let prompt = match input["prompt"].as_str() {
        Some(p) => p,
        None => return "Error: 'prompt' is required".into(),
    };
    let codex = if std::path::Path::new("/Applications/Codex.app/Contents/Resources/codex").exists()
    {
        "/Applications/Codex.app/Contents/Resources/codex".to_string()
    } else {
        "codex".to_string()
    };
    let last_message_path = codex_last_message_path();
    let args = vec![
        "exec".to_string(),
        "--cd".to_string(),
        project_path.to_string_lossy().into_owned(),
        "--sandbox".to_string(),
        "workspace-write".to_string(),
        "-c".to_string(),
        "approval_policy=\"never\"".to_string(),
        "--skip-git-repo-check".to_string(),
        "--color".to_string(),
        "never".to_string(),
        "--output-last-message".to_string(),
        last_message_path.to_string_lossy().into_owned(),
        prompt.to_string(),
    ];
    let cfg = ProcessConfig::new(codex, args)
        .with_working_dir(project_path.clone())
        .with_timeout(input["timeout_secs"].as_u64().unwrap_or(180));
    match runner.run(cfg).await {
        Ok(result) => {
            let final_message = tokio::fs::read_to_string(&last_message_path).await.ok();
            let _ = tokio::fs::remove_file(&last_message_path).await;
            final_message
                .filter(|text| !text.trim().is_empty())
                .unwrap_or_else(|| result.combined_output())
        }
        Err(e) => format!("Error: {}", e),
    }
}

fn codex_last_message_path() -> PathBuf {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "scriptron-codex-{}-{}.txt",
        std::process::id(),
        millis
    ))
}
