(() => {
  const ENHANCED = 'data-cloudos-start-enhanced';
  let activeView = 'home';
  let refreshTimer = 0;

  const kernel = () => window.kernel;
  const windows = () => {
    try { return kernel()?.getWindows?.() || []; } catch { return []; }
  };
  const apps = () => [...document.querySelectorAll('.start-app-btn')];

  function focusWindow(id) {
    try { kernel()?.restoreWindow?.(id); kernel()?.focusWindow?.(id); } catch {}
    document.querySelector('.start-menu-overlay')?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
  }
  function minimizeWindow(id) { try { kernel()?.minimizeWindow?.(id); } catch {} }
  function closeWindow(id) { try { kernel()?.closeWindow?.(id); } catch {} }

  function iconFor(win) { return win.icon || '▣'; }
  function safe(text) {
    const node = document.createElement('span');
    node.textContent = String(text ?? '');
    return node.innerHTML;
  }

  function renderOpen(panel) {
    const list = windows().filter(win => !win.isSystem);
    const grouped = new Map();
    list.forEach(win => {
      const key = win.appId || win.title || win.id;
      const group = grouped.get(key) || { name: win.title || win.appId || 'Aplicativo', icon: iconFor(win), items: [] };
      group.items.push(win); grouped.set(key, group);
    });
    panel.innerHTML = `
      <div class="cloudos-running-head">
        <div><strong>Aplicativos abertos</strong><span>${list.length} janela${list.length === 1 ? '' : 's'}</span></div>
        <button type="button" data-action="close-all" ${list.length ? '' : 'disabled'}>Fechar todas</button>
      </div>
      <div class="cloudos-running-list">
        ${list.length ? [...grouped.values()].map(group => `
          <section class="cloudos-running-group">
            <header><span class="cloudos-running-icon">${safe(group.icon)}</span><span>${safe(group.name)}</span><b>${group.items.length}</b></header>
            ${group.items.map(win => `
              <article class="cloudos-running-window" data-window-id="${safe(win.id)}">
                <button type="button" class="cloudos-window-focus" title="Alternar para esta janela">
                  <span>${safe(win.title || group.name)}</span>
                  <small>${win.isMinimized ? 'Minimizada' : win.isActive ? 'Ativa' : 'Em execução'}</small>
                </button>
                <div class="cloudos-window-actions">
                  <button type="button" data-action="minimize" title="Minimizar">−</button>
                  <button type="button" data-action="focus" title="Restaurar">□</button>
                  <button type="button" data-action="close" class="danger" title="Fechar">×</button>
                </div>
              </article>`).join('')}
          </section>`).join('') : '<div class="cloudos-empty-running"><span>◇</span><strong>Nenhum aplicativo aberto</strong><small>Os aplicativos em execução aparecerão aqui.</small></div>'}
      </div>`;
  }

  function renderAll(panel, menu) {
    const source = apps();
    panel.innerHTML = `<div class="cloudos-all-head"><strong>Todos os aplicativos</strong><span>${source.length} disponíveis</span></div><div class="cloudos-all-grid"></div>`;
    const grid = panel.querySelector('.cloudos-all-grid');
    source.sort((a,b) => (a.textContent || '').localeCompare(b.textContent || '', 'pt-BR')).forEach(original => {
      const copy = original.cloneNode(true);
      copy.addEventListener('click', () => original.click());
      grid.appendChild(copy);
    });
  }

  function switchView(menu, view) {
    activeView = view;
    const nativeSections = [...menu.children].filter(node => node.classList?.contains('start-section'));
    const panel = menu.querySelector('.cloudos-start-panel');
    const nav = menu.querySelector('.cloudos-start-nav');
    nav?.querySelectorAll('button').forEach(button => button.classList.toggle('active', button.dataset.view === view));
    nativeSections.forEach(section => section.hidden = view !== 'home');
    panel.hidden = view === 'home';
    if (view === 'running') renderOpen(panel);
    if (view === 'all') renderAll(panel, menu);
  }

  function enhance(menu) {
    if (menu.hasAttribute(ENHANCED)) return;
    menu.setAttribute(ENHANCED, 'true');
    menu.classList.add('cloudos-start-menu');
    const search = menu.querySelector('.start-search');
    const nav = document.createElement('nav');
    nav.className = 'cloudos-start-nav';
    nav.setAttribute('aria-label', 'Seções do menu Iniciar');
    nav.innerHTML = `
      <button type="button" data-view="home" class="active">Início</button>
      <button type="button" data-view="all">Todos</button>
      <button type="button" data-view="running">Abertos <span class="cloudos-running-count">0</span></button>`;
    search?.after(nav);
    const panel = document.createElement('div');
    panel.className = 'cloudos-start-panel';
    panel.hidden = true;
    const bottom = menu.querySelector('.start-bottom');
    menu.insertBefore(panel, bottom || null);

    nav.addEventListener('click', event => {
      const button = event.target.closest('button[data-view]');
      if (button) switchView(menu, button.dataset.view);
    });
    panel.addEventListener('click', event => {
      const target = event.target.closest('button');
      if (!target) return;
      const row = target.closest('[data-window-id]');
      const id = row?.dataset.windowId;
      if (target.dataset.action === 'close-all') {
        windows().filter(win => !win.isSystem).forEach(win => closeWindow(win.id));
        setTimeout(() => renderOpen(panel), 60); return;
      }
      if (!id) return;
      if (target.dataset.action === 'minimize') minimizeWindow(id);
      else if (target.dataset.action === 'close') closeWindow(id);
      else focusWindow(id);
      setTimeout(() => activeView === 'running' && renderOpen(panel), 60);
    });

    const allButton = [...menu.querySelectorAll('.start-section-btn')].find(button => button.textContent?.includes('Todos'));
    allButton?.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); switchView(menu, 'all'); });
    updateCount(menu);
  }

  function updateCount(menu) {
    const count = windows().filter(win => !win.isSystem).length;
    const badge = menu.querySelector('.cloudos-running-count');
    if (badge) badge.textContent = String(count);
    if (activeView === 'running') renderOpen(menu.querySelector('.cloudos-start-panel'));
  }

  function scan() {
    const menu = document.querySelector('.start-menu');
    if (menu) { enhance(menu); updateCount(menu); }
  }
  const observer = new MutationObserver(() => { clearTimeout(refreshTimer); refreshTimer = setTimeout(scan, 20); });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  setInterval(scan, 750);
  addEventListener('DOMContentLoaded', scan);
})();
