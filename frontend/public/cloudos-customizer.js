(() => {
  const KEY = 'cloudos.customWallpaper.v1';
  const FIT = 'cloudos.customWallpaperFit.v1';

  function applyWallpaper() {
    const desktop = document.querySelector('.desktop');
    if (!desktop) return;
    const image = localStorage.getItem(KEY);
    if (!image) return;
    desktop.style.backgroundImage = `linear-gradient(rgba(4,2,12,.18),rgba(4,2,12,.30)),url("${image}")`;
    desktop.style.backgroundSize = localStorage.getItem(FIT) || 'cover';
    desktop.style.backgroundPosition = 'center';
    desktop.style.backgroundRepeat = 'no-repeat';
  }

  function addPicker() {
    const heading = [...document.querySelectorAll('.settings-card h3')]
      .find(node => node.textContent?.trim() === 'Plano de Fundo');
    const card = heading?.closest('.settings-card');
    if (!card || card.querySelector('[data-cloudos-custom-wallpaper]')) return;

    const section = document.createElement('div');
    section.dataset.cloudosCustomWallpaper = 'true';
    section.className = 'cloudos-wallpaper-picker';
    section.innerHTML = `
      <div class="cloudos-wallpaper-picker__title">Sua imagem</div>
      <div class="cloudos-wallpaper-picker__preview" aria-label="Pré-visualização do plano de fundo"></div>
      <div class="cloudos-wallpaper-picker__actions">
        <label class="cloudos-neon-button">
          Escolher imagem
          <input type="file" accept="image/png,image/jpeg,image/webp" hidden>
        </label>
        <select class="cloudos-wallpaper-fit" aria-label="Ajuste da imagem">
          <option value="cover">Preencher</option>
          <option value="contain">Ajustar</option>
          <option value="auto">Centralizar</option>
        </select>
        <button type="button" class="cloudos-ghost-button">Restaurar padrão</button>
      </div>`;
    card.appendChild(section);

    const input = section.querySelector('input');
    const preview = section.querySelector('.cloudos-wallpaper-picker__preview');
    const fit = section.querySelector('select');
    const reset = section.querySelector('button');
    const current = localStorage.getItem(KEY);
    fit.value = localStorage.getItem(FIT) || 'cover';
    if (current) preview.style.backgroundImage = `url("${current}")`;

    input.addEventListener('change', () => {
      const file = input.files?.[0];
      if (!file) return;
      if (!['image/png','image/jpeg','image/webp'].includes(file.type)) {
        alert('Escolha uma imagem PNG, JPG ou WebP.');
        return;
      }
      if (file.size > 8 * 1024 * 1024) {
        alert('A imagem deve ter no máximo 8 MB.');
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        const value = String(reader.result || '');
        try {
          localStorage.setItem(KEY, value);
          preview.style.backgroundImage = `url("${value}")`;
          applyWallpaper();
        } catch {
          alert('Não foi possível salvar a imagem. Escolha um arquivo menor.');
        }
      };
      reader.readAsDataURL(file);
    });

    fit.addEventListener('change', () => {
      localStorage.setItem(FIT, fit.value);
      applyWallpaper();
    });

    reset.addEventListener('click', () => {
      localStorage.removeItem(KEY);
      localStorage.removeItem(FIT);
      location.reload();
    });
  }

  const observer = new MutationObserver(() => {
    applyWallpaper();
    addPicker();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  addEventListener('DOMContentLoaded', () => { applyWallpaper(); addPicker(); });
})();
