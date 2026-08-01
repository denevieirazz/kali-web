import React, { useState, useEffect, useRef } from 'react';
import { appsRegistry } from '../registry';

const SpotlightSearch = ({ isOpen, onClose, onLaunchApp }) => {
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef(null);

  const filteredApps = (appsRegistry || []).filter(app =>
    (app.title || '').toLowerCase().includes(query.toLowerCase())
  );

  useEffect(() => {
    if (isOpen) {
      setQuery('');
      setActiveIndex(0);
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  }, [isOpen]);

  useEffect(() => {
    setActiveIndex(0);
  }, [query]);

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') {
      onClose();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredApps.length > 0) {
        setActiveIndex((prev) => (prev + 1) % filteredApps.length);
      }
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (filteredApps.length > 0) {
        setActiveIndex((prev) => (prev - 1 + filteredApps.length) % filteredApps.length);
      }
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (filteredApps[activeIndex]) {
        onLaunchApp(filteredApps[activeIndex].id);
        onClose();
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div style={styles.overlay} onClick={onClose}>
      <div style={styles.modal} onClick={(e) => e.stopPropagation()}>
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Buscar aplicações táticas... (↑ ↓ para navegar, Enter para abrir)"
          style={styles.input}
        />
        <div style={styles.resultsContainer}>
          {filteredApps.length === 0 ? (
            <div style={styles.noResults}>Nenhum módulo encontrado.</div>
          ) : (
            filteredApps.map((app, index) => {
              const IconComponent = typeof app.icon === 'function' || typeof app.icon === 'object' ? app.icon : null;
              return (
                <div
                  key={app.id}
                  onClick={() => {
                    onLaunchApp(app.id);
                    onClose();
                  }}
                  style={{
                    ...styles.resultItem,
                    backgroundColor: index === activeIndex ? 'rgba(88, 166, 255, 0.2)' : 'transparent',
                    borderLeft: index === activeIndex ? '3px solid #58a6ff' : '3px solid transparent'
                  }}
                >
                  <span style={styles.appIcon}>
                    {IconComponent ? <IconComponent size={20} color="#58a6ff" /> : app.icon || '📱'}
                  </span>
                  <span style={styles.appTitle}>{app.title}</span>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
};

const styles = {
  overlay: {
    position: 'fixed',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    backdropFilter: 'blur(8px)',
    zIndex: 10000,
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'flex-start',
    paddingTop: '15vh'
  },
  modal: {
    width: '600px',
    maxWidth: '90%',
    backgroundColor: '#161b22',
    border: '1px solid #30363d',
    borderRadius: '12px',
    boxShadow: '0 10px 40px rgba(0, 0, 0, 0.8)',
    overflow: 'hidden'
  },
  input: {
    width: '100%',
    padding: '20px',
    backgroundColor: 'transparent',
    border: 'none',
    borderBottom: '1px solid #30363d',
    outline: 'none',
    color: '#58a6ff',
    fontSize: '18px',
    fontFamily: 'monospace',
    boxSizing: 'border-box'
  },
  resultsContainer: {
    maxHeight: '300px',
    overflowY: 'auto'
  },
  resultItem: {
    display: 'flex',
    alignItems: 'center',
    padding: '12px 20px',
    cursor: 'pointer',
    transition: 'background 0.1s'
  },
  appIcon: {
    fontSize: '24px',
    marginRight: '15px',
    display: 'flex',
    alignItems: 'center'
  },
  appTitle: {
    color: '#c9d1d9',
    fontFamily: 'monospace'
  },
  noResults: {
    padding: '20px',
    color: '#8b949e',
    textAlign: 'center',
    fontFamily: 'monospace'
  }
};

export default SpotlightSearch;
