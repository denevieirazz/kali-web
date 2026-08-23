import { useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import { validateDisplayName, validateNewPassword, validateUsername } from '../../services/accountContract.js';
import { copyRecoveryCode, printRecoveryCode, saveRecoveryCodeAsText } from '../../services/recoveryCodeActions';
import { apiClient } from '../../services/apiClient';
import kernel from '../../core/kernel';
import './SetupWizard.css';

type Step = 'welcome' | 'distro-select' | 'installing-runtime' | 'account' | 'ready';
const STEPS: Step[] = ['welcome', 'distro-select', 'installing-runtime', 'account', 'ready'];

type DistroOption = {
  id: string;
  name: string;
  icon: string;
  category: string;
  description: string;
  isInstalled?: boolean;
  state?: string;
  version?: string;
  sizeEstimateMB?: number;
};

type ProvisionStep = {
  id: string;
  label: string;
  done: boolean;
};

const PROVISION_STEPS_BASE: ProvisionStep[] = [
  { id: 'wsl', label: 'Verificando e inicializando subsistema WSL 2', done: false },
  { id: 'distro', label: 'Registrando distribuição selecionada', done: false },
  { id: 'home', label: 'Criando estrutura CloudOS Home (Downloads, Documentos, Projetos)', done: false },
  { id: 'runtime', label: 'Configurando Runtime Gráfico Xpra e DBus', done: false },
  { id: 'apps', label: 'Integrando aplicativos e atalhos de sistema', done: false },
];

function passwordStrength(password: string) {
  if (!password) return { level: 'empty', label: 'Digite uma senha.', detail: 'Uma frase maior é mais fácil de lembrar e mais difícil de adivinhar.' };
  if (password.length < 8) return { level: 'invalid', label: 'Muito curta', detail: 'O mínimo é 8 caracteres.' };
  if (password.length < 12) return { level: 'weak', label: 'Fraca', detail: 'Recomendamos uma frase maior, mesmo sem números ou símbolos obrigatórios.' };
  if (password.length < 16) return { level: 'medium', label: 'Razoável', detail: 'Uma frase longa aumenta a resistência sem exigir combinações artificiais.' };
  return { level: 'strong', label: 'Mais forte', detail: 'Frases longas e únicas são recomendadas.' };
}

export default function SetupWizard() {
  const [step, setStep] = useState<Step>('welcome');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [accentColor, setAccentColor] = useState('#6366f1');
  const [recoveryCode, setRecoveryCode] = useState<string | null>(null);
  const [recoverySaved, setRecoverySaved] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Distro OOBE state
  const [distroData, setDistroData] = useState<{ active: string; installed: DistroOption[]; online: DistroOption[] } | null>(null);
  const [selectedDistro, setSelectedDistro] = useState<string>('kali-linux');
  const [distroChoiceMode, setDistroChoiceMode] = useState<'existing' | 'reinstall' | 'new' | 'custom'>('existing');

  // Installation Progress state
  const [provisionProgress, setProvisionProgress] = useState(0);
  const [provisionSteps, setProvisionSteps] = useState<ProvisionStep[]>(PROVISION_STEPS_BASE);

  const completedSetupHandoff = useRef(false);
  const createdAccountInThisFlow = useRef(false);
  const { setTheme } = useSystem();
  const { createAdmin, checkSetupStatus, confirmRecoveryCodeSaved, setupStatus, setupStatusMessage } = useUserStore();
  const strength = useMemo(() => passwordStrength(password), [password]);

  useEffect(() => {
    if (setupStatus === 'checking') void checkSetupStatus();
    void loadDistros();
  }, [checkSetupStatus, setupStatus]);

  async function loadDistros() {
    try {
      const data = await apiClient<{ active: string; installed: DistroOption[]; online: DistroOption[] }>('/api/linux-runtime/distros');
      setDistroData(data);
      if (data.installed && data.installed.length > 0) {
        setSelectedDistro(data.active || data.installed[0].id);
        setDistroChoiceMode('existing');
      } else {
        setSelectedDistro('ubuntu');
        setDistroChoiceMode('new');
      }
    } catch {
      setSelectedDistro('kali-linux');
    }
  }

  useEffect(() => {
    if (setupStatus !== 'complete' || createdAccountInThisFlow.current || completedSetupHandoff.current) return;
    completedSetupHandoff.current = true;
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    kernel.bootPhase = 'WINLOGON';
  }, [setupStatus]);

  const currentIndex = STEPS.indexOf(step);

  async function startProvisioning() {
    setStep('installing-runtime');
    setProvisionProgress(10);

    try {
      if (distroChoiceMode === 'reinstall') {
        // Reinstalação explícita
        await apiClient('/api/linux-runtime/distros/unregister', { method: 'POST', body: JSON.stringify({ distro: selectedDistro }) });
      }

      setProvisionSteps(prev => prev.map((s, idx) => idx <= 0 ? { ...s, done: true } : s));
      setProvisionProgress(25);
      await new Promise(r => setTimeout(r, 600));

      if (distroChoiceMode === 'new' || distroChoiceMode === 'reinstall') {
        await apiClient('/api/linux-runtime/distros/install', { method: 'POST', body: JSON.stringify({ distro: selectedDistro }) });
      }

      setProvisionSteps(prev => prev.map((s, idx) => idx <= 1 ? { ...s, done: true } : s));
      setProvisionProgress(50);
      await new Promise(r => setTimeout(r, 600));

      // Provisiona CloudOS Home e Runtime
      await apiClient('/api/linux-runtime/distros/provision', { method: 'POST', body: JSON.stringify({ distro: selectedDistro }) });

      setProvisionSteps(prev => prev.map((s, idx) => idx <= 2 ? { ...s, done: true } : s));
      setProvisionProgress(75);
      await new Promise(r => setTimeout(r, 600));

      setProvisionSteps(prev => prev.map((s, idx) => idx <= 3 ? { ...s, done: true } : s));
      setProvisionProgress(90);
      await new Promise(r => setTimeout(r, 500));

      setProvisionSteps(prev => prev.map(s => ({ ...s, done: true })));
      setProvisionProgress(100);
      await new Promise(r => setTimeout(r, 700));

      // Avança para tela de criação de conta
      setStep('account');
    } catch (err: any) {
      setError(err.message || 'Falha durante o provisionamento do sistema.');
      setStep('distro-select');
    }
  }

  async function goNext() {
    setError(null);
    if (step === 'welcome') return setStep('distro-select');
    if (step === 'distro-select') {
      return void startProvisioning();
    }
    if (step === 'account') {
      const validation = validateDisplayName(displayName) || validateUsername(username) || validateNewPassword(password, confirmPassword);
      if (validation) return setError(validation);
      return void createRealAccount();
    }
  }

  async function createRealAccount() {
    if (loading) return;
    createdAccountInThisFlow.current = true;
    setLoading(true);
    setError(null);

    const result = await createAdmin(username.trim(), displayName.trim(), password, confirmPassword);
    setPassword('');
    setConfirmPassword('');

    if (!result.success || !result.recoveryCode) {
      createdAccountInThisFlow.current = false;
      const refreshedStatus = await checkSetupStatus();
      setLoading(false);
      if (refreshedStatus !== 'complete') setError(result.message || 'Não foi possível criar a conta no agente local.');
      return;
    }

    setLoading(false);
    setTheme({ accentColor });
    setRecoveryCode(result.recoveryCode);
    setRecoverySaved(false);
    setStep('ready');
  }

  function completeSetup() {
    kernel.sysCreateUserHome(username.trim());
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    confirmRecoveryCodeSaved();
    setRecoveryCode(null);
    setRecoverySaved(false);
    useSystem.getState().unlock();
  }

  const unavailable = setupStatus === 'unavailable';

  return (
    <div className="setup-wizard">
      <div className="setup-bg-decorator" style={{ top: '-10%', right: '-10%' }} />
      <div className="setup-bg-decorator" style={{ bottom: '-10%', left: '-10%', background: 'radial-gradient(circle, var(--accent) 0%, transparent 70%)' }} />
      
      <motion.div initial={{ scale: 0.96, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="setup-container">
        {/* Painel Esquerdo com Identidade Visual */}
        <aside className="setup-left">
          <div className="setup-cloud-mark">◈</div>
          <h2>CloudOS</h2>
          <p>
            {step === 'welcome' && 'Experiência de primeiro uso para configurar seu computador híbrido.'}
            {step === 'distro-select' && 'Selecione ou reutilize o sistema operacional base para seu ambiente.'}
            {step === 'installing-runtime' && 'Instalando componentes do sistema e criando o CloudOS Home.'}
            {step === 'account' && 'Crie sua conta administradora segura para acesso ao computador.'}
            {step === 'ready' && 'Tudo pronto para você começar a utilizar o CloudOS.'}
          </p>
          <div className="setup-security-note">
            <strong>Plataforma Híbrida Oficial</strong>
            <span>Integração nativa Windows Host + WSL 2 com sistema de arquivos unificado.</span>
          </div>
        </aside>

        {/* Painel Direito com o Conteúdo da Etapa */}
        <main className="setup-right">
          <div className="setup-step-indicator" aria-label={`Etapa ${currentIndex + 1} de ${STEPS.length}`}>
            {STEPS.map(item => (
              <div key={item} className={`step-dot ${item === step ? 'active' : ''}`} />
            ))}
          </div>

          <div className="setup-content">
            <AnimatePresence mode="wait">
              {unavailable ? (
                <motion.section key="unavailable" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <span className="setup-kicker">SERVIÇO INDISPONÍVEL</span>
                  <h1 className="setup-title">Não foi possível conectar ao agente</h1>
                  <p className="setup-description">Certifique-se de que o backend do CloudOS está em execução.</p>
                  {setupStatusMessage && <div className="setup-alert error">{setupStatusMessage}</div>}
                  <button className="setup-btn setup-btn-primary inline" onClick={() => checkSetupStatus()}>Tentar novamente</button>
                </motion.section>
              ) : step === 'welcome' ? (
                /* ==================================================
                   TELA 1: BEM-VINDO AO CLOUDOS
                   ================================================== */
                <motion.section key="welcome" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <span className="setup-kicker">FIRST BOOT EXPERIENCE</span>
                  <h1 className="setup-title">Bem-vindo ao CloudOS</h1>
                  <p className="setup-description">Vamos preparar seu ambiente de trabalho híbrido.</p>
                  <ul className="setup-feature-list">
                    <li>🖥️ Ambiente gráfico multijanela de alta fidelidade</li>
                    <li>🐧 Suporte a múltiplos sistemas Linux (Ubuntu, Kali, Debian, Arch, Fedora, Alpine)</li>
                    <li>📁 CloudOS Home com sistema de arquivos unificado e Mark of the Web</li>
                  </ul>
                </motion.section>
              ) : step === 'distro-select' ? (
                /* ==================================================
                   TELA 2: ESCOLHA SEU SISTEMA (COM DETECÇÃO CASO 1 E 2)
                   ================================================== */
                <motion.section key="distro-select" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <span className="setup-kicker">SISTEMA OPERACIONAL</span>
                  <h1 className="setup-title compact">
                    {distroData?.installed && distroData.installed.length > 0 ? 'Sistemas Encontrados' : 'Escolha seu Sistema Base'}
                  </h1>
                  <p className="setup-description">
                    {distroData?.installed && distroData.installed.length > 0
                      ? 'Detectamos distribuições instaladas via WSL 2. Você pode utilizá-la ou instalar uma nova.'
                      : 'Selecione a distribuição Linux que será provisionada no seu computador:'}
                  </p>

                  {distroData?.installed && distroData.installed.length > 0 ? (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 10 }}>
                      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 8 }}>
                        <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12 }}>
                          <input type="radio" name="distroChoiceMode" checked={distroChoiceMode === 'existing'} onChange={() => setDistroChoiceMode('existing')} />
                          <span>Utilizar existente</span>
                        </label>
                        <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12 }}>
                          <input type="radio" name="distroChoiceMode" checked={distroChoiceMode === 'reinstall'} onChange={() => setDistroChoiceMode('reinstall')} />
                          <span style={{ color: '#f87171' }}>Reinstalar do zero</span>
                        </label>
                        <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 12 }}>
                          <input type="radio" name="distroChoiceMode" checked={distroChoiceMode === 'new'} onChange={() => setDistroChoiceMode('new')} />
                          <span>Instalar novo</span>
                        </label>
                      </div>

                      {distroChoiceMode === 'reinstall' && (
                        <div className="setup-alert" style={{ background: 'rgba(239, 68, 68, 0.15)', borderColor: '#ef4444', color: '#fca5a5' }}>
                          ⚠️ <strong>Aviso:</strong> A reinstalação removerá os pacotes customizados da distribuição anterior e recriará um ambiente limpo.
                        </div>
                      )}

                      {distroChoiceMode === 'existing' || distroChoiceMode === 'reinstall' ? (
                        <div className="setup-distro-grid">
                          {distroData.installed.map(d => (
                            <div key={d.id} className={`setup-distro-card ${selectedDistro === d.id ? 'selected' : ''}`} onClick={() => setSelectedDistro(d.id)}>
                              <span className="setup-distro-icon">{d.icon || '🐉'}</span>
                              <span className="setup-distro-title">{d.name}</span>
                              <span className="setup-distro-meta">{d.category}</span>
                              <span className="setup-distro-badge">✓ Instalado (WSL {d.version || '2'})</span>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <div className="setup-distro-grid">
                          {distroData.online?.map(o => (
                            <div key={o.id} className={`setup-distro-card ${selectedDistro === o.id ? 'selected' : ''}`} onClick={() => setSelectedDistro(o.id)}>
                              <span className="setup-distro-icon">{o.icon || '📦'}</span>
                              <span className="setup-distro-title">{o.name}</span>
                              <span className="setup-distro-meta">{o.category}</span>
                              <span className="setup-distro-meta">{o.description}</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="setup-distro-grid">
                      {distroData?.online?.map(o => (
                        <div key={o.id} className={`setup-distro-card ${selectedDistro === o.id ? 'selected' : ''}`} onClick={() => setSelectedDistro(o.id)}>
                          <span className="setup-distro-icon">{o.icon || '📦'}</span>
                          <span className="setup-distro-title">{o.name}</span>
                          <span className="setup-distro-meta">{o.category}</span>
                          <span className="setup-distro-meta">{o.description}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </motion.section>
              ) : step === 'installing-runtime' ? (
                /* ==================================================
                   TELA 3: PREPARANDO SISTEMA (PROGRESSO REAL)
                   ================================================== */
                <motion.section key="installing-runtime" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <span className="setup-kicker">PROVISIONAMENTO</span>
                  <h1 className="setup-title compact">Preparando Sistema...</h1>
                  <p className="setup-description">Configurando o motor híbrido e o sistema de arquivos CloudOS Home.</p>

                  <div style={{ marginTop: 18, marginBottom: 20 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8, fontSize: 13 }}>
                      <strong>Instalação em andamento</strong>
                      <strong>{provisionProgress}%</strong>
                    </div>
                    <div style={{ width: '100%', height: 8, borderRadius: 4, background: 'rgba(255, 255, 255, 0.1)', overflow: 'hidden' }}>
                      <motion.div style={{ height: '100%', background: 'var(--accent, #6366f1)' }} animate={{ width: `${provisionProgress}%` }} transition={{ duration: 0.4 }} />
                    </div>
                  </div>

                  <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                    {provisionSteps.map(s => (
                      <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 13, color: s.done ? 'var(--text-primary)' : 'var(--text-secondary)' }}>
                        <span style={{ color: s.done ? '#4ade80' : 'rgba(255, 255, 255, 0.3)', fontWeight: 'bold' }}>
                          {s.done ? '✓' : '○'}
                        </span>
                        <span>{s.label}</span>
                      </div>
                    ))}
                  </div>
                </motion.section>
              ) : step === 'account' ? (
                /* ==================================================
                   TELA 4: SUA CONTA (NOME, SENHA, AVATAR/COR)
                   ================================================== */
                <motion.form key="account" className="setup-form" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onSubmit={event => { event.preventDefault(); void goNext(); }}>
                  <span className="setup-kicker">SUA CONTA</span>
                  <h1 className="setup-title compact">Criar Usuário Administrador</h1>
                  
                  <label className="setup-field">
                    Nome de exibição
                    <input className="setup-input" value={displayName} onChange={event => setDisplayName(event.target.value)} autoComplete="name" maxLength={80} placeholder="Ex: Douglas Vieira" />
                  </label>

                  <label className="setup-field">
                    Nome de usuário
                    <input className="setup-input" value={username} onChange={event => setUsername(event.target.value)} autoComplete="username" maxLength={64} placeholder="Ex: admin" />
                  </label>

                  <div className="setup-password-grid">
                    <label className="setup-field">
                      Senha
                      <input type="password" className="setup-input" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" minLength={8} maxLength={128} />
                    </label>
                    <label className="setup-field">
                      Confirmar senha
                      <input type="password" className="setup-input" value={confirmPassword} onChange={event => setConfirmPassword(event.target.value)} autoComplete="new-password" minLength={8} maxLength={128} />
                    </label>
                  </div>

                  <div className={`setup-password-strength setup-password-strength--${strength.level}`} data-password-strength={strength.level}>
                    <strong>{strength.label}</strong>
                    <span>{strength.detail}</span>
                  </div>

                  <div style={{ marginTop: 12 }}>
                    <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Cor de destaque pessoal</span>
                    <div className="setup-themes" style={{ marginTop: 6 }}>
                      {['#6366f1', '#f43f5e', '#10b981', '#f59e0b', '#8b5cf6', '#06b6d4'].map(color => (
                        <button type="button" aria-label={`Cor ${color}`} key={color} className={`theme-card ${accentColor === color ? 'selected' : ''}`} onClick={() => setAccentColor(color)}>
                          <span className="theme-preview" style={{ background: color }} />
                        </button>
                      ))}
                    </div>
                  </div>
                  <button type="submit" hidden aria-hidden="true" />
                </motion.form>
              ) : (
                /* ==================================================
                   TELA 5: FINALIZAÇÃO (SEU CLOUDOS ESTÁ PRONTO)
                   ================================================== */
                <motion.section key="ready" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                  <span className="setup-kicker">CONFIGURAÇÃO CONCLUÍDA</span>
                  <h1 className="setup-title compact">Seu CloudOS está pronto!</h1>
                  <p className="setup-description">O ambiente foi provisionado com sucesso e está pronto para uso.</p>

                  <div style={{ background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-subtle)', borderRadius: 12, padding: 16, marginTop: 14 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--border-subtle)' }}>
                      <span style={{ color: 'var(--text-secondary)' }}>Sistema Operacional:</span>
                      <strong>{selectedDistro}</strong>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--border-subtle)' }}>
                      <span style={{ color: 'var(--text-secondary)' }}>Armazenamento Padrão:</span>
                      <strong>CloudOS Home (Unificado)</strong>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0' }}>
                      <span style={{ color: 'var(--text-secondary)' }}>Usuário Ativo:</span>
                      <strong>{displayName || username || 'Administrador'}</strong>
                    </div>
                  </div>

                  {recoveryCode && (
                    <div style={{ marginTop: 14, fontSize: 12, color: 'var(--text-secondary)' }}>
                      Chave de recuperação gerada: <code>{recoveryCode.slice(0, 8)}...</code>
                    </div>
                  )}
                </motion.section>
              )}
            </AnimatePresence>
            {error && <div className="setup-alert error" role="alert">{error}</div>}
          </div>

          {!unavailable && (
            <footer className="setup-footer">
              {currentIndex > 0 && step !== 'installing-runtime' && step !== 'ready' && (
                <button className="setup-btn setup-btn-secondary" onClick={() => { setError(null); setStep(STEPS[currentIndex - 1]); }}>
                  Voltar
                </button>
              )}
              {step === 'welcome' && (
                <button className="setup-btn setup-btn-primary" onClick={() => setStep('distro-select')}>
                  Começar →
                </button>
              )}
              {step === 'distro-select' && (
                <button className="setup-btn setup-btn-primary" onClick={() => void startProvisioning()}>
                  Instalar Sistema →
                </button>
              )}
              {step === 'account' && (
                <button className="setup-btn setup-btn-primary" onClick={() => void goNext()} disabled={loading}>
                  {loading ? 'Criando conta…' : 'Criar Conta e Finalizar →'}
                </button>
              )}
              {step === 'ready' && (
                <button className="setup-btn setup-btn-primary" onClick={() => completeSetup()}>
                  Entrar no CloudOS 🚀
                </button>
              )}
            </footer>
          )}
        </main>
      </motion.div>
    </div>
  );
}
