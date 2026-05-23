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

Delete or replace:

- `crates/agent-loop/`
- `crates/hermes/`
- Custom Anthropic, Gemini, OpenAI-compatible, DeepSeek, OpenRouter provider code.
- Custom CLI model provider code.
- Custom tool-use loop, planner, retry, and final-response synthesis code.
- Custom skill retry/runtime logic.
- Custom TronHub/CLI/Skill runtime management surfaces that duplicate official Hermes behavior.

Keep or migrate:

- `.tron` file parsing and serialization.
- Run cell naming and reference semantics.
- Document cells as context.
- Blackboard as ScripTron notebook state.
- Workspace and project file management.
- RustBridge as the Swift-to-local-host boundary.

SwiftUI changes:

- Change run cells from one-shot `run_task_preview` output into live Hermes sessions.
- Add a run cell action menu for common Hermes commands instead of relying on slash commands:
  - Run prompt
  - Background task
  - Steer session
  - Interrupt session
  - Compress session
  - Branch session
  - Show status/usage
- Redesign run logs around Hermes events:
  - `message.delta`
  - `message.complete`
  - `tool.start`
  - `tool.progress`
  - `tool.complete`
  - `approval.request`
  - `clarify.request`
  - `secret.request`
  - delegation and subagent status events
- Approval UI:
  - Present as modal sheet/popover.
  - Actions: allow once, always allow, deny.
- Clarify UI:
  - Present as a modal question with an input field.
  - Submit through the Rust bridge.
- Multi-agent UI:
  - Start with a collapsible "Agents" or "Delegations" panel inside each run cell.

Model Management changes:

- Replace the current provider/API-key cards with Hermes-managed model status.
- Surface only a small, friendly control set:
  - Check Hermes install
  - Login through Hermes
  - Select model/provider through Hermes
  - Show Hermes gateway status
  - Open doctor/log output
- Do not rebuild Hermes OAuth or model installation in ScripTron.

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

Suggested Rust modules:

- `hermes_gateway`
  - process lifecycle and JSON-RPC transport
- `hermes_events`
  - raw event normalization
- `tron_context`
  - `.tron` cells, blackboard, and run references to Hermes prompt/session inputs
- `workspace`
  - project and file operations currently embedded in `scriptron-core`

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
6. Once the spike works, remove `crates/agent-loop`, local `crates/hermes`, and custom provider/auth paths.
