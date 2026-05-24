# Hermes Agent Migration TODO

## Decision

ScripTron should stop maintaining its own agent runtime. The product becomes a native SwiftUI desktop host for `.tron` workflows, while the official Hermes Agent runtime owns models, OAuth, tools, skills, approvals, clarify, multi-agent behavior, and streaming execution.

The Rust layer remains, but only as a local host/compatibility layer between SwiftUI and Hermes. It should not contain model providers, tool-use loops, retry planners, or agent orchestration.

## Files Kept For Now

- `macos/ScripTronNative/`
  - Native SwiftUI app and the primary product surface.
  - Keep `AppModel.swift`, `ProjectStudioView.swift`, `WorkspaceView.swift`, `RustBridge.swift`, and the design system.
- `crates/scriptron-ffi/`
  - C ABI bridge used by Swift.
  - Keep and reshape into the Hermes gateway API boundary.
- `crates/scriptron-core/`
  - Temporary host layer.
  - Keep workspace, `.tron`, blackboard, and context logic.
  - Remove embedded agent/provider/tool runtime during migration.
- `crates/tron-parser/`
  - Keep `.tron` parse/serialize support.
- `crates/process-runner/`
  - Keep for launching and supervising Hermes gateway processes.
- `docs/UI_REFACTOR_PLAN.md`, `docs_ui_system.md`, `docs/screenshots/`
  - Keep as UI reference material.
- `readme.md`, `README_zh.md`
  - Keep briefly, but rewrite after the Hermes migration because they still describe the older architecture.

## Files Removed In This Cleanup

- Old Tauri/Web shell:
  - `src-tauri/`
  - `ui/`
  - root `package.json`
  - root `package-lock.json`
  - root `build-linux.sh`
  - root `build-macos.sh`
- Checked-in build artifacts:
  - `macos/ScripTronNative/dist/`
- Old TronHub examples and local registry fixtures:
  - `docs/tronhub-templates/`
  - `registry/`
- Obsolete planning docs:
  - `docs_architecture_nodes.md`
  - `docs_native_swift_migration.md`
  - `docs_phase0_2_execution.md`
- Local system files:
  - `.DS_Store`

## Phase 1: Remove Self-Written Agent Runtime

Goal: remove ScripTron's custom runtime and reshape SwiftUI around Hermes TUI Gateway semantics.

Stage 1 closure status: closed for the native host and CI contract. ScripTron no longer owns agent runtime behavior in the tested path; SwiftUI now targets Hermes gateway semantics with a dummy bridge for deterministic tests. Real Hermes process supervision and JSON-RPC transport stay in Phase 2.

Deleted or replaced:

- [x] `crates/agent-loop/`
- [x] local Rust `crates/hermes/`
- [x] `crates/auth/`
- [x] Custom Anthropic, Gemini, OpenAI-compatible, DeepSeek, OpenRouter provider code.
- [x] Custom CLI model provider code.
- [x] Custom tool-use loop, planner, retry, and final-response synthesis code.
- [x] Custom skill retry/runtime logic.
- [x] Custom TronHub/CLI/Skill runtime management surfaces that duplicate official Hermes behavior.

Keep or migrate:

- [x] `.tron` file parsing and serialization.
- [x] Run cell naming and reference semantics.
- [x] Document cells as context.
- [x] Blackboard as ScripTron notebook state.
- [x] Workspace and project file management.
- [x] RustBridge as the Swift-to-local-host boundary.

SwiftUI changes:

- [x] Change run cells from one-shot `run_task_preview` output into live Hermes sessions.
- [x] Add a run cell action menu for common Hermes commands instead of relying on slash commands:
  - Run prompt
  - Background task
  - Steer session
  - Interrupt session
  - Compress session
  - Branch session
  - Show status/usage
- [x] Redesign run logs around Hermes events:
  - `message.delta`
  - `message.complete`
  - `tool.start`
  - `tool.progress`
  - `tool.complete`
  - `approval.request`
  - `clarify.request`
  - `secret.request`
  - delegation and subagent status events
- [x] Approval UI:
  - Present as modal sheet/popover.
  - Actions: allow once, always allow, deny.
- [x] Clarify UI:
  - Present as a modal question with an input field.
  - Submit through the Rust bridge.
- [x] Multi-agent UI:
  - Start with a collapsible "Agents" or "Delegations" panel inside each run cell.

Model Management changes:

- [x] Replace the current provider/API-key cards with Hermes-managed model status.
- [x] Surface only a small, friendly control set:
  - Check Hermes install
  - Login through Hermes
  - Select model/provider through Hermes
  - Show Hermes gateway status
  - Open doctor/log output
- [x] Do not rebuild Hermes OAuth or model installation in ScripTron.

CLI and Skill marketplace changes:

- [x] Split both CLI and Skill surfaces into two source partitions:
  - `Hermes Official / Hub`: Hermes built-in, optional, trusted, and community skills discoverable through Hermes (`hermes skills browse/search/install`, Skills Hub, direct URL, well-known endpoint, skills.sh, etc.).
  - `TronHub`: ScripTron workspace-specific extensions, local project workflow packs, and compatibility wrappers maintained outside Hermes.
- [x] Add a shared marketplace UX for CLI and Skill pages:
  - Search box with local filtering and optional remote search.
  - Source segmented control: `Hermes Official / Hub` and `TronHub`.
  - Category sidebar/chips matching the Hermes Skills Hub style: All, Software Dev, Creative, Research, MLOps, Productivity, AI Agents, DevOps, Security, Apple, and other available categories.
  - Cards show source, trust level, category, platform, installed state, install/update/remove actions, and whether the item wraps an external CLI.
- [x] Do not duplicate Hermes skill execution. ScripTron should install/select/surface skills, then route execution through Hermes sessions.
- [x] If a TronHub item is compatible with Hermes skill format, prefer installing/registering it under Hermes so the skill appears in Hermes slash commands and platform skill management. Keep it under ScripTron only when it is ScripTron-specific metadata, project templates, `.tron` workflow packs, or compatibility glue that Hermes cannot own directly.

Stage 1 closure evidence:

- Unit tests cover `.tron` editing, plain file editing, run cell submission, gen cell replacement, Hermes event grouping, model management, skill/model management, and CLI/Skill catalog source/category/search behavior through the dummy bridge.
- UI smoke testing covered Skill Market Hermes search, Skill Market TronHub `writer`, Hermes-compatible TronHub skill action, CLI Market TronHub `ripgrep`, CLI Market Hermes official items, and CLI search filtering.
- CI contract enforces removal of legacy adaptive skill runtime, one-shot run preview APIs, and local provider/API-key management surfaces.

## Phase 2: Rust Bridge Hermes Compatibility Layer

Goal: keep Rust as the middle layer, but make it a Hermes host rather than an agent core.

New Rust responsibilities:

- Detect official Hermes Agent installation.
- Start, stop, and supervise Hermes TUI Gateway.
- Speak JSON-RPC over stdio with Hermes.
- Maintain request ids and pending responses.
- Continuously read Hermes streaming events.
- Store events in a Swift-pollable event queue.
- Translate `.tron` run cells, document context, references, and blackboard into Hermes requests.
- Translate Hermes raw events into Swift-friendly event structs.

Proposed RustBridge methods:

- `hermes_status`
- `hermes_install_check`
- `hermes_start_gateway`
- `hermes_stop_gateway`
- `hermes_session_create`
- `hermes_session_list`
- `hermes_session_resume`
- `hermes_session_interrupt`
- `hermes_session_compress`
- `hermes_session_branch`
- `hermes_prompt_submit`
- `hermes_prompt_background`
- `hermes_session_steer`
- `hermes_poll_events`
- `hermes_approval_respond`
- `hermes_clarify_respond`
- `hermes_secret_respond`
- `hermes_command_catalog`
- `hermes_command_dispatch`
- `hermes_skills_browse`
- `hermes_skills_search`
- `hermes_skills_install`
- `hermes_skills_remove`
- `hermes_skills_update`
- `hermes_skill_sources`
- `tronhub_search`
- `tronhub_install`
- `tronhub_remove`

Suggested Rust modules:

- `hermes_gateway`
  - process lifecycle and JSON-RPC transport
- `hermes_events`
  - raw event normalization
- `tron_context`
  - `.tron` cells, blackboard, and run references to Hermes prompt/session inputs
- `workspace`
  - project and file operations currently embedded in `scriptron-core`
- `extension_catalog`
  - merged catalog view for Hermes skills and TronHub extensions, including search, categories, source partitions, trust badges, and install state.

## Phase 3: CLI / Skill Catalog Unification

Goal: make ScripTron a native catalog and workflow surface over Hermes official skills plus ScripTron/TronHub extensions.

Research baseline from Hermes docs:

- Hermes Skills Hub exposes searchable skills across built-in, optional, Anthropic/LobeHub/community-style registries and categories.
- Hermes skills can wrap external CLIs or APIs when the behavior can be described as instructions plus shell commands or existing tools.
- Hermes supports third-party installation paths including direct GitHub identifiers, `skills.sh`, well-known endpoints, direct `SKILL.md` URLs, and custom taps.
- Installed skills in `~/.hermes/skills/` are automatically available as slash commands in Hermes CLI/TUI sessions.
- Hermes applies trust/security levels and scanning to third-party/community skills. ScripTron should preserve and display these trust labels rather than hiding them.

SwiftUI requirements:

- Replace separate one-dimensional `CLI Market`, `Skill Market`, `CLI Management`, and `Skill Management` browsing with a unified catalog pattern while preserving sidebar entries for now.
- Each CLI/Skill page has:
  - Search box.
  - Source segmented control: `Hermes Official / Hub` and `TronHub`.
  - Category filter list/chips.
  - Installed/available/update-needed filters.
  - Cards with name, description, source, category, trust, platform, CLI dependency hint, install state, and primary action.
- `Hermes Official / Hub` partition:
  - Reads from Hermes skills browse/search APIs or CLI wrappers.
  - Installs through Hermes so the skill lands in `~/.hermes/skills/`.
  - Shows official/builtin/trusted/community trust state.
- `TronHub` partition:
  - Reads ScripTron extension cache.
  - Installs ScripTron-only project resources into the workspace.
  - For Hermes-compatible `SKILL.md` packages, offers "Install into Hermes" as the preferred action.

Ownership rule:

- Hermes owns executable agent capabilities: skills, external CLI wrappers, OAuth/setup prompts, trust warnings, slash-command registration, and runtime execution.
- ScripTron owns workspace UX: project templates, `.tron` workflow packs, local metadata, search/categories across sources, visual installation state, and migration/compatibility helpers.

## Open Questions

- Should `.tron` blackboard remain ScripTron-only state, or should selected blackboard entries sync into Hermes memory?
- Should each run cell map to a stable Hermes session, or should each `.tron` file own one session with run cells as submitted prompts?
- How much of existing project memory should migrate into Hermes memory versus staying as ScripTron metadata?
- Should legacy `readme.md` and `README_zh.md` be rewritten immediately after the first Hermes spike or after the full migration?

## Immediate Next Steps

1. Add a minimal `HermesGatewayManager` in Rust.
2. Start Hermes TUI Gateway as a supervised child process.
3. Implement `hermes_session_create`, `hermes_prompt_submit`, and `hermes_poll_events`.
4. Wire one Swift run cell to streaming `message.delta`.
5. Add approval and clarify modal prototypes.
6. Remove remaining custom skill retry and TronHub/CLI/Skill runtime surfaces after Hermes official library integration is wired.
