# TronHub Package Templates

TronHub packages are stored in a repository with three top-level folders:

```text
ScripTron_Extension/
  models/
    <model-provider>/
      manifest.json
      model.json
      install.sh
      run.sh
      README.md
  clis/
    <tool-cli>/
      manifest.json
      cli.json
      install.sh
      run.sh
      README.md
  skills/
    <skill-name>/
      skill.json
      SKILL.md
      README.md
```

`models` are special CLI packages. They use the same install and run contract as `clis`, but their `manifest.json` must set `"kind": "model"` so ScripTron shows them in Model Management.

## Model and CLI Contract

- `manifest.json` is the registry entry copied into `/Users/<user>/ScripTron/.register/<name>/manifest.json`.
- `install.sh` installs external dependencies and must be executable.
- `run.sh` is the single runtime entry point and must be executable.
- `model.json` or `cli.json` can declare `"command": "./run.sh"` so ScripTron resolves the copied runtime script correctly.
- Scripts should use `set -euo pipefail`, detect dependencies before running them, and only print success after the command succeeds.

Required `run.sh` actions:

- `--action login`: authenticate or print that no login is needed.
- `--action chat --prompt "<text>"`: model providers return a response.
- `--action run --input "<payload>"`: tool CLIs perform work and return text or Markdown.
- `--action version`: print dependency versions for diagnostics.

## Skill Contract

Skills do not execute directly. A skill declares instructions in `SKILL.md` and required dependencies in `skill.json`:

```json
{
  "name": "example-skill",
  "kind": "skill",
  "requires": {
    "clis": [
      {
        "name": "example-tool-cli",
        "version": ">=0.1.0",
        "required": true,
        "reason": "Provides the local operation used by this skill."
      }
    ],
    "models": [
      {
        "name": "example-model-provider",
        "version": ">=0.1.0",
        "required": false,
        "reason": "Improves natural-language generation quality."
      }
    ]
  }
}
```

The app can use this dependency block to warn users before a skill runs or to offer one-click installation from TronHub.
