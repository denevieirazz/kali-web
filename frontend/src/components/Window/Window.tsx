// ============================================
// Window Component - Draggable & Resizable
// ============================================
import { useRef, useCallback, type ReactNode, Suspense } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import { useContextMenuStore } from '../../stores/contextMenuStore';
import { ProcessProvider } from '../../contexts/ProcessContext';
import './Window.css';

interface Props {
  windowId: string;
  children: ReactNode;
}

export default function Window({ windowId, children }: Props) {
  const win = useWindowManager(s => s.windows.find(w => w.id === windowId));
  const { closeWindow, minimizeWindow, toggleMaximize, focusWindow, moveWindow, resizeWindow } = useWindowManager();
  
  const windowRef = useRef<HTMLDivElement>(null);
  const isDragging = useRef(false);
  const isResizing = useRef(false);
  const dragOffset = useRef({ x: 0, y: 0 });
  const resizeDir = useRef('');
  const resizeStart = useRef({ x: 0, y: 0, width: 0, height: 0, winX: 0, winY: 0 });

  const handleMouseDown = useCallback(() => {
    // System windows (taskbar, desktop) should never steal focus
    if (win && !win.isActive && !win.isSystem) {
      focusWindow(windowId);
    }
  }, [win, windowId, focusWindow]);

  // Title bar drag
  const handleTitleMouseDown = useCallback((e: React.MouseEvent) => {
    if (!win || win.isMaximized) return;
    e.preventDefault();
    isDragging.current = true;
    dragOffset.current = { x: e.clientX - win.x, y: e.clientY - win.y };
    
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      moveWindow(windowId, e.clientX - dragOffset.current.x, Math.max(0, e.clientY - dragOffset.current.y));
    };
    
    const handleMouseUp = () => {
      isDragging.current = false;
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
    
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  }, [win, windowId, moveWindow]);

  // Resize handlers
  const handleResizeMouseDown = useCallback((e: React.MouseEvent, direction: string) => {
    if (!win || !win.isResizable || win.isMaximized) return;
    e.preventDefault();
    e.stopPropagation();
    isResizing.current = true;
    resizeDir.current = direction;
    resizeStart.current = {
      x: e.clientX,
      y: e.clientY,
      width: win.width,
      height: win.height,
      winX: win.x,
      winY: win.y,
    };

    const handleMouseMove = (e: MouseEvent) => {
      if (!isResizing.current) return;
      const dx = e.clientX - resizeStart.current.x;
      const dy = e.clientY - resizeStart.current.y;
      const dir = resizeDir.current;
      
      let newW = resizeStart.current.width;
      let newH = resizeStart.current.height;
      let newX = resizeStart.current.winX;
      let newY = resizeStart.current.winY;

      if (dir.includes('e')) newW += dx;
      if (dir.includes('s')) newH += dy;
      if (dir.includes('w')) { newW -= dx; newX += dx; }
      if (dir.includes('n')) { newH -= dy; newY += dy; }

      if (newW >= (win?.minWidth || 300)) {
        if (dir.includes('w')) moveWindow(windowId, newX, dir.includes('n') ? newY : win!.y);
        resizeWindow(windowId, newW, newH);
      }
      if (newH >= (win?.minHeight || 200)) {
        if (dir.includes('n')) moveWindow(windowId, dir.includes('w') ? newX : win!.x, newY);
        resizeWindow(windowId, newW, newH);
      }
    };

    const handleMouseUp = () => {
      isResizing.current = false;
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  }, [win, windowId, moveWindow, resizeWindow]);

  const { openContextMenu } = useContextMenuStore();

  const handleClose = useCallback(() => {
    // kernel.closeWindow() encerra o processo internamente
    closeWindow(windowId);
  }, [windowId, closeWindow]);

  const handleWindowContextMenu = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    if (!win) return;

    openContextMenu(e.clientX, e.clientY, [
      { id: 'restore', label: 'Restaurar', disabled: !win.isMaximized, onClick: () => toggleMaximize(windowId) },
      { id: 'move', label: 'Mover', disabled: win.isMaximized, onClick: () => {} },
      { id: 'size', label: 'Tamanho', disabled: !win.isResizable || win.isMaximized, onClick: () => {} },
      { id: 'min', label: 'Minimizar', onClick: () => minimizeWindow(windowId) },
      { id: 'max', label: 'Maximizar', disabled: win.isMaximized, onClick: () => toggleMaximize(windowId) },
      { id: 'sep1', label: '', separator: true },
      { id: 'close', label: 'Fechar', shortcut: 'Alt+F4', onClick: handleClose }
    ]);
  }, [win, windowId, toggleMaximize, minimizeWindow, handleClose, openContextMenu]);

  if (!win || win.isMinimized) return null;

  return (
    <div
      ref={windowRef}
      className={`window ${win.isActive ? 'active' : ''} ${win.isMaximized ? 'maximized' : ''} ${!win.hasFrame ? 'frameless' : ''} ${win.isSystem ? 'system-window' : ''}`}
      style={{
        left: win.x,
        top: win.y,
        width: win.width,
        height: win.height,
        zIndex: win.zIndex,
      }}
      onMouseDown={handleMouseDown}
    >
      {/* Title Bar - Only show if hasFrame is True */}
      {win.hasFrame && (
        <div className="window-titlebar" onMouseDown={handleTitleMouseDown} onDoubleClick={() => toggleMaximize(windowId)} onContextMenu={handleWindowContextMenu}>
          <div className="window-titlebar-left">
            <span className="window-icon">{win.icon}</span>
            <span className="window-title text-ellipsis">{win.title}</span>
          </div>
          <div className="window-controls">
            {win.isMinimizable && (
              <button className="window-btn minimize" onClick={(e) => { e.stopPropagation(); minimizeWindow(windowId); }} title="Minimizar">
                <svg width="12" height="12" viewBox="0 0 12 12"><rect y="5" width="12" height="1.5" rx="0.75" fill="currentColor"/></svg>
              </button>
            )}
            {win.isMaximizable && (
              <button className="window-btn maximize" onClick={(e) => { e.stopPropagation(); toggleMaximize(windowId); }} title={win.isMaximized ? "Restaurar" : "Maximizar"}>
                {win.isMaximized ? (
                  <svg width="12" height="12" viewBox="0 0 12 12"><rect x="2.5" y="0" width="9" height="9" rx="1.5" stroke="currentColor" strokeWidth="1.3" fill="none"/><rect x="0" y="2.5" width="9" height="9" rx="1.5" stroke="currentColor" strokeWidth="1.3" fill="none"/></svg>
                ) : (
                  <svg width="12" height="12" viewBox="0 0 12 12"><rect x="1" y="1" width="10" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" fill="none"/></svg>
                )}
              </button>
            )}
            {win.isClosable && (
              <button className="window-btn close" onClick={(e) => { e.stopPropagation(); handleClose(); }} title="Fechar">
                <svg width="12" height="12" viewBox="0 0 12 12"><path d="M1 1L11 11M11 1L1 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
              </button>
            )}
          </div>
        </div>
      )}

      {/* Content */}
      <div className="window-content">
        <ProcessProvider pid={win.processId}>
          <Suspense fallback={
            <div className="window-loader">
              <div className="spinner" />
              <span>Carregando executável...</span>
            </div>
          }>
            {children}
          </Suspense>
        </ProcessProvider>
      </div>

      {/* Resize Handles */}
      {win.isResizable && !win.isMaximized && (
        <>
          <div className="resize-handle n" onMouseDown={(e) => handleResizeMouseDown(e, 'n')} />
          <div className="resize-handle s" onMouseDown={(e) => handleResizeMouseDown(e, 's')} />
          <div className="resize-handle e" onMouseDown={(e) => handleResizeMouseDown(e, 'e')} />
          <div className="resize-handle w" onMouseDown={(e) => handleResizeMouseDown(e, 'w')} />
          <div className="resize-handle ne" onMouseDown={(e) => handleResizeMouseDown(e, 'ne')} />
          <div className="resize-handle nw" onMouseDown={(e) => handleResizeMouseDown(e, 'nw')} />
          <div className="resize-handle se" onMouseDown={(e) => handleResizeMouseDown(e, 'se')} />
          <div className="resize-handle sw" onMouseDown={(e) => handleResizeMouseDown(e, 'sw')} />
        </>
      )}
    </div>
  );
}
