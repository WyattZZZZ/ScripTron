# ScripTron Native SwiftUI

This is the native macOS migration path for ScripTron.

## Architecture

```text
SwiftUI macOS app
  |
  | C ABI, JSON request/response
  v
scriptron-ffi
  |
  v
scriptron-core
  |
  +-- tron-parser
  +-- process-runner
```

`scriptron-core` is now a host layer, not an agent runtime. The custom Rust
agent/provider crates were removed; the next runtime path is the official Hermes
Agent TUI Gateway over JSON-RPC.

Swift calls three exported Rust functions:

- `scriptron_init()`
- `scriptron_call(_ requestJson)`
- `scriptron_free_string(_ pointer)`

The request format is:

```json
{
  "method": "list_workspace_files",
  "params": {}
}
```

The response format is:

```json
{
  "ok": true,
  "data": []
}
```

Errors use:

```json
{
  "ok": false,
  "error": "message"
}
```

## Rust API Surface

The current FFI bridge exposes:

- `get_workspace_path`
- `list_workspace_files`
- `list_dir_files`
- `open_tron_file`
- `save_tron_file`
- `create_tron_file`
- `get_active_config`
- `set_active_config`
- `build_task`
- `run_task_preview`
- `poll_events`

`run_task_preview` and `poll_events` currently return migration placeholder
events. Real agent execution should be wired through the Hermes Gateway methods
listed in `TODO_HERMES_MIGRATION.md`.

## Workspace Metadata

On startup, `scriptron-core` ensures the user workspace exists at `~/ScripTron` and contains:

- `.troner.json`: workspace-level agent memory shared across projects.
- `.register/`: workspace-local CLI registry. Entries can be model CLIs or software/tool CLIs.

Registry manifests support an optional `kind` field:

```json
{
  "name": "local-model-cli",
  "kind": "model",
  "description": "Runs a local model through a CLI adapter.",
  "version": "1.0.0",
  "command": "local-model-cli"
}
```

If `kind` is omitted, it defaults to `tool`. Existing legacy manifests from `~/.scriptron/registry` are copied into `~/ScripTron/.register` the first time the new workspace registry is initialized.

## Build

```bash
./build-native.sh
```

This first builds `scriptron-ffi`, then builds the SwiftUI package.

## Current Local Toolchain Note

On this machine, Rust builds and the FFI smoke test pass. Swift compilation is currently blocked by the installed Command Line Tools:

```text
SDK is built with swiftlang-6.1.0.110.5
compiler is swiftlang-6.1.0.110.21
```

Install a matching full Xcode or reinstall Command Line Tools, then run `./build-native.sh`.

## FFI Smoke Test

The Rust library has been verified from a native C process:

```text
scriptron_init -> ok
get_workspace_path -> /Users/wyattzhang/ScripTron
list_workspace_files -> []
create_tron_file -> ok
save_tron_file -> ok
open_tron_file -> edited cells returned
run_task_preview -> queued 3 events
poll_events -> thinking/tool_result/complete
```
