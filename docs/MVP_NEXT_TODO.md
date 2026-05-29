# ScripTron MVP Next TODO

This document captures the post-MVP direction agreed on May 27, 2026. The current MVP remains Hermes-first; the next version should move ScripTron to a multi-agent runtime with project-scoped skill activation.

## Goal

Turn ScripTron into a multi-agent workspace that can run Codex, Claude Code, Hermes, and future agents through a common adapter layer. Skills are installed and managed by ScripTron, activated per project, then appended to the selected agent without modifying that agent's official or builtin skills.

## Architecture

- `AgentAdapter` layer handles agent initialization, status checks, auth/setup, prompt submission, and project skill sync.
- `SkillFormatAdapter` layer renders ScripTron-managed skills into the format each agent can load.
- ScripTron owns the installed skill registry. Skill sources are only discovery/import channels.
- TronHub stays responsible for CLI/model wrappers only. TronHub skill support should be removed or hidden.
- Project-specific active skills live under each project's `.scriptron` folder and are synced to the active agent before run.

## Multi-Agent Adapter Layer

- [ ] Add a common agent API:
  - `list_agents`
  - `get_active_agent`
  - `set_active_agent`
  - `agent_status(agent)`
  - `agent_init(agent)`
  - `agent_sync_project_skills(agent, project_path)`
  - `agent_prompt_submit(agent, project_path, cells, blackboard)`
- [ ] Implement `HermesAgentAdapter`:
  - install/check Hermes
  - guide `hermes model`
  - check API keys and Hermes auth
  - run `hermes doctor`
  - test `hermes chat`
  - submit via `hermes chat`
- [ ] Implement `CodexAgentAdapter`:
  - check `codex`
  - run `codex doctor`
  - guide `codex login`
  - submit via `codex exec`
  - document that newly exported skills may require a new Codex session to load reliably
- [ ] Implement `ClaudeAgentAdapter`:
  - check `claude`
  - run `claude doctor`
  - guide Claude auth/API key setup
  - submit via `claude -p`
  - prefer runtime `--plugin-dir` for project skills

## Graphical Agent Initialization

- [ ] Replace the Hermes-only model management mental model with an Agent Runtime / Agent Setup page.
- [ ] Provide a setup wizard per agent:
  - locate/install binary
  - check version
  - check auth/provider state
  - guide OAuth/API key setup
  - run doctor
  - run test prompt
  - mark ready
- [ ] Keep Hermes install using the CN GitHub mirror by default.
- [ ] Surface provider-not-configured failures with a direct "Open Agent Setup" action.

## Skill Sources

ScripTron should support multiple skill sources, but installed skills are normalized into ScripTron ownership.

- [ ] Local folder import.
- [ ] Local zip/tar import.
- [ ] GitHub repo/path import.
- [ ] URL zip/tar import.
- [ ] Hermes skills registry browse/search/import.
- [ ] Claude plugin marketplace browse/import.
- [ ] Codex / Agent Skills format import.
- [ ] Future registry source support.

## Installed Skills Registry

- [ ] Normalize all imported skills into:

```text
~/ScripTron/.skills/<skill-name>/
├─ SKILL.md
├─ scripts/
├─ assets/
├─ references/
└─ scriptron.skill.json
```

- [ ] Validate imported skills require `SKILL.md`.
- [ ] Preserve `scripts/`, `assets/`, and `references/`.
- [ ] Store source metadata in `scriptron.skill.json`.
- [ ] Add installed skill management:
  - list
  - inspect
  - remove
  - update when source metadata supports it
  - validate

## Skill Format Adapter Layer

- [ ] Add `CodexSkillAdapter`:
  - export only under `~/.codex/skills/scriptron-project-<project-id>-<skill>/`
  - use `SKILL.md`
  - never modify `.system`, plugin caches, or official/user-managed skills
- [ ] Add `ClaudeSkillAdapter`:
  - export to `project/.scriptron/agent_exports/claude/`
  - generate `.claude-plugin/plugin.json`
  - generate `skills/<skill-name>/SKILL.md`
  - run Claude with `--plugin-dir project/.scriptron/agent_exports/claude`
  - keep fallback to `~/.claude/skills/scriptron-project-*` if needed later
- [ ] Add `HermesSkillAdapter`:
  - export only under `~/.hermes/skills/scriptron-project-<project-id>-<skill>/`
  - use `SKILL.md`
  - never uninstall or mutate non-ScripTron Hermes skills
- [ ] Add `UnknownAgentSkillAdapter`:
  - do not write agent directories
  - append active skill summaries to the prompt context

## Project Skillset

- [ ] Add project-level skill activation:

```text
project/.scriptron/
├─ skillset.json
├─ skills/<skill-name>/
└─ agent_exports/
   ├─ claude/
   ├─ codex/
   └─ hermes/
```

- [ ] Use `skillset.json` for active project skills:

```json
{
  "active_skills": [
    {
      "name": "resume-optimizer",
      "source": "installed",
      "path": ".scriptron/skills/resume-optimizer",
      "enabled": true
    }
  ]
}
```

- [ ] Add APIs:
  - `list_project_skills(project_path)`
  - `activate_project_skill(project_path, skill_name)`
  - `deactivate_project_skill(project_path, skill_name)`
  - `ensure_project_skills_from_mentions(project_path, text)`
  - `sync_agent_project_skills(project_path, agent)`

## Project Skills UI

- [ ] Add a Project Skills configuration view in the project workspace.
- [ ] Show installed ScripTron skills available for activation.
- [ ] Show current project active skills.
- [ ] Support activate, deactivate, inspect, and sync to current agent.
- [ ] Show current active agent and export status.
- [ ] Make clear that official agent skills are not ScripTron-managed and will not be modified.

## Mention and Run Cell Integration

- [ ] Extend mention search in run cells to search installed skills, project files, and run functions.
- [ ] Support syntax:

```text
@skill-name
@skill-name#module
@file.tron
@run-name
```

- [ ] Selecting a skill mention activates the skill for the current project.
- [ ] Hand-written `@skill-name` tokens are detected before run and auto-activate matching installed skills.
- [ ] Before every run:
  - parse mentions
  - activate missing project skills
  - sync active project skills to the selected agent
  - submit through the selected agent adapter

## Run Cell Syntax Highlighting

- [ ] Add run-cell mention highlighting:
  - skill mention: skill style
  - skill module mention: skill module style
  - file mention: file style
  - run/function mention: function style
  - unknown mention: warning style
- [ ] If SwiftUI `TextEditor` cannot support inline attributed text cleanly, replace the run-cell editor with an `NSTextView` wrapper.

## TronHub Scope Change

- [ ] Keep TronHub CLI/model support.
- [ ] Keep `.register` as the CLI/model wrapper registry.
- [ ] Remove or hide TronHub skill browsing and install.
- [ ] Stop treating `kind=skill` as a TronHub install kind.
- [ ] Keep installed skills under ScripTron's `.skills` registry only.

## Run Flow

- [ ] Replace the Hermes-only run entry with:

```text
submitAgentPrompt
  -> get active agent
  -> parse @mentions
  -> activate missing project skills
  -> sync project skills to active agent
  -> run active agent adapter
  -> normalize events back to ScripTron UI
```

## Testing Checklist

- [ ] Rust tests for agent adapter dispatch.
- [ ] Rust tests for skill source import normalization.
- [ ] Rust tests for project skill activation/deactivation.
- [ ] Rust tests for Codex, Claude, Hermes skill format exports.
- [ ] Rust tests prove ScripTron does not overwrite official/builtin agent skills.
- [ ] Rust tests for `@skill` auto-activation.
- [ ] Rust tests that TronHub skill support is hidden or removed while CLI/model remains.
- [ ] Swift tests for Agent Setup UI.
- [ ] Swift tests for Skill Sources UI.
- [ ] Swift tests for Installed Skills management.
- [ ] Swift tests for Project Skills UI.
- [ ] Swift tests for mention picker skill selection.
- [ ] Swift tests for run-cell mention highlighting.
- [ ] Swift tests for `submitAgentPrompt` calling the expected bridge methods.

## MVP E2E Checklist

- [ ] Build and run Rust core tests.
- [ ] Build and run Rust FFI tests.
- [ ] Build and run Swift package tests.
- [ ] Check Hermes installation status.
- [ ] Check Codex and Claude CLI availability.
- [ ] Run Hermes skill browse/search real E2E when `SCRIPTRON_RUN_REAL_HERMES_E2E=1`.
- [ ] Run real `hermes chat` once a Hermes inference provider is configured.
- [ ] Verify current UI can load workspace, model management, skill/CLI management, project studio, and run-cell states through tests.
