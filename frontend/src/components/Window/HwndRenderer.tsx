import { useEffect, useRef, useState } from 'react';
import { useWindowManager } from '../../stores/windowManager';
import kernel from '../../core/kernel';
import './HwndRenderer.css';

export default function HwndRenderer({ windowId }: { windowId: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const { getWindow } = useWindowManager();
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });
  const [isRenderMode, setIsRenderMode] = useState<'canvas' | 'dom'>('canvas');
  const [domHtml, setDomHtml] = useState<string>('');
  const startedRef = useRef(false);
  const [procId, setProcId] = useState<number | null>(null);

  // Efeito principal: Configura listeners E dispara binário — roda só uma vez por janela
  useEffect(() => {
    const win = getWindow(windowId);
    if (!win || !win.processId) return;

    setDimensions({ width: win.width || 800, height: win.height || 600 });

    const currentProcId = win.processId;
    setProcId(currentProcId);

    // Configura os escutadores antes de iniciar o processo
    const offGdiDraw = kernel.on('gdi:draw', (data: { pid: number, commands: any[] }) => {
      if (data.pid !== currentProcId) return;
      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      for (const cmd of data.commands) {
        if (cmd.op === 'fillStyle') ctx.fillStyle = cmd.color;
        if (cmd.op === 'fillRect') ctx.fillRect(cmd.x, cmd.y, cmd.w, cmd.h);
        if (cmd.op === 'font') ctx.font = cmd.font;
        if (cmd.op === 'fillText') ctx.fillText(cmd.text, cmd.x, cmd.y);
        if (cmd.op === 'clearRect') ctx.clearRect(cmd.x, cmd.y, cmd.w, cmd.h);
      }
    });

    const offDomUpdate = kernel.on('user32:dom_update', (data: { pid: number, html: string }) => {
       if (data.pid !== currentProcId) return;
       setIsRenderMode('dom');
       setDomHtml(data.html);
    });

    const offModeChange = kernel.on('user32:set_mode', (data: { pid: number, mode: 'canvas' | 'dom' }) => {
        if (data.pid !== currentProcId) return;
        setIsRenderMode(data.mode);
    });

    // Inicia o binário uma única vez
    if (!startedRef.current && win.params?.binaryPath) {
       startedRef.current = true;
       kernel.executeBinary(currentProcId, win.params.binaryPath);
    }

    return () => {
      offGdiDraw();
      offDomUpdate();
      offModeChange();
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [windowId]); // só re-executa se a janela mudar — isRenderMode fora das deps

  // Transmitindo input de usuário devolta para o Processo
  const handleMouseEvent = (e: React.MouseEvent, type: string) => {
     if(!procId || isRenderMode !== 'canvas') return;
     const rect = canvasRef.current?.getBoundingClientRect();
     if (!rect) return;
     const x = e.clientX - rect.left;
     const y = e.clientY - rect.top;

     kernel.emit('user32:mouse', { pid: procId, type, x, y, button: e.button });
  };

  const handleGlobalClick = (e: React.MouseEvent) => {
      // DOM events intercept (se for um botao html gerado pelo gdi)
      if (isRenderMode === 'dom') {
          const target = e.target as HTMLElement;
          if (target.id) {
              kernel.emit('user32:dom_event', { pid: procId, event: 'click', elementId: target.id });
          }
      }
  };

  return (
    <div 
       ref={containerRef} 
       className="hwnd-renderer"
       onClick={handleGlobalClick}
       style={{ width: '100%', height: '100%', overflow: 'hidden', position: 'relative', backgroundColor: '#ffffff' }}
    >
      {isRenderMode === 'canvas' ? (
          <canvas
            ref={canvasRef}
            width={dimensions.width}
            height={dimensions.height}
            onMouseDown={(e) => handleMouseEvent(e, 'mousedown')}
            onMouseUp={(e) => handleMouseEvent(e, 'mouseup')}
            onMouseMove={(e) => handleMouseEvent(e, 'mousemove')}
            onClick={(e) => handleMouseEvent(e, 'click')}
            style={{ display: 'block', width: '100%', height: '100%' }}
          />
      ) : (
          <div 
             className="hwnd-dom-layer" 
             dangerouslySetInnerHTML={{ __html: domHtml }} 
             style={{ width: '100%', height: '100%' }}
          />
      )}
    </div>
  );
}
