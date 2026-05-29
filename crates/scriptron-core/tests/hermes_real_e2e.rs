use scriptron_core::ScriptronCore;
use std::{
    fs,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

fn unique_temp_home(label: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!("scriptron-{label}-{}-{nanos}", std::process::id()))
}

#[tokio::test]
async fn real_hermes_skills_browse_search_hits_official_repository() {
    if std::env::var("SCRIPTRON_RUN_REAL_HERMES_E2E").as_deref() != Ok("1") {
        eprintln!("skipping real Hermes E2E: set SCRIPTRON_RUN_REAL_HERMES_E2E=1");
        return;
    }

    if let Ok(bin) = std::env::var("SCRIPTRON_REAL_HERMES_BIN") {
        std::env::set_var("SCRIPTRON_HERMES_BIN", bin);
    }

    let home = unique_temp_home("real-hermes-e2e");
    fs::create_dir_all(&home).expect("create temp home");
    std::env::set_var("HOME", &home);
    std::env::set_var("HERMES_HOME", home.join(".hermes"));

    let core = ScriptronCore::init().await.expect("init core");
    let status = core.hermes_status().await.expect("hermes status");
    assert!(
        status.installed,
        "real Hermes binary not available: {:?}",
        status.diagnostic
    );

    let browsed = core
        .hermes_skills_browse()
        .await
        .expect("browse real Hermes official skill repository");
    assert!(
        !browsed.is_empty(),
        "Hermes official skills browse returned no items"
    );
    assert!(browsed
        .iter()
        .all(|item| item.source == "Hermes Official / Hub"));
    assert!(
        browsed.iter().any(|item| item.trust_level == "official"),
        "expected at least one official Hermes skill, got {:?}",
        browsed
            .iter()
            .map(|item| (item.name.as_str(), item.trust_level.as_str()))
            .take(20)
            .collect::<Vec<_>>()
    );
    assert!(
        browsed.iter().any(|item| item.wraps_external_cli),
        "expected Hermes browse to expose official CLI wrapper skills, got first items: {:?}",
        browsed
            .iter()
            .map(|item| (
                item.name.as_str(),
                item.description.as_str(),
                item.wraps_external_cli,
                item.tags.as_slice(),
                item.icon.as_str()
            ))
            .take(20)
            .collect::<Vec<_>>()
    );
    assert!(
        browsed
            .iter()
            .filter(|item| item.wraps_external_cli)
            .all(|item| item.tags.iter().any(|tag| tag == "cli") && item.icon == "terminal"),
        "CLI wrapper catalog items must carry cli tag and terminal icon"
    );

    let searched = core
        .hermes_skills_search("github".to_string())
        .await
        .expect("search real Hermes official skill repository");
    assert!(
        !searched.is_empty(),
        "Hermes skill search returned no results"
    );
    assert!(searched
        .iter()
        .all(|item| item.source == "Hermes Official / Hub"));
}
