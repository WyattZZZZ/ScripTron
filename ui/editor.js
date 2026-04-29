// ── Cell editor ───────────────────────────────────────────────────────────────
// Manages the cell-based editor for a single .tron file.
// Exported to window.Editor for use by main.js

window.Editor = (() => {
  // Current open file state
  let filePath = null;
  let cells = [];    // [{run, content}]
  let dirty = false;
  let onDirty = null;

  const area = () => document.getElementById('editor-area');

  // ── Public API ────────────────────────────────────────────────────────────

  function load(path, rawCells) {
    filePath = path;
    cells = rawCells.map(c => ({ ...c }));
    dirty = false;
    render();
  }

  function getCells() {
    syncFromDom();
    return cells;
  }

  function getFilePath() { return filePath; }
  function isDirty() { return dirty; }

  function setOnDirty(fn) { onDirty = fn; }

  // ── Render ─────────────────────────────────────────────────────────────────

  function render() {
    const el = area();
    // Remove everything except the welcome screen (keep it in DOM, just hide)
    el.querySelectorAll('.cell-wrapper, #cells-toolbar').forEach(n => n.remove());

    const ws = document.getElementById('welcome-screen');
    if (cells.length === 0 && !filePath) {
      ws.style.display = '';
      return;
    }
    ws.style.display = 'none';

    cells.forEach((cell, idx) => {
      el.appendChild(makeCellWrapper(cell, idx));
    });

    // Bottom toolbar
    const toolbar = document.createElement('div');
    toolbar.id = 'cells-toolbar';
    toolbar.innerHTML = `
      <button class="add-cell-btn" onclick="Editor.addCell(${cells.length}, true)">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
        Add run cell
      </button>
      <button class="add-cell-btn" onclick="Editor.addCell(${cells.length}, false)">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
        Add note
      </button>
    `;
    el.appendChild(toolbar);
  }

  function makeCellWrapper(cell, idx) {
    const wrapper = document.createElement('div');
    wrapper.className = 'cell-wrapper';
    wrapper.dataset.idx = idx;

    // Insert-above strip
    wrapper.appendChild(makeAddRow(idx));

    // The cell itself
    wrapper.appendChild(makeCell(cell, idx));

    return wrapper;
  }

  function makeAddRow(insertIdx) {
    const row = document.createElement('div');
    row.className = 'add-cell-row';
    row.innerHTML = `
      <button class="add-cell-btn" onclick="Editor.addCell(${insertIdx}, true)">+ run</button>
      <button class="add-cell-btn" onclick="Editor.addCell(${insertIdx}, false)">+ note</button>
    `;
    return row;
  }

  function makeCell(cell, idx) {
    const div = document.createElement('div');
    div.className = `cell ${cell.run ? 'run-cell' : 'static-cell'}`;
    div.dataset.idx = idx;

    div.innerHTML = `
      <div class="cell-header">
        <span class="cell-badge">${cell.run ? 'Run' : 'Note'}</span>
        <button class="cell-type-btn" onclick="Editor.toggleCellType(${idx})">
          Switch to ${cell.run ? 'note' : 'run'}
        </button>
        <div class="cell-actions">
          <button class="icon-btn" title="Move up" onclick="Editor.moveCell(${idx}, -1)">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="18 15 12 9 6 15"/></svg>
          </button>
          <button class="icon-btn" title="Move down" onclick="Editor.moveCell(${idx}, 1)">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>
          </button>
          <button class="icon-btn" title="Delete cell" onclick="Editor.deleteCell(${idx})" style="color:var(--error)">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>
          </button>
        </div>
      </div>
      <div class="cell-body">
        <textarea
          placeholder="${cell.run ? 'Describe the task in plain language…' : 'Notes, context, documentation…'}"
          data-idx="${idx}"
          oninput="Editor._onInput(this)"
        >${escHtml(cell.content)}</textarea>
      </div>
    `;

    // Auto-size textarea on load
    const ta = div.querySelector('textarea');
    requestAnimationFrame(() => autoSize(ta));

    return div;
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  function addCell(insertIdx, run) {
    syncFromDom();
    cells.splice(insertIdx, 0, { run, content: '' });
    markDirty();
    render();
    // Focus new cell
    const textareas = area().querySelectorAll('textarea');
    if (textareas[insertIdx]) {
      textareas[insertIdx].focus();
    }
  }

  function deleteCell(idx) {
    syncFromDom();
    if (cells.length <= 1) return; // keep at least one cell
    cells.splice(idx, 1);
    markDirty();
    render();
  }

  function toggleCellType(idx) {
    syncFromDom();
    cells[idx].run = !cells[idx].run;
    markDirty();
    render();
    const textareas = area().querySelectorAll('textarea');
    if (textareas[idx]) textareas[idx].focus();
  }

  function moveCell(idx, dir) {
    syncFromDom();
    const target = idx + dir;
    if (target < 0 || target >= cells.length) return;
    [cells[idx], cells[target]] = [cells[target], cells[idx]];
    markDirty();
    render();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  function syncFromDom() {
    area().querySelectorAll('textarea[data-idx]').forEach(ta => {
      const i = parseInt(ta.dataset.idx, 10);
      if (cells[i] !== undefined) {
        cells[i].content = ta.value;
      }
    });
  }

  function _onInput(ta) {
    autoSize(ta);
    const i = parseInt(ta.dataset.idx, 10);
    if (cells[i] !== undefined) {
      cells[i].content = ta.value;
    }
    markDirty();
  }

  function autoSize(ta) {
    ta.style.height = 'auto';
    ta.style.height = Math.min(ta.scrollHeight, 600) + 'px';
  }

  function markDirty() {
    dirty = true;
    if (onDirty) onDirty();
  }

  function escHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  // ── New / empty state ──────────────────────────────────────────────────────

  function showWelcome() {
    filePath = null;
    cells = [];
    dirty = false;
    area().querySelectorAll('.cell-wrapper, #cells-toolbar').forEach(n => n.remove());
    document.getElementById('welcome-screen').style.display = '';
  }

  return {
    load,
    getCells,
    getFilePath,
    isDirty,
    setOnDirty,
    addCell,
    deleteCell,
    toggleCellType,
    moveCell,
    showWelcome,
    _onInput,
  };
})();
