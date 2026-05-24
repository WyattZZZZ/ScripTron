# Stage 2 Hermes Bridge Test Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Stage 2 from tests first: Rust becomes the Hermes Gateway compatibility layer, and Skill Market's Hermes partition reads and installs directly through the official Hermes skills repository/Hub instead of local ScripTron fixtures.

**Architecture:** Stage 2 adds a narrow Rust bridge around the official Hermes CLI/TUI Gateway process. SwiftUI consumes bridge methods only; Hermes Official / Hub catalog data comes from `hermes skills browse/search/list/install/remove/update` shaped responses, while TronHub remains a separate ScripTron workspace source.

**Tech Stack:** Rust `scriptron-core` and `scriptron-ffi`, Swift `ScripTronNative`, XCTest, Tokio tests, fake Hermes executable integration tests, existing CI shell assertions.

---

## External Contract

Hermes Official / Hub must be treated as a Hermes-owned source:

- Skill browsing/search/install calls go through Hermes commands or the Hermes Gateway, not through `.tronhub` fixtures.
- Hermes-compatible TronHub skills may offer "Install into Hermes", but the install path still calls Hermes with a path/URL/package reference.
- ScripTron must not execute Hermes skills locally, copy them into workspace `.skills` as the primary path, or rebuild Hermes trust/security prompts.

Useful Hermes command surface for tests:

- `hermes skills browse`
- `hermes skills search <query>`
- `hermes skills list`
- `hermes skills install <skill-or-url>`
- `hermes skills remove <name>`
- `hermes skills update <name>`

## Files

- Create: `crates/scriptron-core/tests/hermes_gateway_fake.rs`
- Create: `crates/scriptron-core/tests/fixtures/fake-hermes`
- Create: `crates/scriptron-core/tests/fixtures/hermes-skills-browse.json`
- Modify: `crates/scriptron-core/src/lib.rs`
- Modify: `crates/scriptron-ffi/src/lib.rs`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/RustBridge.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/AppModel.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/HermesMigrationSupport.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/WorkspaceView.swift`
- Test: `macos/ScripTronNative/Tests/ScripTronNativeTests/HermesStage2BridgeTests.swift`
- Test: `macos/ScripTronNative/Tests/ScripTronNativeTests/UIBridgeDummyTests.swift`
- Modify: `scripts/ci/assert-hermes-stage1.sh` or create `scripts/ci/assert-hermes-stage2.sh`
- Modify: `.github/workflows/build.yml`

## Unit Test Inventory

### Rust Core Unit Tests

- `test_hermes_status_detects_missing_binary`
  - Given `SCRIPTRON_HERMES_BIN` points to a missing executable.
  - Expect `hermes_status` returns `installed=false`, `running=false`, and a friendly diagnostic.

- `test_hermes_status_detects_fake_binary`
  - Given `SCRIPTRON_HERMES_BIN` points to `tests/fixtures/fake-hermes`.
  - Expect `hermes_status` returns `installed=true`, version from fake CLI, and gateway not started.

- `test_hermes_skills_browse_parses_official_hub_items`
  - Fake Hermes prints JSON for `skills browse --json`.
  - Expect `HermesSkillCatalogItem` fields: name, description, category, source=`Hermes Official / Hub`, trust level, installed, package/ref, external CLI hint.

- `test_hermes_skills_search_passes_query_to_hermes`
  - Call `hermes_skills_search("github")`.
  - Fake Hermes records argv.
  - Expect argv contains `skills search github --json`, and only matching results are returned.

- `test_hermes_skills_install_uses_official_hermes_install`
  - Call `hermes_skills_install("github-pr-review")`.
  - Expect fake Hermes receives `skills install github-pr-review`.
  - Expect no workspace `.skills/github-pr-review` directory is created.

- `test_tronhub_hermes_compatible_skill_installs_via_hermes_reference`
  - Given TronHub entry with manifest containing a Hermes-compatible `SKILL.md` path or URL.
  - Call `hermes_skills_install` with that reference.
  - Expect Hermes install is invoked, not `install_tronhub_entry`.

- `test_hermes_gateway_json_rpc_round_trips_request_ids`
  - Fake Hermes gateway echoes JSON-RPC responses over stdio.
  - Submit two requests.
  - Expect responses map to correct request ids.

- `test_hermes_event_queue_normalizes_streaming_events`
  - Fake Hermes emits `message.delta`, `tool.start`, `approval.request`, `clarify.request`.
  - Expect stored poll queue maps to existing Swift-friendly event fields.

### Rust FFI Unit Tests

- `test_ffi_exposes_stage2_methods`
  - Assert FFI dispatch supports `hermes_status`, `hermes_start_gateway`, `hermes_stop_gateway`, `hermes_prompt_submit`, `hermes_poll_events`, `hermes_skills_browse`, `hermes_skills_search`, `hermes_skills_install`, `hermes_skills_remove`, `hermes_skills_update`.

- `test_ffi_rejects_unknown_hermes_skill_action_with_clear_error`
  - Call unknown method.
  - Expect stable error string, no panic.

### Swift Unit Tests

- `testHermesSkillMarketLoadsOfficialHubFromBridgeNotFixtures`
  - Stub `hermes_skills_browse` with official Hub JSON.
  - Call `model.loadWorkspaceManagementData()`.
  - Expect `model.hermesSkillCatalog` contains official items.
  - Expect `ExtensionCatalogFixtures.hermesSkillItems` is no longer used by Skill Market.

- `testHermesSkillSearchCallsBridgeWithQuery`
  - Set Skill Market search query to `github`.
  - Trigger search action or debounced load helper.
  - Expect bridge call method `hermes_skills_search` and params `query=github`.

- `testInstallHermesOfficialSkillCallsHermesInstall`
  - Given item source `.hermesHub`.
  - Call model action for install.
  - Expect bridge void call `hermes_skills_install` with `name` or `ref`.
  - Expect it does not call `install_tronhub`.

- `testInstallHermesCompatibleTronHubSkillCallsHermesInstallWithReference`
  - Given TronHub skill item with `hermesCompatible=true` and `hermesInstallRef`.
  - Call primary action.
  - Expect bridge void call `hermes_skills_install`.

- `testInstallScripTronOnlyTronHubPackCallsTronHubInstall`
  - Given TronHub workflow pack or non-Hermes-compatible extension.
  - Call primary action.
  - Expect bridge void call `install_tronhub`.

- `testModelManagementUsesHermesStatusAndDoctorOutput`
  - Stub `hermes_status` and optional `hermes_doctor`.
  - Expect Model Management state shows install status, gateway status, active model, and doctor/log action labels.

## Integration Test Inventory

### Rust Integration Tests With Fake Hermes

- `fake_hermes_skills_browse_search_install_flow`
  - Environment: `SCRIPTRON_HERMES_BIN=crates/scriptron-core/tests/fixtures/fake-hermes`.
  - Run browse, search, install, list.
  - Verify fake Hermes command log and returned catalog state.

- `fake_hermes_gateway_prompt_and_poll_flow`
  - Start fake gateway.
  - Submit prompt with `.tron` document context and blackboard.
  - Poll events.
  - Verify response, tool event, and approval event are preserved.

- `fake_hermes_gateway_shutdown_cleans_child`
  - Start gateway.
  - Stop gateway.
  - Verify process exits and status reports `running=false`.

### Swift Integration Tests With Dummy Bridge

- `testStage2SkillMarketOfficialHubHappyPath`
  - Dummy bridge provides official Hermes Hub results through `hermes_skills_browse`.
  - Verify Skill Market source `.hermesHub` shows official items and install action.

- `testStage2SkillMarketTronHubHermesCompatiblePath`
  - Dummy bridge provides TronHub compatible item.
  - Verify UI model action routes to `hermes_skills_install`.

### Swift + Rust FFI Integration Tests

- `testRustBridgeCallsRustFfiAndFakeHermesOfficialSkillRepository`
  - Swift XCTest sets `SCRIPTRON_HERMES_BIN` to the fake Hermes executable.
  - Calls `RustBridge.shared.initialize()`.
  - Calls `hermes_status`, `hermes_skills_browse`, `hermes_skills_search`, and `hermes_skills_install`.
  - Verifies fake Hermes argv log and confirms Hermes Official / Hub install does not create workspace `.skills/<name>`.

### Manual UI Smoke Tests

- Launch with fake Hermes:
  - `SCRIPTRON_HERMES_BIN=crates/scriptron-core/tests/fixtures/fake-hermes`
  - `SCRIPTRON_DUMMY_BRIDGE` unset.
- Open Skill Market.
- Select `Hermes Official / Hub`.
- Search `github`.
- Verify results came from fake Hermes official catalog.
- Click install.
- Verify status says Hermes install completed or queued through Hermes.
- Select `TronHub`.
- Verify compatible item still says `Install into Hermes`.

## TDD Task Order

### Task 1: Rust Hermes CLI Detection Contract

**Files:**
- Test: `crates/scriptron-core/tests/hermes_gateway_fake.rs`
- Create: `crates/scriptron-core/tests/fixtures/fake-hermes`
- Modify: `crates/scriptron-core/src/lib.rs`

- [x] Write failing tests for missing and fake Hermes binary detection.
- [x] Run `cargo test -p scriptron-core hermes_status --test hermes_gateway_fake`.
- [x] Implement `HermesStatus` and `ScripTronCore::hermes_status`.
- [x] Re-run targeted test until green.

### Task 2: Official Hermes Skill Browse/Search

**Files:**
- Test: `crates/scriptron-core/tests/hermes_gateway_fake.rs`
- Create: `crates/scriptron-core/tests/fixtures/hermes-skills-browse.json`
- Modify: `crates/scriptron-core/src/lib.rs`

- [x] Write failing tests for `hermes_skills_browse` and `hermes_skills_search`.
- [x] Verify failure because methods do not exist or return fixtures.
- [x] Implement command execution through configured Hermes binary.
- [x] Normalize results into `ExtensionCatalogItem`-compatible Rust structs.
- [x] Re-run targeted Rust tests.

### Task 3: Hermes Skill Install Ownership

**Files:**
- Test: `crates/scriptron-core/tests/hermes_gateway_fake.rs`
- Modify: `crates/scriptron-core/src/lib.rs`

- [x] Write failing test proving Hermes Official skill install calls `hermes skills install`.
- [ ] Write failing test proving Hermes-compatible TronHub skill install also calls Hermes with its ref/path.
- [x] Verify workspace `.skills` is untouched for both tests.
- [x] Implement `hermes_skills_install`.
- [x] Re-run targeted Rust tests.

### Task 4: FFI Stage 2 Method Surface

**Files:**
- Modify: `crates/scriptron-ffi/src/lib.rs`
- Test: Rust integration test or existing FFI test location.

- [x] Write failing dispatch tests for Stage 2 methods.
- [x] Add FFI method routing.
- [x] Re-run `cargo test --workspace`.

### Task 5: Swift Bridge and AppModel Catalog Loading

**Files:**
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/RustBridge.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/AppModel.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/HermesMigrationSupport.swift`
- Test: `macos/ScripTronNative/Tests/ScripTronNativeTests/HermesStage2BridgeTests.swift`

- [x] Write failing Swift tests for `hermes_skills_browse`, `hermes_skills_search`, and `hermes_skills_install` bridge calls.
- [x] Add Codable models for Hermes official catalog items.
- [x] Add AppModel arrays and actions for Hermes official skills.
- [x] Re-run `swift test --filter HermesStage2BridgeTests`.

### Task 6: Skill Market Removes Official Fixtures

**Files:**
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/WorkspaceView.swift`
- Modify: `macos/ScripTronNative/Sources/ScripTronNative/HermesMigrationSupport.swift`
- Test: `macos/ScripTronNative/Tests/ScripTronNativeTests/UIBridgeDummyTests.swift`

- [x] Write failing test that Skill Market Hermes source renders bridge-provided official results.
- [x] Remove `ExtensionCatalogFixtures.hermesSkillItems` from runtime UI path.
- [x] Keep fixtures only for tests or delete them if no longer needed.
- [x] Re-run Swift tests.

### Task 7: Integration and CI Closure

**Files:**
- Create or modify: `scripts/ci/assert-hermes-stage2.sh`
- Modify: `.github/workflows/build.yml`
- Test: shell script assertions

- [ ] Add CI assertion that Skill Market runtime code does not use hard-coded Hermes skill fixtures.
- [ ] Add CI assertion that Hermes Official install path calls `hermes_skills_install`, not `install_tronhub`.
- [ ] Add fake Hermes integration test command to CI if it is stable on Linux.
- [ ] Run:
  - `cargo fmt --all --check`
  - `cargo test --workspace`
  - `cargo build -p scriptron-ffi`
  - `swift test` in `macos/ScripTronNative`
  - `scripts/ci/assert-workflow.sh && scripts/ci/assert-no-adaptive-skill.sh && scripts/ci/assert-hermes-stage1.sh && scripts/ci/assert-hermes-stage2.sh`

## Acceptance Criteria

- Hermes Official / Hub Skill Market data is loaded from Hermes official skills browse/search, not ScripTron fixtures.
- Installing a Hermes Official / Hub skill calls Hermes install.
- Installing a Hermes-compatible TronHub skill calls Hermes install with a path/URL/ref.
- ScripTron-only TronHub resources still call TronHub install.
- Rust can detect Hermes, invoke fake Hermes skills commands, start/stop a fake gateway, submit prompts, and poll normalized events.
- Swift unit tests cover bridge routing and UI model behavior.
- Integration tests run without real Hermes by using a fake Hermes executable.
- CI enforces the Stage 2 ownership boundary.
