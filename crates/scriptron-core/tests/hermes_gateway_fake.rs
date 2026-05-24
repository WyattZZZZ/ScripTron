use scriptron_core::ScriptronCore;
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

fn fixture_path(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join(name)
}

fn unique_temp_home(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!("scriptron-{label}-{}-{nanos}", std::process::id()))
}

#[tokio::test]
async fn fake_hermes_skills_flow_uses_official_hub_and_does_not_write_workspace_skills() {
    let home = unique_temp_home("stage2-hermes-skills");
    fs::create_dir_all(&home).expect("create temp home");
    let command_log = home.join("fake-hermes-commands.log");

    std::env::set_var("HOME", &home);
    std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
    std::env::set_var("FAKE_HERMES_LOG", &command_log);

    let core = ScriptronCore::init().await.expect("init core");

    let status = core.hermes_status().await.expect("hermes status");
    assert!(status.installed);
    assert_eq!(status.version.as_deref(), Some("hermes 0.0.0-fake"));
    assert!(!status.running);

    let browsed = core
        .hermes_skills_browse()
        .await
        .expect("browse official hub");
    assert_eq!(
        browsed
            .iter()
            .map(|item| item.name.as_str())
            .collect::<Vec<_>>(),
        vec!["github-pr-review", "research-brief"]
    );
    assert!(browsed
        .iter()
        .all(|item| item.source == "Hermes Official / Hub"));
    assert_eq!(browsed[0].category, "Software Dev");
    assert_eq!(browsed[0].trust_level, "official");
    assert_eq!(browsed[0].install_ref.as_deref(), Some("github-pr-review"));

    let searched = core
        .hermes_skills_search("github".to_string())
        .await
        .expect("search official hub");
    assert_eq!(searched.len(), 1);
    assert_eq!(searched[0].name, "github-pr-review");

    core.hermes_skills_install("github-pr-review".to_string())
        .await
        .expect("install official skill through hermes");

    assert!(
        !home
            .join("ScripTron")
            .join(".skills")
            .join("github-pr-review")
            .exists(),
        "Hermes Official / Hub installs must not write workspace .skills"
    );

    let log = fs::read_to_string(command_log).expect("read fake hermes command log");
    assert!(log.contains("--version"));
    assert!(log.contains("skills browse --json"));
    assert!(log.contains("skills search github --json"));
    assert!(log.contains("skills install github-pr-review"));
}
