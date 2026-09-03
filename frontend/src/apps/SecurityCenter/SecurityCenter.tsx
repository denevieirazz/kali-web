import { useMemo, useState } from 'react';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import './SecurityCenter.css';

type Group = 'começar' | 'rede' | 'web' | 'sistema' | 'evidência';
type Block = {
  id: string;
  appId: string;
  icon: string;
  title: string;
  description: string;
  group: Group;
  badge?: string;
};

const GROUP_LABEL: Record<Group, string> = {
  começar: 'Comece por aqui',
  rede: 'Rede & Wi‑Fi',
  web: 'Web & DNS',
  sistema: 'Ambiente',
  evidência: 'Evidência & apoio',
};

const BLOCKS: Block[] = [
  { id: 'tool-center', appId: 'kali-tool-center', icon: '🐉', title: 'Assessment de rede', description: 'Descobrir dispositivos, portas, serviços, histórico e findings em presets guiados.', group: 'começar', badge: 'recomendado' },
  { id: 'network-inspector', appId: 'network-inspector', icon: '⌁', title: 'Diagnosticar um IP', description: 'Ping, latência, rota, PTR, ARP/MAC e gateway em uma tela.', group: 'rede' },
  { id: 'wifi-inspector', appId: 'wifi-inspector', icon: '📶', title: 'Saúde do Wi‑Fi', description: 'Sinal, canal, segurança, redes visíveis e recomendações.', group: 'rede' },
  { id: 'network-shield', appId: 'network-shield', icon: '🛡️', title: 'Proteção deste PC', description: 'Firewall, perfil de rede e portas TCP locais em escuta.', group: 'rede' },
  { id: 'dns-inspector', appId: 'dns-inspector', icon: '🧭', title: 'Consultar DNS', description: 'A, AAAA, CNAME, MX, NS e TXT de um nome por vez.', group: 'web' },
  { id: 'web-inspector', appId: 'web-inspector', icon: '🌍', title: 'Analisar um site', description: 'HTTP, TLS, headers, cookies, prioridade automática e explicação simples.', group: 'web', badge: 'assistido' },
  { id: 'browser', appId: 'browser', icon: '🌐', title: 'Abrir navegador', description: 'Confirme visualmente o alvo ou painel dentro do CloudOS.', group: 'web' },
  { id: 'env-doctor', appId: 'env-doctor', icon: '🩺', title: 'Verificar ambiente', description: 'Diagnostique runtime, dependências e integração antes de iniciar.', group: 'sistema' },
  { id: 'install-linux', appId: 'install-linux', icon: '🐧', title: 'Preparar Linux / Kali', description: 'Instale ou ajuste a distribuição usada pelas ferramentas Linux.', group: 'sistema' },
  { id: 'terminal', appId: 'cloudos-terminal', icon: '⚡', title: 'Terminal CloudOS', description: 'Abra o terminal quando uma checagem manual realmente for necessária.', group: 'sistema' },
  { id: 'system-monitor', appId: 'system-monitor', icon: '📈', title: 'Monitorar o PC', description: 'Veja saúde e consumo do sistema durante uma avaliação.', group: 'sistema' },
  { id: 'windows-installer', appId: 'windows-installer', icon: '📦', title: 'Instalar dependência', description: 'Abra a central de instaladores quando faltar uma ferramenta do Windows.', group: 'sistema' },
  { id: 'files', appId: 'cloudos-files', icon: '📁', title: 'Abrir evidências', description: 'Acesse JSONs, relatórios e arquivos exportados pelas ferramentas.', group: 'evidência' },
  { id: 'workspace', appId: 'workflow-workspace', icon: '🗂️', title: 'Workspace do projeto', description: 'Organize notas, arquivos e contexto do trabalho em uma área separada.', group: 'evidência' },
];

export default function SecurityCenter() {
  const [filter, setFilter] = useState<Group | 'todos'>('todos');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const visible = useMemo(() => filter === 'todos' ? BLOCKS : BLOCKS.filter(block => block.group === filter), [filter]);

  const openBlock = (block: Block) => {
    setNotice('');
    setError('');
    try {
      launchWorkflowApp(block.appId);
      setNotice(`${block.title} aberto. Quando terminar, volte aqui e escolha o próximo bloco.`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : `Não foi possível abrir ${block.title}.`);
    }
  };

  return <div className="sec-root">
    <header className="sec-hero">
      <div>
        <small>CloudOS · Security Center</small>
        <h1>Um botão. Uma função.</h1>
        <p>Escolha o que você quer descobrir. Cada bloco abre uma ferramenta pequena e específica; não precisa decorar comandos.</p>
      </div>
      <div className="sec-flow"><span>1. escolha</span><b>→</b><span>2. execute</span><b>→</b><span>3. leia</span><b>→</b><span>4. próximo bloco</span></div>
    </header>

    {(notice || error) && <div className={`sec-banner ${error ? 'is-error' : ''}`} role={error ? 'alert' : 'status'}>
      <span>{error || notice}</span><button type="button" onClick={() => { setNotice(''); setError(''); }}>×</button>
    </div>}

    <section className="sec-start">
      <div><strong>Não sabe por onde começar?</strong><span>Use “Assessment de rede”, depois vá abrindo os blocos conforme o CloudOS mostrar o que merece revisão.</span></div>
      <button type="button" onClick={() => openBlock(BLOCKS[0])}>🎯 Começar assessment</button>
    </section>

    <nav className="sec-filters" aria-label="Categorias do Security Center">
      <button type="button" className={filter === 'todos' ? 'is-active' : ''} onClick={() => setFilter('todos')}>Todos · {BLOCKS.length}</button>
      {(Object.keys(GROUP_LABEL) as Group[]).map(group => <button type="button" key={group} className={filter === group ? 'is-active' : ''} onClick={() => setFilter(group)}>{GROUP_LABEL[group]}</button>)}
    </nav>

    <main className="sec-grid">
      {visible.map(block => <article className={`sec-card sec-card--${block.group}`} key={block.id}>
        <header><span className="sec-icon">{block.icon}</span>{block.badge && <em>{block.badge}</em>}</header>
        <small>{GROUP_LABEL[block.group]}</small>
        <strong>{block.title}</strong>
        <p>{block.description}</p>
        <button type="button" onClick={() => openBlock(block)}>Abrir função →</button>
      </article>)}
    </main>

    <footer className="sec-footer">
      <strong>Fluxo simples sugerido</strong>
      <span>Assessment de rede → Diagnosticar IP → Saúde Wi‑Fi → Proteção deste PC → DNS → Web → Evidências.</span>
      <small>Os blocos de assessment continuam limitados às políticas de escopo e não executam exploit, brute force ou bypass automático.</small>
    </footer>
  </div>;
}
