import { useState, useEffect, Component } from 'react';
import { Rnd } from 'react-rnd';
import { X, Minus, Square } from 'lucide-react';

class WindowErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("Erro na janela:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: '20px', color: '#ff6b6b', background: '#1e1e1e', height: '100%' }}>
          <h4>Erro ao carregar o aplicativo.</h4>
          <p style={{ fontSize: '12px', marginTop: '10px', opacity: 0.8 }}>
            {this.state.error?.toString()}
          </p>
        </div>
      );
    }
    return this.props.children;
  }
}

export default function Window({ win, onClose, onFocus, onPositionChange, children, isMobile }) {
  const [maximized, setMaximized] = useState(false);
  const [maxW, setMaxW] = useState(window.innerWidth);
  const [maxH, setMaxH] = useState(window.innerHeight - 50);
  const [size, setSize] = useState({ width: win.w || 750, height: win.h || 500 });
  const [pos, setPos] = useState({ x: win.x || 50, y: win.y || 50 });

  useEffect(() => {
    const handleResize = () => {
      setMaxW(window.innerWidth);
      setMaxH(window.innerHeight - 50);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const isFull = isMobile || maximized;

  // Lógica de Window Snapping estilo Windows 11 (Split Screen)
  const handleDragStop = (e, d) => {
    if (d.x <= 10) {
      // Snapping na Esquerda -> Ocupa metade esquerda da tela
      setPos({ x: 0, y: 0 });
      setSize({ width: Math.floor(window.innerWidth / 2), height: window.innerHeight - 48 });
    } else if (d.x >= window.innerWidth - (win.w || 300) - 20) {
      // Snapping na Direita -> Ocupa metade direita da tela
      setPos({ x: Math.floor(window.innerWidth / 2), y: 0 });
      setSize({ width: Math.floor(window.innerWidth / 2), height: window.innerHeight - 48 });
    } else {
      setPos({ x: d.x, y: d.y });
    }
  };

  return (
    <Rnd
      size={isFull ? { width: maxW, height: maxH } : size}
      position={isFull ? { x: 0, y: 0 } : pos}
      minWidth={isMobile ? window.innerWidth : 300}
      minHeight={isMobile ? window.innerHeight - 50 : 200}
      maxWidth={maxW} maxHeight={maxH}
      bounds="parent"
      dragHandleClassName="window-header"
      onMouseDown={onFocus}
      onDragStop={(e, d) => {
        handleDragStop(e, d);
        onPositionChange?.({ x: d.x, y: d.y, w: size.width, h: size.height });
      }}
      onResizeStop={(e, direction, ref, delta, position) => {
        const newW = parseInt(ref.style.width, 10);
        const newH = parseInt(ref.style.height, 10);
        setSize({ width: newW, height: newH });
        setPos(position);
        onPositionChange?.({ x: position.x, y: position.y, w: newW, h: newH });
      }}
      style={{ zIndex: win.z, position: 'absolute' }}
      enableResizing={!isFull}
      disableDragging={isFull}
    >
      <div className="window-wrapper" style={{ height: '100%', width: '100%', borderRadius: isMobile ? 0 : 8 }}>
        <div className="window-header">
          <div className="window-title">
            {win.icon && <win.icon size={16} />} 
            {win.title}
          </div>
          <div className="window-controls">
            {!isMobile && <button className="win-btn"><Minus size={14} /></button>}
            {!isMobile && (
              <button className="win-btn" onClick={() => setMaximized(!maximized)}>
                <Square size={12} />
              </button>
            )}
            <button className="win-btn close" onClick={onClose}><X size={16} /></button>
          </div>
        </div>
        <div className="window-body">
          <WindowErrorBoundary>
            {children}
          </WindowErrorBoundary>
        </div>
      </div>
    </Rnd>
  );
}
