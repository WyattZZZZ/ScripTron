# ScripTron UI System

This document records the Phase 0-6 UI rewrite rules so the next phases can extend the product without drifting away from the two reference screens.

## Information Architecture

ScripTron now uses two primary layers:

- Workspace Dashboard: the default entry point for projects, search, collaboration, project health, and the Command Center.
- Project Studio: the active automation workspace with Explorer, Tool Nodes, RAG Nodes, History, Extensions, Settings, editor cells, run log, and status bar.

Hash preview routes:

- `#project`: Project Studio, Node Library.
- `#editor`: Project Studio, Explorer/editor preview.
- `#history`: Project Studio, History/run log.
- `#settings`: Project Studio, Settings.
- `#extensions`: Project Studio, Extensions.
- `#blackboard`: Project Studio, Settings with blackboard preview data.

## Tokens

Core tokens live in `ui/style.css` under `:root`.

- App background: `--app-bg #f5f7f9`
- Sidebar background: `--sidebar-bg #edf3f7`
- Primary surfaces: `--surface`, `--surface-soft`, `--surface-raised`, `--surface-active`
- Borders: `--border`, `--border-soft`
- Text: `--text`, `--text-muted`, `--text-subtle`
- Primary action: `--primary #007967`, `--primary-strong #006f60`, `--primary-soft #8bf0dd`
- RAG accent: `--accent #7044c1`, `--accent-soft #eadfff`
- Status: `--success`, `--warning`, `--error`
- Shadows: `--shadow-card`, `--shadow-float`
- Radii: `--radius-lg 24px`, `--radius-md 16px`, `--radius-sm 10px`

Use Manrope for product UI and the existing monospace stack for code, logs, and blackboard payloads.

## Components

Workspace components:

- Sidebar: brand, primary New Project action, project filters, help/logout footer.
- Topbar: search, notification, settings, user profile.
- Project cards: icon, state pill, health metric, progress bar, edited time.
- Wide project card: key metrics plus a calm visual block.
- Start Automating CTA: primary green panel with centered add action.
- Command Center: floating desktop-only quick action surface.

Project Studio components:

- Project sidebar: project mark, New Script, Explorer/Search/Tool Nodes/RAG Nodes/History, Extensions/Settings.
- Project topbar: product name, file tabs, share/settings, run status pill, Debug, Run, user avatar.
- Explorer: project file card and editor shell.
- Node Library: Tool Nodes grid, RAG Nodes grid, installed registry cards.
- History: run summary cards and live execution panel entry.
- Settings: provider cards, API key inputs, blackboard section.
- Extensions: installed tool cards sourced from the Marketplace registry.
- Statusbar: runtime, encoding, cursor, connection state.

## States

Status language should stay consistent across pages:

- `idle`: muted blue-gray.
- `running`: accent purple.
- `done` / success: green.
- `error`: red, with a retry entry in the run log.
- `draft`: muted blue-gray with dashed or low-emphasis framing.
- `offline`: red soft pill for unavailable knowledge sources.

Run state is mirrored in both the execution panel dot and the topbar run status pill.

## Responsive Rules

- Desktop: full sidebar, multi-column project and node grids, Command Center visible.
- Below 1200px: grids reduce to two columns, Project Studio spacing tightens, run status pill hides to protect the topbar.
- Below 860px: sidebars collapse to icon rails, grids become one column, nonessential topbar text hides, statusbar scrolls horizontally.
- Below 640px: topbars wrap, workspace search becomes full width, editor and cards use tighter padding while preserving the project icon rail.

The Tauri minimum width is 760px, so the 760px screenshot is the primary compact-app target.

## Accessibility And Motion

- Native buttons and links handle Enter/Space activation.
- `Cmd/Ctrl+K` opens the quick action path: New Script from Workspace, Node Library from Project Studio.
- `Esc` returns from Project Studio to Workspace when no modal is open.
- Focus-visible styles use the primary color and must remain visible on all card and button surfaces.
- `prefers-reduced-motion` disables nonessential animation.

## Verification Matrix

Run these before landing major UI changes:

```bash
node --check ui/main.js
node --check ui/marketplace.js
node --check ui/editor.js
PATH="/opt/homebrew/opt/rustup/bin:$PATH" npm run build
```

Visual screenshots used for Phase 0-6:

- Workspace: `ui-preview.png`
- Project Studio / Node Library: `ui-project-preview.png`
- Editor: `ui-editor-preview.png`
- History: `ui-history-preview.png`
- Settings: `ui-settings-preview.png`
- Extensions: `ui-extensions-preview.png`
- Blackboard: `ui-blackboard-preview.png`
- Compact Project Studio: `ui-tablet-preview.png`
