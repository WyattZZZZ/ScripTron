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
  +-- cli-registry
  +-- auth
  +-- agent-loop
  +-- process-runner
```

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
- `list_tools`
- `install_tool_from_json`
- `remove_tool`
- `get_auth_status`
- `store_api_key`
- `disconnect_provider`
- `get_active_config`
- `set_active_config`
- `build_task`
- `run_task_preview`
- `poll_events`

`run_task_preview` and `poll_events` are the first polling queue version. Real agent execution should reuse the same event shape and replace preview events with live `agent-loop` output.

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
