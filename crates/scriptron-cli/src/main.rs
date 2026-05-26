use chrono::Utc;
use std::{
    env, fs,
    path::{Path, PathBuf},
};
use tron_parser::TronCell;

fn main() {
    let mut args: Vec<String> = env::args().skip(1).collect();
    let dry_run = take_flag(&mut args, "--dry-run");

    let result = match args.as_slice() {
        [domain, action, rest @ ..] if domain == "project" && action == "create" => {
            let Some(name) = rest.first() else {
                fail("project create requires <name>");
            };
            project_create(name, dry_run)
        }
        [domain, action, rest @ ..] if domain == "project" && action == "open" => {
            let Some(path) = rest.first() else {
                fail("project open requires <path>");
            };
            project_open(path, dry_run)
        }
        [domain, action, rest @ ..] if domain == "file" && action == "create" => {
            let Some(path) = rest.first() else {
                fail("file create requires <path>");
            };
            file_create(path, dry_run)
        }
        [domain, action, rest @ ..] if domain == "tron" && action == "create" => {
            let Some(path) = rest.first() else {
                fail("tron create requires <path>");
            };
            tron_create(path, dry_run)
        }
        [domain, action, rest @ ..] if domain == "tronhub" && action == "sync" => tronhub_sync(),
        [domain, action, rest @ ..] if domain == "tronhub" && action == "list" => {
            let Some(kind) = rest.first() else {
                fail("tronhub list requires <skill|cli|model>");
            };
            tronhub_list(kind)
        }
        [domain, action, rest @ ..] if domain == "tronhub" && action == "install" => {
            let Some(kind) = rest.first() else {
                fail("tronhub install requires <skill|cli|model> <name>");
            };
            let Some(name) = rest.get(1) else {
                fail("tronhub install requires <skill|cli|model> <name>");
            };
            tronhub_install(kind, name)
        }
        _ => {
            println!(
                "Usage:\n  scriptron project create <name> [--dry-run]\n  scriptron project open <path> [--dry-run]\n  scriptron file create <path> [--dry-run]\n  scriptron tron create <path> [--dry-run]\n  scriptron tronhub sync\n  scriptron tronhub list <skill|cli|model>\n  scriptron tronhub install <skill|cli|model> <name>"
            );
            Ok(())
        }
    };

    if let Err(error) = result {
        fail(&error);
    }
}

fn take_flag(args: &mut Vec<String>, flag: &str) -> bool {
    if let Some(index) = args.iter().position(|arg| arg == flag) {
        args.remove(index);
        true
    } else {
        false
    }
}

fn project_create(name: &str, dry_run: bool) -> Result<(), String> {
    let root = workspace_dir();
    let directory_name = sanitized_project_directory_name(name);
    if directory_name.is_empty() {
        return Err(
            "project create requires a name with letters, numbers, dash, or underscore".into(),
        );
    }
    let target = root.join(directory_name);
    ensure_allowed(&target, None)?;
    if dry_run {
        return print_plan("project.create", &target);
    }
    fs::create_dir_all(&target).map_err(|e| e.to_string())?;
    fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(target.join("main.tron"))
        .and_then(|mut file| {
            use std::io::Write;
            file.write_all(starter_tron_content(name).as_bytes())
        })
        .map_err(|e| e.to_string())?;
    audit(
        &target,
        "project.create",
        serde_json::json!({ "name": name, "path": target }),
    )?;
    println!("Created project {}", target.display());
    Ok(())
}

fn project_open(path: &str, dry_run: bool) -> Result<(), String> {
    let target = absolutize(path)?;
    ensure_allowed(&target, env_project_path().as_deref())?;
    if dry_run {
        return print_plan("project.open", &target);
    }
    if !target.is_dir() {
        return Err(format!(
            "Project path is not a directory: {}",
            target.display()
        ));
    }
    audit(
        &target,
        "project.open",
        serde_json::json!({ "path": target }),
    )?;
    println!("{}", target.display());
    Ok(())
}

fn file_create(path: &str, dry_run: bool) -> Result<(), String> {
    let target = absolutize(path)?;
    ensure_allowed(&target, env_project_path().as_deref())?;
    if dry_run {
        return print_plan("file.create", &target);
    }
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&target)
        .map_err(|e| e.to_string())?;
    audit_for_file(&target, "file.create")?;
    println!("Created file {}", target.display());
    Ok(())
}

fn tron_create(path: &str, dry_run: bool) -> Result<(), String> {
    let target = absolutize(path)?;
    ensure_allowed(&target, env_project_path().as_deref())?;
    if dry_run {
        return print_plan("tron.create", &target);
    }
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let cells = Vec::<TronCell>::new();
    let blackboard = serde_json::json!({ "entries": [], "notes": [], "audit": [] });
    let content = tron_parser::serialize_with_blackboard(&cells, &blackboard);
    fs::write(&target, content).map_err(|e| e.to_string())?;
    audit_for_file(&target, "tron.create")?;
    println!("Created tron file {}", target.display());
    Ok(())
}

fn tronhub_sync() -> Result<(), String> {
    let hub_dir = workspace_dir().join(".tronhub");
    let repo_dir = hub_dir.join("ScripTron_Extension");
    fs::create_dir_all(&hub_dir).map_err(|e| e.to_string())?;
    let status = if repo_dir.join(".git").exists() {
        std::process::Command::new("git")
            .arg("-C")
            .arg(&repo_dir)
            .arg("pull")
            .arg("--ff-only")
            .status()
    } else {
        if repo_dir.exists() {
            fs::remove_dir_all(&repo_dir).map_err(|e| e.to_string())?;
        }
        std::process::Command::new("git")
            .arg("clone")
            .arg("--depth")
            .arg("1")
            .arg("https://github.com/WyattZZZZ/ScripTron_Extension")
            .arg(&repo_dir)
            .status()
    }
    .map_err(|e| e.to_string())?;
    if !status.success() {
        return Err("git sync failed for ScripTron_Extension".into());
    }
    println!("Synced {}", repo_dir.display());
    Ok(())
}

fn tronhub_list(kind: &str) -> Result<(), String> {
    ensure_tronhub_cache()?;
    let source = tronhub_kind_dir(kind);
    let installed = installed_kind_dir(kind);
    let mut entries = Vec::new();
    if source.exists() {
        for entry in fs::read_dir(&source).map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            if entry.file_type().map_err(|e| e.to_string())?.is_dir() {
                let name = entry.file_name().to_string_lossy().into_owned();
                entries.push(serde_json::json!({
                    "name": name,
                    "kind": normalized_kind(kind),
                    "installed": installed.join(&name).exists(),
                    "path": entry.path()
                }));
            }
        }
    }
    entries.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    println!(
        "{}",
        serde_json::to_string_pretty(&entries).map_err(|e| e.to_string())?
    );
    Ok(())
}

fn tronhub_install(kind: &str, name: &str) -> Result<(), String> {
    ensure_tronhub_cache()?;
    let source = tronhub_kind_dir(kind).join(sanitize(name));
    if !source.exists() {
        return Err(format!("TronHub {} '{}' was not found", kind, name));
    }
    let target = installed_kind_dir(kind).join(sanitize(name));
    if target.exists() {
        fs::remove_dir_all(&target).map_err(|e| e.to_string())?;
    }
    copy_dir_all(&source, &target)?;
    if normalized_kind(kind) == "cli" || normalized_kind(kind) == "model" {
        let manifest = target.join("manifest.json");
        if !manifest.exists() {
            fs::write(
                &manifest,
                serde_json::to_string_pretty(&generated_cli_manifest(kind, name, &target))
                    .map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
        }
    } else {
        let manifest = target.join("skill.json");
        if !manifest.exists() {
            fs::write(
                &manifest,
                serde_json::to_string_pretty(&serde_json::json!({
                    "name": name,
                    "description": format!("TronHub skill '{}'.", name),
                    "version": "0.1.0"
                }))
                .map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
        }
    }
    println!("Installed {} {}", normalized_kind(kind), name);
    Ok(())
}

fn ensure_tronhub_cache() -> Result<(), String> {
    if !workspace_dir()
        .join(".tronhub")
        .join("ScripTron_Extension")
        .exists()
    {
        tronhub_sync()?;
    }
    Ok(())
}

fn workspace_dir() -> PathBuf {
    home_dir().join("ScripTron")
}

fn tronhub_kind_dir(kind: &str) -> PathBuf {
    let folder = match normalized_kind(kind) {
        "skill" => "skills",
        "model" => "models",
        _ => "clis",
    };
    workspace_dir()
        .join(".tronhub")
        .join("ScripTron_Extension")
        .join(folder)
}

fn installed_kind_dir(kind: &str) -> PathBuf {
    if normalized_kind(kind) == "skill" {
        workspace_dir().join(".skills")
    } else {
        workspace_dir().join(".register")
    }
}

fn normalized_kind(kind: &str) -> &'static str {
    match kind {
        "skill" | "skills" => "skill",
        "model" | "models" => "model",
        _ => "cli",
    }
}

fn generated_cli_manifest(kind: &str, name: &str, installed_dir: &Path) -> serde_json::Value {
    let command = first_child_path(installed_dir)
        .unwrap_or_else(|| installed_dir.join(name))
        .to_string_lossy()
        .into_owned();
    serde_json::json!({
        "name": name,
        "kind": if normalized_kind(kind) == "model" { "model" } else { "tool" },
        "description": format!("TronHub {} '{}'.", normalized_kind(kind), name),
        "version": "0.1.0",
        "command": command,
        "args_schema": [
            { "name": "input", "description": "Input prompt, path, or task payload.", "required": false, "type": "string" }
        ],
        "examples": [format!("{} --help", name)]
    })
}

fn first_child_path(dir: &Path) -> Option<PathBuf> {
    fs::read_dir(dir)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| path.file_name().and_then(|n| n.to_str()) != Some("manifest.json"))
}

fn copy_dir_all(source: &Path, target: &Path) -> Result<(), String> {
    fs::create_dir_all(target).map_err(|e| e.to_string())?;
    for entry in fs::read_dir(source).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let file_type = entry.file_type().map_err(|e| e.to_string())?;
        let destination = target.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_all(&entry.path(), &destination)?;
        } else {
            fs::copy(entry.path(), destination).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn print_plan(action: &str, target: &Path) -> Result<(), String> {
    println!(
        "{}",
        serde_json::json!({
            "dry_run": true,
            "action": action,
            "target": target,
            "allowed": true
        })
    );
    Ok(())
}

fn ensure_allowed(path: &Path, project_path: Option<&Path>) -> Result<(), String> {
    let path = normalize(path);
    let documents = home_dir().join("Documents");
    let workspace = workspace_dir();
    if path.starts_with(normalize(&workspace)) {
        return Ok(());
    }
    if path.starts_with(normalize(&documents)) {
        return Ok(());
    }
    if let Some(project_path) = project_path {
        if path.starts_with(normalize(project_path)) {
            return Ok(());
        }
    }
    Err(format!(
        "Refusing to write outside ~/ScripTron, ~/Documents, or SCRIPTRON_PROJECT: {}",
        path.display()
    ))
}

fn audit_for_file(target: &Path, action: &str) -> Result<(), String> {
    let project = env_project_path()
        .or_else(|| target.parent().map(Path::to_path_buf))
        .ok_or_else(|| "Cannot resolve audit directory".to_string())?;
    audit(&project, action, serde_json::json!({ "path": target }))
}

fn audit(project: &Path, action: &str, payload: serde_json::Value) -> Result<(), String> {
    let audit_dir = project.join(".scriptron");
    fs::create_dir_all(&audit_dir).map_err(|e| e.to_string())?;
    let line = serde_json::json!({
        "action": action,
        "payload": payload,
        "created_at": Utc::now().to_rfc3339()
    });
    let mut existing =
        fs::read_to_string(audit_dir.join("blackboard_audit.jsonl")).unwrap_or_default();
    existing.push_str(&line.to_string());
    existing.push('\n');
    fs::write(audit_dir.join("blackboard_audit.jsonl"), existing).map_err(|e| e.to_string())
}

fn absolutize(path: &str) -> Result<PathBuf, String> {
    let path = PathBuf::from(path);
    if path.is_absolute() {
        Ok(path)
    } else {
        env::current_dir()
            .map(|cwd| cwd.join(path))
            .map_err(|e| e.to_string())
    }
}

fn normalize(path: &Path) -> PathBuf {
    path.components().collect()
}

fn home_dir() -> PathBuf {
    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn env_project_path() -> Option<PathBuf> {
    env::var("SCRIPTRON_PROJECT").ok().map(PathBuf::from)
}

fn sanitize(name: &str) -> String {
    name.trim().replace(['/', ':'], "-")
}

fn sanitized_project_directory_name(name: &str) -> String {
    let lower = name.trim().replace(' ', "-").to_lowercase();
    let mut out = String::with_capacity(lower.len());
    let mut last_dash = false;
    for ch in lower.chars() {
        let safe = if ch.is_ascii_alphanumeric() || ch == '_' {
            Some(ch)
        } else if ch == '-' || ch == '/' || ch == ':' || ch == '\\' {
            Some('-')
        } else {
            None
        };
        match safe {
            Some('-') if !last_dash => {
                out.push('-');
                last_dash = true;
            }
            Some('-') => {}
            Some(ch) => {
                out.push(ch);
                last_dash = false;
            }
            None => {}
        }
    }
    out.trim_matches('-').to_string()
}

fn starter_tron_content(project_name: &str) -> String {
    format!(
        r#"---blackboard---
{{
  "entries": [],
  "notes": []
}}
---

---run: false---
# {project_name}

Describe the project context, source material, and constraints here.
---

---run: true---
[[scriptron:run-name]] first-run

Summarize the project goal and suggest the next concrete step.
---
"#
    )
}

fn fail(message: &str) -> ! {
    eprintln!("Error: {message}");
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn temp_home(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock before unix epoch")
            .as_nanos();
        env::temp_dir().join(format!(
            "scriptron-cli-{label}-{}-{nanos}",
            std::process::id()
        ))
    }

    #[test]
    fn project_create_uses_scriptron_workspace_and_writes_starter_tron() {
        let _guard = env_lock().lock().expect("lock env");
        let home = temp_home("project-create");
        fs::create_dir_all(&home).expect("create temp home");
        env::set_var("HOME", &home);
        env::remove_var("SCRIPTRON_PROJECT");

        project_create("Weekly Digest", false).expect("create project");

        let project = home.join("ScripTron").join("weekly-digest");
        let starter = fs::read_to_string(project.join("main.tron")).expect("read starter tron");
        assert!(starter.contains("---blackboard---"));
        assert!(starter.contains("# Weekly Digest"));
        assert!(starter.contains("[[scriptron:run-name]] first-run"));

        let _ = fs::remove_dir_all(home);
    }

    #[test]
    fn project_create_does_not_overwrite_existing_starter_tron() {
        let _guard = env_lock().lock().expect("lock env");
        let home = temp_home("project-create-existing");
        let project = home.join("ScripTron").join("existing");
        fs::create_dir_all(&project).expect("create project");
        fs::write(project.join("main.tron"), "keep me").expect("write existing starter");
        env::set_var("HOME", &home);
        env::remove_var("SCRIPTRON_PROJECT");

        let result = project_create("Existing", false);

        assert!(result.is_err());
        assert_eq!(
            fs::read_to_string(project.join("main.tron")).expect("read existing starter"),
            "keep me"
        );

        let _ = fs::remove_dir_all(home);
    }

    #[test]
    fn project_create_rejects_names_without_safe_path_characters() {
        let _guard = env_lock().lock().expect("lock env");
        let home = temp_home("project-create-invalid-name");
        fs::create_dir_all(&home).expect("create temp home");
        env::set_var("HOME", &home);
        env::remove_var("SCRIPTRON_PROJECT");

        let result = project_create("!!!", false);

        assert!(result.is_err());
        assert!(!home.join("ScripTron").join("main.tron").exists());

        let _ = fs::remove_dir_all(home);
    }
}
