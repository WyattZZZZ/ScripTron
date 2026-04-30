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

// ── Boot ──────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
  await Marketplace.init(() => {
    renderSettings(); // refresh settings after tool install
  });

  renderSettings();

  workspacePath = await invoke('get_workspace_path') || '~/ScripTron';
  await refreshFileTree();

  setupSidebarTabs();
  setupRunButton();
  setupExecPanel();
  setupWelcomeButtons();
  setupNewFileButton();
  setupInstallLocalButton();

  Editor.setOnDirty(() => markCurrentTabDirty());

  // Listen for execution events from Rust
  execUnlisten = listen('execution-event', handleExecEvent);
});

// ── Sidebar tab switching ─────────────────────────────────────────────────────
function setupSidebarTabs() {
  document.querySelectorAll('.sidebar-tab').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.panel;
      document.querySelectorAll('.sidebar-tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.sidebar-panel').forEach(p => p.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById(`panel-${target}`).classList.add('active');
    });
  });
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
  document.getElementById('btn-new-file').addEventListener('click', () => {
    showNewFileModal();
  });
  document.getElementById('btn-welcome-new').addEventListener('click', () => {
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
  document.getElementById('btn-welcome-open').addEventListener('click', async () => {
    // Switch sidebar to files panel
    document.querySelectorAll('.sidebar-tab').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.sidebar-panel').forEach(p => p.classList.remove('active'));
    document.querySelector('[data-panel="files"]').classList.add('active');
    document.getElementById('panel-files').classList.add('active');
  });
}

function setupInstallLocalButton() {
  document.getElementById('btn-install-local').addEventListener('click', () => {
    Marketplace.installFromLocalFile();
  });
}

// ── Run ───────────────────────────────────────────────────────────────────────
function setupRunButton() {
  document.getElementById('btn-run').addEventListener('click', () => {
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
  setStatusDot('running');
  clearLog();
  currentRunEvents = [];
  expandExecPanel();

  try {
    await invoke('run_task', {
      cells,
      project_path: workspacePath,
    });
  } catch (e) {
    appendLog({ type: 'error', message: String(e) });
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
  if (event.type === 'complete') setStatusDot('done');
  if (event.type === 'error') setStatusDot('error');
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
  log.scrollTop = log.scrollHeight;
}

function clearLog() {
  document.getElementById('exec-log').innerHTML = '';
  setStatusDot('running');
}

function setStatusDot(state) {
  const dot = document.getElementById('exec-status-dot');
  dot.className = `status-dot ${state}`;
}

// ── Execution panel toggle ────────────────────────────────────────────────────
function setupExecPanel() {
  document.getElementById('exec-header').addEventListener('click', toggleExecPanel);
  document.getElementById('btn-clear-log').addEventListener('click', e => {
    e.stopPropagation();
    clearLog();
    setStatusDot('idle');
  });
}

function toggleExecPanel() {
  const panel = document.getElementById('exec-panel');
  const icon = document.getElementById('toggle-icon');
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
  panel.classList.remove('collapsed');
  icon.setAttribute('points', '18 15 12 9 6 15');
}

// ── Settings — multi-provider ─────────────────────────────────────────────────

let _providerStatuses = [];
let _activeConfig = { provider: 'anthropic', model: 'claude-opus-4-7' };

async function renderSettings() {
  const container = document.getElementById('settings-content');
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
}

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

  const cleanup = () => {
    document.getElementById('modal-overlay').classList.add('hidden');
    confirm.replaceWith(confirm.cloneNode(true));
    cancel.replaceWith(cancel.cloneNode(true));
  };

  document.getElementById('modal-confirm').addEventListener('click', async () => {
    if (onConfirm) await onConfirm();
    cleanup();
  });

  document.getElementById('modal-cancel').addEventListener('click', cleanup);

  document.getElementById('modal-overlay').addEventListener('click', e => {
    if (e.target === document.getElementById('modal-overlay')) cleanup();
  });
};

// ── Utilities ─────────────────────────────────────────────────────────────────
function escHtml(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
