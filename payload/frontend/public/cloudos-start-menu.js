(() => {
  const ENHANCED = 'data-cloudos-start-enhanced-v2';
  let activeView = 'home';
  let unsubscribe;
  let scheduled = false;
  const api = () => window.cloudOS;
  const windows = () => api()?.windows?.() || [];
  const safe = value => { const node = document.createElement('span'); node.textContent = String(value ?? ''); return node.innerHTML; };
  const closeMenu = () => document.querySelector('.start-menu-overlay')?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));

  function renderOpen(menu) {
    const panel = menu.querySelector('.cloudos-start-panel');
    if (!panel) return;
    const list = windows();
    const groups = new Map();
    for (const win of list) {
      const key = win.appId || win.title || win.id;
      const group = groups.get(key) || { name: win.title || win.appId || 'Aplicativo', icon: win.icon || '▣', items: [] };
      group.items.push(win); groups.set(key, group);
    }
    panel.innerHTML = `<div class="cloudos-running-head"><div><strong>Aplicativos abertos</strong><small>${list.length} janela${list.length === 1 ? '' : 's'}</small></div><button data-action="close-all" ${list.length ? '' : 'disabled'}>Fechar todas</button></div><div class="cloudos-running-list">${list.length ? [...groups.values()].map(group => `<section class="cloudos-running-group"><header><span>${safe(group.icon)}</span><strong>${safe(group.name)}</strong><b>${group.items.length}</b></header>${group.items.map(win => `<div class="cloudos-running-window" data-window-id="${safe(win.id)}"><button class="cloudos-window-focus" data-action="focus"><span>${safe(win.title || group.name)}</span><small>${win.isMinimized ? 'Minimizada' : win.isActive ? 'Ativa' : 'Em execução'}</small></button><div class="cloudos-window-actions"><button data-action="minimize" title="Minimizar">−</button><button data-action="maximize" title="Maximizar ou restaurar">□</button><button class="danger" data-action="close" title="Fechar">×</button></div></div>`).join('')}</section>`).join('') : '<div class="cloudos-empty-running"><span>◇</span><strong>Nenhum aplicativo aberto</strong><small>Os aplicativos em execução aparecerão aqui.</small></div>'}</div>`;
  }

  function updateCount(menu) {
    const badge = menu.querySelector('.cloudos-running-count');
    if (badge) badge.textContent = String(windows().length);
    if (activeView === 'running') renderOpen(menu);
  }

  function switchView(menu, view) {
    activeView = view;
    const nativeSections = [...menu.children].filter(node => node.classList?.contains('start-section'));
    const panel = menu.querySelector('.cloudos-start-panel');
    menu.querySelectorAll('.cloudos-start-nav button').forEach(button => button.classList.toggle('active', button.dataset.view === view));
    nativeSections.forEach(section => section.hidden = view !== 'home');
    if (panel) panel.hidden = view === 'home';
    if (view === 'running') renderOpen(menu);
    if (view === 'all') {
      const apps = [...menu.querySelectorAll('.start-app-btn')];
      panel.innerHTML = '<div class="cloudos-running-head"><strong>Todos os aplicativos</strong></div><div class="cloudos-all-grid"></div>';
      const grid = panel.querySelector('.cloudos-all-grid');
      apps.sort((a,b) => (a.textContent || '').localeCompare(b.textContent || '', 'pt-BR')).forEach(original => {
        const copy = original.cloneNode(true); copy.addEventListener('click', () => original.click()); grid.appendChild(copy);
      });
    }
  }

  function enhance(menu) {
    if (menu.hasAttribute(ENHANCED)) return;
    menu.setAttribute(ENHANCED, 'true'); menu.classList.add('cloudos-start-menu');
    const nav = document.createElement('nav'); nav.className = 'cloudos-start-nav';
    nav.innerHTML = '<button data-view="home" class="active">Início</button><button data-view="all">Todos</button><button data-view="running">Abertos <span class="cloudos-running-count">0</span></button>';
    menu.querySelector('.start-search')?.after(nav);
    const panel = document.createElement('div'); panel.className = 'cloudos-start-panel'; panel.hidden = true;
    menu.insertBefore(panel, menu.querySelector('.start-bottom') || null);
    nav.addEventListener('click', event => { const button = event.target.closest('button[data-view]'); if (button) switchView(menu, button.dataset.view); });
    panel.addEventListener('click', event => {
      const button = event.target.closest('button'); if (!button || button.disabled) return;
      const action = button.dataset.action; const id = button.closest('[data-window-id]')?.dataset.windowId; const bridge = api();
      if (!bridge) return;
      if (action === 'close-all') bridge.closeAll();
      else if (id && action === 'minimize') bridge.minimize(id);
      else if (id && action === 'close') bridge.close(id);
      else if (id && action === 'maximize') { const win = windows().find(item => item.id === id); win?.isMaximized ? bridge.restore(id) : bridge.maximize(id); }
      else if (id) { bridge.restore(id); bridge.focus(id); closeMenu(); }
      requestAnimationFrame(() => renderOpen(menu));
    });
    updateCount(menu);
    unsubscribe?.(); unsubscribe = api()?.subscribe?.(() => { if (!scheduled) { scheduled = true; requestAnimationFrame(() => { scheduled = false; updateCount(menu); }); } });
  }

  const scan = () => { const menu = document.querySelector('.start-menu'); if (menu) { enhance(menu); updateCount(menu); } };
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  addEventListener('DOMContentLoaded', scan); scan();
})();
