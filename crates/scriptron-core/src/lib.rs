use agent_loop::{
    AgentLoop, AnthropicProvider, CliModelProvider, ExecutionEvent, GeminiProvider, LlmProvider,
    OpenAiCompatProvider,
};
use auth::{all_provider_statuses, AppConfig, AuthManager, Credentials, Provider, ProviderStatus};
use chrono::Utc;
use cli_registry::{CliKind, CliRegistry, ToolManifest};
use process_runner::{ProcessConfig, ProcessRunner};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::Arc,
};
use tokio::sync::{mpsc, RwLock};
use tron_parser::{TronCell, TronFile, TronTask};

#[derive(Debug, Serialize, Deserialize)]
pub struct TronFileDto {
    pub path: String,
    pub cells: Vec<TronCell>,
    pub blackboard: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_tron: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ActiveConfig {
    pub provider: String,
    pub model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryNote {
    pub id: String,
    pub scope: String,
    pub content: String,
    pub source: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalMemory {
    pub user_name_preference: String,
    pub agent_style_preference: String,
    pub execution_rules: Vec<String>,
    pub notes: Vec<MemoryNote>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMemory {
    pub project_path: String,
    pub project_name: String,
    pub archived: bool,
    pub format_rules: Vec<String>,
    pub task_constraints: Vec<String>,
    pub glossary: BTreeMap<String, String>,
    pub long_context: Vec<MemoryNote>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterInfo {
    pub path: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRetryAttempt {
    pub attempt: u32,
    pub status: String,
    pub reason: String,
    pub correction: String,
    pub input: serde_json::Value,
    pub output: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRetryTrace {
    pub id: String,
    pub skill: String,
    pub status: String,
    pub attempts: Vec<SkillRetryAttempt>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronerMemory {
    pub schema_version: u32,
    pub global_memory: GlobalMemory,
    pub projects: BTreeMap<String, ProjectMemory>,
    pub register: RegisterInfo,
    pub skill_retry_traces: Vec<SkillRetryTrace>,
    pub audit_log: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySnapshot {
    pub global_memory: GlobalMemory,
    pub project_memory: ProjectMemory,
    pub effective_prompt: String,
    pub skill_retry_traces: Vec<SkillRetryTrace>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronMentionModule {
    pub name: String,
    pub kind: String,
    pub injection: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MentionItem {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub path: String,
    pub detail: String,
    pub installed: bool,
    pub modules: Vec<TronMentionModule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MentionSearchResult {
    pub tools: Vec<MentionItem>,
    pub files: Vec<MentionItem>,
    pub cloud_suggestions: Vec<MentionItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TronhubEntry {
    pub name: String,
    pub kind: String,
    pub description: String,
    pub source_path: String,
    pub installed: bool,
    pub manifest_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillEntry {
    pub name: String,
    pub description: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillIndexEntry {
    pub name: String,
    pub description: String,
    pub path: String,
    pub required_clis: Vec<String>,
    pub capabilities: Vec<String>,
    pub tags: Vec<String>,
    pub document: String,
    pub tokens: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunTaskPreviewResult {
    pub events: Vec<ExecutionEvent>,
    pub blackboard: serde_json::Value,
    pub log_path: String,
}

pub struct ScriptronCore {
    registry: Arc<RwLock<CliRegistry>>,
    auth: Arc<AuthManager>,
    workspace_dir: PathBuf,
    config: Arc<RwLock<AppConfig>>,
    config_path: PathBuf,
    runner: ProcessRunner,
}

impl ScriptronCore {
    pub async fn init() -> anyhow::Result<Self> {
        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("."));

        let data_dir = home.join(".scriptron");
        let legacy_registry_dir = data_dir.join("registry");
        let auth_dir = data_dir.join("credentials");
        let config_path = data_dir.join("config.json");
        let workspace_dir = home.join("ScripTron");
        let registry_dir = workspace_dir.join(".register");

        tokio::fs::create_dir_all(&workspace_dir).await?;
        ensure_workspace_layout(&workspace_dir).await?;
        migrate_legacy_registry(&legacy_registry_dir, &registry_dir).await?;
        let bootstrap_runner = ProcessRunner::new();
        let _ = sync_tronhub_cache(&workspace_dir, &bootstrap_runner).await;
        tokio::fs::create_dir_all(&auth_dir).await?;

        Ok(Self {
            registry: Arc::new(RwLock::new(CliRegistry::load(&registry_dir).await?)),
            auth: Arc::new(AuthManager::new(auth_dir)),
            workspace_dir,
            config: Arc::new(RwLock::new(AppConfig::load(&config_path))),
            config_path,
            runner: ProcessRunner::new(),
        })
    }

    pub fn workspace_path(&self) -> String {
        self.workspace_dir.to_string_lossy().into_owned()
    }

    pub async fn list_workspace_files(&self) -> Result<Vec<FileEntry>, String> {
        list_dir(self.workspace_dir.clone()).await
    }

    pub async fn list_dir_files(&self, path: String) -> Result<Vec<FileEntry>, String> {
        list_dir(PathBuf::from(path)).await
    }

    pub async fn open_tron_file(&self, path: String) -> Result<TronFileDto, String> {
        tron_parser::parse_file(&path)
            .map(|f| TronFileDto {
                path: f.path.to_string_lossy().into_owned(),
                cells: f.cells,
                blackboard: f.blackboard,
            })
            .map_err(|e| e.to_string())
    }

    pub async fn save_tron_file(
        &self,
        path: String,
        cells: Vec<TronCell>,
        blackboard: Option<serde_json::Value>,
    ) -> Result<(), String> {
        let content = tron_parser::serialize_with_blackboard(
            &cells,
            &blackboard.unwrap_or_else(|| serde_json::json!({})),
        );
        tokio::fs::write(path, content)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn create_tron_file(&self, path: String) -> Result<TronFileDto, String> {
        let cells = Vec::<TronCell>::new();
        let blackboard = serde_json::json!({ "entries": [], "notes": [] });
        let content = tron_parser::serialize_with_blackboard(&cells, &blackboard);
        tokio::fs::write(&path, &content)
            .await
            .map_err(|e| e.to_string())?;
        Ok(TronFileDto {
            path,
            cells,
            blackboard,
        })
    }

    pub async fn list_tools(&self) -> Vec<ToolManifest> {
        self.registry.read().await.list_tools().to_vec()
    }

    pub async fn install_tool_from_json(&self, manifest_json: String) -> Result<(), String> {
        let manifest: ToolManifest =
            serde_json::from_str(&manifest_json).map_err(|e| e.to_string())?;
        self.registry
            .write()
            .await
            .install_tool(manifest)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn remove_tool(&self, name: String) -> Result<(), String> {
        self.registry
            .write()
            .await
            .remove_tool(&name)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn sync_tronhub(&self) -> Result<(), String> {
        sync_tronhub_cache(&self.workspace_dir, &self.runner)
            .await
            .map_err(|e| e.to_string())?;
        self.registry
            .write()
            .await
            .reload()
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn list_tronhub(&self, kind: String) -> Result<Vec<TronhubEntry>, String> {
        list_tronhub_entries(&self.workspace_dir, &kind)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn install_tronhub(&self, kind: String, name: String) -> Result<(), String> {
        install_tronhub_entry(&self.workspace_dir, &kind, &name)
            .await
            .map_err(|e| e.to_string())?;
        if kind == "skill" || kind == "skills" {
            install_skill_tool_adapters(&self.workspace_dir, &name)
                .await
                .map_err(|e| e.to_string())?;
            rebuild_skill_index(&self.workspace_dir)
                .await
                .map_err(|e| e.to_string())?;
        }
        if kind == "cli" || kind == "model" || kind == "skill" || kind == "skills" {
            self.registry
                .write()
                .await
                .reload()
                .await
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    pub async fn list_skills(&self) -> Result<Vec<SkillEntry>, String> {
        list_installed_skills(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn remove_skill(&self, name: String) -> Result<(), String> {
        let path = self.workspace_dir.join(".skills").join(safe_name(&name));
        if path.exists() {
            tokio::fs::remove_dir_all(path)
                .await
                .map_err(|e| e.to_string())?;
        }
        rebuild_skill_index(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn get_auth_status(&self) -> Vec<ProviderStatus> {
        all_provider_statuses(&self.auth).await
    }

    /// Run a TronHub plugin's `install.sh` to install the underlying tool/CLI.
    /// `kind` is "model" or "cli". Returns the script's combined output.
    /// On success, writes a `.installed` marker file inside the plugin directory.
    pub async fn run_plugin_install_script(
        &self,
        kind: String,
        name: String,
    ) -> Result<String, String> {
        let target_dir = installed_kind_dir(&self.workspace_dir, &kind).join(safe_name(&name));
        if !target_dir.exists() {
            return Err(format!("Plugin '{}' is not installed", name));
        }
        let script_path = target_dir.join("install.sh");
        if !script_path.exists() {
            // No install.sh: treat as already installed.
            let _ = tokio::fs::write(target_dir.join(".installed"), b"").await;
            return Ok(format!("No install.sh for '{}', skipping.", name));
        }
        let result = self
            .runner
            .run(
                ProcessConfig::new("bash", vec![script_path.to_string_lossy().into_owned()])
                    .with_working_dir(target_dir.clone())
                    .with_timeout(600)
                    .with_env("PATH", plugin_runtime_path()),
            )
            .await
            .map_err(|e| e.to_string())?;
        if !result.success() {
            return Err(result.combined_output());
        }
        let _ = tokio::fs::write(target_dir.join(".installed"), b"").await;
        Ok(result.combined_output())
    }

    /// Returns names of installed plugins whose dependencies have been installed
    /// (i.e. `.installed` marker exists in the plugin directory).
    pub async fn list_installed_dependencies(&self) -> Vec<String> {
        let mut out = Vec::new();
        for kind in ["model", "cli"] {
            let dir = installed_kind_dir(&self.workspace_dir, kind);
            let mut rd = match tokio::fs::read_dir(&dir).await {
                Ok(rd) => rd,
                Err(_) => continue,
            };
            while let Ok(Some(entry)) = rd.next_entry().await {
                let path = entry.path();
                if path.is_dir() && path.join(".installed").exists() {
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        out.push(name.to_string());
                    }
                }
            }
        }
        out
    }

    /// Run a TronHub plugin's `--action login` flow (OAuth or device code).
    pub async fn run_plugin_login(&self, name: String) -> Result<String, String> {
        let manifest = {
            let registry = self.registry.read().await;
            registry
                .get_tool(&name)
                .cloned()
                .ok_or_else(|| format!("Plugin '{}' not found", name))?
        };
        let working_dir = std::path::Path::new(&manifest.command)
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| self.workspace_dir.clone());
        let result = self
            .runner
            .run(
                ProcessConfig::new(
                    &manifest.command,
                    vec!["--action".to_string(), "login".to_string()],
                )
                .with_working_dir(working_dir)
                .with_timeout(300)
                .with_env("PATH", plugin_runtime_path()),
            )
            .await
            .map_err(|e| e.to_string())?;
        if !result.success() {
            return Err(result.combined_output());
        }
        Ok(result.combined_output())
    }

    pub async fn store_api_key(&self, provider: String, api_key: String) -> Result<(), String> {
        let p = parse_provider(&provider)?;
        self.auth
            .store(&p, &Credentials::from_api_key(api_key))
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn disconnect_provider(&self, provider: String) -> Result<(), String> {
        let p = parse_provider(&provider)?;
        self.auth.delete(&p).await.map_err(|e| e.to_string())
    }

    pub async fn get_active_config(&self) -> ActiveConfig {
        let cfg = self.config.read().await.clone();
        ActiveConfig {
            provider: cfg.active_provider.id().into(),
            model: cfg.active_model,
        }
    }

    pub async fn set_active_config(&self, provider: String, model: String) -> Result<(), String> {
        let active_provider = parse_provider(&provider)?;
        let cfg = AppConfig {
            active_provider,
            active_model: model,
        };
        cfg.save(&self.config_path).map_err(|e| e.to_string())?;
        *self.config.write().await = cfg;
        Ok(())
    }

    pub async fn build_task(
        &self,
        cells: Vec<TronCell>,
        project_path: String,
        blackboard: Option<serde_json::Value>,
    ) -> serde_json::Value {
        let file = TronFile {
            path: PathBuf::from("task.tron"),
            cells,
            blackboard: blackboard.unwrap_or_else(|| serde_json::json!({})),
        };
        serde_json::to_value(file.build_task(PathBuf::from(project_path)))
            .unwrap_or_else(|_| serde_json::json!({}))
    }

    pub async fn run_tron_task(
        &self,
        cells: Vec<TronCell>,
        project_path: String,
        blackboard: Option<serde_json::Value>,
    ) -> Result<Vec<ExecutionEvent>, String> {
        let project_path = PathBuf::from(project_path);
        let blackboard = blackboard.unwrap_or_else(|| serde_json::json!({}));
        self.run_orchestrated_tron_task(cells, project_path, blackboard)
            .await
    }

    pub async fn run_tron_task_preview(
        &self,
        cells: Vec<TronCell>,
        project_path: String,
        blackboard: Option<serde_json::Value>,
        tron_path: Option<String>,
    ) -> Result<RunTaskPreviewResult, String> {
        let mut blackboard = blackboard.unwrap_or_else(|| serde_json::json!({}));
        let log_path = run_log_path(tron_path.as_deref(), &project_path);
        let mut events = vec![ExecutionEvent::Warning {
            message: format!("Run started. Log file: {}", log_path.display()),
        }];
        events.extend(
            self.run_orchestrated_tron_task(
                cells.clone(),
                PathBuf::from(project_path),
                blackboard.clone(),
            )
            .await?,
        );
        let response = events
            .iter()
            .filter_map(|event| match event {
                ExecutionEvent::Text { content } => Some(content.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        update_blackboard_notes(
            &mut blackboard,
            &response,
            tron_path.as_deref().unwrap_or("run"),
        );
        if let Some(path) = tron_path {
            self.save_tron_file(path, cells, Some(blackboard.clone()))
                .await?;
        }
        write_run_log(&log_path, &events).await?;
        Ok(RunTaskPreviewResult {
            events,
            blackboard,
            log_path: log_path.to_string_lossy().into_owned(),
        })
    }

    async fn run_orchestrated_tron_task(
        &self,
        cells: Vec<TronCell>,
        project_path: PathBuf,
        blackboard: serde_json::Value,
    ) -> Result<Vec<ExecutionEvent>, String> {
        let graph = build_function_graph(&cells, &project_path)?;
        if graph.roots.is_empty() {
            return Ok(vec![
                ExecutionEvent::Error {
                    message: "No run cells to execute.".into(),
                },
                ExecutionEvent::Complete,
            ]);
        }

        let plan = build_execution_plan(&graph)?;
        let provider = self.agent_provider(&project_path).await?;
        let mut outputs: HashMap<String, String> = HashMap::new();

        for level in plan {
            let mut handles = Vec::new();
            for name in level {
                let function = graph
                    .functions
                    .get(&name)
                    .cloned()
                    .ok_or_else(|| format!("Missing function '{name}'"))?;
                let dependency_context = graph
                    .refs
                    .get(&name)
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .filter_map(|dep| outputs.get(&dep).map(|out| (dep, out.clone())))
                    .map(|(dep, out)| format!("### Referenced function: {dep}\n\n{out}"))
                    .collect::<Vec<_>>();
                let task = TronTask {
                    instructions: vec![function.body.clone()],
                    context: graph
                        .context
                        .iter()
                        .cloned()
                        .chain(function.context.iter().cloned())
                        .chain(dependency_context)
                        .collect(),
                    blackboard: blackboard.clone(),
                    project_path: project_path.clone(),
                };
                let agent = AgentLoop::new(provider.clone(), self.registry.clone());
                handles.push(tokio::spawn(async move {
                    let (output, events) = run_agent_to_events(agent, task).await?;
                    Ok::<(String, String, Vec<ExecutionEvent>), String>((name, output, events))
                }));
            }

            let mut level_events = Vec::new();
            for handle in handles {
                let (name, output, events) = handle.await.map_err(|e| e.to_string())??;
                outputs.insert(name, output);
                level_events.extend(events);
            }
            outputs.insert(
                format!("__events_{}", outputs.len()),
                serde_json::to_string(&level_events).unwrap_or_default(),
            );
        }

        let mut response = String::new();
        for root in &graph.roots {
            if let Some(output) = outputs.get(root) {
                if graph.roots.len() > 1 {
                    response.push_str(&format!("## {root}\n\n{output}\n\n"));
                } else {
                    response.push_str(output);
                }
            }
        }

        let mut events = Vec::new();
        let mut internal_event_keys = outputs
            .keys()
            .filter(|key| key.starts_with("__events_"))
            .cloned()
            .collect::<Vec<_>>();
        internal_event_keys.sort();
        for key in internal_event_keys {
            if let Some(raw) = outputs.get(&key) {
                if let Ok(mut parsed) = serde_json::from_str::<Vec<ExecutionEvent>>(raw) {
                    events.append(&mut parsed);
                }
            }
        }
        events.push(ExecutionEvent::Text {
            content: response.trim().to_string(),
        });
        events.push(ExecutionEvent::Complete);
        Ok(events)
    }

    pub async fn get_memory_snapshot(
        &self,
        project_path: Option<String>,
    ) -> Result<MemorySnapshot, String> {
        let mut memory = self.load_troner_memory().await?;
        let project_path = project_path.unwrap_or_default();
        let project_memory = ensure_project_memory(&mut memory, &project_path);
        self.save_troner_memory(&memory).await?;
        let effective_prompt =
            build_effective_memory_prompt(&memory.global_memory, &project_memory);
        Ok(MemorySnapshot {
            global_memory: memory.global_memory,
            project_memory,
            effective_prompt,
            skill_retry_traces: memory.skill_retry_traces,
        })
    }

    pub async fn update_global_memory(
        &self,
        global_memory: GlobalMemory,
    ) -> Result<TronerMemory, String> {
        let mut memory = self.load_troner_memory().await?;
        memory.global_memory = global_memory;
        memory
            .audit_log
            .push(audit_event("memory.global.update", serde_json::json!({})));
        self.save_troner_memory(&memory).await?;
        Ok(memory)
    }

    pub async fn factory_reset_app_state(&self) -> Result<(), String> {
        let hidden_dirs = [".register", ".skills", ".tronhub"];
        for dir in hidden_dirs {
            let path = self.workspace_dir.join(dir);
            if path.exists() {
                tokio::fs::remove_dir_all(&path)
                    .await
                    .map_err(|e| e.to_string())?;
            }
        }

        let memory_path = self.workspace_dir.join(".troner.json");
        if memory_path.exists() {
            tokio::fs::remove_file(&memory_path)
                .await
                .map_err(|e| e.to_string())?;
        }

        let default_config = AppConfig::default();
        default_config
            .save(&self.config_path)
            .map_err(|e| e.to_string())?;
        *self.config.write().await = default_config;

        ensure_workspace_layout(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?;
        let _ = sync_tronhub_cache(&self.workspace_dir, &self.runner).await;
        self.registry
            .write()
            .await
            .reload()
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub async fn update_project_memory(
        &self,
        project_memory: ProjectMemory,
    ) -> Result<TronerMemory, String> {
        let mut memory = self.load_troner_memory().await?;
        memory
            .projects
            .insert(project_memory.project_path.clone(), project_memory);
        memory
            .audit_log
            .push(audit_event("memory.project.update", serde_json::json!({})));
        self.save_troner_memory(&memory).await?;
        Ok(memory)
    }

    pub async fn run_adaptive_skill(
        &self,
        skill: String,
        input: serde_json::Value,
        max_retries: u32,
        dry_run: bool,
    ) -> Result<SkillRetryTrace, String> {
        let mut memory = self.load_troner_memory().await?;
        let registry = self.registry.read().await;
        let installed = registry.get_tool(&skill).is_some();
        drop(registry);

        let mut attempts = Vec::new();
        let started = now();
        let mut status = "failed".to_string();
        let max_retries = max_retries.clamp(1, 5);

        for attempt in 1..=max_retries {
            let (attempt_status, reason, correction, output) = if !installed {
                (
                    "failed",
                    "command_not_registered",
                    "Check .register for a matching model/tool CLI manifest before retrying.",
                    format!("CLI skill '{skill}' is not registered."),
                )
            } else if dry_run {
                (
                    "planned",
                    "dry_run",
                    "Validated registry presence without executing the command.",
                    format!("Dry-run accepted for skill '{skill}'."),
                )
            } else {
                (
                    "planned",
                    "execution_deferred",
                    "Execution is deferred to the Project Orchestrator safety gate.",
                    format!("Skill '{skill}' is registered and ready for orchestrated execution."),
                )
            };

            attempts.push(SkillRetryAttempt {
                attempt,
                status: attempt_status.into(),
                reason: reason.into(),
                correction: correction.into(),
                input: input.clone(),
                output,
                created_at: now(),
            });

            if installed {
                status = if dry_run { "planned" } else { "ready" }.into();
                break;
            }
        }

        let trace = SkillRetryTrace {
            id: format!("skill-{}", Utc::now().timestamp_millis()),
            skill,
            status,
            attempts,
            created_at: started,
        };
        memory.skill_retry_traces.insert(0, trace.clone());
        memory.skill_retry_traces.truncate(50);
        memory.audit_log.push(audit_event(
            "skill.retry.trace",
            serde_json::to_value(&trace).unwrap_or_default(),
        ));
        self.save_troner_memory(&memory).await?;
        Ok(trace)
    }

    pub async fn search_mentions(
        &self,
        query: String,
        project_path: Option<String>,
    ) -> Result<MentionSearchResult, String> {
        let query = query.trim().to_lowercase();
        let mut tools = list_installed_skills(&self.workspace_dir)
            .await
            .map_err(|e| e.to_string())?
            .iter()
            .filter(|skill| {
                query.is_empty()
                    || skill.name.to_lowercase().contains(&query)
                    || skill.description.to_lowercase().contains(&query)
            })
            .map(|skill| MentionItem {
                id: format!("skill:{}", skill.name),
                label: skill.name.clone(),
                kind: "skill".into(),
                path: skill.path.clone(),
                detail: skill.description.clone(),
                installed: true,
                modules: Vec::new(),
            })
            .collect::<Vec<_>>();
        tools.sort_by(|a, b| a.label.cmp(&b.label));

        let root = project_path
            .filter(|path| !path.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.workspace_dir.clone());
        let files = search_files(&root, &query).await?;
        let cloud_suggestions = marketplace_suggestions(&query);

        Ok(MentionSearchResult {
            tools,
            files,
            cloud_suggestions,
        })
    }

    pub async fn record_mention_reference(
        &self,
        reference: serde_json::Value,
    ) -> Result<(), String> {
        let mut memory = self.load_troner_memory().await?;
        memory
            .audit_log
            .push(audit_event("mention.reference", reference));
        self.save_troner_memory(&memory).await
    }

    pub async fn troner_agent_message(
        &self,
        message: String,
        project_path: Option<String>,
    ) -> Result<String, String> {
        let cwd = project_path
            .filter(|path| !path.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.workspace_dir.clone());
        let memory = self
            .get_memory_snapshot(Some(cwd.to_string_lossy().into_owned()))
            .await?;
        let prompt = format!(
            "Memory context:\n{}\n\nUser request:\n{}",
            memory.effective_prompt, message
        );
        let provider = self.agent_provider(&cwd).await?;
        let agent = AgentLoop::new(provider, self.registry.clone());
        let task = TronTask {
            instructions: vec![prompt],
            context: Vec::new(),
            blackboard: serde_json::json!({}),
            project_path: cwd,
        };
        let (tx, mut rx) = mpsc::channel(128);
        let handle = tokio::spawn(async move { agent.run(task, tx).await });
        let mut transcript = Vec::new();

        while let Some(event) = rx.recv().await {
            if let Some(line) = format_agent_event(&event) {
                transcript.push(line);
            }
            if matches!(event, ExecutionEvent::Complete) {
                break;
            }
        }

        let result = handle.await.map_err(|e| e.to_string())?;
        if let Err(error) = result {
            transcript.push(format!("Error: {error}"));
        }
        let output = transcript.join("\n\n");
        let mut troner = self.load_troner_memory().await?;
        troner.audit_log.push(audit_event(
            "agent.embedded",
            serde_json::json!({
                "message": message,
                "events": transcript.len(),
            }),
        ));
        self.save_troner_memory(&troner).await?;
        if output.trim().is_empty() {
            Ok("(Troner Agent completed without output.)".into())
        } else {
            Ok(output)
        }
    }

    async fn agent_provider(
        &self,
        project_path: &Path,
    ) -> Result<Arc<dyn LlmProvider + Send + Sync>, String> {
        let cfg = self.config.read().await.clone();
        // If the active model matches an installed CLI model plugin, use it.
        let model_cli = {
            let registry = self.registry.read().await;
            registry
                .get_tool(&cfg.active_model)
                .filter(|tool| tool.kind == CliKind::Model)
                .cloned()
        };
        if let Some(model_cli) = model_cli {
            return Ok(Arc::new(CliModelProvider::new(
                model_cli,
                project_path.to_path_buf(),
            )));
        }
        // Otherwise, use the active provider's API key.
        let token = self.auth.access_token(&cfg.active_provider).await.map_err(|e| {
            format!(
                "No credentials for {}. Connect this provider in Model Management before running the embedded agent. ({})",
                cfg.active_provider.id(),
                e
            )
        })?;
        let provider: Arc<dyn LlmProvider + Send + Sync> = match cfg.active_provider {
            Provider::Anthropic => {
                Arc::new(AnthropicProvider::new(token).with_model(cfg.active_model))
            }
            Provider::Gemini => Arc::new(GeminiProvider::new(token).with_model(cfg.active_model)),
            Provider::OpenAi => Arc::new(OpenAiCompatProvider::new_openai(token, cfg.active_model)),
            Provider::DeepSeek => {
                Arc::new(OpenAiCompatProvider::new_deepseek(token, cfg.active_model))
            }
            Provider::OpenRouter => Arc::new(OpenAiCompatProvider::new_openrouter(
                token,
                cfg.active_model,
            )),
        };
        Ok(provider)
    }

    async fn load_troner_memory(&self) -> Result<TronerMemory, String> {
        let path = self.workspace_dir.join(".troner.json");
        let raw = tokio::fs::read_to_string(&path)
            .await
            .map_err(|e| e.to_string())?;
        serde_json::from_str(&raw).map_err(|e| e.to_string())
    }

    async fn save_troner_memory(&self, memory: &TronerMemory) -> Result<(), String> {
        let path = self.workspace_dir.join(".troner.json");
        let json = serde_json::to_string_pretty(memory).map_err(|e| e.to_string())?;
        tokio::fs::write(path, json)
            .await
            .map_err(|e| e.to_string())
    }
}

#[derive(Debug, Clone)]
struct TronFunction {
    body: String,
    context: Vec<String>,
}

#[derive(Debug)]
struct FunctionGraph {
    roots: Vec<String>,
    functions: HashMap<String, TronFunction>,
    refs: HashMap<String, Vec<String>>,
    context: Vec<String>,
}

const RUN_NAME_PREFIX: &str = "[[scriptron:run-name]]";
const GEN_CELL_PREFIX: &str = "[[scriptron:gen-markdown]]";

async fn run_agent_to_events(
    agent: AgentLoop,
    task: TronTask,
) -> Result<(String, Vec<ExecutionEvent>), String> {
    let (tx, mut rx) = mpsc::channel(128);
    let handle = tokio::spawn(async move { agent.run(task, tx).await });
    let mut text = Vec::new();
    let mut events = Vec::new();
    while let Some(event) = rx.recv().await {
        match event {
            ExecutionEvent::Text { content } => {
                text.push(content.clone());
                events.push(ExecutionEvent::Text { content });
            }
            ExecutionEvent::Error { message } => {
                events.push(ExecutionEvent::Error {
                    message: message.clone(),
                });
                return Err(message);
            }
            ExecutionEvent::Complete => {
                events.push(ExecutionEvent::Complete);
                break;
            }
            other => events.push(other),
        }
    }
    handle
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())?;
    Ok((text.join("\n\n").trim().to_string(), events))
}

fn build_function_graph(cells: &[TronCell], project_path: &Path) -> Result<FunctionGraph, String> {
    let current_context = cells
        .iter()
        .filter(|cell| !cell.run)
        .map(|cell| cell.content.trim().to_string())
        .filter(|content| !content.is_empty())
        .collect::<Vec<_>>();
    let mut roots = Vec::new();
    let mut functions = HashMap::<String, TronFunction>::new();

    for (index, cell) in cells.iter().enumerate() {
        if !cell.run || cell.content.starts_with(GEN_CELL_PREFIX) {
            continue;
        }
        let (name, body) = parse_run_function(&cell.content, index);
        roots.push(name.clone());
        functions.insert(
            name.clone(),
            TronFunction {
                body,
                context: Vec::new(),
            },
        );
    }

    for (path, file_cells) in project_tron_cells(project_path)? {
        let file_context = file_cells
            .iter()
            .filter(|cell| !cell.run)
            .map(|cell| cell.content.trim().to_string())
            .filter(|content| !content.is_empty())
            .collect::<Vec<_>>();
        for (index, cell) in file_cells.iter().enumerate() {
            if !cell.run || cell.content.starts_with(GEN_CELL_PREFIX) {
                continue;
            }
            let (name, body) = parse_run_function(&cell.content, index);
            functions
                .entry(name.clone())
                .or_insert_with(|| TronFunction {
                    body,
                    context: vec![format!(
                        "Context from referenced .tron file {}:\n{}",
                        path.display(),
                        file_context.join("\n\n")
                    )],
                });
        }
    }

    let names = functions.keys().cloned().collect::<Vec<_>>();
    let refs = functions
        .iter()
        .map(|(name, function)| {
            (
                name.clone(),
                extract_known_function_refs(&function.body, &names, name),
            )
        })
        .collect::<HashMap<_, _>>();

    Ok(FunctionGraph {
        roots,
        functions,
        refs,
        context: current_context,
    })
}

fn build_execution_plan(graph: &FunctionGraph) -> Result<Vec<Vec<String>>, String> {
    let mut needed = BTreeSet::new();
    let mut depths = HashMap::<String, usize>::new();
    let mut visiting = Vec::<String>::new();

    fn visit(
        name: &str,
        graph: &FunctionGraph,
        needed: &mut BTreeSet<String>,
        depths: &mut HashMap<String, usize>,
        visiting: &mut Vec<String>,
    ) -> Result<usize, String> {
        if let Some(depth) = depths.get(name) {
            needed.insert(name.to_string());
            return Ok(*depth);
        }
        if visiting.iter().any(|item| item == name) {
            let mut cycle = visiting.clone();
            cycle.push(name.to_string());
            return Err(format!(
                "Circular run-cell reference detected: {}",
                cycle.join(" -> ")
            ));
        }
        if !graph.functions.contains_key(name) {
            return Err(format!("Missing referenced run-cell function: {name}"));
        }
        visiting.push(name.to_string());
        let mut max_child = 0;
        for dep in graph.refs.get(name).cloned().unwrap_or_default() {
            max_child = max_child.max(visit(&dep, graph, needed, depths, visiting)?);
        }
        visiting.pop();
        let depth = max_child + 1;
        if depth > 5 {
            return Err(format!(
                "Reference tree is deeper than 5 levels near {name}."
            ));
        }
        depths.insert(name.to_string(), depth);
        needed.insert(name.to_string());
        Ok(depth)
    }

    for root in &graph.roots {
        visit(root, graph, &mut needed, &mut depths, &mut visiting)?;
    }

    let mut by_depth = BTreeMap::<usize, Vec<String>>::new();
    for name in needed {
        let depth = depths.get(&name).copied().unwrap_or(1);
        by_depth.entry(depth).or_default().push(name);
    }
    Ok(by_depth.into_values().collect())
}

fn parse_run_function(content: &str, index: usize) -> (String, String) {
    let mut lines = content.lines().collect::<Vec<_>>();
    if let Some(first) = lines.first() {
        if first.starts_with(RUN_NAME_PREFIX) {
            let name = first.trim_start_matches(RUN_NAME_PREFIX).trim().to_string();
            lines.remove(0);
            let body = lines.join("\n").trim().to_string();
            if !name.is_empty() {
                return (name, body);
            }
        }
    }
    (
        content
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .map(|line| line.chars().take(40).collect::<String>())
            .unwrap_or_else(|| format!("run_{}", index + 1)),
        content.trim().to_string(),
    )
}

fn extract_known_function_refs(content: &str, names: &[String], self_name: &str) -> Vec<String> {
    let mut out = names
        .iter()
        .filter(|name| name.as_str() != self_name)
        .filter(|name| {
            content.contains(&format!("@{name}")) || content.contains(&format!("#{name}"))
        })
        .cloned()
        .collect::<Vec<_>>();
    out.sort();
    out.dedup();
    out
}

fn project_tron_cells(project_path: &Path) -> Result<Vec<(PathBuf, Vec<TronCell>)>, String> {
    fn walk(dir: &Path, out: &mut Vec<(PathBuf, Vec<TronCell>)>) -> Result<(), String> {
        let entries = match std::fs::read_dir(dir) {
            Ok(entries) => entries,
            Err(_) => return Ok(()),
        };
        for entry in entries {
            let entry = entry.map_err(|e| e.to_string())?;
            let path = entry.path();
            if path
                .file_name()
                .and_then(|name| name.to_str())
                .map(|name| name.starts_with('.'))
                .unwrap_or(false)
            {
                continue;
            }
            if path.is_dir() {
                walk(&path, out)?;
            } else if path.extension().and_then(|ext| ext.to_str()) == Some("tron") {
                if let Ok(file) = tron_parser::parse_file(&path) {
                    out.push((path, file.cells));
                }
            }
        }
        Ok(())
    }

    let mut out = Vec::new();
    walk(project_path, &mut out)?;
    Ok(out)
}

fn update_blackboard_notes(blackboard: &mut serde_json::Value, response: &str, source: &str) {
    let summary = summarize_run_note(response);
    if summary.is_empty() {
        return;
    }
    if !blackboard.is_object() {
        *blackboard = serde_json::json!({});
    }
    let Some(obj) = blackboard.as_object_mut() else {
        return;
    };
    let notes = obj
        .entry("notes")
        .or_insert_with(|| serde_json::Value::Array(Vec::new()));
    if !notes.is_array() {
        *notes = serde_json::Value::Array(Vec::new());
    }
    let Some(items) = notes.as_array_mut() else {
        return;
    };
    items.insert(
        0,
        serde_json::json!({
            "id": format!("note-{}", Utc::now().timestamp_millis()),
            "source": source,
            "summary": summary,
            "created_at": now(),
            "tags": ["run"]
        }),
    );
    items.truncate(10);
}

fn run_log_path(tron_path: Option<&str>, project_path: &str) -> PathBuf {
    let root = PathBuf::from(project_path);
    let stem = tron_path
        .and_then(|path| Path::new(path).file_stem())
        .and_then(|stem| stem.to_str())
        .unwrap_or("run");
    root.join(".scriptron").join("run-logs").join(format!(
        "{}-{}.jsonl",
        safe_name(stem),
        Utc::now().timestamp_millis()
    ))
}

async fn write_run_log(path: &Path, events: &[ExecutionEvent]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| e.to_string())?;
    }
    let mut lines = String::new();
    for event in events {
        let value = serde_json::to_value(event).map_err(|e| e.to_string())?;
        lines.push_str(&serde_json::to_string(&value).map_err(|e| e.to_string())?);
        lines.push('\n');
    }
    tokio::fs::write(path, lines)
        .await
        .map_err(|e| e.to_string())
}

fn summarize_run_note(response: &str) -> String {
    let compact = response
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    compact.chars().take(500).collect::<String>()
}

async fn ensure_workspace_layout(workspace_dir: &Path) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(workspace_dir.join(".register")).await?;
    tokio::fs::create_dir_all(workspace_dir.join(".skills")).await?;
    tokio::fs::create_dir_all(workspace_dir.join(".tronhub")).await?;
    rebuild_skill_index(workspace_dir).await?;

    let troner_path = workspace_dir.join(".troner.json");
    if !troner_path.exists() {
        let default_memory = default_troner_memory();
        tokio::fs::write(troner_path, serde_json::to_string_pretty(&default_memory)?).await?;
    } else {
        let raw = tokio::fs::read_to_string(&troner_path).await?;
        if serde_json::from_str::<TronerMemory>(&raw).is_err() {
            let legacy: serde_json::Value =
                serde_json::from_str(&raw).unwrap_or_else(|_| serde_json::json!({}));
            let mut migrated = default_troner_memory();
            if let Some(notes) = legacy
                .pointer("/agent_memory/notes")
                .and_then(|v| v.as_array())
            {
                migrated.global_memory.notes = notes
                    .iter()
                    .filter_map(|value| value.as_str())
                    .map(|content| MemoryNote {
                        id: format!("note-{}", Utc::now().timestamp_millis()),
                        scope: "global".into(),
                        content: content.into(),
                        source: "legacy-migration".into(),
                        created_at: now(),
                    })
                    .collect();
            }
            tokio::fs::write(troner_path, serde_json::to_string_pretty(&migrated)?).await?;
        }
    }

    Ok(())
}

async fn sync_tronhub_cache(workspace_dir: &Path, runner: &ProcessRunner) -> anyhow::Result<()> {
    let hub_dir = workspace_dir.join(".tronhub");
    let repo_dir = hub_dir.join("ScripTron_Extension");
    tokio::fs::create_dir_all(&hub_dir).await?;
    let args = if repo_dir.join(".git").exists() {
        vec![
            "-C".to_string(),
            repo_dir.to_string_lossy().into_owned(),
            "pull".to_string(),
            "--ff-only".to_string(),
        ]
    } else {
        if repo_dir.exists() {
            tokio::fs::remove_dir_all(&repo_dir).await?;
        }
        vec![
            "clone".to_string(),
            "--depth".to_string(),
            "1".to_string(),
            "https://github.com/WyattZZZZ/ScripTron_Extension".to_string(),
            repo_dir.to_string_lossy().into_owned(),
        ]
    };
    runner
        .run(
            ProcessConfig::new("git", args)
                .with_working_dir(hub_dir)
                .with_timeout(60),
        )
        .await
        .map(|_| ())
        .map_err(|e| anyhow::anyhow!(e.to_string()))
}

async fn list_tronhub_entries(
    workspace_dir: &Path,
    kind: &str,
) -> anyhow::Result<Vec<TronhubEntry>> {
    let source_dir = tronhub_kind_dir(workspace_dir, kind);
    let install_dir = installed_kind_dir(workspace_dir, kind);
    let mut entries = Vec::new();
    if !source_dir.exists() {
        return Ok(entries);
    }
    let mut rd = tokio::fs::read_dir(&source_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        let manifest_json = read_manifest_json(&path).await?;
        let description = manifest_json
            .as_deref()
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(raw).ok())
            .and_then(|json| {
                json.get("description")
                    .and_then(|v| v.as_str())
                    .map(str::to_string)
            })
            .unwrap_or_else(|| format!("TronHub {} package '{}'.", kind, name));
        entries.push(TronhubEntry {
            name: name.clone(),
            kind: normalized_kind(kind).into(),
            description,
            source_path: path.to_string_lossy().into_owned(),
            installed: install_dir.join(&name).exists(),
            manifest_json,
        });
    }
    entries.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(entries)
}

async fn install_tronhub_entry(workspace_dir: &Path, kind: &str, name: &str) -> anyhow::Result<()> {
    let source_dir = tronhub_kind_dir(workspace_dir, kind).join(safe_name(name));
    if !source_dir.exists() {
        anyhow::bail!(
            "TronHub {} '{}' was not found. Try syncing TronHub first.",
            kind,
            name
        );
    }
    let target_dir = installed_kind_dir(workspace_dir, kind).join(safe_name(name));
    if target_dir.exists() {
        tokio::fs::remove_dir_all(&target_dir).await?;
    }
    copy_dir_all(&source_dir, &target_dir).await?;
    if kind == "cli" || kind == "model" {
        let manifest = target_dir.join("manifest.json");
        let needs_generate = if manifest.exists() {
            // Regenerate if the stored command is not an executable file.
            let raw = tokio::fs::read_to_string(&manifest)
                .await
                .unwrap_or_default();
            serde_json::from_str::<serde_json::Value>(&raw)
                .ok()
                .and_then(|j| {
                    j.get("command")
                        .and_then(|v| v.as_str())
                        .map(str::to_string)
                })
                .map(|cmd| {
                    let p = std::path::Path::new(&cmd);
                    !p.exists()
                        || p.metadata()
                            .map(|m| {
                                use std::os::unix::fs::PermissionsExt;
                                m.permissions().mode() & 0o111 == 0
                            })
                            .unwrap_or(true)
                })
                .unwrap_or(true)
        } else {
            true
        };
        if needs_generate {
            let generated = generated_cli_manifest(kind, name, &target_dir);
            tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
        }
    } else if kind == "skill" {
        let manifest = target_dir.join("skill.json");
        if !manifest.exists() {
            let generated = serde_json::json!({
                "name": name,
                "description": format!("TronHub skill '{}'.", name),
                "version": "0.1.0"
            });
            tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
        }
    }
    Ok(())
}

async fn list_installed_skills(workspace_dir: &Path) -> anyhow::Result<Vec<SkillEntry>> {
    let skill_dir = workspace_dir.join(".skills");
    let mut skills = Vec::new();
    tokio::fs::create_dir_all(&skill_dir).await?;
    let mut rd = tokio::fs::read_dir(&skill_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        let description = read_skill_description(&path)
            .await?
            .unwrap_or_else(|| format!("Installed TronHub skill '{}'.", name));
        skills.push(SkillEntry {
            name,
            description,
            path: path.to_string_lossy().into_owned(),
        });
    }
    skills.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(skills)
}

async fn rebuild_skill_index(workspace_dir: &Path) -> anyhow::Result<Vec<SkillIndexEntry>> {
    let skill_dir = workspace_dir.join(".skills");
    tokio::fs::create_dir_all(&skill_dir).await?;
    let mut index = Vec::new();
    let mut rd = tokio::fs::read_dir(&skill_dir).await?;
    while let Some(entry) = rd.next_entry().await? {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        if let Some(card) = read_skill_index_entry(&path).await? {
            index.push(card);
        }
    }
    index.sort_by(|a, b| a.name.cmp(&b.name));
    tokio::fs::write(
        skill_dir.join("index.json"),
        serde_json::to_string_pretty(&index)?,
    )
    .await?;
    Ok(index)
}

async fn read_skill_index_entry(path: &Path) -> anyhow::Result<Option<SkillIndexEntry>> {
    let manifest = path.join("skill.json");
    if !manifest.exists() {
        return Ok(None);
    }
    let raw = tokio::fs::read_to_string(&manifest).await?;
    let json: serde_json::Value = serde_json::from_str(&raw)?;
    let name = json
        .get("name")
        .and_then(|v| v.as_str())
        .or_else(|| path.file_name().and_then(|v| v.to_str()))
        .unwrap_or_default()
        .to_string();
    let description = json
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let required_clis = json
        .pointer("/requires/clis")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    item.get("name")
                        .and_then(|v| v.as_str())
                        .map(str::to_string)
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let capabilities = json
        .get("capabilities")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let tags = json
        .get("tags")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let document = skill_index_document(&name, &description, &required_clis, &capabilities, &tags);
    let tokens = tokenize_skill_index_document(&document);
    Ok(Some(SkillIndexEntry {
        name,
        description,
        path: path.to_string_lossy().into_owned(),
        required_clis,
        capabilities,
        tags,
        document,
        tokens,
    }))
}

async fn install_skill_tool_adapters(workspace_dir: &Path, skill_name: &str) -> anyhow::Result<()> {
    let skill_dir = workspace_dir.join(".skills").join(safe_name(skill_name));
    for folder in ["tools", "clis"] {
        let adapter_root = skill_dir.join(folder);
        if !adapter_root.exists() {
            continue;
        }
        let mut rd = tokio::fs::read_dir(&adapter_root).await?;
        while let Some(entry) = rd.next_entry().await? {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let adapter_name = entry.file_name().to_string_lossy().into_owned();
            let target = workspace_dir
                .join(".register")
                .join(safe_name(&adapter_name));
            if target.exists() {
                tokio::fs::remove_dir_all(&target).await?;
            }
            copy_dir_all(&path, &target).await?;
            let manifest = target.join("manifest.json");
            if !manifest.exists() {
                let generated = generated_cli_manifest("cli", &adapter_name, &target);
                tokio::fs::write(manifest, serde_json::to_string_pretty(&generated)?).await?;
            }
        }
    }
    Ok(())
}

fn skill_index_document(
    name: &str,
    description: &str,
    required_clis: &[String],
    capabilities: &[String],
    tags: &[String],
) -> String {
    format!(
        "{} {} {} {} {}",
        name,
        description,
        tags.join(" "),
        capabilities.join(" "),
        required_clis.join(" ")
    )
    .to_lowercase()
}

fn tokenize_skill_index_document(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut tokens = lower
        .split(|c: char| !c.is_alphanumeric())
        .filter(|term| term.len() >= 2)
        .map(str::to_string)
        .collect::<Vec<_>>();
    let chars = lower.chars().filter(|ch| is_cjk(*ch)).collect::<Vec<_>>();
    for window in chars.windows(2) {
        tokens.push(window.iter().collect());
    }
    for window in chars.windows(3) {
        tokens.push(window.iter().collect());
    }
    tokens
}

fn is_cjk(ch: char) -> bool {
    ('\u{4e00}'..='\u{9fff}').contains(&ch)
        || ('\u{3400}'..='\u{4dbf}').contains(&ch)
        || ('\u{3040}'..='\u{30ff}').contains(&ch)
}

async fn read_manifest_json(path: &Path) -> anyhow::Result<Option<String>> {
    let manifest = path.join("manifest.json");
    if manifest.exists() {
        Ok(Some(tokio::fs::read_to_string(manifest).await?))
    } else {
        Ok(None)
    }
}

async fn read_skill_description(path: &Path) -> anyhow::Result<Option<String>> {
    let manifest = path.join("skill.json");
    if manifest.exists() {
        let raw = tokio::fs::read_to_string(manifest).await?;
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&raw) {
            return Ok(json
                .get("description")
                .and_then(|v| v.as_str())
                .map(str::to_string));
        }
    }
    Ok(None)
}

fn generated_cli_manifest(kind: &str, name: &str, installed_dir: &Path) -> serde_json::Value {
    // Read the plugin's own metadata file (model.json or cli.json) for the declared command.
    let meta_command = ["model.json", "cli.json"]
        .iter()
        .filter_map(|fname| std::fs::read_to_string(installed_dir.join(fname)).ok())
        .filter_map(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
        .filter_map(|json| {
            json.get("command")
                .and_then(|v| v.as_str())
                .map(str::to_string)
        })
        .next();

    let command = if let Some(rel) = meta_command {
        // Resolve relative paths (e.g. "./run.sh") against the installed directory.
        if rel.starts_with("./") || rel.starts_with("../") {
            installed_dir
                .join(&rel)
                .canonicalize()
                .unwrap_or_else(|_| installed_dir.join(&rel))
                .to_string_lossy()
                .into_owned()
        } else {
            rel
        }
    } else {
        first_child_path(installed_dir)
            .unwrap_or_else(|| installed_dir.join(name))
            .to_string_lossy()
            .into_owned()
    };

    serde_json::json!({
        "name": name,
        "kind": if kind == "model" { "model" } else { "tool" },
        "description": format!("TronHub {} '{}'.", kind, name),
        "version": "0.1.0",
        "command": command,
        "args_schema": [
            { "name": "input", "description": "Input prompt, path, or task payload.", "required": false, "type": "string" }
        ],
        "examples": [
            format!("{} --help", name)
        ]
    })
}

fn first_child_path(dir: &Path) -> Option<PathBuf> {
    std::fs::read_dir(dir)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| path.file_name().and_then(|n| n.to_str()) != Some("manifest.json"))
}

fn tronhub_kind_dir(workspace_dir: &Path, kind: &str) -> PathBuf {
    let folder = match kind {
        "skill" | "skills" => "skills",
        "model" | "models" => "models",
        _ => "clis",
    };
    workspace_dir
        .join(".tronhub")
        .join("ScripTron_Extension")
        .join(folder)
}

fn installed_kind_dir(workspace_dir: &Path, kind: &str) -> PathBuf {
    match kind {
        "skill" | "skills" => workspace_dir.join(".skills"),
        _ => workspace_dir.join(".register"),
    }
}

fn plugin_runtime_path() -> String {
    let base = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    match std::env::var("PATH") {
        Ok(existing) if !existing.is_empty() => format!("{base}:{existing}"),
        _ => base.to_string(),
    }
}

fn normalized_kind(kind: &str) -> &'static str {
    match kind {
        "skill" | "skills" => "skill",
        "model" | "models" => "model",
        _ => "cli",
    }
}

fn safe_name(name: &str) -> String {
    name.trim().replace(['/', ':', '\\'], "-")
}

fn default_troner_memory() -> TronerMemory {
    TronerMemory {
        schema_version: 1,
        global_memory: GlobalMemory {
            user_name_preference: String::new(),
            agent_style_preference:
                "Concise, direct, Chinese by default unless the user asks otherwise.".into(),
            execution_rules: vec![
                "Preview risky writes before execution.".into(),
                "Prefer project-local changes and avoid touching unrelated files.".into(),
            ],
            notes: Vec::new(),
        },
        projects: BTreeMap::new(),
        register: RegisterInfo {
            path: ".register".into(),
            description: "Workspace-local registry for model CLIs and tool/software CLIs.".into(),
        },
        skill_retry_traces: Vec::new(),
        audit_log: Vec::new(),
    }
}

fn ensure_project_memory(memory: &mut TronerMemory, project_path: &str) -> ProjectMemory {
    let key = project_path.to_string();
    memory
        .projects
        .entry(key.clone())
        .or_insert_with(|| ProjectMemory {
            project_name: Path::new(project_path)
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default(),
            project_path: key.clone(),
            archived: false,
            format_rules: Vec::new(),
            task_constraints: Vec::new(),
            glossary: BTreeMap::new(),
            long_context: Vec::new(),
        })
        .clone()
}

fn build_effective_memory_prompt(global: &GlobalMemory, project: &ProjectMemory) -> String {
    format!(
        "Global style: {}\nUser name preference: {}\nExecution rules:\n{}\nProject: {}\nFormat rules:\n{}\nTask constraints:\n{}",
        global.agent_style_preference,
        empty_dash(&global.user_name_preference),
        bullet_lines(&global.execution_rules),
        empty_dash(&project.project_name),
        bullet_lines(&project.format_rules),
        bullet_lines(&project.task_constraints),
    )
}

fn bullet_lines(items: &[String]) -> String {
    if items.is_empty() {
        "  -".into()
    } else {
        items
            .iter()
            .map(|item| format!("  - {item}"))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

fn empty_dash(value: &str) -> String {
    if value.trim().is_empty() {
        "-".into()
    } else {
        value.into()
    }
}

fn audit_event(event: &str, payload: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "event": event,
        "payload": payload,
        "created_at": now(),
    })
}

fn now() -> String {
    Utc::now().to_rfc3339()
}

async fn migrate_legacy_registry(
    legacy_registry_dir: &Path,
    registry_dir: &Path,
) -> anyhow::Result<()> {
    if !legacy_registry_dir.exists() || registry_has_entries(registry_dir).await? {
        return Ok(());
    }

    tokio::fs::create_dir_all(registry_dir).await?;
    let mut entries = tokio::fs::read_dir(legacy_registry_dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        let source = entry.path();
        if !source.is_dir() {
            continue;
        }
        let target = registry_dir.join(entry.file_name());
        if !target.exists() {
            copy_dir_all(&source, &target).await?;
        }
    }

    Ok(())
}

async fn registry_has_entries(registry_dir: &Path) -> anyhow::Result<bool> {
    if !registry_dir.exists() {
        return Ok(false);
    }
    let mut entries = tokio::fs::read_dir(registry_dir).await?;
    Ok(entries.next_entry().await?.is_some())
}

async fn copy_dir_all(source: &Path, target: &Path) -> anyhow::Result<()> {
    tokio::fs::create_dir_all(target).await?;
    let mut entries = tokio::fs::read_dir(source).await?;
    while let Some(entry) = entries.next_entry().await? {
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        if source_path.is_dir() {
            Box::pin(copy_dir_all(&source_path, &target_path)).await?;
        } else {
            tokio::fs::copy(&source_path, &target_path).await?;
        }
    }
    Ok(())
}

async fn search_files(root: &Path, query: &str) -> Result<Vec<MentionItem>, String> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];

    while let Some(dir) = stack.pop() {
        let mut rd = match tokio::fs::read_dir(&dir).await {
            Ok(rd) => rd,
            Err(_) => continue,
        };
        while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
                continue;
            }
            let path_text = path.to_string_lossy().into_owned();
            if !query.is_empty()
                && !name.to_lowercase().contains(query)
                && !path_text.to_lowercase().contains(query)
            {
                continue;
            }
            let is_tron = path.extension().map(|ext| ext == "tron").unwrap_or(false);
            let modules = if is_tron {
                tron_modules(&path).unwrap_or_default()
            } else {
                Vec::new()
            };
            out.push(MentionItem {
                id: format!("file:{path_text}"),
                label: name,
                kind: if is_tron {
                    "tron".into()
                } else {
                    "file".into()
                },
                path: path_text,
                detail: path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .into_owned(),
                installed: true,
                modules,
            });
            if out.len() >= 80 {
                return Ok(out);
            }
        }
    }
    out.sort_by(|a, b| a.label.cmp(&b.label));
    Ok(out)
}

fn tron_modules(path: &Path) -> Result<Vec<TronMentionModule>, String> {
    let parsed = tron_parser::parse_file(path).map_err(|e| e.to_string())?;
    let mut modules = Vec::new();
    for (index, cell) in parsed.cells.iter().enumerate() {
        if cell.run {
            let name = first_nonempty_line(&cell.content)
                .map(clean_heading)
                .filter(|line| !line.is_empty())
                .unwrap_or_else(|| format!("run_{}", index + 1));
            modules.push(TronMentionModule {
                name,
                kind: "executable".into(),
                injection: "function_call".into(),
            });
        } else {
            for line in cell.content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') {
                    let name = clean_heading(trimmed);
                    if !name.is_empty() {
                        modules.push(TronMentionModule {
                            name,
                            kind: "text".into(),
                            injection: "prompt_injection".into(),
                        });
                    }
                }
            }
        }
    }
    Ok(modules)
}

fn first_nonempty_line(content: &str) -> Option<&str> {
    content.lines().map(str::trim).find(|line| !line.is_empty())
}

fn clean_heading(line: &str) -> String {
    line.trim_start_matches('#')
        .trim()
        .trim_matches(':')
        .to_string()
}

fn marketplace_suggestions(query: &str) -> Vec<MentionItem> {
    if query.len() < 2 {
        return Vec::new();
    }
    ["pdf-cli", "excel-cli", "archive-cli", "hr-report-cli"]
        .iter()
        .filter(|name| name.contains(query))
        .map(|name| MentionItem {
            id: format!("cloud:{name}"),
            label: (*name).into(),
            kind: "cloud".into(),
            path: format!("marketplace://{name}"),
            detail: "Available from cloud plugin registry".into(),
            installed: false,
            modules: Vec::new(),
        })
        .collect()
}

fn format_agent_event(event: &ExecutionEvent) -> Option<String> {
    match event {
        ExecutionEvent::Thinking { content } => {
            if content.trim().is_empty() {
                None
            } else {
                Some(content.trim().to_string())
            }
        }
        ExecutionEvent::Text { content } => {
            if content.trim().is_empty() {
                None
            } else {
                Some(content.trim().to_string())
            }
        }
        ExecutionEvent::Plan { content } => {
            if content.trim().is_empty() {
                None
            } else {
                Some(format!("Plan:\n{}", content.trim()))
            }
        }
        ExecutionEvent::StepStarted {
            step_id,
            tool,
            args,
        } => Some(format!(
            "Step `{}` started: `{}` with `{}`",
            step_id,
            tool,
            compact_json(args)
        )),
        ExecutionEvent::StepRetried {
            step_id,
            tool,
            attempt,
            decision,
            reason,
        } => Some(format!(
            "Step `{}` retry {} for `{}`: {} ({})",
            step_id, attempt, tool, decision, reason
        )),
        ExecutionEvent::StepCompleted {
            step_id,
            tool,
            output,
        } => Some(format!(
            "Step `{}` completed: `{}`\n{}",
            step_id,
            tool,
            output.trim()
        )),
        ExecutionEvent::StepFailed {
            step_id,
            tool,
            error,
        } => Some(format!(
            "Step `{}` failed: `{}`\n{}",
            step_id,
            tool,
            error.trim()
        )),
        ExecutionEvent::SkillSelected { skills } => {
            if skills.is_empty() {
                None
            } else {
                Some(format!("Selected skills: {}", skills.join(", ")))
            }
        }
        ExecutionEvent::ToolCall { tool, args } => {
            Some(format!("Running `{}` with `{}`", tool, compact_json(args)))
        }
        ExecutionEvent::ToolResult {
            tool,
            output,
            success,
        } => Some(format!(
            "{} `{}`:\n{}",
            if *success { "Result from" } else { "Failed" },
            tool,
            output.trim()
        )),
        ExecutionEvent::Warning { message } => Some(format!("Warning: {message}")),
        ExecutionEvent::Error { message } => Some(format!("Error: {message}")),
        ExecutionEvent::Complete => None,
    }
}

fn compact_json(value: &serde_json::Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".into())
}

async fn list_dir(dir: PathBuf) -> Result<Vec<FileEntry>, String> {
    let mut rd = tokio::fs::read_dir(dir).await.map_err(|e| e.to_string())?;
    let mut entries = Vec::new();
    while let Some(entry) = rd.next_entry().await.map_err(|e| e.to_string())? {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let is_dir = path.is_dir();
        let is_tron = path.extension().map(|e| e == "tron").unwrap_or(false);
        entries.push(FileEntry {
            name,
            path: path.to_string_lossy().into_owned(),
            is_dir,
            is_tron,
        });
    }
    entries.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));
    Ok(entries)
}

fn parse_provider(s: &str) -> Result<Provider, String> {
    Provider::from_id(s).ok_or_else(|| format!("Unknown provider: {}", s))
}
