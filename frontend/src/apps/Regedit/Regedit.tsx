import { useState, useMemo } from 'react';
import { useRegistry } from '../../stores/registry';
import './Regedit.css';

// Build a nested tree representation of paths
interface TreeNode {
  name: string;
  path: string;
  children: Record<string, TreeNode>;
}

function buildRegistryTree(paths: string[]): Record<string, TreeNode> {
  const root: Record<string, TreeNode> = {};
  
  for (const path of paths) {
    const parts = path.split('\\');
    let current = root;
    let currentPath = '';

    for (const part of parts) {
      currentPath += (currentPath ? '\\' : '') + part;
      if (!current[part]) {
        current[part] = {
          name: part,
          path: currentPath,
          children: {}
        };
      }
      current = current[part].children;
    }
  }
  
  return root;
}

const TreeItem = ({ node, isRoot = false, selectedPath, onSelect }: { node: TreeNode, isRoot?: boolean, selectedPath: string, onSelect: (path: string) => void }) => {
  const [expanded, setExpanded] = useState(isRoot || node.name.startsWith('HKEY_'));
  const hasChildren = Object.keys(node.children).length > 0;
  
  return (
    <div className="reg-tree-node">
      <div 
        className={`reg-tree-label ${selectedPath === node.path ? 'selected' : ''}`}
        onClick={() => {
          onSelect(node.path);
          if (hasChildren && selectedPath === node.path) {
            setExpanded(!expanded);
          }
        }}
        onDoubleClick={() => setExpanded(!expanded)}
      >
        <div className="reg-tree-arrow" style={{ visibility: hasChildren ? 'visible' : 'hidden' }} onClick={(e) => {
          e.stopPropagation();
          setExpanded(!expanded);
        }}>
          {expanded ? '▼' : '▶'}
        </div>
        <div className="reg-tree-icon">📁</div>
        <span className="reg-tree-text">{node.name}</span>
      </div>
      
      {expanded && hasChildren && (
        <div className="reg-tree-children">
          {Object.values(node.children).map(child => (
            <TreeItem key={child.path} node={child} selectedPath={selectedPath} onSelect={onSelect} />
          ))}
        </div>
      )}
    </div>
  );
};

export default function RegeditApp() {
  const { hives } = useRegistry();
  const [selectedPath, setSelectedPath] = useState<string>('HKEY_LOCAL_MACHINE\\SOFTWARE\\ObsidianOS\\CurrentVersion');
  const [addressBar, setAddressBar] = useState(selectedPath);
  
  const allPaths = Object.keys(hives);
  const tree = useMemo(() => buildRegistryTree(allPaths), [allPaths]);
  
  // Handlers
  const handleSelectPath = (path: string) => {
    setSelectedPath(path);
    setAddressBar(path);
  };
  
  // Get values for current path
  const currentKeyValues = hives[selectedPath] || {};
  const valueEntries = Object.entries(currentKeyValues);

  return (
    <div className="regedit-container">
      {/* Menu Bar */}
      <div className="regedit-menu">
        <div className="menu-item">Arquivo</div>
        <div className="menu-item">Editar</div>
        <div className="menu-item">Exibir</div>
        <div className="menu-item">Favoritos</div>
        <div className="menu-item">Ajuda</div>
      </div>
      
      {/* Address Bar */}
      <div className="regedit-address-bar">
        <span className="address-label">Computador\</span>
        <input 
          type="text" 
          value={addressBar} 
          onChange={(e) => setAddressBar(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              if (hives[addressBar]) setSelectedPath(addressBar);
            }
          }}
        />
      </div>
      
      {/* Split View */}
      <div className="regedit-content">
        {/* Left Pane: Tree */}
        <div className="regedit-sidebar">
          <div className="reg-tree-root">
            <div className="reg-tree-label">
              <div className="reg-tree-arrow">▼</div>
              <div className="reg-tree-icon">💻</div>
              <span className="reg-tree-text">Computador</span>
            </div>
            <div className="reg-tree-children">
              {Object.values(tree).map(node => (
                <TreeItem key={node.path} node={node} isRoot={true} selectedPath={selectedPath} onSelect={handleSelectPath} />
              ))}
            </div>
          </div>
        </div>
        
        {/* Divider */}
        <div className="regedit-divider" />
        
        {/* Right Pane: Values */}
        <div className="regedit-main">
          <table className="reg-table">
            <thead>
              <tr>
                <th style={{ width: '30%' }}>Nome</th>
                <th style={{ width: '25%' }}>Tipo</th>
                <th style={{ width: '45%' }}>Dados</th>
              </tr>
            </thead>
            <tbody>
              {/* Default Value */}
              <tr>
                <td><div className="reg-val-name"><div className="reg-icon-ab">ab</div>(Padrão)</div></td>
                <td>REG_SZ</td>
                <td>{valueEntries.length === 0 ? '(valor não definido)' : '(nenhum)'}</td>
              </tr>
              
              {/* Custom Values */}
              {valueEntries.map(([name, data]) => (
                <tr key={name}>
                  <td>
                    <div className="reg-val-name">
                      {data.type === 'REG_SZ' || data.type === 'REG_EXPAND_SZ' ? (
                        <div className="reg-icon-ab">ab</div>
                      ) : (
                        <div className="reg-icon-bin">01</div>
                      )}
                      {name}
                    </div>
                  </td>
                  <td>{data.type}</td>
                  <td>
                    {typeof data.value === 'object' ? JSON.stringify(data.value) : String(data.value)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      
      {/* Status bar */}
      <div className="regedit-statusbar">
        Computador\{selectedPath}
      </div>
    </div>
  );
}
