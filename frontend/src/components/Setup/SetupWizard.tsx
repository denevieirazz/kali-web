import { useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import { validateDisplayName, validateNewPassword, validateUsername } from '../../services/accountContract.js';
import { copyRecoveryCode, printRecoveryCode, saveRecoveryCodeAsText } from '../../services/recoveryCodeActions';
import { apiClient } from '../../services/apiClient';
import kernel from '../../core/kernel';
import './SetupWizard.css';

type Step = 'welcome' | 'distro' | 'account' | 'theme' | 'recovery';
const STEPS: Step[] = ['welcome', 'distro', 'account', 'theme', 'recovery'];

type DistroOption = { id: string; name: string; icon: string; category: string; description: string; isInstalled?: boolean; state?: string; version?: string };

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
  
  // Distro selection state
  const [distroData, setDistroData] = useState<{ active: string; installed: DistroOption[]; online: DistroOption[] } | null>(null);
  const [selectedDistro, setSelectedDistro] = useState<string>('kali-linux');
  const [distroMode, setDistroMode] = useState<'existing' | 'new' | 'custom'>('existing');

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
        setDistroMode('existing');
      } else {
        setSelectedDistro('ubuntu');
        setDistroMode('new');
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
  async function goNext() {
    setError(null);
    if (step === 'welcome') return setStep('distro');
    if (step === 'distro') {
      try {
        await apiClient('/api/linux-runtime/distros/active', { method: 'POST', body: JSON.stringify({ distro: selectedDistro }) });
        if (distroMode === 'new') {
          await apiClient('/api/linux-runtime/distros/install', { method: 'POST', body: JSON.stringify({ distro: selectedDistro }) });
        }
      } catch {}
      return setStep('account');
    }
    if (step === 'account') {
      const validation = validateDisplayName(displayName) || validateUsername(username) || validateNewPassword(password, confirmPassword);
      if (validation) return setError(validation);
      return setStep('theme');
    }
    if (step === 'theme') void createRealAccount();
  }

  async function createRealAccount() {
    if (loading) return;
    createdAccountInThisFlow.current = true;
    setLoading(true); setError(null);
    const result = await createAdmin(username.trim(), displayName.trim(), password, confirmPassword);
    setPassword(''); setConfirmPassword('');
    if (!result.success || !result.recoveryCode) {
      createdAccountInThisFlow.current = false;
      const refreshedStatus = await checkSetupStatus();
      setLoading(false);
      if (refreshedStatus !== 'complete') setError(result.message || 'Não foi possível criar a conta no agente local.');
      return;
    }
    setLoading(false); setTheme({ accentColor }); setRecoveryCode(result.recoveryCode); setRecoverySaved(false); setStep('recovery');
  }

  function completeSetup() {
    kernel.sysCreateUserHome(username.trim());
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    confirmRecoveryCodeSaved();
    setRecoveryCode(null); setRecoverySaved(false);
    useSystem.getState().unlock();
  }

  function finishSetup(allowUnsaved = false) {
    if (!recoveryCode) return;
    if (!recoverySaved && !allowUnsaved) return;
    completeSetup();
  }

  function continueWithoutSaving() {
    if (!recoveryCode) return;
    const confirmed = window.confirm('Sem o arquivo ou código de recuperação, uma senha esquecida não poderá ser redefinida. Continuar sem salvar?');
    if (confirmed) finishSetup(true);
  }

  async function runRecoveryAction(action: 'copy' | 'save' | 'print') {
    if (!recoveryCode) return;
    setError(null);
    try {
      if (action === 'copy') await copyRecoveryCode(recoveryCode);
      if (action === 'save') { await saveRecoveryCodeAsText(recoveryCode); setRecoverySaved(true); }
      if (action === 'print') { printRecoveryCode(recoveryCode); setRecoverySaved(true); }
    } catch (actionError) { setError(actionError instanceof Error ? actionError.message : 'Não foi possível concluir esta ação.'); }
  }

  const unavailable = setupStatus === 'unavailable';
  return <div className="setup-wizard">
    <div className="setup-bg-decorator" style={{ top: '-10%', right: '-10%' }} /><div className="setup-bg-decorator" style={{ bottom: '-10%', left: '-10%', background: 'radial-gradient(circle, var(--accent) 0%, transparent 70%)' }} />
    <motion.div initial={{ scale: .96, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="setup-container">
      <aside className="setup-left"><div className="setup-cloud-mark">C</div><h2>CloudOS</h2><p>{step === 'welcome' && 'Configure uma conta real protegida pelo agente local.'}{step === 'distro' && 'Selecione ou instale a distribuição Linux base para o CloudOS.'}{step === 'account' && 'Sua senha é derivada no agente local e não fica salva nesta interface.'}{step === 'theme' && 'Personalize o ambiente antes de concluir a criação.'}{step === 'recovery' && 'Este arquivo ou código permite criar uma nova senha se você esquecer a atual.'}</p><div className="setup-security-note"><strong>Conta local real</strong><span>Credenciais não ficam no navegador, kernel ou sistema de arquivos virtual.</span></div></aside>
      <main className="setup-right">
        <div className="setup-step-indicator" aria-label={`Etapa ${currentIndex + 1} de ${STEPS.length}`}>{STEPS.map(item => <div key={item} className={`step-dot ${item === step ? 'active' : ''}`} />)}</div>
        <div className="setup-content"><AnimatePresence mode="wait">
          {unavailable ? <motion.section key="unavailable" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}><span className="setup-kicker">AGENTE INDISPONÍVEL</span><h1 className="setup-title">Não foi possível verificar a instalação</h1><p className="setup-description">Reconecte o agente local para consultar o estado real.</p>{setupStatusMessage && <div className="setup-alert error">{setupStatusMessage}</div>}<button className="setup-btn setup-btn-primary inline" onClick={() => checkSetupStatus()}>Tentar novamente</button></motion.section>
          : step === 'welcome' ? <motion.section key="welcome" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}><span className="setup-kicker">PRIMEIRO ACESSO</span><h1 className="setup-title">Sua conta começa aqui.</h1><p className="setup-description">Crie a conta administradora do CloudOS. Depois você poderá salvar um arquivo de recuperação em um local escolhido por você.</p><ul className="setup-feature-list"><li>Senha armazenada somente como hash no agente</li><li>Sessão autenticada para recursos do computador</li><li>Recuperação offline de uso único</li></ul></motion.section>
          : step === 'distro' ? <motion.section key="distro" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
            <span className="setup-kicker">SISTEMA OPERACIONAL BASE</span>
            <h1 className="setup-title compact">{distroData?.installed && distroData.installed.length > 0 ? 'Sistemas Encontrados' : 'Escolha seu Sistema Base'}</h1>
            <p className="setup-description">{distroData?.installed && distroData.installed.length > 0 ? 'Detectamos distribuições Linux instaladas no dispositivo via WSL 2. Você pode utilizar uma existente ou provisionar uma nova.' : 'Selecione a distribuição Linux que deseja instalar como motor gráfico do CloudOS.'}</p>
            {distroData?.installed && distroData.installed.length > 0 ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
                <div style={{ display: 'flex', gap: 16 }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 13 }}>
                    <input type="radio" name="distroMode" checked={distroMode === 'existing'} onChange={() => setDistroMode('existing')} />
                    <strong>Utilizar sistema existente</strong>
                  </label>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer', fontSize: 13 }}>
                    <input type="radio" name="distroMode" checked={distroMode === 'new'} onChange={() => setDistroMode('new')} />
                    <strong>Instalar novo sistema</strong>
                  </label>
                </div>
                {distroMode === 'existing' ? (
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
          : step === 'account' ? <motion.form key="account" className="setup-form" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onSubmit={event => { event.preventDefault(); void goNext(); }}><span className="setup-kicker">CONTA ADMINISTRADORA</span><h1 className="setup-title compact">Identifique-se</h1><label className="setup-field">Nome de exibição<input className="setup-input" value={displayName} onChange={event => setDisplayName(event.target.value)} autoComplete="name" maxLength={80} placeholder="Como você quer ser chamado" /></label><label className="setup-field">Nome de usuário<input className="setup-input" value={username} onChange={event => setUsername(event.target.value)} autoComplete="username" maxLength={64} placeholder="exemplo.usuario" /></label><div className="setup-password-grid"><label className="setup-field">Senha<input type="password" className="setup-input" value={password} onChange={event => setPassword(event.target.value)} autoComplete="new-password" minLength={8} maxLength={128} /></label><label className="setup-field">Confirmar senha<input type="password" className="setup-input" value={confirmPassword} onChange={event => setConfirmPassword(event.target.value)} autoComplete="new-password" minLength={8} maxLength={128} /></label></div><div className={`setup-password-strength setup-password-strength--${strength.level}`} data-password-strength={strength.level}><strong>{strength.label}</strong><span>{strength.detail}</span></div><small className="setup-field-help">Mínimo de 8 caracteres. Espaços e frases-senha são aceitos. Não exigimos maiúsculas, números ou símbolos.</small><button type="submit" hidden aria-hidden="true" /></motion.form>
          : step === 'theme' ? <motion.section key="theme" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}><span className="setup-kicker">APARÊNCIA</span><h1 className="setup-title compact">Escolha uma cor</h1><p className="setup-description">A conta será criada no agente quando você continuar.</p><div className="setup-themes">{['#6366f1','#f43f5e','#10b981','#f59e0b','#8b5cf6','#06b6d4'].map(color => <button type="button" aria-label={`Cor ${color}`} key={color} className={`theme-card ${accentColor === color ? 'selected' : ''}`} onClick={() => setAccentColor(color)}><span className="theme-preview" style={{ background: color }} /><span className="theme-name">{color}</span></button>)}</div></motion.section>
          : <motion.section key="recovery" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}><span className="setup-kicker">PROTEJA SUA CONTA</span><h1 className="setup-title compact">Guarde uma forma de recuperação</h1><p className="setup-description">Este arquivo permite criar uma nova senha se você esquecer a atual. Guarde-o em um local seguro. O CloudOS não salva esse código automaticamente e não poderá mostrá-lo novamente depois desta etapa.</p><div className="setup-recovery-code"><code>{recoveryCode}</code></div><div className="setup-recovery-actions" aria-label="Ações para o código de recuperação"><button type="button" className="setup-btn setup-btn-secondary" onClick={() => void runRecoveryAction('save')}>Salvar arquivo de recuperação</button><button type="button" className="setup-btn setup-btn-secondary" onClick={() => void runRecoveryAction('print')}>Imprimir</button><button type="button" className="setup-btn setup-btn-secondary" onClick={() => void runRecoveryAction('copy')}>Copiar</button></div><label className="setup-confirm-save"><input type="checkbox" checked={recoverySaved} onChange={event => setRecoverySaved(event.target.checked)} /><span><strong>Confirmei que guardei o arquivo ou código</strong><small>O original não ficará disponível depois que você entrar.</small></span></label><button type="button" className="setup-btn setup-btn-link" onClick={continueWithoutSaving}>Continuar sem salvar</button></motion.section>}
        </AnimatePresence>{error && <div className="setup-alert error" role="alert">{error}</div>}</div>
        {!unavailable && <footer className="setup-footer">{currentIndex > 0 && step !== 'recovery' && <button className="setup-btn setup-btn-secondary" onClick={() => { setError(null); setStep(STEPS[currentIndex - 1]); }}>Voltar</button>}{step !== 'recovery' ? <button className="setup-btn setup-btn-primary" onClick={() => void goNext()} disabled={loading}>{loading ? 'Criando conta…' : step === 'theme' ? 'Criar conta' : 'Continuar'}</button> : <button className="setup-btn setup-btn-primary" onClick={() => finishSetup(false)} disabled={!recoverySaved}>Entrar no CloudOS</button>}</footer>}

      </main>
    </motion.div>
  </div>;
}
