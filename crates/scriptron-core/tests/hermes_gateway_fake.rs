use scriptron_core::ScriptronCore;
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
    let _guard = env_lock().lock().expect("lock env");
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
    let providers = core.get_auth_status().await;
    assert_eq!(providers[0].provider, "hermes");
    assert!(providers[0].connected);
    assert_eq!(providers[0].auth_method, "hermes 0.0.0-fake");

    let browsed = core
        .hermes_skills_browse()
        .await
        .expect("browse official hub");
    assert_eq!(
        browsed
            .iter()
            .map(|item| item.name.as_str())
            .collect::<Vec<_>>(),
        vec!["claude-code", "github-pr-review", "research-brief"]
    );
    assert!(browsed
        .iter()
        .all(|item| item.source == "Hermes Official / Hub"));
    let github_review = browsed
        .iter()
        .find(|item| item.name == "github-pr-review")
        .expect("github review skill should be visible");
    assert_eq!(github_review.category, "Software Dev");
    assert_eq!(github_review.trust_level, "official");
    assert_eq!(
        github_review.install_ref.as_deref(),
        Some("github-pr-review")
    );

    let cli_wrapper = browsed
        .iter()
        .find(|item| item.name == "claude-code")
        .expect("official Hermes CLI wrapper skill should be visible");
    assert!(cli_wrapper.wraps_external_cli);
    assert_eq!(cli_wrapper.tags, vec!["official", "cli", "coding"]);
    assert_eq!(cli_wrapper.icon, "terminal");

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
    assert!(log.contains("skills browse --size 100"));
    assert!(log.contains("skills search github --limit 20"));
    assert!(log.contains("skills install github-pr-review"));
}

#[tokio::test]
async fn fake_hermes_runtime_commands_surface_status_doctor_and_auth() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("stage2-hermes-runtime");
    fs::create_dir_all(&home).expect("create temp home");
    let command_log = home.join("fake-hermes-commands.log");

    std::env::set_var("HOME", &home);
    std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
    std::env::set_var("FAKE_HERMES_LOG", &command_log);

    let core = ScriptronCore::init().await.expect("init core");

    let status = core.hermes_status_report().await.expect("status report");
    assert!(status.success);
    assert!(status.output.contains("Hermes Agent Status"));
    assert!(status.output.contains("OpenAI Codex"));

    let doctor = core.hermes_doctor().await.expect("doctor");
    assert!(doctor.success);
    assert!(doctor.output.contains("Hermes Doctor"));
    assert!(doctor.output.contains("Command Installation"));

    let auth = core
        .hermes_auth_status("codex".to_string())
        .await
        .expect("auth status");
    assert!(auth.success);
    assert!(auth.output.contains("codex: logged in"));

    let log = fs::read_to_string(command_log).expect("read fake hermes command log");
    assert!(log.contains("status"));
    assert!(log.contains("doctor"));
    assert!(log.contains("auth status codex"));
}

#[tokio::test]
async fn fake_hermes_runtime_resolves_common_gui_app_binary_paths_without_shell_path() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("stage2-gui-path");
    let local_bin = home.join(".local").join("bin");
    fs::create_dir_all(&local_bin).expect("create local bin");
    fs::copy(fixture_path("fake-hermes"), local_bin.join("hermes")).expect("copy fake hermes");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(local_bin.join("hermes"), fs::Permissions::from_mode(0o755))
            .expect("chmod fake hermes");
    }
    let command_log = home.join("fake-hermes-commands.log");

    std::env::set_var("HOME", &home);
    std::env::remove_var("SCRIPTRON_HERMES_BIN");
    std::env::set_var("FAKE_HERMES_LOG", &command_log);
    std::env::set_var("PATH", "/usr/bin:/bin:/usr/sbin:/sbin");

    let core = ScriptronCore::init().await.expect("init core");

    let status = core.hermes_status().await.expect("hermes status");
    assert!(status.installed);
    assert_eq!(status.version.as_deref(), Some("hermes 0.0.0-fake"));

    let report = core
        .hermes_status_report()
        .await
        .expect("status report");
    assert!(report.success);
    assert!(report.output.contains("Hermes Agent Status"));

    let log = fs::read_to_string(command_log).expect("read fake hermes command log");
    assert!(log.contains("--version"));
    assert!(log.contains("status"));
}

#[tokio::test]
async fn fake_hermes_provider_link_status_combines_hermes_auth_local_cli_and_api_keys() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("stage2-provider-link");
    fs::create_dir_all(&home).expect("create temp home");
    let command_log = home.join("fake-hermes-commands.log");
    let bin_dir = home.join("bin");
    fs::create_dir_all(&bin_dir).expect("create bin dir");
    fs::write(
        bin_dir.join("codex"),
        "#!/usr/bin/env bash\nprintf 'codex-cli 9.9.9\\n'\n",
    )
    .expect("write fake codex");
    fs::write(
        bin_dir.join("claude"),
        "#!/usr/bin/env bash\nprintf '2.1.999 (Claude Code)\\n'\n",
    )
    .expect("write fake claude");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(bin_dir.join("codex"), fs::Permissions::from_mode(0o755))
            .expect("chmod fake codex");
        fs::set_permissions(bin_dir.join("claude"), fs::Permissions::from_mode(0o755))
            .expect("chmod fake claude");
    }

    std::env::set_var("HOME", &home);
    std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
    std::env::set_var("FAKE_HERMES_LOG", &command_log);
    std::env::set_var(
        "PATH",
        format!(
            "{}:{}",
            bin_dir.display(),
            std::env::var("PATH").unwrap_or_default()
        ),
    );
    std::env::set_var("OPENAI_API_KEY", "sk-test");
    std::env::set_var("ANTHROPIC_API_KEY", "sk-ant-test");

    let core = ScriptronCore::init().await.expect("init core");

    let codex = core
        .hermes_provider_link_status("codex".to_string())
        .await
        .expect("codex link status");
    assert!(codex.success);
    assert!(codex.output.contains("Hermes auth"));
    assert!(codex.output.contains("codex: logged in"));
    assert!(codex.output.contains("Local Codex CLI"));
    assert!(codex.output.contains("codex-cli 9.9.9"));

    let claude = core
        .hermes_provider_link_status("anthropic".to_string())
        .await
        .expect("claude link status");
    assert!(claude.success);
    assert!(claude.output.contains("Claude Code CLI"));
    assert!(claude.output.contains("2.1.999"));
    assert!(claude.output.contains("ANTHROPIC_API_KEY: set"));

    let api = core
        .hermes_provider_link_status("openai".to_string())
        .await
        .expect("api link status");
    assert!(api.success);
    assert!(api.output.contains("OPENAI_API_KEY: set"));

    let log = fs::read_to_string(command_log).expect("read fake hermes command log");
    assert!(log.contains("auth status codex"));
    assert!(log.contains("auth status anthropic"));
    assert!(log.contains("auth status openai"));
}

#[tokio::test]
async fn fake_hermes_internal_setup_saves_provider_api_key_without_leaking_secret() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("stage2-hermes-setup-key");
    let hermes_home = home.join(".hermes");
    fs::create_dir_all(&hermes_home).expect("create hermes home");
    fs::write(
        hermes_home.join(".env"),
        "OPENAI_API_KEY=old-value\nOTHER_SETTING=keep-me\n",
    )
    .expect("seed hermes env");

    std::env::set_var("HOME", &home);
    std::env::set_var("HERMES_HOME", &hermes_home);
    std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));

    let core = ScriptronCore::init().await.expect("init core");
    let secret = "sk-scriptron-secret";
    let report = core
        .hermes_save_api_key("openai".to_string(), secret.to_string())
        .await
        .expect("save api key");

    assert!(report.success);
    assert_eq!(report.exit_code, 0);
    assert!(report.output.contains("OPENAI_API_KEY"));
    assert!(report.output.contains(".env"));
    assert!(!report.output.contains(secret));

    let env_contents = fs::read_to_string(hermes_home.join(".env")).expect("read hermes env");
    assert!(env_contents.contains("OPENAI_API_KEY=sk-scriptron-secret"));
    assert!(env_contents.contains("OTHER_SETTING=keep-me"));
    assert!(!env_contents.contains("OPENAI_API_KEY=old-value"));
}

#[tokio::test]
async fn fake_hermes_internal_setup_test_chat_runs_hermes_chat() {
    let _guard = env_lock().lock().expect("lock env");
    let home = unique_temp_home("stage2-hermes-setup-chat");
    fs::create_dir_all(&home).expect("create temp home");
    let command_log = home.join("fake-hermes-commands.log");

    std::env::set_var("HOME", &home);
    std::env::remove_var("HERMES_HOME");
    std::env::set_var("SCRIPTRON_HERMES_BIN", fixture_path("fake-hermes"));
    std::env::set_var("FAKE_HERMES_LOG", &command_log);

    let core = ScriptronCore::init().await.expect("init core");
    let report = core.hermes_test_chat().await.expect("test chat");

    assert!(report.success);
    assert!(report.output.contains("Fake Hermes response"));

    let log = fs::read_to_string(command_log).expect("read fake hermes command log");
    assert!(log.contains("chat -q"));
    assert!(log.contains("SCRIPTRON_E2E_OK"));
}
