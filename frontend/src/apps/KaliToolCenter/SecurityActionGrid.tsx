import { useMemo, useState } from 'react';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import './SecurityActionGrid.css';

type Action = {
  id: string;
  icon: string;
  title: string;
  description: string;
  category: 'começar' | 'rede' | 'web' | 'sistema' | 'evidência';
  actionLabel: string;
  appId?: string;
  anchorId?: string;
};

type Props = {
  activeScope: string | null;
  onNotice: (message: string) => void;
  onError: (message: string) => void;
};

const ACTIONS: Action[] = [
  {
    id: 'network-assessment', icon: '🎯', title: 'Descobrir dispositivos',
    description: 'Vai direto para a avaliação de rede local com presets guiados.',
    category: 'começar', actionLabel: 'Começar', anchorId: 'network-assessment-block',
  },
  {
    id: 'network-inspector', icon: '⌁', title: 'Diagnosticar um IP',
    description: 'Ping, latência, rota, PTR, ARP/MAC e gateway em uma tela simples.',
    category: 'rede', actionLabel: 'Abrir', appId: 'network-inspector',
  },
  {
    id: 'wifi-inspector', icon: '📶', title: 'Ver saúde do Wi‑Fi',
    description: 'Sinal, canal, segurança, redes visíveis e recomendações de conexão.',
    category: 'rede', actionLabel: 'Abrir', appId: 'wifi-inspector',
  },
  {
    id: 'network-shield', icon: '🛡️', title: 'Ver proteção deste PC',
    description: 'Firewall, perfil de rede e portas TCP locais em escuta.',
    category: 'rede', actionLabel: 'Revisar', appId: 'network-shield',
  },
  {
    id: 'dns-inspector', icon: '🧭', title: 'Consultar DNS',
    description: 'A, AAAA, CNAME, MX, NS e TXT de um nome por vez.',
    category: 'rede', actionLabel: 'Consultar', appId: 'dns-inspector',
  },
  {
    id: 'web-inspector', icon: '🌍', title: 'Analisar um site',
    description: 'HTTP, TLS, headers, cookies, prioridade e explicação para técnico leigo.',
    category: 'web', actionLabel: 'Analisar', appId: 'web-inspector',
  },
  {
    id: 'browser', icon: '🌐', title: 'Abrir navegador',
    description: 'Confirme visualmente o site ou painel sem sair do CloudOS.',
    category: 'web', actionLabel: 'Abrir', appId: 'browser',
  },
  {
    id: 'terminal', icon: '⚡', title: 'Abrir Terminal CloudOS',
    description: 'Para quando o técnico precisar conferir algo manualmente no ambiente Linux/Windows.',
    category: 'sistema', actionLabel: 'Abrir', appId: 'cloudos-terminal',
  },
  {
    id: 'env-doctor', icon: '🩺', title: 'Verificar ambiente',
    description: 'Diagnostica dependências, runtime e integração antes de culpar a ferramenta.',
    category: 'sistema', actionLabel: 'Diagnosticar', appId: 'env-doctor',
  },
  {
    id: 'install-linux', icon: '🐧', title: 'Preparar Linux / Kali',
    description: 'Abre a Central Windows + Linux para corrigir ou preparar a distribuição.',
    category: 'sistema', actionLabel: 'Preparar', appId: 'install-linux',
  },
  {
    id: 'files', icon: '📁', title: 'Abrir evidências',
    description: 'Acesse os arquivos e relatórios exportados pelo CloudOS.',
    category: 'evidência', actionLabel: 'Abrir', appId: 'cloudos-files',
  },
  {
    id: 'workspace', icon: '🗂️', title: 'Abrir workspace',
    description: 'Organize alvo, notas e material de trabalho em uma área separada.',
    category: 'evidência', actionLabel: 'Abrir', appId: 'workflow-workspace',
  },
  {
    id: 'tool-catalog', icon: '🧰', title: 'Ver todas as ferramentas',
    description: 'Pula para o catálogo completo de ferramentas reconhecidas no Kali.',
    category: 'evidência', actionLabel: 'Ver catálogo', anchorId: 'kali-tool-catalog',
  },
];

const CATEGORY_LABEL: Record<Action['category'], string> = {
  começar: 'Comece por aqui',
  rede: 'Rede & Wi‑Fi',
  web: 'Web',
  sistema: 'Sistema',
  evidência: 'Evidência & apoio',
};

export default function SecurityActionGrid({ activeScope, onNotice, onError }: Props) {
  const [filter, setFilter] = useState<Action['category'] | 'todos'>('todos');
  const actions = useMemo(() => filter === 'todos' ? ACTIONS : ACTIONS.filter(action => action.category === filter), [filter]);

  const runAction = (action: Action) => {
    onError('');
    try {
      if (action.anchorId) {
        const element = document.getElementById(action.anchorId);
        if (!element) throw new Error('A área solicitada ainda não está disponível nesta tela.');
        element.scrollIntoView({ behavior: 'smooth', block: 'start' });
        onNotice(`${action.title}: área aberta logo abaixo.`);
        return;
      }
      if (action.appId) {
        launchWorkflowApp(action.appId);
        onNotice(`${action.title}: ferramenta aberta no CloudOS.`);
      }
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : `Não foi possível abrir ${action.title}.`);
    }
  };

  return <section className="sag-root" aria-label="Ações rápidas de segurança">
    <header className="sag-header">
      <div>
        <small>Modo por blocos</small>
        <h2>Escolha uma tarefa. Um botão faz uma coisa.</h2>
        <p>Feito para técnico de TI que quer seguir um fluxo visual sem decorar comandos.</p>
      </div>
      <div className="sag-scope">
        <span>Escopo atual</span>
        <strong>{activeScope || 'não selecionado'}</strong>
      </div>
    </header>

    <nav className="sag-filters" aria-label="Categorias de ações rápidas">
      <button type="button" className={filter === 'todos' ? 'is-active' : ''} onClick={() => setFilter('todos')}>Todos</button>
      {(Object.keys(CATEGORY_LABEL) as Action['category'][]).map(category => (
        <button type="button" key={category} className={filter === category ? 'is-active' : ''} onClick={() => setFilter(category)}>{CATEGORY_LABEL[category]}</button>
      ))}
    </nav>

    <div className="sag-grid">
      {actions.map(action => <article className={`sag-card sag-card--${action.category}`} key={action.id}>
        <div className="sag-icon" aria-hidden="true">{action.icon}</div>
        <div className="sag-card-body">
          <small>{CATEGORY_LABEL[action.category]}</small>
          <strong>{action.title}</strong>
          <p>{action.description}</p>
        </div>
        <button type="button" onClick={() => runAction(action)}>{action.actionLabel} →</button>
      </article>)}
    </div>

    <footer className="sag-footer">
      <strong>Fluxo recomendado para iniciante:</strong>
      <span>Descobrir dispositivos → Diagnosticar IP → Wi‑Fi → Proteção deste PC → DNS/Web → Salvar evidência.</span>
    </footer>
  </section>;
}
