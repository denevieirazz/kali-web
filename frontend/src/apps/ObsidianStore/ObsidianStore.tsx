import { useState, useEffect } from 'react';
import { useFileSystem } from '../../stores/fileSystem';
import kernel from '../../core/kernel';
import { FiSearch, FiCheck, FiStar, FiShield } from 'react-icons/fi';
import './ObsidianStore.css';

interface StoreApp {
  id: string;
  name: string;
  developer: string;
  description: string;
  icon: string;
  category: string;
  price: string;
  rating: string;
  isOfficial?: boolean;
  code: string; 
}

const OFFICIAL_APPS: StoreApp[] = [
  {
    id: 'snake',
    name: 'Obsidian Snake',
    developer: 'Obsidian Studio',
    description: 'O clássico jogo da cobrinha remasterizado. Use as setas para jogar.',
    icon: '🐍',
    category: 'Jogos',
    price: 'Grátis',
    rating: '4.9',
    isOfficial: true,
    code: `
      print("Iniciando Obsidian Snake...");
      OS.User32.CreateElement('div', 'game-board', { 
        style: { width: '400px', height: '400px', background: '#111', margin: '20px auto', position: 'relative', border: '2px solid #333' } 
      });
      OS.User32.CreateElement('div', 'score', { 
        innerText: 'Score: 0',
        style: { textAlign: 'center', fontSize: '20px', padding: '10px' } 
      });

      let snake = [{x: 10, y: 10}];
      let food = {x: 15, y: 15};
      let dx = 1;
      let dy = 0;
      let score = 0;

      // Render cells
      const render = () => {
        const board = document.getElementById('game-board');
        if (!board) return;
        board.innerHTML = '';
        
        // Render snake
        snake.forEach(p => {
           const el = document.createElement('div');
           el.style.position = 'absolute';
           el.style.width = '18px';
           el.style.height = '18px';
           el.style.background = '#4ade80';
           el.style.left = (p.x * 20) + 'px';
           el.style.top = (p.y * 20) + 'px';
           el.style.borderRadius = '4px';
           board.appendChild(el);
        });

        // Render food
        const f = document.createElement('div');
        f.style.position = 'absolute';
        f.style.width = '18px';
        f.style.height = '18px';
        f.style.background = '#ef4444';
        f.style.left = (food.x * 20) + 'px';
        f.style.top = (food.y * 20) + 'px';
        f.style.borderRadius = '50%';
        board.appendChild(f);
      };

      OS.User32.AddEventListener('keydown', (e) => {
        if (e.key === 'ArrowUp' && dy === 0) { dx = 0; dy = -1; }
        if (e.key === 'ArrowDown' && dy === 0) { dx = 0; dy = 1; }
        if (e.key === 'ArrowLeft' && dx === 0) { dx = -1; dy = 0; }
        if (e.key === 'ArrowRight' && dx === 0) { dx = 1; dy = 0; }
      });

      const gameLoop = setInterval(() => {
        const board = document.getElementById('game-board');
        if (!board) { clearInterval(gameLoop); return; }

        const head = { x: snake[0].x + dx, y: snake[0].y + dy };
        
        // Wall collision
        if (head.x < 0 || head.x >= 20 || head.y < 0 || head.y >= 20) {
           clearInterval(gameLoop);
           alert('Game Over! Score: ' + score);
           return;
        }

        snake.unshift(head);

        if (head.x === food.x && head.y === food.y) {
           score += 10;
           OS.User32.SetText('score', 'Score: ' + score);
           food = { x: Math.floor(Math.random()*20), y: Math.floor(Math.random()*20) };
        } else {
           snake.pop();
        }
        render();
      }, 150);

      render();
    `
  },
  {
      id: 'task-pro',
      name: 'Task Pro',
      developer: 'Obsidian Studio',
      description: 'Gerenciador de tarefas avançado com suporte a categorias.',
      icon: '✅',
      category: 'Produtividade',
      price: 'Grátis',
      rating: '4.7',
      isOfficial: true,
      code: `
        print("Task Pro carregando...");
        OS.User32.CreateElement('div', 'container', { style: { padding: '20px' } });
        OS.User32.CreateElement('h2', 'title', { innerText: 'Minhas Tarefas' });
        OS.User32.CreateElement('input', 'task-input', { 
            style: { width: '70%', padding: '10px', background: '#222', border: '1px solid #444', color: '#fff' } 
        });
        OS.User32.CreateElement('button', 'add-btn', { innerText: 'Adicionar', style: { marginLeft: '10px', padding: '10px', background: '#4f46e5', color: '#fff', border: 'none', borderRadius: '4px' } });
        OS.User32.CreateElement('ul', 'list', { style: { marginTop: '20px', listStyle: 'none', padding: 0 } });

        OS.User32.OnMessage('add-btn', 'click', () => {
            const input = document.getElementById('task-input');
            const list = document.getElementById('list');
            if (input && input.value) {
                const li = document.createElement('li');
                li.innerText = '• ' + input.value;
                li.style.padding = '8px 0';
                li.style.borderBottom = '1px solid #333';
                list.appendChild(li);
                input.value = '';
            }
        });
      `
  }
];

export default function ObsidianStore() {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('Todos');
  const [installedApps, setInstalledApps] = useState<Set<string>>(new Set());
  
  const { nodes } = useFileSystem();

  useEffect(() => {
    const installed = new Set<string>();
    Object.values(nodes).forEach(node => {
        if (node.path.includes('ObsidianOS Apps')) {
            const appId = node.metadata?.appId;
            if (appId) installed.add(appId);
        }
    });
    setInstalledApps(installed);
  }, [nodes]);

  const handleInstall = (app: StoreApp) => {
    const installPath = 'C:\\Program Files\\ObsidianOS Apps';
    const fileName = `${app.id}.obx`;
    
    // O conteúdo é o código JS puro. O SdkAppRunner vai ler isso.
    const content = `/* ObsidianOS App: ${app.name} */\n${app.code}`;

    kernel.fsCreateFile(installPath, fileName, content, 'exe');
    
    const node = kernel.fsGetNode(`${installPath}\\${fileName}`);
    if (node) {
        if(!node.metadata) node.metadata = {};
        node.metadata.type = 'binary_executable';
        node.metadata.appId = app.id;
        kernel.emit('fs:snapshot', kernel.fsGetSnapshot());
    }

    kernel.log('INFO', 'Store', `Instalado: ${app.name}`);
    alert(`${app.name} instalado com sucesso em Program Files!`);
  };

  const categories = ['Todos', 'Jogos', 'Utilidades', 'Produtividade', 'Personalização'];

  const filteredApps = OFFICIAL_APPS.filter(app => {
    const matchesSearch = app.name.toLowerCase().includes(search.toLowerCase());
    const matchesCategory = category === 'Todos' || app.category === category;
    return matchesSearch && matchesCategory;
  });

  return (
    <div className="obsidian-store">
      <div className="store-header">
        <h1 className="store-title">Obsidian Store</h1>
        <p style={{ color: '#888' }}>Aplicativos oficiais e da comunidade.</p>
        
        <div className="store-search-container">
          <FiSearch className="store-search-icon" />
          <input
            type="text"
            className="store-search-input"
            placeholder="Pesquisar..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="store-categories">
        {categories.map(cat => (
          <div
            key={cat}
            className={`category-pill ${category === cat ? 'active' : ''}`}
            onClick={() => setCategory(cat)}
          >
            {cat}
          </div>
        ))}
      </div>

      <div className="store-content">
        <div className="app-grid">
          {filteredApps.map(app => (
            <div key={app.id} className="app-card">
              {app.isOfficial && (
                <div className="official-badge" title="App Verificado">
                  <FiShield size={12} /> Oficial
                </div>
              )}
              <div className="app-card-header">
                <div className="app-card-icon">{app.icon}</div>
                <div className="app-card-info">
                  <span className="app-name">{app.name}</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span className="app-developer">{app.developer}</span>
                    <span style={{ fontSize: '12px', color: '#fbbf24', display: 'flex', alignItems: 'center', gap: '2px' }}>
                      <FiStar size={10} fill="#fbbf24" /> {app.rating}
                    </span>
                  </div>
                </div>
              </div>

              <div className="app-description">
                {app.description}
              </div>

              <div className="app-card-footer">
                <span className="app-price free">{app.price}</span>
                
                {installedApps.has(app.id) ? (
                  <button className="app-install-btn installed">
                    <FiCheck /> Instalado
                  </button>
                ) : (
                  <button className="app-install-btn" onClick={() => handleInstall(app)}>
                    Instalar
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
