import { useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import './QuickDnsChecks.css';

type DnsType = 'A' | 'AAAA' | 'CNAME' | 'MX' | 'NS' | 'TXT';
type DnsRecordBucket = { status: string; records: unknown[]; errorCode?: string };
type DnsInspection = {
  name: string;
  durationMs: number;
  records: Record<DnsType, DnsRecordBucket>;
  summary: { presentTypes: string[]; recommendations: string[] };
  resolvers: string[];
  completedAt: string;
};

type Block = { type: DnsType; icon: string; title: string; description: string };
const BLOCKS: Block[] = [
  { type: 'A', icon: '4️⃣', title: 'IPv4 do domínio', description: 'Mostra os endereços IPv4 publicados para o nome exato.' },
  { type: 'AAAA', icon: '6️⃣', title: 'IPv6 do domínio', description: 'Mostra os endereços IPv6 publicados para o nome exato.' },
  { type: 'CNAME', icon: '🔗', title: 'Alias / CNAME', description: 'Mostra se o nome aponta para outro nome canônico.' },
  { type: 'MX', icon: '✉️', title: 'Servidores de e-mail', description: 'Mostra os registros MX e suas prioridades.' },
  { type: 'NS', icon: '🧭', title: 'Nameservers', description: 'Mostra os servidores autoritativos publicados.' },
  { type: 'TXT', icon: '📄', title: 'Registros TXT', description: 'Mostra políticas e verificações TXT públicas do nome exato.' },
];

function cleanName(value: string) {
  return value.trim().replace(/^https?:\/\//i, '').split('/')[0].replace(/:\d+$/, '').replace(/\.$/, '');
}

export default function QuickDnsChecks() {
  const [name, setName] = useState('');
  const [selected, setSelected] = useState<DnsType>('A');
  const [result, setResult] = useState<DnsInspection | null>(null);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');

  const run = async (type: DnsType) => {
    const target = cleanName(name);
    if (!target || !target.includes('.')) { setError('Informe um hostname ou domínio, por exemplo app.empresa.com.'); return; }
    setSelected(type); setError(''); setNotice('');
    if (result?.name === target) { setNotice(`Mostrando ${type} da coleta atual.`); return; }
    setLoading(true);
    try {
      const data = await apiClient<DnsInspection>('/api/security/tools/network/dns/lookup', {
        method: 'POST', timeoutMs: 15_000, body: JSON.stringify({ name: target }),
      });
      setResult(data); setName(data.name);
      setNotice(`DNS consultado em ${data.durationMs} ms. Selecione qualquer bloco para trocar a visualização.`);
    } catch (cause) {
      setResult(null);
      setError(cause instanceof Error ? cause.message : 'A consulta DNS não foi concluída.');
    } finally { setLoading(false); }
  };

  const selectedBucket = result?.records[selected] || null;
  const printableRecords = useMemo(() => (selectedBucket?.records || []).map(record => typeof record === 'string' ? record : JSON.stringify(record)), [selectedBucket]);

  const copyForAi = async () => {
    if (!result) return;
    const payload = {
      schemaVersion: 1,
      kind: 'cloudos-quick-dns-check',
      purpose: 'authorized-defensive-dns-inventory',
      name: result.name,
      records: result.records,
      summary: result.summary,
      resolvers: result.resolvers,
      constraints: { exactNameOnly: true, noEnumeration: true, noWordlists: true, arbitraryArguments: false },
    };
    try { await navigator.clipboard.writeText(JSON.stringify(payload, null, 2)); setNotice('Inventário DNS copiado para a IA.'); }
    catch { setError('Não foi possível copiar para a área de transferência.'); }
  };

  return <section className="qdc-root" aria-label="Checks DNS de um clique">
    <header className="qdc-head"><div><small>DNS · um botão por tipo</small><h2>Escolha qual registro quer entender</h2><p>Uma consulta do nome exato coleta A, AAAA, CNAME, MX, NS e TXT; depois os botões apenas trocam a visão.</p></div><button type="button" onClick={() => launchWorkflowApp('dns-inspector')}>Abrir DNS Inspector completo</button></header>
    {(error || notice) && <div className={`qdc-banner ${error ? 'is-error' : ''}`}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}
    <label className="qdc-name"><span>Hostname ou domínio exato</span><input value={name} onChange={event => { setName(event.target.value); if (result && cleanName(event.target.value) !== result.name) setResult(null); }} placeholder="app.empresa.com" /></label>
    <div className="qdc-grid">{BLOCKS.map(block => <article key={block.type} className={result && selected === block.type ? 'is-active' : ''}><div>{block.icon}</div><strong>{block.title}</strong><p>{block.description}</p><button type="button" disabled={loading} onClick={() => void run(block.type)}>{loading ? 'Consultando…' : `Ver ${block.type} →`}</button></article>)}</div>
    {result && <section className="qdc-result"><header><div><small>{result.name}</small><strong>{selected} · {printableRecords.length} registro(s)</strong><span>DNS do host: {result.resolvers.join(', ') || 'não informado'}</span></div><button type="button" onClick={() => void copyForAi()}>Copiar tudo para IA</button></header><div className="qdc-records">{printableRecords.length ? printableRecords.map((record, index) => <code key={`${selected}-${index}`}>{record}</code>) : <p>Nenhum registro {selected} foi retornado nesta coleta.</p>}</div>{result.summary.recommendations.length > 0 && <div className="qdc-recommend"><strong>Como interpretar</strong>{result.summary.recommendations.map((item, index) => <p key={`${index}-${item}`}>{item}</p>)}</div>}<small className="qdc-note">Consulta exata somente. Sem enumeração de subdomínios, wordlist ou tentativa de adivinhar nomes.</small></section>}
  </section>;
}
