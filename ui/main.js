// ── ScripTron — main application ─────────────────────────────────────────────
// Entry point. Wires Tauri IPC, sidebar navigation, tab management,
// execution stream rendering, and settings panel.

'use strict';

// ── Tauri IPC shim (graceful fallback for browser preview) ────────────────────
const isTauri = typeof window.__TAURI__ !== 'undefined';

function invoke(cmd, args) {
  if (isTauri) {
    return window.__TAURI__.core.invoke(cmd, args || {});
  }
  // Browser preview stubs
  console.log('[invoke]', cmd, args);
  return Promise.resolve(null);
}

function listen(event, handler) {
  if (isTauri) {
    return window.__TAURI__.event.listen(event, payload => handler(payload.payload));
  }
  return () => {};
}

// Make invoke globally available for marketplace.js / editor.js
window.invoke = invoke;

// ── State ─────────────────────────────────────────────────────────────────────
let openTabs = [];   // [{path, name, dirty}]
let activeTab = -1;
let workspacePath = '';
let isRunning = false;
let execUnlisten = null;
let currentRunEvents = [];
let currentRunState = 'idle';

// ── Boot ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  boot().catch(error => {
    console.error('ScripTron boot failed:', error);
    appendLog({ type: 'error', message: `UI boot failed: ${error?.message || error}` });
  });
});

async function boot() {
  document.body.dataset.scriptronBoot = 'binding';
  bindCoreInteractions();
  setupInitialViewFromHash();
  document.body.dataset.scriptronBoot = 'bound';

  await safeInit('workspace path', async () => {
    workspacePath = await invoke('get_workspace_path') || '~/ScripTron';
  });
  await safeInit('file tree', refreshFileTree);

  await safeInit('marketplace', async () => {
    if (!window.Marketplace) return;
    await Marketplace.init(() => {
      safeInit('settings refresh', renderSettings);
      safeInit('extensions refresh', renderExtensions);
    });
  });
  await safeInit('settings', renderSettings);
  await safeInit('extensions', renderExtensions);

  if (window.Editor?.setOnDirty) {
    Editor.setOnDirty(() => markCurrentTabDirty());
  }

  execUnlisten = listen('execution-event', handleExecEvent);
  document.body.dataset.scriptronBoot = 'ready';
}

function bindCoreInteractions() {
  setupSidebarTabs();
  setupRunButton();
  setupExecPanel();
  setupWelcomeButtons();
  setupNewFileButton();
  setupInstallLocalButton();
  setupViewNavigation();
  setupWorkspaceFilters();
  setupCommandCenter();
  setupHistoryActions();
  setupMarketplaceAudit();
  setupUtilityActions();
  setupKeyboardNavigation();
}

async function safeInit(label, fn) {
  try {
    return await fn();
  } catch (error) {
    console.error(`Failed to initialize ${label}:`, error);
    return null;
  }
}

// ── Sidebar tab switching ─────────────────────────────────────────────────────
function setupSidebarTabs() {
  document.querySelectorAll('.sidebar-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.panel;
      const panel = document.getElementById(`panel-${target}`);
      if (!panel) return;
      document.querySelectorAll('.sidebar-tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.sidebar-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      panel.classList.add('active');
      if (target === 'extensions') renderExtensions();
      if (target === 'settings') renderSettings();
    });
  });
}

function setupViewNavigation() {
  document.querySelectorAll('[data-open-project]').forEach(btn => {
    btn.addEventListener('click', () => {
      showProjectView('marketplace');
    });
  });

  document.getElementById('btn-back-workspace')?.addEventListener('click', () => {
    showWorkspaceView();
  });

  document.getElementById('project-logo-link')?.addEventListener('click', () => {
    showProjectView('marketplace');
  });

  document.querySelectorAll('[data-panel-jump]').forEach(btn => {
    btn.addEventListener('click', () => {
      showProjectView(btn.dataset.panelJump);
    });
  });
}

function setupInitialViewFromHash() {
  const hash = window.location.hash;
  if (hash === '#project') {
    showProjectView('marketplace');
  } else if (hash === '#editor') {
    showProjectView('files');
    loadPreviewScript();
  } else if (hash === '#settings') {
    showProjectView('settings');
  } else if (hash === '#history') {
    showProjectView('history');
  } else if (hash === '#extensions') {
    showProjectView('extensions');
  } else if (hash === '#blackboard') {
    showProjectView('files');
    loadPreviewScript();
    showProjectView('settings');
    renderSettings();
  }
}

function showWorkspaceView() {
  document.getElementById('workspace-view')?.classList.add('active');
  document.getElementById('project-view')?.classList.remove('active');
}

function showProjectView(panel = 'files') {
  document.getElementById('workspace-view')?.classList.remove('active');
  document.getElementById('project-view')?.classList.add('active');
  activateProjectPanel(panel);
}

function activateProjectPanel(panel) {
  const targetPanel = document.getElementById(`panel-${panel}`);
  if (!targetPanel) return;
  document.querySelectorAll('.sidebar-tab').forEach(b => {
    b.classList.toggle('active', b.dataset.panel === panel);
  });
  document.querySelectorAll('.sidebar-panel').forEach(p => p.classList.remove('active'));
  targetPanel.classList.add('active');
}

function setupWorkspaceFilters() {
  document.querySelectorAll('.workspace-nav-item').forEach(btn => {
    btn.addEventListener('click', () => {
      const group = btn.closest('.workspace-nav');
      if (!group) return;
      group.querySelectorAll('.workspace-nav-item').forEach(item => item.classList.remove('active'));
      btn.classList.add('active');
      applyWorkspaceFilter(btn.dataset.workspaceFilter || 'all');
    });
  });
}

function applyWorkspaceFilter(filter) {
  const cards = [...document.querySelectorAll('[data-project-groups]')];
  let visibleCount = 0;
  cards.forEach(card => {
    const groups = (card.dataset.projectGroups || 'all').split(/\s+/);
    const visible = filter === 'all' || groups.includes(filter);
    card.classList.toggle('is-filtered-out', !visible);
    if (visible) visibleCount += 1;
  });

  const startCard = document.getElementById('btn-welcome-new');
  if (startCard) startCard.classList.toggle('is-filtered-out', filter !== 'all');

  const empty = document.getElementById('workspace-empty');
  if (empty) empty.classList.toggle('hidden', visibleCount > 0);
}

function setupCommandCenter() {
  document.querySelector('.command-center button:first-of-type')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
  document.querySelector('.command-center button:last-of-type')?.addEventListener('click', () => {
    showProjectView('history');
  });
  document.getElementById('btn-debug')?.addEventListener('click', () => {
    showProjectView('files');
    expandExecPanel();
  });
}

function setupKeyboardNavigation() {
  document.addEventListener('keydown', e => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      const visibleWorkspace = document.getElementById('workspace-view')?.classList.contains('active');
      if (visibleWorkspace) {
        showProjectView('files');
        showNewFileModal();
      } else {
        showProjectView('marketplace');
      }
    }
    if (e.key === 'Escape') {
      const projectActive = document.getElementById('project-view')?.classList.contains('active');
      const modalOpen = !document.getElementById('modal-overlay')?.classList.contains('hidden');
      if (projectActive && !modalOpen) showWorkspaceView();
    }
  });
}

function setupHistoryActions() {
  document.getElementById('btn-open-live-log')?.addEventListener('click', () => {
    showProjectView('files');
    expandExecPanel();
  });
  document.getElementById('btn-history-new-run')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
}

function setupMarketplaceAudit() {
  document.addEventListener('scriptron:marketplace-audit', e => {
    const detail = e.detail || {};
    const ok = detail.status !== 'error';
    const event = {
      type: ok ? 'tool_result' : 'error',
      content: detail.message || `${detail.action || 'Tool update'}: ${detail.name || 'unknown tool'}`,
      tool: detail.name || 'marketplace',
      status: detail.status || 'success',
    };
    appendLog(event);
    appendEventToBlackboard(event);
  });
}

function setupUtilityActions() {
  document.querySelectorAll('[data-utility-action]').forEach(btn => {
    btn.addEventListener('click', () => {
      const action = btn.dataset.utilityAction;
      if (action === 'workspace-settings') {
        showProjectView('settings');
      } else if (action === 'notifications') {
        showModal('Notifications', '<p>No new automation alerts. Failed runs and install events will appear here.</p>', 'Done');
      } else if (action === 'share-workspace') {
        showModal('Share Workspace', '<p>Workspace sharing is ready for collaborators once account sync is connected.</p>', 'Done');
      } else if (action === 'share-project') {
        showModal('Share Project', '<p>Project sharing will use the active workspace collaborators.</p>', 'Done');
      } else if (action === 'help') {
        showModal('Help Center', '<p>Create a script, add run cells, then use Run or Debug to inspect the live log.</p>', 'Done');
      } else if (action === 'logout') {
        showModal('Log Out', '<p>Local sessions stay on this device. Account sign-out will be enabled with cloud sync.</p>', 'Done');
      }
    });
  });
}

function loadPreviewScript() {
  if (isTauri || openTabs.length > 0) return;
  const tab = {
    path: '/preview/customer_onboarding.tron',
    name: 'Main.script',
    dirty: false,
    blackboard: { entries: [], notes: [] },
    cells: [
      {
        run: false,
        content: 'Goal: prepare a customer onboarding workflow that sends a welcome email, creates account tasks, and records the provisioning checklist.',
      },
      {
        run: true,
        content: 'Draft the welcome email sequence for a new Pro Plan customer. Keep the tone concise, warm, and action-oriented.',
      },
      {
        run: true,
        content: 'Create a provisioning checklist with owner, due date, and success criteria for each step.',
      },
    ],
  };
  openTabs = [tab];
  activeTab = 0;
  Editor.load(tab.path, tab.cells);
  renderTabs();
  appendLog({ type: 'thinking', content: 'Preview log ready. Run a script to stream live events here.' });
  appendEventToBlackboard({ type: 'thinking', content: 'Preview log ready. Run a script to stream live events here.' });
  setRunStatus('idle');
}

// ── File tree ─────────────────────────────────────────────────────────────────
async function refreshFileTree() {
  const tree = document.getElementById('file-tree');
  tree.innerHTML = '';
  try {
    const entries = await invoke('list_workspace_files') || [];
    if (entries.length === 0) {
      tree.innerHTML = `<div style="padding:12px;font-size:12px;color:var(--text-dim)">No files yet — create one!</div>`;
      return;
    }
    entries.forEach(entry => {
      const item = document.createElement('div');
      item.className = `file-item${entry.is_tron ? ' tron-file' : ''}`;
      const iconSvg = entry.is_dir
        ? `<svg class="file-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`
        : entry.is_tron
          ? `<span class="file-icon" style="font-size:13px">⬡</span>`
          : `<svg class="file-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/></svg>`;

      item.innerHTML = `${iconSvg}<span class="file-name truncate">${escHtml(entry.name)}</span>`;

      if (entry.is_tron) {
        item.addEventListener('click', () => openFile(entry.path, entry.name));
        // Highlight active
        if (openTabs[activeTab]?.path === entry.path) {
          item.classList.add('active');
        }
      }
      tree.appendChild(item);
    });
  } catch (e) {
    tree.innerHTML = `<div style="padding:12px;font-size:12px;color:var(--error)">${e}</div>`;
  }
}

// ── Tab management ────────────────────────────────────────────────────────────
function renderTabs() {
  const tabBar = document.getElementById('tabs');
  tabBar.innerHTML = '';
  openTabs.forEach((tab, idx) => {
    const el = document.createElement('div');
    el.className = `tab${idx === activeTab ? ' active' : ''}`;
    el.innerHTML = `
      <span class="tab-dot" style="${tab.dirty ? '' : 'display:none'}"></span>
      <span>${escHtml(tab.name)}</span>
      <button class="tab-close" title="Close">×</button>
    `;
    el.addEventListener('click', e => {
      if (e.target.classList.contains('tab-close')) {
        closeTab(idx);
      } else {
        switchTab(idx);
      }
    });
    tabBar.appendChild(el);
  });

  const runBtn = document.getElementById('btn-run');
  runBtn.disabled = openTabs.length === 0 || isRunning;
}

function switchTab(idx) {
  if (idx === activeTab) return;
  if (activeTab >= 0) saveCurrentTab();
  activeTab = idx;
  const tab = openTabs[idx];
  document.getElementById('btn-run').disabled = isRunning;
  // Re-load editor with this tab's cells
  loadEditorForTab(tab);
  renderTabs();
  refreshFileTree();
}

async function loadEditorForTab(tab) {
  try {
    const file = await invoke('open_tron_file', { path: tab.path });
    if (file) {
      tab.cells = file.cells;
      tab.blackboard = file.blackboard || { entries: [], notes: [] };
    }
    Editor.load(tab.path, tab.cells || []);
  } catch (e) {
    Editor.load(tab.path, tab.cells || []);
  }
}

async function openFile(path, name) {
  // Check if already open
  const existing = openTabs.findIndex(t => t.path === path);
  if (existing >= 0) {
    switchTab(existing);
    return;
  }
  try {
    const file = await invoke('open_tron_file', { path });
    const tab = { path, name, dirty: false, cells: file?.cells || [], blackboard: file?.blackboard || { entries: [], notes: [] } };
    openTabs.push(tab);
    await saveCurrentTab();
    activeTab = openTabs.length - 1;
    Editor.load(tab.path, tab.cells);
    showProjectView('files');
    renderTabs();
    refreshFileTree();
    document.getElementById('btn-run').disabled = isRunning;
  } catch (e) {
    alert(`Could not open file: ${e}`);
  }
}

function closeTab(idx) {
  if (openTabs[idx]?.dirty) {
    if (!confirm(`"${openTabs[idx].name}" has unsaved changes. Close anyway?`)) return;
  }
  openTabs.splice(idx, 1);
  if (activeTab >= openTabs.length) activeTab = openTabs.length - 1;
  if (openTabs.length === 0) {
    Editor.showWelcome();
    document.getElementById('btn-run').disabled = true;
  } else {
    loadEditorForTab(openTabs[activeTab]);
  }
  renderTabs();
  refreshFileTree();
}

async function saveCurrentTab() {
  if (activeTab < 0 || !openTabs[activeTab]) return;
  const tab = openTabs[activeTab];
  const cells = Editor.getCells();
  tab.cells = cells;
  try {
    await invoke('save_tron_file', { path: tab.path, cells, blackboard: tab.blackboard || { entries: [], notes: [] } });
    tab.dirty = false;
    renderTabs();
  } catch (e) {
    console.error('Save failed:', e);
  }
}

function markCurrentTabDirty() {
  if (activeTab < 0 || !openTabs[activeTab]) return;
  openTabs[activeTab].dirty = true;
  renderTabs();
}

// ── New file ──────────────────────────────────────────────────────────────────
function setupNewFileButton() {
  document.getElementById('btn-new-file')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
  document.getElementById('btn-welcome-new')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
  document.getElementById('btn-new-project')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
  document.getElementById('btn-editor-new')?.addEventListener('click', () => {
    showProjectView('files');
    showNewFileModal();
  });
}

function showNewFileModal() {
  showModal('New Task File', `
    <label>File name</label>
    <input id="new-file-name" type="text" placeholder="my_task" />
  `, 'Create', async () => {
    const raw = document.getElementById('new-file-name').value.trim();
    if (!raw) return;
    const name = raw.endsWith('.tron') ? raw : `${raw}.tron`;
    const path = `${workspacePath}/${name}`;
    try {
      const file = await invoke('create_tron_file', { path });
      const tab = { path, name, dirty: false, cells: file?.cells || [], blackboard: file?.blackboard || { entries: [], notes: [] } };
      openTabs.push(tab);
      activeTab = openTabs.length - 1;
      Editor.load(tab.path, tab.cells);
      renderTabs();
      refreshFileTree();
      document.getElementById('btn-run').disabled = false;
    } catch (e) {
      alert(`Could not create file: ${e}`);
    }
  });
  setTimeout(() => document.getElementById('new-file-name').focus(), 50);
}

function setupWelcomeButtons() {
  document.getElementById('btn-welcome-open')?.addEventListener('click', async () => {
    showProjectView('files');
  });
}

function setupInstallLocalButton() {
  document.getElementById('btn-install-local')?.addEventListener('click', () => {
    window.Marketplace?.installFromLocalFile?.();
  });
}

// ── Run ───────────────────────────────────────────────────────────────────────
function setupRunButton() {
  document.getElementById('btn-run')?.addEventListener('click', () => {
    if (isRunning) return;
    runTask();
  });
  document.addEventListener('keydown', e => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'r') {
      e.preventDefault();
      if (!isRunning && openTabs.length > 0) runTask();
    }
    if ((e.metaKey || e.ctrlKey) && e.key === 's') {
      e.preventDefault();
      saveCurrentTab();
    }
  });
}

async function runTask() {
  if (activeTab < 0) return;
  const tab = openTabs[activeTab];
  await saveCurrentTab();

  const cells = Editor.getCells();
  const hasRunCells = cells.some(c => c.run && c.content.trim());
  if (!hasRunCells) {
    appendLog({ type: 'error', message: 'No run cells with content found.' });
    setRunStatus('error', 'Needs content');
    expandExecPanel();
    return;
  }

  isRunning = true;
  document.getElementById('btn-run').classList.add('running');
  document.getElementById('btn-run').disabled = true;
  document.getElementById('btn-run').innerHTML = `
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <rect x="6" y="6" width="12" height="12" rx="2"/>
    </svg> Running…`;
  setRunStatus('running');
  clearLog();
  currentRunEvents = [];
  expandExecPanel();

  try {
    await invoke('run_task', {
      cells,
      project_path: workspacePath,
    });
    if (currentRunState === 'running') {
      setRunStatus('done');
      appendLog({ type: 'complete' });
    }
  } catch (e) {
    appendLog({ type: 'error', message: String(e) });
    setRunStatus('error');
  } finally {
    isRunning = false;
    document.getElementById('btn-run').classList.remove('running');
    document.getElementById('btn-run').disabled = false;
    document.getElementById('btn-run').innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg> Run`;
  }
}

// ── Execution event handling ───────────────────────────────────────────────────
function handleExecEvent(event) {
  currentRunEvents.push(event);
  appendEventToBlackboard(event);
  appendLog(event);
  if (event.type === 'complete') setRunStatus('done');
  if (event.type === 'error') setRunStatus('error');
}

function appendEventToBlackboard(event) {
  if (activeTab < 0 || !openTabs[activeTab]) return;
  const tab = openTabs[activeTab];
  if (!tab.blackboard || typeof tab.blackboard !== 'object') {
    tab.blackboard = { entries: [], notes: [] };
  }
  if (!Array.isArray(tab.blackboard.entries)) tab.blackboard.entries = [];
  tab.blackboard.entries.push({
    ts: new Date().toISOString(),
    type: event.type,
    payload: event,
  });
}

function appendLog(event) {
  const log = document.getElementById('exec-log');
  if (!log) return;
  const entry = document.createElement('div');
  entry.className = `log-entry log-${event.type}`;

  let icon, text;

  switch (event.type) {
    case 'thinking':
      icon = '💭';
      text = event.content;
      break;
    case 'tool_call':
      icon = '⚙';
      const argsStr = typeof event.args === 'object'
        ? JSON.stringify(event.args, null, 2)
        : String(event.args);
      text = `${event.tool}(${argsStr})`;
      break;
    case 'tool_result':
      entry.classList.add(event.success ? 'success' : 'fail');
      icon = event.success ? '✓' : '✗';
      text = `[${event.tool}] ${event.output}`;
      break;
    case 'text':
      entry.className = 'log-entry log-text-event';
      icon = '✦';
      text = event.content;
      break;
    case 'warning':
      icon = '⚠';
      text = event.message;
      break;
    case 'error':
      icon = '✗';
      text = event.message;
      break;
    case 'complete':
      icon = '✓';
      text = 'Task complete.';
      break;
    default:
      icon = '·';
      text = JSON.stringify(event);
  }

  entry.innerHTML = `<span class="log-icon">${icon}</span><span class="log-text">${escHtml(text)}</span>`;
  log.appendChild(entry);
  if (event.type === 'error') {
    const retry = document.createElement('div');
    retry.className = 'log-retry-row';
    retry.innerHTML = '<button class="btn-secondary" type="button">Retry last run</button>';
    retry.querySelector('button').addEventListener('click', () => {
      if (!isRunning && activeTab >= 0) runTask();
    });
    log.appendChild(retry);
  }
  log.scrollTop = log.scrollHeight;
}

function clearLog() {
  const log = document.getElementById('exec-log');
  if (!log) return;
  log.innerHTML = '';
  setRunStatus('running');
}

function setRunStatus(state, label) {
  currentRunState = state;
  const dot = document.getElementById('exec-status-dot');
  if (dot) dot.className = `status-dot ${state}`;

  const pill = document.getElementById('run-status-pill');
  if (!pill) return;
  const labels = {
    idle: 'Idle',
    running: 'Running',
    done: 'Success',
    error: 'Error',
  };
  pill.className = `run-status-pill ${state}`;
  pill.innerHTML = `<span class="status-dot ${state}"></span><span>${escHtml(label || labels[state] || state)}</span>`;
}

function setStatusDot(state) {
  setRunStatus(state);
}

// ── Execution panel toggle ────────────────────────────────────────────────────
function setupExecPanel() {
  const header = document.getElementById('exec-header');
  const clearBtn = document.getElementById('btn-clear-log');
  if (!header || !clearBtn) return;
  header.addEventListener('click', toggleExecPanel);
  clearBtn.addEventListener('click', e => {
    e.stopPropagation();
    clearLog();
    setRunStatus('idle');
  });
}

function toggleExecPanel() {
  const panel = document.getElementById('exec-panel');
  const icon = document.getElementById('toggle-icon');
  if (!panel || !icon) return;
  if (panel.classList.contains('collapsed')) {
    expandExecPanel();
  } else {
    panel.classList.add('collapsed');
    icon.setAttribute('points', '6 9 12 15 18 9');
  }
}

function expandExecPanel() {
  const panel = document.getElementById('exec-panel');
  const icon = document.getElementById('toggle-icon');
  if (!panel || !icon) return;
  panel.classList.remove('collapsed');
  icon.setAttribute('points', '18 15 12 9 6 15');
}

// ── Settings — multi-provider ─────────────────────────────────────────────────

let _providerStatuses = [];
let _activeConfig = { provider: 'anthropic', model: 'claude-opus-4-7' };

async function renderSettings() {
  const container = document.getElementById('settings-content');
  if (!container) return;
  container.innerHTML = '';

  try {
    [_providerStatuses, _activeConfig] = await Promise.all([
      invoke('get_auth_status').then(r => r || []),
      invoke('get_active_config').then(r => r || _activeConfig),
    ]);
  } catch (_) {}

  // ── Active provider pill ──────────────────────────────────────────────────
  const activeStatus = _providerStatuses.find(s => s.provider === _activeConfig.provider);
  const activeName = activeStatus?.display_name || _activeConfig.provider;

  const activePill = document.createElement('div');
  activePill.style.cssText = 'padding:12px;border-bottom:1px solid var(--border)';
  activePill.innerHTML = `
    <div class="settings-section-title" style="margin-bottom:8px">Active Model</div>
    <div style="display:flex;align-items:center;gap:10px;background:var(--bg);border:1px solid var(--border-run);border-radius:8px;padding:10px 12px">
      <span style="font-size:18px">${providerIcon(_activeConfig.provider)}</span>
      <div style="flex:1;min-width:0">
        <div style="font-size:13px;font-weight:600;color:var(--text-bright)">${escHtml(activeName)}</div>
        <div style="font-size:11px;color:var(--text-dim);font-family:monospace">${escHtml(_activeConfig.model)}</div>
      </div>
    </div>
  `;
  container.appendChild(activePill);

  // ── Provider list ─────────────────────────────────────────────────────────
  const section = document.createElement('div');
  section.style.cssText = 'padding:10px 0';

  const title = document.createElement('div');
  title.className = 'panel-header';
  title.innerHTML = '<span>Providers</span>';
  section.appendChild(title);

  _providerStatuses.forEach(s => {
    const isActive = s.provider === _activeConfig.provider;
    const card = document.createElement('div');
    card.className = 'provider-card';
    card.dataset.provider = s.provider;
    card.innerHTML = `
      <div class="provider-card-top">
        <span class="provider-icon">${providerIcon(s.provider)}</span>
        <div class="provider-card-info">
          <span class="provider-card-name">${escHtml(s.display_name)}</span>
          <span class="provider-card-status ${s.connected ? 'ok' : 'off'}">
            ${s.connected ? '● Connected' : '○ Not connected'}
          </span>
        </div>
        ${isActive ? '<span class="active-badge">Active</span>' : ''}
      </div>
      ${s.connected ? `
        <div class="provider-card-bottom">
          <select class="model-select" data-provider="${s.provider}" onchange="onModelChange(this)">
            ${s.available_models.map(m =>
              `<option value="${escHtml(m)}" ${(isActive && m === _activeConfig.model) ? 'selected' : ''}>${escHtml(m)}</option>`
            ).join('')}
          </select>
          <div style="display:flex;gap:6px">
            ${!isActive ? `<button class="btn-primary" style="font-size:11px;padding:4px 10px"
              onclick="activateProvider('${s.provider}', this)">Use</button>` : ''}
            <button class="btn-secondary" style="font-size:11px;padding:4px 10px"
              onclick="disconnectProvider('${s.provider}')">Disconnect</button>
          </div>
        </div>
      ` : `
        <div class="provider-card-bottom">
          ${connectButton(s)}
        </div>
      `}
    `;
    section.appendChild(card);
  });

  container.appendChild(section);

  // ── Project blackboard inspector (core runtime first) ─────────────────────
  const bb = document.createElement('div');
  bb.className = 'settings-section';
  const tab = openTabs[activeTab];
  const board = tab?.blackboard || { entries: [], notes: [] };
  const entries = Array.isArray(board.entries) ? board.entries : [];
  const last = entries.length ? entries[entries.length - 1] : null;

  bb.innerHTML = `
    <div class="settings-section-title">Project Blackboard</div>
    <div style="padding:14px;border:1px solid var(--border);border-radius:14px;background:var(--bg-cell)">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px">
        <span style="font-size:12px;color:var(--text-dim)">Entries: <strong style="color:var(--text)">${entries.length}</strong></span>
        <button class="btn-secondary" style="font-size:11px;padding:4px 10px" onclick="clearActiveBlackboard()">Clear</button>
      </div>
      <div style="margin-top:8px;font-size:11px;color:var(--text-dim)">
        ${last ? `Last event: <code class="mono">${escHtml(last.type || 'unknown')}</code> @ ${escHtml(last.ts || '')}` : 'No events yet.'}
      </div>
      ${renderBlackboardEntries(entries)}
    </div>
  `;
  container.appendChild(bb);
}

function renderBlackboardEntries(entries) {
  if (!entries.length) return '';
  const recent = entries.slice(-5).reverse();
  return `
    <div class="blackboard-list">
      ${recent.map((entry, idx) => {
        const type = entry.type || entry.payload?.type || 'event';
        const ts = entry.ts || '';
        const payload = JSON.stringify(entry.payload || entry, null, 2);
        return `
          <details class="blackboard-entry" ${idx === 0 ? 'open' : ''}>
            <summary><span>${escHtml(type)}</span><span style="margin-left:auto;color:var(--text-subtle);font-size:10px">${escHtml(ts)}</span></summary>
            <pre>${escHtml(payload)}</pre>
          </details>
        `;
      }).join('')}
    </div>
  `;
}

function renderExtensions() {
  const container = document.getElementById('extensions-content');
  if (!container || !window.Marketplace) return;
  const tools = Marketplace.getTools() || [];
  const cards = tools.length ? tools : [
    {
      name: 'No installed tools',
      version: 'Ready',
      description: 'Install a Tool Node from the Node Library to make it available to scripts.',
      command: 'node-library',
    },
  ];

  container.innerHTML = cards.map(tool => `
    <article class="extension-card">
      <div class="extension-card-header">
        <span class="node-icon mint"><span class="material-symbols-outlined">${tools.length ? 'extension' : 'add_circle'}</span></span>
        <span class="status-pill ${tools.length ? 'active' : 'idle'}">${tools.length ? 'Installed' : 'Empty'}</span>
      </div>
      <h2>${escHtml(tool.name)}</h2>
      <p>${escHtml(tool.description || 'Automation capability installed from the local registry.')}</p>
      <div class="extension-card-footer">
        <span class="tool-version">${escHtml(tool.command || tool.version || 'available')}</span>
        <button class="btn-secondary" type="button" data-panel-jump-inline="marketplace">${tools.length ? 'Configure' : 'Open Library'}</button>
      </div>
    </article>
  `).join('');

  container.querySelectorAll('[data-panel-jump-inline]').forEach(btn => {
    btn.addEventListener('click', () => showProjectView(btn.dataset.panelJumpInline));
  });
}

window.clearActiveBlackboard = async () => {
  if (activeTab < 0 || !openTabs[activeTab]) return;
  if (!confirm('Clear blackboard entries for this file?')) return;
  openTabs[activeTab].blackboard = { entries: [], notes: [] };
  openTabs[activeTab].dirty = true;
  await saveCurrentTab();
  await renderSettings();
};

function providerIcon(id) {
  const icons = {
    anthropic:  '🤖',
    gemini:     '✦',
    openai:     '⬡',
    deepseek:   '🌊',
    openrouter: '↔',
  };
  return icons[id] || '?';
}

function connectButton(s) {
  if (s.auth_method === 'oauth' || s.auth_method === 'openrouter_oauth') {
    const label = s.auth_method === 'openrouter_oauth' ? 'Connect OpenRouter' : `Sign in with ${s.display_name.split(' ')[s.display_name.split(' ').length - 1]}`;
    return `<button class="btn-primary" style="font-size:11px;padding:4px 10px;width:100%"
      onclick="startOAuth('${s.provider}')">🔗 ${escHtml(label)}</button>`;
  }
  // API key
  const hints = {
    anthropic:  'sk-ant-…',
    openai:     'sk-…',
    deepseek:   'sk-…',
  };
  return `
    <div style="display:flex;gap:6px;width:100%">
      <input id="key-${s.provider}" type="password" placeholder="${hints[s.provider] || 'API key'}"
        style="flex:1;background:var(--bg);border:1px solid var(--border);color:var(--text);
               padding:5px 8px;border-radius:5px;font-size:12px;outline:none"
        autocomplete="off" />
      <button class="btn-primary" style="font-size:11px;padding:4px 10px;white-space:nowrap"
        onclick="saveApiKey('${s.provider}')">Save</button>
    </div>
    ${s.provider === 'anthropic'
      ? '<p style="font-size:11px;color:var(--text-dim);margin-top:6px">Claude Code credentials are reused automatically if present.</p>'
      : ''}
  `;
}

window.saveApiKey = async (provider) => {
  const input = document.getElementById(`key-${provider}`);
  const key = input?.value.trim();
  if (!key) return;
  try {
    await invoke('store_api_key', { provider, api_key: key });
    await renderSettings();
  } catch (e) {
    alert(`Failed to save: ${e}`);
  }
};

window.startOAuth = async (provider) => {
  const card = document.querySelector(`[data-provider="${provider}"]`);
  if (card) {
    const btn = card.querySelector('button');
    if (btn) { btn.textContent = '⏳ Waiting for browser…'; btn.disabled = true; }
  }
  try {
    await invoke('start_oauth_flow', { provider });
    await renderSettings();
  } catch (e) {
    alert(`OAuth failed: ${e}`);
    await renderSettings();
  }
};

window.disconnectProvider = async (provider) => {
  if (!confirm('Disconnect this provider?')) return;
  try {
    await invoke('disconnect_provider', { provider });
    // If we disconnected the active provider, reset to anthropic
    if (_activeConfig.provider === provider) {
      const fallback = _providerStatuses.find(s => s.connected && s.provider !== provider);
      if (fallback) {
        await invoke('set_active_config', { provider: fallback.provider, model: fallback.default_model });
      }
    }
    await renderSettings();
  } catch (e) {
    alert(`Failed to disconnect: ${e}`);
  }
};

window.activateProvider = async (provider, btn) => {
  const select = document.querySelector(`.model-select[data-provider="${provider}"]`);
  const model = select?.value || _providerStatuses.find(s => s.provider === provider)?.default_model || '';
  try {
    if (btn) { btn.textContent = '…'; btn.disabled = true; }
    await invoke('set_active_config', { provider, model });
    _activeConfig = { provider, model };
    await renderSettings();
  } catch (e) {
    alert(`Failed to set active provider: ${e}`);
    await renderSettings();
  }
};

window.onModelChange = async (select) => {
  const provider = select.dataset.provider;
  const model = select.value;
  if (provider === _activeConfig.provider) {
    try {
      await invoke('set_active_config', { provider, model });
      _activeConfig.model = model;
      await renderSettings();
    } catch (e) {
      console.error(e);
    }
  }
};

// ── Modal ─────────────────────────────────────────────────────────────────────
window.showModal = function showModal(title, bodyHtml, confirmLabel, onConfirm, confirmColor) {
  document.getElementById('modal-title').textContent = title;
  document.getElementById('modal-body').innerHTML = bodyHtml;
  document.getElementById('modal-confirm').textContent = confirmLabel || 'Confirm';
  if (confirmColor) {
    document.getElementById('modal-confirm').style.background = confirmColor;
  } else {
    document.getElementById('modal-confirm').style.background = '';
  }
  document.getElementById('modal-overlay').classList.remove('hidden');

  const confirm = document.getElementById('modal-confirm');
  const cancel = document.getElementById('modal-cancel');
  const overlay = document.getElementById('modal-overlay');

  const onEsc = (e) => {
    if (e.key === 'Escape') cleanup();
  };

  const cleanup = () => {
    overlay.classList.add('hidden');
    confirm.replaceWith(confirm.cloneNode(true));
    cancel.replaceWith(cancel.cloneNode(true));
    document.removeEventListener('keydown', onEsc);
  };

  document.getElementById('modal-confirm').addEventListener('click', async () => {
    if (onConfirm) await onConfirm();
    cleanup();
  });

  document.getElementById('modal-cancel').addEventListener('click', cleanup);

  overlay.addEventListener('click', e => {
    if (e.target === overlay) cleanup();
  });
  document.addEventListener('keydown', onEsc);
};

// ── Utilities ─────────────────────────────────────────────────────────────────
function escHtml(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
