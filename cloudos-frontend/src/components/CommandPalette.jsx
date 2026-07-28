import { useState, useEffect } from 'react';
import { Search, Lock } from 'lucide-react';
import { AppRegistry } from '../registry';

export const CommandPalette = ({ isOpen, onClose, openApp, actions }) => {
  const [query, setQuery] = useState('');

  useEffect(() => {
    const handleKey = (e) => {
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'p') {
        e.preventDefault();
        isOpen ? onClose() : actions.togglePalette();
      }
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [isOpen, onClose, actions]);

  if (!isOpen) return null;

  const commands = [
    ...Object.values(AppRegistry).map(app => ({
      name: `Abrir ${app.title}`,
      icon: app.icon,
      action: () => { openApp(app.id); onClose(); }
    })),
    { name: 'Bloquear Sistema', icon: Lock, action: () => { actions.lock(); onClose(); } }
  ];

  const filtered = commands.filter(c => c.name.toLowerCase().includes(query.toLowerCase()));

  return (
    <div className="cmd-palette-overlay" onClick={onClose}>
      <div className="cmd-palette" onClick={(e) => e.stopPropagation()}>
        <div className="cmd-input-wrapper">
          <Search size={16} className="cmd-search-icon" />
          <input 
            autoFocus 
            className="cmd-input" 
            placeholder="Digite um comando ou busque um app..." 
            value={query} 
            onChange={(e) => setQuery(e.target.value)} 
          />
        </div>
        <div className="cmd-list">
          {filtered.map((cmd, i) => (
            <div key={i} className="cmd-item" onClick={cmd.action}>
              <cmd.icon size={16} />
              <span>{cmd.name}</span>
            </div>
          ))}
          {filtered.length === 0 && <div className="cmd-empty">Nenhum comando encontrado.</div>}
        </div>
      </div>
    </div>
  );
};
