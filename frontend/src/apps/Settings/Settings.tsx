import { useEffect, useMemo, useRef, useState } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useRegistry } from '../../stores/registry';
import kernel from '../../core/kernel';
import { apiClient, getApiBase } from '../../services/apiClient';
import { useUserStore } from '../../stores/userStore';
import { getUserStorageKey } from '../../services/userScope.js';
import './Settings.css';

type Section = 'system'|'display'|'personalization'|'storage'|'network'|'apps'|'accounts'|'linux'|'privacy'|'update'|'diagnostics'|'about';
type Health = { api: 'checking'|'online'|'offline'; latency?: number; runtime?: Record<string, unknown> };
type ProductStatus = {schemaVersion:number;product:string;version:string;sha:string|null;channel:string;signing:string;stableUpdatesEnabled:boolean;mode:'Full'|'WebOnly';nativeHost:boolean;wslCorePayload:boolean;protocolVersion:number;dataDirectory:string;logDirectory:string;updateConfigured:boolean};
type UpdateStatus = {configured:boolean;channel:string;state:string;currentVersion?:string;latestVersion?:string;sha256?:string;size?:number};
type DistroInfo = { id: string; name: string; icon: string; category: string; description: string; state?: string; version?: string; isInstalled?: boolean; isWslDefault?: boolean; isActiveInCloudOS?: boolean; sizeEstimateMB?: number };

const sections: { id: Section; label: string; icon: string }[] = [
  {id:'system',label:'Geral',icon:'💻'},{id:'display',label:'Aparência',icon:'🖥️'},
  {id:'personalization',label:'Personalização',icon:'🎨'},{id:'storage',label:'Armazenamento',icon:'💾'},
  {id:'network',label:'Rede e Internet',icon:'🌐'},{id:'apps',label:'Aplicativos',icon:'📦'},
  {id:'accounts',label:'Contas',icon:'👤'},{id:'linux',label:'Sistemas / Multi-Distro',icon:'🐧'},
  {id:'privacy',label:'Privacidade',icon:'🔒'},{id:'update',label:'Atualizações',icon:'🔄'},
  {id:'diagnostics',label:'Diagnóstico',icon:'🩺'},{id:'about',label:'Sobre',icon:'ℹ️'}
];
const accents=['#6366f1','#8b5cf6','#a855f7','#ec4899','#ef4444','#f97316','#22c55e','#06b6d4','#3b82f6'];
const pref=(key:string,fallback:boolean)=>{const k=getUserStorageKey(key);return localStorage.getItem(k)===null?fallback:localStorage.getItem(k)==='true'};

export default function SettingsApp({}: { windowId: string }) {
  const [active,setActive]=useState<Section>('system');
  const { theme,setTheme,currentUser,brightness,setBrightness }=useSystem();
  const [health,setHealth]=useState<Health>({api:'checking'});
  const [product,setProduct]=useState<ProductStatus|null>(null);
  const [productNotice,setProductNotice]=useState<string|null>(null);
  const [distroData,setDistroData]=useState<{active:string;installed:DistroInfo[];online:DistroInfo[]}|null>(null);
  const [distroLoading,setDistroLoading]=useState(false);
  const [distroNotice,setDistroNotice]=useState<string|null>(null);
  const [update,setUpdate]=useState<UpdateStatus|null>(null);
  const [updateStatus,setUpdateStatus]=useState('Pronto para verificar');
  const [storageEstimate,setStorageEstimate]=useState<{usage:number;quota:number}|null>(null);
  const [now,setNow]=useState(Date.now());
  const [privacy,setPrivacy]=useState({metrics:pref('cloudos.privacy.metrics',true),terminal:pref('cloudos.privacy.terminal',true),files:pref('cloudos.privacy.files',true)});
  const [accountNotice,setAccountNotice]=useState<string|null>(null);
  const [rotatedRecoveryCode,setRotatedRecoveryCode]=useState<string|null>(null);
  const rotatedRecoveryCodeRef=useRef<string|null>(null);
  const [recoveryCodeSaved,setRecoveryCodeSaved]=useState(false);
  const [rotatingRecoveryCode,setRotatingRecoveryCode]=useState(false);
  const rotateRecoveryCode=useUserStore(s=>s.rotateRecoveryCode);
  const confirmRecoveryCodeSaved=useUserStore(s=>s.confirmRecoveryCodeSaved);
  const taskbarPosition=String(useRegistry(s=>s.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Position?.value||'bottom'));
  const taskbarAlignment=String(useRegistry(s=>s.hives['HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar']?.Alignment?.value||'center'));
  const processes=kernel.getProcesses();
  const windows=kernel.getWindows().filter(w=>!w.isSystem);
  const resources=kernel.resources;
  const apps=useMemo(()=>Array.from(new Map(windows.map(w=>[w.appId,w])).values()),[now]);

  useEffect(()=>{const id=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(id)},[]);
  useEffect(()=>{if(active!=='accounts'){rotatedRecoveryCodeRef.current=null;setRotatedRecoveryCode(null);setRecoveryCodeSaved(false);setAccountNotice(null)}},[active]);
  useEffect(()=>()=>{rotatedRecoveryCodeRef.current=null},[]);
  useEffect(()=>{if(['system','storage','update','diagnostics','about'].includes(active))void loadProduct();if(active==='linux')void loadDistros();if(active==='network'||active==='diagnostics')void checkHealth();if(active==='storage')void loadStorageEstimate()},[active]);

  async function loadDistros(){setDistroLoading(true);try{const data=await apiClient<{active:string;installed:DistroInfo[];online:DistroInfo[]}>('/api/linux-runtime/distros');setDistroData(data);setDistroNotice(null)}catch{setDistroNotice('Catálogo de sistemas WSL indisponível nesta sessão.')}finally{setDistroLoading(false)}}
  async function switchActiveDistro(distroId:string){try{await apiClient('/api/linux-runtime/distros/active',{method:'POST',body:JSON.stringify({distro:distroId})});setDistroNotice(`Sistema ativo definido como: ${distroId}.`);await loadDistros()}catch(err:any){setDistroNotice(err.message||'Falha ao alterar sistema ativo.')}}
  async function triggerInstallDistro(distroId:string){try{await apiClient('/api/linux-runtime/distros/install',{method:'POST',body:JSON.stringify({distro:distroId})});setDistroNotice(`Instalação de ${distroId} iniciada em segundo plano via WSL.`);await loadDistros()}catch(err:any){setDistroNotice(err.message||'Falha ao iniciar instalação da distribuição.')}}
  async function triggerUnregisterDistro(distroId:string){
    if(!window.confirm(`Tem certeza que deseja excluir a distribuição ${distroId}?`))return;
    try{await apiClient('/api/linux-runtime/distros/unregister',{method:'POST',body:JSON.stringify({distro:distroId})});setDistroNotice(`Distribuição ${distroId} removida com sucesso.`);await loadDistros()}catch(err:any){setDistroNotice(err.message||'Falha ao remover distribuição.')}
  }

  async function rotateAccountRecoveryCode(){
    if(rotatingRecoveryCode)return;
    if(!window.confirm('Gerar um novo código invalida imediatamente o código anterior. Continuar?'))return;
    setRotatingRecoveryCode(true);setAccountNotice(null);rotatedRecoveryCodeRef.current=null;setRotatedRecoveryCode(null);setRecoveryCodeSaved(false);
    const result=await rotateRecoveryCode();setRotatingRecoveryCode(false);
    if(result.success&&result.recoveryCode){rotatedRecoveryCodeRef.current=result.recoveryCode;setRotatedRecoveryCode(result.recoveryCode)}
    else setAccountNotice(result.message||'Não foi possível gerar um novo código.');
  }
  async function copyAccountRecoveryCode(){const code=rotatedRecoveryCodeRef.current;if(!code)return;try{await navigator.clipboard.writeText(code)}catch{setAccountNotice('Selecione e copie o código manualmente.')}}
  async function checkHealth(){
    setHealth({api:'checking'}); const start=performance.now();
    try { await apiClient('/api/health', { skipAuth:true });
      let runtime:Record<string,unknown>|undefined; try{runtime=await apiClient<Record<string,unknown>>('/api/runtime',{skipAuth:true})}catch{}
      setHealth({api:'online',latency:Math.round(performance.now()-start),runtime});
    } catch { setHealth({api:'offline'}); }
  }
  async function loadProduct(){try{setProduct(await apiClient<ProductStatus>('/api/product/status'));setProductNotice(null)}catch{setProductNotice('Diagnóstico de produto indisponível nesta sessão.')}}
  async function loadStorageEstimate(){try{const estimate=await navigator.storage?.estimate?.();if(estimate)setStorageEstimate({usage:estimate.usage||0,quota:estimate.quota||0})}catch{setStorageEstimate(null)}}
  async function checkProductUpdate(){setUpdateStatus('Verificando feed...');setUpdate(null);try{const result=await apiClient<UpdateStatus>('/api/product/update');setUpdate(result);setUpdateStatus(result.state==='available'?`Versão ${result.latestVersion} disponível`:result.state==='current'?'Você já está na versão mais recente':result.state==='disabled'?'Canal stable desativado neste lote':'Nenhuma fonte de atualização configurada')}catch{setUpdateStatus('Não foi possível verificar a atualização. Consulte o Diagnóstico.')}}
  async function productAction(path:string,success:string){setProductNotice(null);try{const result=await apiClient<{ok:boolean;fileName?:string}>(path,{method:'POST'});setProductNotice(result.fileName?`${success}: ${result.fileName}`:success)}catch{setProductNotice('A ação não pôde ser concluída nesta sessão.')}}
  function setReg(path:string,value:string){useRegistry.getState().setValue(path,'REG_SZ',value)}
  function setPrivacyValue(key:keyof typeof privacy,value:boolean){const next={...privacy,[key]:value};setPrivacy(next);localStorage.setItem(getUserStorageKey(`cloudos.privacy.${key}`),String(value))}
  function chooseWallpaper(file?:File){if(!file)return;if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>8*1024*1024){alert('Use PNG, JPG ou WebP de até 8 MB.');return}const r=new FileReader();r.onload=()=>{localStorage.setItem(getUserStorageKey('cloudos.customWallpaper.v1'),String(r.result));location.reload()};r.readAsDataURL(file)}
  const Toggle=({on,onChange,label,desc}:{on:boolean;onChange:()=>void;label:string;desc:string})=><div className="settings-toggle-row"><div><span className="settings-label">{label}</span><span className="settings-desc">{desc}</span></div><button className={`settings-toggle ${on?'on':''}`} onClick={onChange} aria-pressed={on}><span className="toggle-thumb"/></button></div>;
  const Row=({label,value}:{label:string;value:React.ReactNode})=><div className="settings-data-row"><span>{label}</span><strong>{value}</strong></div>;
  const mb=(bytes:number)=>`${(bytes/1024/1024).toFixed(1)} MB`;

  function content(){switch(active){
    case 'system': return <><h2>Geral</h2><div className="settings-hero"><div className="settings-hero-icon">◈</div><div><h3>CloudOS Unified</h3><p>Foundation local com componentes supervisionados.</p></div><span className="status-pill ok">Em execução</span></div><div className="settings-grid"><div className="settings-card"><h3>Desempenho</h3><Row label="CPU" value={`${resources.cpuUsage.toFixed(1)}%`}/><Row label="Memória" value={`${Math.round(resources.usedMemory)} / ${resources.totalMemory} MB`}/><Row label="Processos" value={processes.length}/><Row label="Janelas abertas" value={windows.length}/></div><div className="settings-card"><h3>Inicialização</h3><Row label="Modo atual" value={product?.mode||'Consultando…'}/><Row label="Host disponível" value={product?.nativeHost?'Sim':'Não'}/><Row label="Tempo ativo" value={`${Math.floor(resources.uptime/60)} min`}/><Row label="Usuário" value={currentUser?.displayName||currentUser?.username||'Local'}/><button className="settings-action" onClick={()=>window.location.reload()}>Reiniciar interface</button></div></div></>;
    case 'display': return <><h2>Aparência</h2><div className="settings-card"><h3>Brilho</h3><div className="settings-slider-row"><input className="settings-slider" type="range" min="20" max="100" value={brightness} onChange={e=>setBrightness(Number(e.target.value))}/><b>{brightness}%</b></div></div><div className="settings-card"><h3>Escala visual</h3><select className="settings-select" value={localStorage.getItem(getUserStorageKey('cloudos.display.scale'))||'1'} onChange={e=>{localStorage.setItem(getUserStorageKey('cloudos.display.scale'),e.target.value);document.documentElement.style.fontSize=`${Number(e.target.value)*100}%`}}><option value="0.9">90%</option><option value="1">100%</option><option value="1.1">110%</option><option value="1.25">125%</option></select></div><div className="settings-card"><h3>Informações</h3><Row label="Área disponível" value={`${window.innerWidth} × ${window.innerHeight}`}/><Row label="Pixel ratio" value={window.devicePixelRatio}/></div></>;
    case 'personalization': return <><h2>Personalização</h2><div className="settings-card"><h3>Tema</h3><div className="settings-theme-selector"><button className={`theme-option ${theme.mode==='dark'?'active':''}`} onClick={()=>setTheme({mode:'dark'})}><span className="theme-preview dark-preview"/>Escuro</button><button className={`theme-option ${theme.mode==='light'?'active':''}`} onClick={()=>setTheme({mode:'light'})}><span className="theme-preview light-preview"/>Claro</button></div></div><div className="settings-card"><h3>Cor de destaque</h3><div className="settings-accent-grid">{accents.map(c=><button key={c} aria-label={c} className={`accent-option ${theme.accentColor===c?'active':''}`} style={{background:c}} onClick={()=>{setTheme({accentColor:c});document.documentElement.style.setProperty('--accent',c)}}/>)}</div></div><div className="settings-card"><h3>Plano de fundo pessoal</h3><label className="settings-action file-button">Escolher imagem<input hidden type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>chooseWallpaper(e.target.files?.[0])}/></label><button className="settings-secondary" onClick={()=>{localStorage.removeItem(getUserStorageKey('cloudos.customWallpaper.v1'));location.reload()}}>Restaurar padrão</button></div><div className="settings-card"><Toggle label="Transparência" desc="Acrílico, blur e superfícies translúcidas" on={theme.transparency} onChange={()=>setTheme({transparency:!theme.transparency})}/></div><div className="settings-card"><h3>Barra de tarefas</h3><Row label="Posição" value={<select className="settings-select" value={taskbarPosition} onChange={e=>setReg('HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar\\Position',e.target.value)}><option value="bottom">Abaixo</option><option value="top">Acima</option><option value="left">Esquerda</option><option value="right">Direita</option></select>}/><Row label="Alinhamento" value={<select className="settings-select" value={taskbarAlignment} onChange={e=>setReg('HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar\\Alignment',e.target.value)}><option value="center">Centralizado</option><option value="left">À esquerda</option></select>}/></div></>;
    case 'storage': return <><h2>Armazenamento</h2><div className="settings-card"><h3>Dados do CloudOS</h3><Row label="Diretório de dados" value={product?.dataDirectory||'Consultando…'}/><Row label="Uso do armazenamento web" value={storageEstimate?mb(storageEstimate.usage):'Indisponível'}/><Row label="Limite estimado" value={storageEstimate?mb(storageEstimate.quota):'Indisponível'}/><p className="settings-desc">Arquivos Windows concedidos e Linux Home não são copiados ou removidos por esta tela.</p><button className="settings-action" onClick={()=>productAction('/api/product/folder/data/open','Pasta de dados aberta')}>Abrir pasta de dados</button></div></>;
    case 'network': return <><h2>Rede e Internet</h2><div className="settings-hero"><div className="settings-hero-icon">◎</div><div><h3>Backend local</h3><p>Diagnóstico real da API do CloudOS.</p></div><span className={`status-pill ${health.api==='online'?'ok':health.api==='offline'?'bad':''}`}>{health.api==='checking'?'Verificando':health.api==='online'?'Conectado':'Indisponível'}</span></div><div className="settings-card"><Row label="Origem da API" value={getApiBase()}/><Row label="Latência local" value={health.latency!==undefined?`${health.latency} ms`:'-'}/><Row label="Online no navegador" value={navigator.onLine?'Sim':'Não'}/><button className="settings-action" onClick={checkHealth}>Verificar novamente</button></div></>;
    case 'apps': return <><h2>Aplicativos</h2><div className="settings-card"><Row label="Aplicativos com janela" value={apps.length}/><Row label="Janelas abertas" value={windows.length}/></div><div className="settings-app-list">{apps.length?apps.map(app=><div className="settings-app-row" key={app.appId}><span className="app-icon">{app.icon||'▣'}</span><div><strong>{app.title}</strong><small>{windows.filter(w=>w.appId===app.appId).length} janela(s)</small></div><button onClick={()=>kernel.focusWindow(app.id)}>Abrir</button><button className="danger" onClick={()=>windows.filter(w=>w.appId===app.appId).forEach(w=>kernel.closeWindow(w.id))}>Fechar</button></div>):<div className="settings-empty">Nenhum aplicativo aberto.</div>}</div></>;
    case 'accounts': return <><h2>Contas</h2><div className="settings-hero"><div className="settings-avatar">{String(currentUser?.displayName||currentUser?.username||'U').slice(0,1).toUpperCase()}</div><div><h3>{currentUser?.displayName||currentUser?.username||'Usuário local'}</h3><p>{currentUser?.role==='admin'?'Conta administrativa local do CloudOS':'Conta de usuário padrão do CloudOS'}</p></div></div><div className="settings-card"><Row label="Nome de usuário" value={currentUser?.username||'-'}/><Row label="Tipo" value={currentUser?.role==='admin'?'Administrador local':'Usuário padrão'}/><button className="settings-secondary" onClick={()=>kernel.sysLock()}>Bloquear sessão</button></div><div className="settings-card"><h3>Código de recuperação</h3><p className="settings-recovery-description">Gere um código novo se a conta foi criada antes deste recurso ou se o código anterior não está mais seguro. O código antigo será invalidado.</p>{accountNotice&&<div className="settings-recovery-notice">{accountNotice}</div>}{rotatedRecoveryCode?<div className="settings-recovery-result"><strong>Mostrado uma única vez</strong><div><code>{rotatedRecoveryCode}</code><button className="settings-secondary" onClick={copyAccountRecoveryCode}>Copiar</button></div><label><input type="checkbox" checked={recoveryCodeSaved} onChange={e=>setRecoveryCodeSaved(e.target.checked)}/><span>Confirmei que salvei o novo código</span></label><button className="settings-action" disabled={!recoveryCodeSaved} onClick={()=>{confirmRecoveryCodeSaved();rotatedRecoveryCodeRef.current=null;setRotatedRecoveryCode(null);setRecoveryCodeSaved(false);setAccountNotice('Código salvo. Ele não ficará armazenado nesta interface.')}}>Fechar código</button></div>:<button className="settings-action" disabled={rotatingRecoveryCode} onClick={rotateAccountRecoveryCode}>{rotatingRecoveryCode?'Gerando…':'Gerar novo código'}</button>}</div></>;
    case 'linux': return <>
      <h2>Sistemas Operacionais & Distribuições (Multi-Distro)</h2>
      <div className="settings-hero">
        <div className="settings-hero-icon">🐧</div>
        <div>
          <h3>Gerenciador de Sistemas Híbrido</h3>
          <p>Alterne ou instale novas distribuições Linux (Ubuntu, Kali, Debian, Arch, Fedora, Alpine) no CloudOS.</p>
        </div>
        <span className="status-pill ok">Ativo: {distroData?.active || 'kali-linux'}</span>
      </div>
      {distroNotice && <div className="settings-recovery-notice">{distroNotice}</div>}
      
      <div className="settings-card">
        <h3>Sistemas Instalados no Dispositivo</h3>
        {distroLoading && <p>Consultando distribuições WSL registradas...</p>}
        {distroData?.installed?.length ? (
          <div className="settings-app-list">
            {distroData.installed.map(d => (
              <div className="settings-app-row" key={d.id}>
                <span className="app-icon" style={{ fontSize: '1.4rem' }}>{d.icon || '🐧'}</span>
                <div>
                  <strong>{d.name} {d.isActiveInCloudOS && <span className="status-pill ok" style={{ marginLeft: 8, fontSize: '0.75rem' }}>Ativo</span>}</strong>
                  <small>{d.category} · Estado: {d.state || 'Instalado'} · WSL {d.version || '2'}</small>
                </div>
                {!d.isActiveInCloudOS && (
                  <div style={{ display: 'flex', gap: 8 }}>
                    <button className="settings-action" onClick={() => switchActiveDistro(d.id)}>
                      Definir como Ativo
                    </button>
                    <button className="settings-secondary" style={{ color: '#ef4444' }} onClick={() => triggerUnregisterDistro(d.id)}>
                      Excluir
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p className="settings-desc">Nenhum sistema adicional detectado.</p>
        )}
      </div>

      <div className="settings-card">
        <h3>Catálogo de Sistemas Disponíveis (Microsoft Store / CloudOS)</h3>
        <div className="settings-app-list">
          {distroData?.online?.filter(o => !distroData.installed.some(i => i.id.toLowerCase() === o.id.toLowerCase())).map(o => (
            <div className="settings-app-row" key={o.id}>
              <span className="app-icon" style={{ fontSize: '1.4rem' }}>{o.icon || '📦'}</span>
              <div>
                <strong>{o.name}</strong>
                <small>{o.category} · Tamanho estimado: {o.sizeEstimateMB} MB · {o.description}</small>
              </div>
              <button className="settings-secondary" onClick={() => triggerInstallDistro(o.id)}>
                Instalar Sistema
              </button>
            </div>
          ))}
        </div>
      </div>

      <div className="settings-card">
        <h3>Experiência de Primeiro Boot (OOBE)</h3>
        <p className="settings-desc">Deseja reiniciar a configuração inicial do CloudOS (seleção de distro, provisionamento e criação de perfil)?</p>
        <button className="settings-secondary" onClick={() => {
          if (!window.confirm('Deseja reiniciar a experiência de Primeiro Boot (OOBE)?')) return;
          localStorage.removeItem('cloudos-oobe-completed');
          localStorage.removeItem('obsidianos-setup-completed');
          useSystem.getState().setBootPhase('setup');
        }}>
          Executar Primeiro Boot (OOBE)
        </button>
      </div>
    </>;
    case 'privacy': return <><h2>Privacidade</h2><div className="settings-card"><Toggle label="Métricas locais" desc="Permitir gráficos e diagnóstico no dispositivo" on={privacy.metrics} onChange={()=>setPrivacyValue('metrics',!privacy.metrics)}/></div><div className="settings-card"><Toggle label="Acesso ao terminal" desc="Permitir integração com terminal local" on={privacy.terminal} onChange={()=>setPrivacyValue('terminal',!privacy.terminal)}/></div><div className="settings-card"><Toggle label="Sistema de arquivos" desc="Permitir armazenamento virtual persistente" on={privacy.files} onChange={()=>setPrivacyValue('files',!privacy.files)}/></div></>;
    case 'update': return <><h2>Atualizações</h2><div className="settings-hero"><div className="settings-hero-icon">↻</div><div><h3>Atualização controlada</h3><p>A verificação é somente leitura. Aplicação e rollback pertencem ao Bootstrap.</p></div></div><div className="settings-card"><Row label="Versão" value={product?.version||'Consultando…'}/><Row label="Canal" value={product?.channel||'Consultando…'}/><Row label="Estado" value={updateStatus}/>{update?.sha256&&<Row label="SHA-256 do pacote" value={`${update.sha256.slice(0,12)}…${update.sha256.slice(-12)}`}/>}<button className="settings-action" onClick={checkProductUpdate}>Verificar atualização</button><p className="settings-desc">Stable permanece desativado até existir release aprovada. Atualizações não são aplicadas durante uma sessão crítica.</p></div></>;
    case 'diagnostics': return <><h2>Diagnóstico</h2>{productNotice&&<div className="settings-recovery-notice">{productNotice}</div>}<div className="settings-card"><h3>Saúde dos componentes</h3><Row label="Backend" value={health.api==='online'?`Online${health.latency!==undefined?` · ${health.latency} ms`:''}`:health.api==='checking'?'Verificando':'Indisponível'}/><Row label="Native Host" value={product?.nativeHost?'Disponível':'Indisponível'}/><Row label="WSL Core" value={product?.wslCorePayload?'Payload disponível':'Payload indisponível'}/><Row label="Protocolo" value={product?.protocolVersion??'-'}/><Row label="Logs" value={product?.logDirectory||'-'}/><div><button className="settings-action" onClick={()=>productAction('/api/product/diagnostics/export','Diagnóstico exportado')}>Exportar diagnóstico</button><button className="settings-secondary" onClick={()=>productAction('/api/product/folder/logs/open','Pasta de logs aberta')}>Abrir logs</button><button className="settings-secondary" onClick={()=>productAction('/api/product/cache/clear','Cache temporário limpo')}>Limpar cache temporário</button><button className="settings-secondary" onClick={checkHealth}>Verificar novamente</button></div></div></>;
    case 'about': return <><h2>Sobre</h2><div className="settings-card about-card"><div className="about-logo">◈</div><h3>CloudOS Unified</h3><p>Build experimental de distribuição Windows.</p><div className="about-info"><Row label="Versão CloudOS" value={product?.version||'development'}/><Row label="SHA base" value={product?.sha?`${product.sha.slice(0,12)}…`:'não informado'}/><Row label="Canal" value={product?.channel||'development'}/><Row label="Assinatura" value={product?.signing||'unsigned-development'}/><Row label="Modo atual" value={product?.mode||import.meta.env.MODE}/><Row label="Host disponível" value={product?.nativeHost?'Sim':'Não'}/><Row label="WSL Core" value={product?.wslCorePayload?'Disponível':'Indisponível'}/><Row label="Diretório de dados" value={product?.dataDirectory||'-'}/><Row label="Diretório dos logs" value={product?.logDirectory||'-'}/><Row label="Versão do protocolo" value={product?.protocolVersion??'-'}/><Row label="Plataforma" value={navigator.platform||'Navegador'}/><Row label="Idioma" value={navigator.language}/><Row label="Núcleos lógicos" value={navigator.hardwareConcurrency||'-'}/></div></div></>;
  }}
  return <div className="settings-app"><aside className="settings-sidebar"><div className="settings-sidebar-header"><div className="settings-user-info"><div className="settings-avatar">{String(currentUser?.displayName||currentUser?.username||'U').slice(0,1).toUpperCase()}</div><span>{currentUser?.displayName||currentUser?.username||'Usuário local'}</span></div></div><nav className="settings-nav">{sections.map(s=><button key={s.id} className={`settings-nav-item ${active===s.id?'active':''}`} onClick={()=>setActive(s.id)}><span className="settings-nav-icon">{s.icon}</span><span>{s.label}</span></button>)}</nav></aside><main className="settings-content"><div className="settings-content-inner">{productNotice&&active!=='diagnostics'&&<div className="settings-recovery-notice">{productNotice}</div>}{content()}</div></main></div>;
}
