import { useMemo, useState } from 'react';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import KaliToolCenter from '../KaliToolCenter/KaliToolCenter';
import QuickDnsChecks from './QuickDnsChecks';
import QuickEnvironmentChecks from './QuickEnvironmentChecks';
import QuickLocalChecks from './QuickLocalChecks';
import QuickWebChecks from './QuickWebChecks';
import './SecurityCenter.css';

type Group = 'começar' | 'rede' | 'web' | 'sistema' | 'evidência';
type Block = { id: string; appId?: string; icon: string; title: string; description: string; group: Group; badge?: string; localView?: 'advanced' };
const GROUP_LABEL: Record<Group, string> = { começar: 'Comece por aqui', rede: 'Rede & Wi‑Fi', web: 'Web & DNS', sistema: 'Ambiente', evidência: 'Evidência & apoio' };
const BLOCKS: Block[] = [
  { id: 'tool-center', icon: '🐉', title: 'Assessment de rede', description: 'Descobrir dispositivos, portas, serviços, histórico e findings em presets guiados.', group: 'começar', badge: 'recomendado', localView: 'advanced' },
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
  const [view, setView] = useState<'blocks' | 'advanced'>('blocks');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const visible = useMemo(() => filter === 'todos' ? BLOCKS : BLOCKS.filter(block => block.group === filter), [filter]);
  const openBlock = (block: Block) => {
    setNotice(''); setError('');
    try {
      if (block.localView === 'advanced') { setView('advanced'); return; }
      if (!block.appId) throw new Error('Este bloco não possui uma ferramenta vinculada.');
      launchWorkflowApp(block.appId); setNotice(`${block.title} aberto. Quando terminar, volte aqui e escolha o próximo bloco.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : `Não foi possível abrir ${block.title}.`); }
  };
  if (view === 'advanced') return <div className="sec-advanced"><div className="sec-advanced-bar"><button type="button" onClick={() => setView('blocks')}>← Voltar para os blocos</button><div><strong>Assessment de rede</strong><span>Modo técnico completo do Kali Tool Center.</span></div></div><KaliToolCenter /></div>;

  return <div className="sec-root">
    <header className="sec-hero"><div><small>CloudOS · Security Center</small><h1>Um botão. Uma função.</h1><p>Escolha o que você quer descobrir. Cada bloco faz uma tarefa pequena e específica; não precisa decorar comandos.</p></div><div className="sec-flow"><span>1. escolha</span><b>→</b><span>2. execute</span><b>→</b><span>3. leia</span><b>→</b><span>4. próximo bloco</span></div></header>
    {(notice || error) && <div className={`sec-banner ${error ? 'is-error' : ''}`} role={error ? 'alert' : 'status'}><span>{error || notice}</span><button type="button" onClick={() => { setNotice(''); setError(''); }}>×</button></div>}
    <section className="sec-start"><div><strong>Não sabe por onde começar?</strong><span>Primeiro entenda este PC, depois descubra a rede. Para internet: DNS primeiro, URL depois.</span></div><button type="button" onClick={() => openBlock(BLOCKS[0])}>🐉 Abrir assessment completo</button></section>

    <QuickEnvironmentChecks />
    <QuickLocalChecks />
    <QuickDnsChecks />
    <QuickWebChecks />

    <section className="sec-toolbox-title"><div><small>Ferramentas completas</small><strong>Abrir um app específico</strong><span>Quando quiser aprofundar, cada bloco abaixo abre uma superfície dedicada.</span></div></section>
    <nav className="sec-filters" aria-label="Categorias do Security Center"><button type="button" className={filter === 'todos' ? 'is-active' : ''} onClick={() => setFilter('todos')}>Todos · {BLOCKS.length}</button>{(Object.keys(GROUP_LABEL) as Group[]).map(group => <button type="button" key={group} className={filter === group ? 'is-active' : ''} onClick={() => setFilter(group)}>{GROUP_LABEL[group]}</button>)}</nav>
    <main className="sec-grid">{visible.map(block => <article className={`sec-card sec-card--${block.group}`} key={block.id}><header><span className="sec-icon">{block.icon}</span>{block.badge && <em>{block.badge}</em>}</header><small>{GROUP_LABEL[block.group]}</small><strong>{block.title}</strong><p>{block.description}</p><button type="button" onClick={() => openBlock(block)}>Abrir função →</button></article>)}</main>
    <footer className="sec-footer"><strong>Fluxo simples sugerido</strong><span>Este PC → rede local → IP → perfil/checks → DNS → Web → evidência. O modo avançado continua disponível quando necessário.</span><small>As coletas rápidas são somente leitura ou usam presets fechados; não executam exploração automática nem ataques de credencial.</small></footer>
  </div>;
}
