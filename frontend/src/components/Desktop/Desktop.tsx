// ============================================
// Desktop Component — with draggable icons + drop from FileExplorer
// ============================================
import { useState, useCallback, useRef, useEffect } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useWindowManager } from '../../stores/windowManager';
import { useProcessManager } from '../../stores/processManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { useAppRegistry } from '../../core/appRegistry';
import { useRubberBand } from '../../hooks/useRubberBand';
import defaultWallpaper from '../../assets/wallpapers/default.png';
import './Desktop.css';

interface DesktopIconData {
  id: string;
  name: string;
  icon: string;
  appId: string;
  x: number;
  y: number;
}

const GRID = 88;
function snapToGrid(v: number) {
  return Math.round(v / GRID) * GRID;
}

function findFreeCell(
  x: number,
  y: number,
  occupied: { x: number; y: number }[],
  desktopW: number,
  desktopH: number
): { x: number; y: number } {
  const snappedX = snapToGrid(x);
  const snappedY = snapToGrid(y);

  const isOccupied = (cx: number, cy: number) =>
    occupied.some((o) => o.x === cx && o.y === cy);

  if (!isOccupied(snappedX, snappedY)) return { x: snappedX, y: snappedY };

  for (let r = 1; r < 20; r++) {
    for (let dx = -r; dx <= r; dx++) {
      for (let dy = -r; dy <= r; dy++) {
        if (Math.abs(dx) !== r && Math.abs(dy) !== r) continue;
        const cx = snappedX + dx * GRID;
        const cy = snappedY + dy * GRID;
        if (cx < 0 || cy < 0 || cx + GRID > desktopW || cy + GRID > desktopH) continue;
        if (!isOccupied(cx, cy)) return { x: cx, y: cy };
      }
    }
  }
  return { x: snappedX, y: snappedY };
}

function buildDefaultIcons(): DesktopIconData[] {
  const raw = [
    { id: 'recycle', name: 'Lixeira', icon: '🗑️', appId: '' },
    { id: 'explorer', name: 'Explorador de Arquivos', icon: '📁', appId: 'file-explorer' },
    { id: 'cloudos-term', name: 'CloudOS Terminal', icon: '⚡', appId: 'cloudos-terminal' },
    { id: 'cloudos-files', name: 'CloudOS Files', icon: '☁️', appId: 'cloudos-files' },
    { id: 'sys-mon', name: 'System Monitor', icon: '📈', appId: 'system-monitor' },
    { id: 'inst-linux', name: 'Windows + Linux', icon: '◈', appId: 'install-linux' },
    { id: 'env-doc', name: 'Environment Doctor', icon: '🩺', appId: 'env-doctor' },
    { id: 'terminal', name: 'Terminal Offline', icon: '💻', appId: 'terminal' },
    { id: 'notepad', name: 'Bloco de Notas', icon: '📝', appId: 'notepad' },
    { id: 'browser', name: 'Navegador', icon: '🌐', appId: 'browser' },
    { id: 'settings', name: 'Configurações', icon: '⚙️', appId: 'settings' },
  ];
  return raw.map((icon, i) => ({
    ...icon,
    x: 12,
    y: 12 + i * GRID,
  }));
}

const STORAGE_KEY = 'cloudos-unified-desktop-icons-v2';

function loadIcons(): DesktopIconData[] {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      return (JSON.parse(saved) as DesktopIconData[]).map((icon) =>
        icon.id === 'inst-linux' ? { ...icon, name: 'Windows + Linux', icon: '◈' } : icon
      );
    }
  } catch {}
  return buildDefaultIcons();
}

function saveIcons(icons: DesktopIconData[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(icons));
}

export default function Desktop() {
  const { closeStartMenu, theme } = useSystem();
  const openWindow = useWindowManager((s) => s.openWindow);
  const createProcess = useProcessManager((s) => s.createProcess);
  const { openContextMenu } = useContextMenuStore();

  const [icons, setIcons] = useState<DesktopIconData[]>(() => {
    const loaded = loadIcons();
    const resolved: DesktopIconData[] = [];
    const occupied: { x: number; y: number }[] = [];
    for (const ic of loaded) {
      const { x, y } = findFreeCell(ic.x, ic.y, occupied, 1400, 900);
      resolved.push({ ...ic, x, y });
      occupied.push({ x, y });
    }
    return resolved;
  });
  const [selectedIcons, setSelectedIcons] = useState<Set<string>>(new Set());
  const [dragOver, setDragOver] = useState(false);

  const iconRefs = useRef<Map<string, HTMLDivElement>>(new Map());
  const desktopRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    saveIcons(icons);
  }, [icons]);

  useEffect(() => {
    const desktop = desktopRef.current;
    if (!desktop) return;
    let lastWidth = 0;
    let lastHeight = 0;
    const observer = new ResizeObserver(([entry]) => {
      const width = Math.floor(entry.contentRect.width);
      const height = Math.floor(entry.contentRect.height);
      if (width === lastWidth && height === lastHeight) return;
      lastWidth = width;
      lastHeight = height;
      const usableHeight = Math.max(GRID, height - 12);
      const rows = Math.max(1, Math.floor(usableHeight / GRID));
      setIcons((previous) =>
        previous.map((icon, index) => ({
          ...icon,
          x: 12 + Math.floor(index / rows) * GRID,
          y: 12 + (index % rows) * GRID,
        }))
      );
    });
    observer.observe(desktop);
    return () => observer.disconnect();
  }, []);

  const getItemRects = useCallback(() => {
    const map = new Map<string, DOMRect>();
    iconRefs.current.forEach((el, key) => {
      if (el) map.set(key, el.getBoundingClientRect());
    });
    return map;
  }, []);

  const { selectionRect, onMouseDown: rubberBandMouseDown, containerRef } = useRubberBand({
    onSelectionChange: (keys) => setSelectedIcons(new Set(keys)),
    getItemRects,
  });

  const handleOpenApp = useCallback(
    (appId: string) => {
      if (!appId) return;
      const app = useAppRegistry.getState().apps[appId];
      if (!app) return;
      const pid = createProcess(app.id, app.name, app.icon);
      openWindow({
        title: app.name,
        icon: app.icon,
        appId: app.id,
        width: app.defaultWidth,
        height: app.defaultHeight,
        minWidth: app.minWidth,
        minHeight: app.minHeight,
        isResizable: app.isResizable,
        processId: pid,
        params: app.binaryPath ? { binaryPath: app.binaryPath } : undefined,
      });
    },
    [openWindow, createProcess]
  );

  const dragIconId = useRef<string | null>(null);
  const dragOffset = useRef({ x: 0, y: 0 });

  const handleIconDragStart = useCallback((e: React.DragEvent, icon: DesktopIconData) => {
    dragIconId.current = icon.id;
    const el = iconRefs.current.get(icon.id);
    if (el) {
      const rect = el.getBoundingClientRect();
      dragOffset.current = { x: e.clientX - rect.left, y: e.clientY - rect.top };
    }
    const ghost = document.createElement('div');
    ghost.style.cssText = 'position:fixed;top:-200px;opacity:0;';
    document.body.appendChild(ghost);
    e.dataTransfer.setDragImage(ghost, 0, 0);
    setTimeout(() => document.body.removeChild(ghost), 0);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('application/obsidianos-icon', icon.id);
  }, []);

  const handleIconDrag = useCallback((e: React.DragEvent, id: string) => {
    if (e.clientX === 0 && e.clientY === 0) return;
    const desktop = desktopRef.current;
    if (!desktop) return;
    const rect = desktop.getBoundingClientRect();
    const x = Math.max(
      0,
      Math.min(rect.width - GRID, e.clientX - rect.left - dragOffset.current.x)
    );
    const y = Math.max(
      0,
      Math.min(rect.height - GRID, e.clientY - rect.top - dragOffset.current.y)
    );
    setIcons((prev) => prev.map((ic) => (ic.id === id ? { ...ic, x, y } : ic)));
  }, []);

  const handleIconDragEnd = useCallback((_e: React.DragEvent, id: string) => {
    const desktop = desktopRef.current;
    const dw = desktop?.getBoundingClientRect().width ?? 1200;
    const dh = desktop?.getBoundingClientRect().height ?? 800;

    setIcons((prev) => {
      const others = prev.filter((ic) => ic.id !== id).map((ic) => ({ x: ic.x, y: ic.y }));
      return prev.map((ic) => {
        if (ic.id !== id) return ic;
        const { x, y } = findFreeCell(ic.x, ic.y, others, dw, dh);
        return { ...ic, x, y };
      });
    });
    dragIconId.current = null;
  }, []);

  const handleIconDoubleClick = useCallback(
    (_e: React.MouseEvent, appId: string) => {
      handleOpenApp(appId);
    },
    [handleOpenApp]
  );

  const handleDesktopMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if ((e.target as HTMLElement).closest('[data-desktop-icon]')) return;
      rubberBandMouseDown(e);
    },
    [rubberBandMouseDown]
  );

  const handleDragOver = useCallback((e: React.DragEvent) => {
    const types = e.dataTransfer.types;
    if (types.includes('application/obsidianos-file') || types.includes('text/plain')) {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
      setDragOver(true);
    }
  }, []);

  const handleDragLeave = useCallback(() => setDragOver(false), []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragOver(false);

      const desktop = desktopRef.current;
      if (!desktop) return;
      const rect = desktop.getBoundingClientRect();
      const dropX = snapToGrid(e.clientX - rect.left);
      const dropY = snapToGrid(e.clientY - rect.top);

      if (e.dataTransfer.getData('application/obsidianos-icon')) return;

      let raw = e.dataTransfer.getData('application/obsidianos-file');
      if (!raw) raw = e.dataTransfer.getData('text/plain');
      if (!raw) return;

      try {
        const data: { path: string; name: string; icon: string; appId?: string } = JSON.parse(raw);
        const id = `dropped-${data.path.replace(/[\\:]/g, '-')}`;
        if (icons.some((ic) => ic.id === id)) return;

        const dw = desktop?.getBoundingClientRect().width ?? 1200;
        const dh = desktop?.getBoundingClientRect().height ?? 800;
        const occupied = icons.map((ic) => ({ x: ic.x, y: ic.y }));
        const { x, y } = findFreeCell(dropX, dropY, occupied, dw, dh);

        setIcons((prev) => [
          ...prev,
          { id, name: data.name, icon: data.icon || '📄', appId: data.appId || '', x, y },
        ]);
      } catch {}
    },
    [icons]
  );

  const handleContextMenu = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      closeStartMenu();
      openContextMenu(e.clientX, e.clientY, [
        {
          id: 'view',
          label: 'Exibir',
          children: [
            { id: 'large', label: 'Ícones grandes', onClick: () => {} },
            { id: 'medium', label: 'Ícones médios', onClick: () => {} },
          ],
        },
        { id: 'sep1', label: '', separator: true },
        {
          id: 'refresh',
          label: 'Atualizar',
          shortcut: 'F5',
          onClick: () => {
            setIcons((prev) => [...prev]);
            setSelectedIcons(new Set());
          },
        },
        {
          id: 'reset-icons',
          label: 'Reorganizar Ícones',
          onClick: () => {
            const fresh = buildDefaultIcons();
            setIcons(fresh);
            saveIcons(fresh);
          },
        },
        { id: 'sep2', label: '', separator: true },
        {
          id: 'display',
          label: 'Configurações de Exibição',
          onClick: () => handleOpenApp('settings'),
        },
        { id: 'personalize', label: 'Personalizar', onClick: () => handleOpenApp('settings'),
        },
      ]);
    },
    [closeStartMenu, openContextMenu, handleOpenApp]
  );

  const handleIconContextMenu = useCallback(
    (e: React.MouseEvent, icon: DesktopIconData) => {
      e.preventDefault();
      e.stopPropagation();
      setSelectedIcons(new Set([icon.id]));
      openContextMenu(e.clientX, e.clientY, [
        { id: 'open', label: 'Abrir', onClick: () => handleOpenApp(icon.appId) },
        { id: 'sep1', label: '', separator: true },
        {
          id: 'remove',
          label: 'Remover da Área de Trabalho',
          onClick: () => {
            setIcons((prev) => prev.filter((ic) => ic.id !== icon.id));
          },
        },
      ]);
    },
    [openContextMenu, handleOpenApp]
  );

  const currentWallpaper =
    theme.wallpaper && theme.wallpaper !== 'default'
      ? theme.wallpaper.startsWith('/') || theme.wallpaper.startsWith('http')
        ? theme.wallpaper
        : `/Wallpapers/${theme.wallpaper}`
      : defaultWallpaper;

  return (
    <div
      className={`desktop ${dragOver ? 'desktop-drag-over' : ''}`}
      style={{ backgroundImage: `url(${currentWallpaper})` }}
      ref={(el) => {
        containerRef.current = el;
        desktopRef.current = el;
      }}
      onClick={() => {
        setSelectedIcons(new Set());
        closeStartMenu();
      }}
      onMouseDown={handleDesktopMouseDown}
      onContextMenu={handleContextMenu}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {icons.map((icon) => (
        <div
          key={icon.id}
          ref={(el) => {
            if (el) iconRefs.current.set(icon.id, el);
            else iconRefs.current.delete(icon.id);
          }}
          data-desktop-icon="true"
          className={`desktop-icon ${selectedIcons.has(icon.id) ? 'selected' : ''} ${
            dragIconId.current === icon.id ? 'dragging' : ''
          }`}
          style={{ position: 'absolute', left: icon.x, top: icon.y }}
          draggable
          onDragStart={(e) => handleIconDragStart(e, icon)}
          onDrag={(e) => handleIconDrag(e, icon.id)}
          onDragEnd={(e) => handleIconDragEnd(e, icon.id)}
          onMouseDown={(e) => {
            e.stopPropagation();
            setSelectedIcons(new Set([icon.id]));
            closeStartMenu();
          }}
          onDoubleClick={(e) => handleIconDoubleClick(e, icon.appId)}
          onContextMenu={(e) => handleIconContextMenu(e, icon)}
        >
          <div className="desktop-icon-image">{icon.icon}</div>
          <span className="desktop-icon-label">{icon.name}</span>
        </div>
      ))}

      {selectionRect && (
        <div
          className="desktop-selection-box"
          style={{
            left: selectionRect.x,
            top: selectionRect.y,
            width: selectionRect.width,
            height: selectionRect.height,
          }}
        />
      )}

      {dragOver && (
        <div className="desktop-drop-hint">
          <span>Soltar para adicionar à Área de Trabalho</span>
        </div>
      )}
    </div>
  );
}
