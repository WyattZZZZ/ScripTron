// ── CLI Marketplace ────────────────────────────────────────────────────────────
// Manages the installed-tools list and install/uninstall flows.

window.Marketplace = (() => {
  let tools = [];
  let onChanged = null;

  // Community registry URLs (community-maintained, decentralised)
  const COMMUNITY_REGISTRY_TOOLS = [
    {
      name: 'excel-cli',
      version: '1.0.0',
      description: 'Create, open, and edit Excel spreadsheets. Drives the locally installed Excel via AppleScript.',
      command: 'excel-cli',
      author: 'ScripTron Community',
      homepage: 'https://github.com/scriptron/excel-cli',
      args_schema: [
        { name: 'action', description: 'open | create | read | write | append', required: true, type: 'string' },
        { name: 'file', description: 'Path to the .xlsx file', required: true, type: 'string' },
        { name: 'sheet', description: 'Sheet name (optional)', required: false, type: 'string' },
        { name: 'data', description: 'JSON data for write/append', required: false, type: 'string' },
      ],
      examples: [
        'excel-cli open sales_report.xlsx',
        'excel-cli create new_data.xlsx',
        'excel-cli write employees.xlsx --sheet=HR --data=\'[{"name":"Alice","dept":"Eng"}]\'',
      ],
    },
    {
      name: 'pdf-cli',
      version: '1.2.0',
      description: 'Merge, split, extract pages from, and generate PDF files.',
      command: 'pdf-cli',
      author: 'ScripTron Community',
      homepage: 'https://github.com/scriptron/pdf-cli',
      args_schema: [
        { name: 'action', description: 'merge | split | extract | generate', required: true, type: 'string' },
        { name: 'input', description: 'Input file(s)', required: true, type: 'string' },
        { name: 'output', description: 'Output file', required: false, type: 'string' },
        { name: 'pages', description: 'Page range for extract (e.g. 1-5)', required: false, type: 'string' },
      ],
      examples: [
        'pdf-cli merge page1.pdf page2.pdf --output combined.pdf',
        'pdf-cli extract report.pdf --pages 1-3 --output summary.pdf',
        'pdf-cli generate --template hr_report --output monthly.pdf',
      ],
    },
    {
      name: 'hr-report-cli',
      version: '0.8.0',
      description: 'Generate HR reports, summarise employee data, and produce formatted output.',
      command: 'hr-report-cli',
      author: 'ScripTron Community',
      homepage: 'https://github.com/scriptron/hr-report-cli',
      args_schema: [
        { name: 'action', description: 'generate | summarise | diff', required: true, type: 'string' },
        { name: 'input', description: 'Input CSV or directory', required: true, type: 'string' },
        { name: 'output', description: 'Output file', required: false, type: 'string' },
        { name: 'format', description: 'pdf | csv | markdown', required: false, type: 'string' },
      ],
      examples: [
        'hr-report-cli generate new_employees/ --output onboarding_report.pdf',
        'hr-report-cli summarise employees.csv --format markdown',
      ],
    },
    {
      name: 'archive-cli',
      version: '1.1.0',
      description: 'Organise, archive, and clean up files according to rules you define.',
      command: 'archive-cli',
      author: 'ScripTron Community',
      homepage: 'https://github.com/scriptron/archive-cli',
      args_schema: [
        { name: 'action', description: 'archive | organise | cleanup | restore', required: true, type: 'string' },
        { name: 'source', description: 'Source directory', required: true, type: 'string' },
        { name: 'dest', description: 'Destination directory', required: false, type: 'string' },
        { name: 'rules', description: 'Path to rules JSON file', required: false, type: 'string' },
      ],
      examples: [
        'archive-cli organise ./Downloads --dest ./Sorted',
        'archive-cli archive ./old_projects --dest ./Archives/2024',
        'archive-cli cleanup ./temp --rules cleanup_rules.json',
      ],
    },
  ];

  async function init(changed) {
    onChanged = changed;
    await refresh();
  }

  async function refresh() {
    try {
      tools = await invoke('list_tools') || [];
      renderInstalled();
    } catch (e) {
      console.error('Failed to load tools:', e);
      tools = [];
    }
  }

  function renderInstalled() {
    const list = document.getElementById('marketplace-list');
    if (!list) return;
    list.innerHTML = '';

    // Community registry section
    const section = document.createElement('div');
    section.innerHTML = `
      <div class="panel-header" style="padding:10px 12px 6px">
        <span>Available Tools</span>
      </div>
    `;

    COMMUNITY_REGISTRY_TOOLS.forEach(t => {
      const installed = tools.some(i => i.name === t.name);
      const card = document.createElement('div');
      card.className = 'tool-card';
      card.innerHTML = `
        <div class="tool-card-name">${escHtml(t.name)}</div>
        <div class="tool-card-desc">${escHtml(t.description)}</div>
        <div class="tool-card-footer">
          <span class="tool-version">v${t.version}</span>
          ${installed
            ? `<span class="tool-installed-badge">Installed</span>`
            : `<button class="btn-primary" style="font-size:11px;padding:3px 10px"
                onclick="Marketplace.installCommunityTool('${t.name}')">Install</button>`}
        </div>
      `;
      if (installed) {
        card.addEventListener('click', () => showToolDetail(t, true));
      }
      section.appendChild(card);
    });

    list.appendChild(section);

    // Installed tools not in community registry
    const extras = tools.filter(t => !COMMUNITY_REGISTRY_TOOLS.some(c => c.name === t.name));
    if (extras.length > 0) {
      const extraSection = document.createElement('div');
      extraSection.innerHTML = `
        <div class="panel-header" style="padding:10px 12px 6px">
          <span>Custom Tools</span>
        </div>
      `;
      extras.forEach(t => {
        const card = document.createElement('div');
        card.className = 'tool-card';
        card.innerHTML = `
          <div class="tool-card-name">${escHtml(t.name)}</div>
          <div class="tool-card-desc">${escHtml(t.description)}</div>
          <div class="tool-card-footer">
            <span class="tool-version">v${t.version || '?'}</span>
            <span class="tool-installed-badge">Installed</span>
          </div>
        `;
        card.addEventListener('click', () => showToolDetail(t, true));
        extraSection.appendChild(card);
      });
      list.appendChild(extraSection);
    }
  }

  function showToolDetail(tool, installed) {
    const argsHtml = (tool.args_schema || []).map(a =>
      `<div style="padding:4px 0;border-bottom:1px solid var(--border);display:flex;gap:8px">
        <code style="color:var(--accent);flex-shrink:0">${escHtml(a.name)}</code>
        <span style="color:var(--text-dim);font-size:12px">${escHtml(a.description)}</span>
        ${a.required ? '<span style="color:var(--warning);font-size:11px">required</span>' : ''}
      </div>`
    ).join('');

    const examplesHtml = (tool.examples || []).map(e =>
      `<div style="background:var(--bg);padding:6px 10px;border-radius:4px;font-family:monospace;font-size:12px;margin:4px 0;color:var(--text-dim)">${escHtml(e)}</div>`
    ).join('');

    showModal(tool.name, `
      <p style="color:var(--text-dim);margin-bottom:12px">${escHtml(tool.description)}</p>
      ${tool.author ? `<p style="font-size:12px;color:var(--text-dim);margin-bottom:8px">by ${escHtml(tool.author)}</p>` : ''}
      ${argsHtml ? `<div style="margin:12px 0"><div style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;color:var(--text-dim);margin-bottom:6px">Arguments</div>${argsHtml}</div>` : ''}
      ${examplesHtml ? `<div style="margin-top:12px"><div style="font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;color:var(--text-dim);margin-bottom:6px">Examples</div>${examplesHtml}</div>` : ''}
    `, installed ? 'Uninstall' : 'Install', async () => {
      if (installed) {
        await uninstallTool(tool.name);
      } else {
        await installCommunityTool(tool.name);
      }
    }, installed ? 'var(--error)' : 'var(--accent)');
  }

  async function installCommunityTool(name) {
    const manifest = COMMUNITY_REGISTRY_TOOLS.find(t => t.name === name);
    if (!manifest) return;
    try {
      await invoke('install_tool_from_json', { manifest_json: JSON.stringify(manifest) });
      await refresh();
      if (onChanged) onChanged();
      emitAudit('install', name, 'success', `${name} installed from Node Library.`);
    } catch (e) {
      emitAudit('install', name, 'error', `Failed to install ${name}: ${e}`);
      alert(`Failed to install ${name}: ${e}`);
    }
  }

  async function uninstallTool(name) {
    try {
      await invoke('remove_tool', { name });
      await refresh();
      if (onChanged) onChanged();
      emitAudit('uninstall', name, 'success', `${name} removed from Node Library.`);
    } catch (e) {
      emitAudit('uninstall', name, 'error', `Failed to remove ${name}: ${e}`);
      alert(`Failed to uninstall ${name}: ${e}`);
    }
  }

  async function installFromLocalFile() {
    // Ask user to paste manifest JSON
    showModal('Install Custom Tool', `
      <label>Paste manifest.json content</label>
      <textarea id="custom-manifest-input" style="min-height:160px;font-family:monospace;font-size:12px"
        placeholder='{"name":"my-tool","description":"...","version":"1.0.0","command":"my-tool","args_schema":[]}'></textarea>
    `, 'Install', async () => {
      const json = document.getElementById('custom-manifest-input').value.trim();
      if (!json) return;
      try {
        const manifest = JSON.parse(json);
        await invoke('install_tool_from_json', { manifest_json: json });
        await refresh();
        if (onChanged) onChanged();
        emitAudit('install', manifest.name || 'custom tool', 'success', `${manifest.name || 'Custom tool'} installed from local manifest.`);
      } catch (e) {
        emitAudit('install', 'custom tool', 'error', `Install failed: ${e}`);
        alert(`Install failed: ${e}`);
      }
    });
  }

  function getTools() { return tools; }

  function emitAudit(action, name, status, message) {
    document.dispatchEvent(new CustomEvent('scriptron:marketplace-audit', {
      detail: { action, name, status, message },
    }));
  }

  function escHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  return {
    init,
    refresh,
    installCommunityTool,
    uninstallTool,
    installFromLocalFile,
    getTools,
  };
})();
