(() => {
  const WALLPAPER_KEY = 'cloudos.customWallpaper.v1';
  const FIT_KEY = 'cloudos.customWallpaperFit.v1';
  const POSITION_KEY = 'cloudos.taskbar.position.v1';
  const ALIGNMENT_KEY = 'cloudos.taskbar.alignment.v1';

  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

  function applyWallpaper() {
    const value = localStorage.getItem(WALLPAPER_KEY);
    if (!value) return;
    document.querySelectorAll('.desktop').forEach((desktop) => {
      desktop.style.backgroundImage = `linear-gradient(rgba(4,2,12,.16),rgba(4,2,12,.28)),url("${value}")`;
      desktop.style.backgroundSize = localStorage.getItem(FIT_KEY) || 'cover';
      desktop.style.backgroundPosition = 'center';
      desktop.style.backgroundRepeat = 'no-repeat';
    });
  }

  function applyTaskbarLayout() {
    const taskbar = document.querySelector('.taskbar');
    if (!taskbar) return;
    const registryClass = [...taskbar.classList].find(name => name.startsWith('position-'));
    const registryPosition = registryClass?.replace('position-', '');
    const position = localStorage.getItem(POSITION_KEY) || registryPosition || 'bottom';
    const alignment = localStorage.getItem(ALIGNMENT_KEY) || 'center';
    document.documentElement.dataset.cloudosTaskbar = position;
    document.documentElement.dataset.cloudosTaskbarAlignment = alignment;
    taskbar.classList.remove('position-top','position-bottom','position-left','position-right','alignment-left','alignment-center');
    taskbar.classList.add(`position-${position}`, `alignment-${alignment}`);
  }

  function applyTheme() {
    const root = document.documentElement;
    const shell = document.querySelector('.obsidianos-root');
    const mode = localStorage.getItem('cloudos.ui.mode');
    const accent = localStorage.getItem('cloudos.ui.accent');
    if (mode) shell?.setAttribute('data-theme', mode);
    if (accent) {
      root.style.setProperty('--accent', accent);
      root.style.setProperty('--accent-hover', accent);
      root.style.setProperty('--text-accent', accent);
    }
  }

  function enhanceSettings() {
    const app = document.querySelector('.settings-app');
    if (!app || app.dataset.patch051 === 'true') return;
    app.dataset.patch051 = 'true';
    app.addEventListener('click', (event) => {
      const button = event.target.closest('button');
      if (!button) return;
      const text = button.textContent?.trim();
      if (text === 'Escuro' || text === 'Claro') {
        localStorage.setItem('cloudos.ui.mode', text === 'Claro' ? 'light' : 'dark');
        queueMicrotask(applyTheme);
      }
    });
    app.addEventListener('change', (event) => {
      const target = event.target;
      if (!(target instanceof HTMLSelectElement)) return;
      const row = target.closest('.settings-data-row');
      const label = row?.querySelector('span')?.textContent?.trim();
      if (label === 'Posição') {
        localStorage.setItem(POSITION_KEY, target.value);
        document.documentElement.dataset.cloudosTaskbar = target.value;
        requestAnimationFrame(() => { applyTaskbarLayout(); window.dispatchEvent(new Event('resize')); });
      }
      if (label === 'Alinhamento') {
        localStorage.setItem(ALIGNMENT_KEY, target.value);
        document.documentElement.dataset.cloudosTaskbarAlignment = target.value;
        requestAnimationFrame(applyTaskbarLayout);
      }
    });
    app.addEventListener('click', (event) => {
      const color = event.target.closest('.accent-option');
      if (!color) return;
      const selected = getComputedStyle(color).backgroundColor || color.style.background;
      localStorage.setItem('cloudos.ui.accent', selected);
      document.documentElement.style.setProperty('--accent', selected);
      document.documentElement.style.setProperty('--text-accent', selected);
    });
  }

  function fixContextMenus() {
    document.querySelectorAll('.context-menu').forEach(menu => {
      const rect = menu.getBoundingClientRect();
      menu.style.left = `${clamp(rect.left, 8, Math.max(8, innerWidth - rect.width - 8))}px`;
      menu.style.top = `${clamp(rect.top, 8, Math.max(8, innerHeight - rect.height - 8))}px`;
      menu.querySelectorAll('.context-submenu').forEach(submenu => {
        const parent = submenu.parentElement?.getBoundingClientRect();
        if (!parent) return;
        submenu.classList.toggle('open-left', parent.right + 220 > innerWidth);
        submenu.classList.toggle('open-up', parent.top + submenu.scrollHeight > innerHeight - 8);
      });
    });
  }

  function addNativeColorControls() {
    const cards = [...document.querySelectorAll('.settings-card')];
    const card = cards.find(node => node.querySelector('h3')?.textContent?.trim() === 'Cor de destaque');
    const grid = card?.querySelector('.settings-accent-grid');
    if (!grid || grid.querySelector('[data-patch-color]')) return;
    [['#111111','Preto'],['#ffffff','Branco']].forEach(([value,label]) => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'accent-option'; button.dataset.patchColor = value;
      button.title = label; button.setAttribute('aria-label', label); button.style.background = value;
      button.addEventListener('click', () => {
        localStorage.setItem('cloudos.ui.accent', value);
        document.documentElement.style.setProperty('--accent', value);
        document.documentElement.style.setProperty('--text-accent', value);
      });
      grid.appendChild(button);
    });
    const custom = document.createElement('label');
    custom.className = 'cloudos-custom-color';
    custom.innerHTML = 'Personalizada <input type="color" aria-label="Escolher cor personalizada">';
    custom.querySelector('input').addEventListener('input', event => {
      const value = event.target.value;
      localStorage.setItem('cloudos.ui.accent', value);
      document.documentElement.style.setProperty('--accent', value);
      document.documentElement.style.setProperty('--text-accent', value);
    });
    grid.appendChild(custom);
  }

  function replaceWallpaperReload() {
    const input = document.querySelector('.settings-app input[type="file"][accept*="image"]');
    if (!input || input.dataset.patch051 === 'true') return;
    input.dataset.patch051 = 'true';
    input.addEventListener('change', () => setTimeout(applyWallpaper, 30));
  }

  function scan() {
    applyWallpaper(); applyTaskbarLayout(); applyTheme(); enhanceSettings();
    addNativeColorControls(); replaceWallpaperReload(); fixContextMenus();
  }
  new MutationObserver(() => requestAnimationFrame(scan)).observe(document.documentElement,{childList:true,subtree:true});
  addEventListener('resize', () => { applyTaskbarLayout(); fixContextMenus(); });
  addEventListener('DOMContentLoaded', scan);
  setInterval(scan, 800);
})();
