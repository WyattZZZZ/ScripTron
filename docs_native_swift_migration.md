# Native Swift Migration

## Decision

ScripTron is moving toward a native macOS frontend:

- SwiftUI owns the app shell, navigation, controls, windows, menus, and native macOS interaction.
- Rust remains the core engine behind a stable C ABI.
- The bridge uses JSON request/response payloads to avoid fragile Swift/Rust struct layout coupling.

## New Crates

- `crates/scriptron-core`: reusable Rust application core with no Tauri dependency.
- `crates/scriptron-ffi`: native library exporting C ABI functions for Swift.

## Exported C ABI

```c
char *scriptron_init(void);
char *scriptron_call(const char *request_json);
void scriptron_free_string(char *ptr);
```

Swift calls `scriptron_call` with a JSON object:

```json
{ "method": "open_tron_file", "params": { "path": "/path/file.tron" } }
```

Rust returns:

```json
{ "ok": true, "data": { "...": "..." } }
```

or:

```json
{ "ok": false, "error": "..." }
```

## Native App Skeleton

The first SwiftUI shell lives in:

```text
macos/ScripTronNative
```

It currently includes:

- Workspace dashboard
- Project Studio shell
- Explorer panel backed by Rust `list_workspace_files` and `open_tron_file`
- Node Library visual shell
- Swift `RustBridge` for C ABI calls

## Verified

```bash
PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo check -p scriptron-ffi
PATH="/opt/homebrew/opt/rustup/bin:$PATH" cargo build -p scriptron-ffi
```

Native C smoke test:

```text
init={"data":{"initialized":true},"ok":true}
path={"data":"/Users/wyattzhang/ScripTron","ok":true}
files={"data":[],"ok":true}
```

## Blocker

Swift compilation is blocked by the local Command Line Tools install, before project sources compile:

```text
failed to build module 'Foundation';
SDK is built with Apple Swift version 6.1 ... 110.5
compiler is Apple Swift version 6.1 ... 110.21
```

Fix by installing a matching full Xcode or reinstalling Command Line Tools, then run:

```bash
cd macos/ScripTronNative
./build-native.sh
```

## Next Steps

1. Add execution streaming over FFI.
2. Add editable SwiftUI cell editor and save through `save_tron_file`.
3. Convert Settings provider cards to SwiftUI and call auth/config FFI methods.
4. Package as a real `.app` bundle using Xcode once the local toolchain is healthy.
