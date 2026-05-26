use scriptron_core::ScriptronCore;
use std::{
    fs,
    path::PathBuf,
    sync::{Mutex, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

fn env_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn unique_temp_home(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!("scriptron-{label}-{}-{nanos}", std::process::id()))
}

#[tokio::test]
async fn create_project_creates_workspace_project_with_starter_tron() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-create-project");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");

    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");

    let project = home.join("ScripTron").join("weekly-digest");
    let starter = fs::read_to_string(project.join("main.tron")).expect("read starter");
    assert!(starter.contains("---blackboard---"));
    assert!(starter.contains("# Weekly Digest"));
    assert!(starter.contains("[[scriptron:run-name]] first-run"));

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn hermes_prompt_submit_exports_workspace_cli_registry_as_local_hermes_skill() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-hermes-bridge-skill");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let workspace = home.join("ScripTron");
    let codex_dir = workspace.join(".register").join("codex");
    fs::create_dir_all(&codex_dir).expect("create codex registry dir");
    fs::write(
        codex_dir.join("run.sh"),
        "#!/usr/bin/env bash\necho codex\n",
    )
    .expect("write run script");
    fs::write(
        codex_dir.join("manifest.json"),
        serde_json::json!({
            "name": "codex",
            "kind": "model",
            "description": "Run Codex from ScripTron.",
            "version": "0.1.0",
            "command": codex_dir.join("run.sh").to_string_lossy(),
            "args_schema": [
                {
                    "name": "prompt",
                    "description": "Prompt text.",
                    "required": true,
                    "type": "string"
                }
            ],
            "examples": ["codex --prompt hello"]
        })
        .to_string(),
    )
    .expect("write manifest");

    let core = ScriptronCore::init().await.expect("init core");
    core.hermes_prompt_submit(
        vec![tron_parser::TronCell {
            run: true,
            content: "[[scriptron:run-name]] bridge\nList available ScripTron tools.".into(),
        }],
        workspace.to_string_lossy().into_owned(),
        None,
        None,
    )
    .await
    .expect("submit hermes prompt");

    let bridge_skill = fs::read_to_string(
        home.join(".hermes")
            .join("skills")
            .join("scriptron-workspace")
            .join("SKILL.md"),
    )
    .expect("read exported bridge skill");
    assert!(bridge_skill.contains("# ScripTron Workspace Tools"));
    assert!(bridge_skill.contains("codex"));
    assert!(bridge_skill.contains("Run Codex from ScripTron."));
    assert!(bridge_skill.contains(&codex_dir.join("run.sh").to_string_lossy().to_string()));
    assert!(bridge_skill.contains("prompt"));

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn archive_and_restore_project_persist_in_project_listing() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-archive-project");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let project_path_text = project_path.to_string_lossy().into_owned();

    core.archive_project(project_path_text.clone())
        .await
        .expect("archive project");
    let archived = core.list_projects().await.expect("list archived projects");
    assert_eq!(archived.len(), 1);
    assert_eq!(archived[0].name, "weekly-digest");
    assert!(archived[0].archived);
    assert_eq!(archived[0].status, "Archived");

    core.restore_project(project_path_text)
        .await
        .expect("restore project");
    let restored = core.list_projects().await.expect("list restored projects");
    assert_eq!(restored.len(), 1);
    assert!(!restored[0].archived);
    assert_eq!(restored[0].status, "Ready");

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn delete_project_removes_directory_and_project_memory() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-delete-project");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let project_path_text = project_path.to_string_lossy().into_owned();

    core.archive_project(project_path_text.clone())
        .await
        .expect("archive project");
    core.delete_project(project_path_text.clone())
        .await
        .expect("delete project");

    assert!(!project_path.exists());
    assert!(core
        .list_projects()
        .await
        .expect("list projects")
        .is_empty());

    let memory: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(home.join("ScripTron").join(".troner.json")).expect("read memory"),
    )
    .expect("parse memory");
    assert!(memory
        .get("projects")
        .and_then(|projects| projects.get(&project_path_text))
        .is_none());

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn create_folder_and_rename_entry_stay_inside_workspace() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-file-management");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let project_path_text = project_path.to_string_lossy().into_owned();

    let created = core
        .create_folder(project_path_text.clone(), "Draft Assets".to_string())
        .await
        .expect("create folder");
    assert_eq!(created.name, "Draft-Assets");
    assert!(project_path.join("Draft-Assets").is_dir());

    let renamed = core
        .rename_entry(
            project_path
                .join("Draft-Assets")
                .to_string_lossy()
                .into_owned(),
            "Final Assets".to_string(),
        )
        .await
        .expect("rename folder");
    assert_eq!(renamed.name, "Final-Assets");
    assert!(!project_path.join("Draft-Assets").exists());
    assert!(project_path.join("Final-Assets").is_dir());

    let outside = core
        .rename_entry(
            home.join("outside").to_string_lossy().into_owned(),
            "Nope".to_string(),
        )
        .await;
    assert!(outside.is_err());

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn create_file_and_delete_entry_stay_inside_workspace() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-create-delete-file");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let project_path_text = project_path.to_string_lossy().into_owned();

    let created = core
        .create_file(project_path_text, "notes.md".to_string())
        .await
        .expect("create file");
    assert_eq!(created.name, "notes.md");
    assert!(project_path.join("notes.md").is_file());

    core.delete_entry(project_path.join("notes.md").to_string_lossy().into_owned())
        .await
        .expect("delete file");
    assert!(!project_path.join("notes.md").exists());

    let outside = core
        .delete_entry(home.join("outside.md").to_string_lossy().into_owned())
        .await;
    assert!(outside.is_err());

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn copy_entry_copies_file_inside_workspace() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-copy-entry");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let source = project_path.join("notes.md");
    fs::write(&source, "Original notes").expect("write notes");

    let copied = core
        .copy_entry(
            source.to_string_lossy().into_owned(),
            project_path.to_string_lossy().into_owned(),
        )
        .await
        .expect("copy file");

    assert_eq!(copied.name, "notes.md-2");
    assert_eq!(
        fs::read_to_string(project_path.join("notes.md-2")).expect("read copied notes"),
        "Original notes"
    );

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn move_entry_moves_directory_inside_workspace() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-move-entry");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let source_dir = project_path.join("Draft Assets");
    fs::create_dir_all(&source_dir).expect("create source dir");
    fs::write(source_dir.join("image.png"), "png").expect("write source file");
    let target_dir = project_path.join("Final Assets");
    fs::create_dir_all(&target_dir).expect("create target dir");

    let moved = core
        .move_entry(
            source_dir.to_string_lossy().into_owned(),
            target_dir.to_string_lossy().into_owned(),
        )
        .await
        .expect("move directory");

    assert_eq!(moved.name, "Draft Assets");
    assert!(target_dir.join("Draft Assets").is_dir());
    assert!(!source_dir.exists());
    assert!(target_dir.join("Draft Assets").join("image.png").is_file());

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn import_zip_project_creates_workspace_project_from_zip() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-import-zip");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let source_dir = home.join("bundle");
    fs::create_dir_all(&source_dir).expect("create source dir");
    fs::write(source_dir.join("main.tron"), "# Imported Project").expect("write tron");
    fs::write(source_dir.join("notes.md"), "Zip contents").expect("write notes");
    let zip_path = home.join("bundle.zip");
    let status = std::process::Command::new("/usr/bin/ditto")
        .args([
            "-c",
            "-k",
            source_dir.to_string_lossy().as_ref(),
            zip_path.to_string_lossy().as_ref(),
        ])
        .status()
        .expect("run ditto");
    assert!(status.success());

    let core = ScriptronCore::init().await.expect("init core");
    let imported = core
        .import_zip_project(zip_path.to_string_lossy().into_owned())
        .await
        .expect("import zip");

    let project_path = home.join("ScripTron").join("bundle");
    assert_eq!(imported.name, "bundle");
    assert_eq!(imported.path, project_path.to_string_lossy());
    assert!(project_path.join("main.tron").is_file());
    assert!(project_path.join("notes.md").is_file());

    let _ = fs::remove_dir_all(home);
}

#[tokio::test]
async fn save_plain_file_writes_content_inside_workspace() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("core-save-plain-file");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);

    let core = ScriptronCore::init().await.expect("init core");
    core.create_project("Weekly Digest".to_string())
        .await
        .expect("create project");
    let project_path = home.join("ScripTron").join("weekly-digest");
    let notes_path = project_path.join("notes.md");
    fs::write(&notes_path, "Initial notes").expect("write notes");

    core.save_plain_file(
        notes_path.to_string_lossy().into_owned(),
        "Edited notes".to_string(),
    )
    .await
    .expect("save notes");

    assert_eq!(
        fs::read_to_string(&notes_path).expect("read notes"),
        "Edited notes"
    );

    let outside = core
        .save_plain_file(
            home.join("outside.md").to_string_lossy().into_owned(),
            "Nope".to_string(),
        )
        .await;
    assert!(outside.is_err());

    let _ = fs::remove_dir_all(home);
}
