import { useState } from 'react';
import { Rnd } from 'react-rnd';
import { X, Minus, Square } from 'lucide-react';

export default function Window({ win, onClose, onFocus, children }) {
  const [maximized, setMaximized] = useState(false);

  return (
    <Rnd
      // Se maximizado, ocupa tudo. Se não, usa o tamanho inicial
      size={maximized ? { width: '100%', height: '100%' } : { width: win.w, height: win.h }}
      position={maximized ? { x: 0, y: 0 } : { x: win.x, y: win.y }}
      minWidth={400} minHeight={250}
      bounds="parent"
      dragHandleClassName="window-header"
      onMouseDown={onFocus}
      style={{ zIndex: win.z, position: 'absolute' }}
      // Desabilita arrasto e redimensionamento se estiver maximizado
      enableResizing={!maximized}
      disableDragging={maximized}
    >
      <div className="window-wrapper" style={{ height: '100%', width: '100%' }}>
        <div className="window-header">
          <div className="window-title">
            {win.icon && <win.icon size={16} />} 
            {win.title}
          </div>
          <div className="window-controls">
            <button className="win-btn"><Minus size={14} /></button>
            <button className="win-btn" onClick={() => setMaximized(!maximized)}>
              <Square size={12} />
            </button>
            <button className="win-btn close" onClick={onClose}><X size={16} /></button>
          </div>
        </div>
        <div className="window-body">
          {children}
        </div>
      </div>
    </Rnd>
  );
}
