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

export default function Window({ win, onClose, onFocus, children, isMobile }) {
  const [maximized, setMaximized] = useState(false);
  const [maxW, setMaxW] = useState(window.innerWidth);
  const [maxH, setMaxH] = useState(window.innerHeight - 50);

  useEffect(() => {
    const handleResize = () => {
      setMaxW(window.innerWidth);
      setMaxH(window.innerHeight - 50);
    };
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const isFull = isMobile || maximized;

  return (
    <Rnd
      size={isFull ? { width: maxW, height: maxH } : { width: win.w, height: win.h }}
      position={isFull ? { x: 0, y: 0 } : { x: win.x, y: win.y }}
      minWidth={isMobile ? window.innerWidth : 300}
      minHeight={isMobile ? window.innerHeight - 50 : 200}
      maxWidth={maxW} maxHeight={maxH}
      bounds="parent"
      dragHandleClassName="window-header"
      onMouseDown={onFocus}
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
