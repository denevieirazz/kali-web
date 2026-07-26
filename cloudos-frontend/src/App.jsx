import { useState, useEffect } from 'react';
import { Terminal as TerminalIcon, FileText, Settings, Search, Wifi, Volume2, Battery } from 'lucide-react';
import Window from './Window';
import { TerminalApp, NotepadApp, SettingsApp } from './apps';

export default function App() {
  const [windows, setWindows] = useState([]);
  const [zIndex, setZIndex] = useState(100);
  const [startOpen, setStartOpen] = useState(false);
  const [time, setTime] = useState(new Date());
  const [bg, setBg] = useState('https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070');

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const openApp = (appId, title, icon, component) => {
    const existing = windows.find(w => w.appId === appId);
    if (existing) return focusWindow(existing.id);
    const newWin = { id: Date.now(), appId, title, icon, x: 150 + Math.random()*100, y: 80 + Math.random()*50, w: 700, h: 450, z: zIndex + 1, component };
    setWindows([...windows, newWin]);
    setZIndex(zIndex + 1);
    setStartOpen(false);
  };

  const closeApp = (id) => setWindows(windows.filter(w => w.id !== id));
  const focusWindow = (id) => {
    setWindows(windows.map(w => w.id === id ? { ...w, z: zIndex + 1 } : w));
    setZIndex(zIndex + 1);
  };

  const apps = [
    { id: 'terminal', title: 'Terminal Linux', icon: TerminalIcon, component: <TerminalApp /> },
    { id: 'notepad', title: 'Bloco de Notas', icon: FileText, component: <NotepadApp /> },
    { id: 'settings', title: 'Configurações', icon: Settings, component: <SettingsApp setBg={setBg} /> }
  ];

  return (
    <div className="desktop" style={{ background: bg.startsWith('http') ? `url(${bg}) center/cover no-repeat` : bg }} onClick={() => startOpen && setStartOpen(false)}>
      
      <div className="desktop-icons">
        {apps.map(app => (
          <div key={app.id} className="d-icon" onDoubleClick={() => openApp(app.id, app.title, app.icon, app.component)}>
            <app.icon size={42} color="white" />
            <span>{app.title}</span>
          </div>
        ))}
      </div>

      {windows.map(win => (
        <Window key={win.id} win={win} onClose={() => closeApp(win.id)} onFocus={() => focusWindow(win.id)}>
          {win.component}
        </Window>
      ))}

      {startOpen && (
        <div className="start-menu" onClick={(e) => e.stopPropagation()}>
          <input className="start-search" placeholder="Pesquisar apps..." />
          <div className="start-grid">
            {apps.map(app => (
              <div key={app.id} className="start-app" onClick={() => openApp(app.id, app.title, app.icon, app.component)}>
                <app.icon size={32} color="white" />
                <span>{app.title}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="taskbar">
        <div className="taskbar-app" onClick={(e) => { e.stopPropagation(); setStartOpen(!startOpen); }}>
          <Search size={24} /> {/* Simulando o botão Iniciar do Win11 */}
        </div>
        
        {apps.map(app => (
          <div key={app.id} className={`taskbar-app ${windows.find(w => w.appId === app.id) ? 'active' : ''}`} onClick={() => openApp(app.id, app.title, app.icon, app.component)}>
            <app.icon size={22} />
          </div>
        ))}

        <div className="taskbar-tray">
          <Wifi size={16} />
          <Volume2 size={16} />
          <Battery size={16} />
          <span>{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</span>
        </div>
      </div>
    </div>
  );
}
