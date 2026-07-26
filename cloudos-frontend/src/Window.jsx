import { Rnd } from 'react-rnd';
import { X, Minus, Square } from 'lucide-react';

export default function Window({ win, onClose, onFocus, children }) {
  return (
    <Rnd
      initial={{ x: win.x, y: win.y, width: win.w, height: win.h }}
      minWidth={400} minHeight={250}
      bounds="parent"
      dragHandleClassName="window-header"
      onMouseDown={onFocus}
      style={{ zIndex: win.z, position: 'absolute' }}
    >
      <div className="window-wrapper" style={{ height: '100%', width: '100%' }}>
        <div className="window-header">
          <div className="window-title">
            {/* Renderiza o ícone se existir */}
            {win.icon && <win.icon size={16} />} 
            {win.title}
          </div>
          <div className="window-controls">
            <button className="win-btn"><Minus size={14} /></button>
            <button className="win-btn"><Square size={12} /></button>
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
