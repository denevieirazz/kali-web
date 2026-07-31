import React, { useState } from 'react';
import { Plus, X } from 'lucide-react';

const TerminalTabs = ({ tabs, activeTab, onSelectTab, onCloseTab, onNewTab, onRenameTab }) => {
  const [editingId, setEditingId] = useState(null);
  const [editTitle, setEditTitle] = useState('');

  const handleDoubleClick = (tab) => {
    setEditingId(tab.id);
    setEditTitle(tab.title);
  };

  const handleRenameSubmit = (id) => {
    if (editTitle.trim()) {
      onRenameTab(id, editTitle.trim());
    }
    setEditingId(null);
  };

  return (
    <div className="terminal-tabs" role="tablist">
      {tabs.map(tab => (
        <div
          key={tab.id}
          role="tab"
          aria-selected={tab.id === activeTab}
          onClick={() => onSelectTab(tab.id)}
          onDoubleClick={() => handleDoubleClick(tab)}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            padding: '0 12px',
            height: 32,
            marginRight: 2,
            borderRadius: '6px 6px 0 0',
            background: tab.id === activeTab ? 'var(--theme-bg)' : 'transparent',
            border: tab.id === activeTab ? '1px solid var(--theme-border)' : '1px solid transparent',
            borderBottom: 'none',
            color: tab.id === activeTab ? 'var(--theme-primary)' : 'var(--theme-muted)',
            fontWeight: 600,
            fontSize: 13,
            cursor: 'pointer',
            userSelect: 'none',
            transition: 'background 0.15s',
          }}
        >
          {editingId === tab.id ? (
            <input
              autoFocus
              value={editTitle}
              onChange={e => setEditTitle(e.target.value)}
              onBlur={() => handleRenameSubmit(tab.id)}
              onKeyDown={e => { if (e.key === 'Enter') handleRenameSubmit(tab.id); if (e.key === 'Escape') setEditingId(null); }}
              style={{
                width: 80,
                background: 'var(--theme-panel)',
                border: '1px solid var(--theme-border)',
                color: 'var(--theme-text)',
                padding: '2px 4px',
                borderRadius: 3,
                fontSize: 13,
              }}
              onClick={e => e.stopPropagation()}
            />
          ) : (
            <>
              <span style={{ marginRight: 6 }}>💻</span>
              {tab.title}
              {tabs.length > 1 && (
                <span
                  onClick={(e) => { e.stopPropagation(); onCloseTab(tab.id); }}
                  style={{ marginLeft: 8, opacity: 0.7, display: 'flex' }}
                >
                  <X size={14} />
                </span>
              )}
            </>
          )}
        </div>
      ))}
      <button
        onClick={onNewTab}
        style={{
          background: 'none',
          border: 'none',
          color: 'var(--theme-primary)',
          cursor: 'pointer',
          padding: '4px 8px',
          display: 'flex',
          alignItems: 'center',
          fontSize: 18,
        }}
        title="Nova Aba (Ctrl+Shift+T)"
      >
        <Plus size={18} />
      </button>
    </div>
  );
};

export default TerminalTabs;
