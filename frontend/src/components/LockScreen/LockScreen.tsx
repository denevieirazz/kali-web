import { useEffect, useRef, useState } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import { validateDisplayName, validateNewPassword, validateUsername } from '../../services/accountContract.js';
import kernel from '../../core/kernel';
import './LockScreen.css';

type PanelMode = 'login' | 'recovery' | 'recovery-code';
type OneTimeCodeOrigin = 'legacy-login' | 'recovery-reset';

export default function LockScreen() {
  const { bootPhase, unlock } = useSystem();
  const {
    currentUser,
    setupStatus,
    setupStatusMessage,
    recoveryAvailable,
    recoveryStatusMessage,
    login,
    recoverAccount,
    checkSetupStatus,
    checkRecoveryStatus,
    confirmRecoveryCodeSaved,
    resetLocalInstallation
  } = useUserStore();
  const [showPanel, setShowPanel] = useState(false);
  const [mode, setMode] = useState<PanelMode>('login');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [rotatedCode, setRotatedCode] = useState<string | null>(null);
  const [recoveredUsername, setRecoveredUsername] = useState<string | null>(null);
  const [oneTimeCodeOrigin, setOneTimeCodeOrigin] = useState<OneTimeCodeOrigin>('recovery-reset');
  const [recoverySaved, setRecoverySaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [time, setTime] = useState(new Date());
  const [isUnlocking, setIsUnlocking] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);
  const copyTimerRef = useRef<number | null>(null);
  const recoveryCheckInFlight = useRef(false);
  const isDevEnvironment = import.meta.env.DEV || import.meta.env.MODE === 'development';

  useEffect(() => {
    const timer = window.setInterval(() => setTime(new Date()), 1000);
    return () => {
      window.clearInterval(timer);
      if (copyTimerRef.current !== null) {
        window.clearTimeout(copyTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    const handleKeyDown = () => {
      if (!showPanel) setShowPanel(true);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [showPanel]);

  useEffect(() => {
    if (setupStatus === 'checking') void checkSetupStatus();
  }, [checkSetupStatus, setupStatus]);

  useEffect(() => {
    if (bootPhase === 'login' && setupStatus === 'required') kernel.bootPhase = 'OOBE';
  }, [bootPhase, setupStatus]);

  useEffect(() => {
    if (setupStatus === 'complete' && recoveryAvailable === null && !recoveryStatusMessage && !recoveryCheckInFlight.current) {
      recoveryCheckInFlight.current = true;
      void checkRecoveryStatus().finally(() => { recoveryCheckInFlight.current = false; });
    }
  }, [checkRecoveryStatus, recoveryAvailable, recoveryStatusMessage, setupStatus]);

  useEffect(() => {
    if (currentUser?.username && !username) setUsername(currentUser.username);
    if (currentUser?.displayName && !displayName) setDisplayName(currentUser.displayName);
  }, [currentUser, displayName, username]);

  if (bootPhase !== 'login') return null;

  const hours = time.getHours().toString().padStart(2, '0');
  const minutes = time.getMinutes().toString().padStart(2, '0');
  const dateStr = time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });

  function resetMessages() {
    setError(null);
    setSuccessMsg(null);
  }

  function switchToRecovery() {
    resetMessages();
    setPassword('');
    setConfirmPassword('');
    setRecoveredUsername(null);
    setMode('recovery');
  }

  function switchToLogin() {
    resetMessages();
    setPassword('');
    setConfirmPassword('');
    setRecoveryCode('');
    setRecoveredUsername(null);
    setMode('login');
  }

  async function handleLogin(event: React.FormEvent) {
    event.preventDefault();
    resetMessages();
    const usernameError = validateUsername(username);
    if (usernameError || !password) return setError(usernameError || 'Informe a senha.');
    setLoading(true);
    const result = await login(username.trim(), password);
    setLoading(false);
    setPassword('');
    if (!result.success) return setError(result.message || 'Conta ou senha não conferem.');
    if (result.recoveryCode) {
      setRotatedCode(result.recoveryCode);
      setOneTimeCodeOrigin('legacy-login');
      setRecoverySaved(false);
      setMode('recovery-code');
      return;
    }
    setSuccessMsg('Conta autenticada. Abrindo o CloudOS…');
    setIsUnlocking(true);
    window.setTimeout(() => unlock(), 650);
  }

  async function handleRecovery(event: React.FormEvent) {
    event.preventDefault();
    resetMessages();
    const code = recoveryCode.trim();
    if (!code) return setError('Informe o código de recuperação.');
    const validation = validateUsername(username, { required: false }) || validateDisplayName(displayName, { required: false }) || validateNewPassword(password, confirmPassword);
    if (validation) return setError(validation);
    setLoading(true);
    const result = await recoverAccount(code, username.trim(), displayName.trim(), password, confirmPassword);
    setLoading(false);
    setPassword('');
    setConfirmPassword('');
    if (!result.success || !result.recoveryCode) {
      return setError(result.message || 'Não foi possível recuperar a conta.');
    }
    setRecoveryCode('');
    setRotatedCode(result.recoveryCode);
    setRecoveredUsername(result.username || useUserStore.getState().currentUser?.username || null);
    setOneTimeCodeOrigin('recovery-reset');
    setRecoverySaved(false);
    setMode('recovery-code');
  }

  function finishRecovery() {
    if (!recoverySaved) return;
    const finalUsername = recoveredUsername || useUserStore.getState().currentUser?.username;
    if (finalUsername) {
      kernel.sysCreateUserHome(finalUsername);
    }
    confirmRecoveryCodeSaved();
    setRotatedCode(null);
    setRecoveredUsername(null);
    setRecoverySaved(false);
    setSuccessMsg('Conta recuperada. Abrindo o CloudOS…');
    setIsUnlocking(true);
    window.setTimeout(() => unlock(), 650);
  }

  async function copyRotatedCode() {
    if (!rotatedCode) return;
    try {
      await navigator.clipboard.writeText(rotatedCode);
      setCopiedCode(true);
      if (copyTimerRef.current !== null) {
        window.clearTimeout(copyTimerRef.current);
      }
      copyTimerRef.current = window.setTimeout(() => {
        setCopiedCode(false);
        copyTimerRef.current = null;
      }, 2000);
    } catch {
      setError('Selecione e salve o código manualmente.');
    }
  }

  async function handleResetDev() {
    if (!window.confirm('Redefinir a instalação local do CloudOS? As contas locais serão removidas.')) return;
    setLoading(true);
    const ok = await resetLocalInstallation();
    setLoading(false);
    if (!ok) setError('Não foi possível redefinir a instalação.');
  }

  function refreshRecoveryStatus() {
    if (recoveryCheckInFlight.current) return;
    recoveryCheckInFlight.current = true;
    void checkRecoveryStatus().finally(() => { recoveryCheckInFlight.current = false; });
  }

  const title = mode === 'recovery' ? 'Recuperar conta' : mode === 'recovery-code' ? 'Novo código de recuperação' : 'Bem-vindo ao CloudOS';
  const subtitle = mode === 'login' ? 'Entre com sua conta local' : mode === 'recovery' ? 'Redefina a conta com segurança' : 'Salve antes de continuar';

  return (
    <div className={`cloudos-lock-screen ${isUnlocking ? 'unlocking' : ''}`} onClick={() => !showPanel && setShowPanel(true)}>
      <div className="bg-glow bg-glow-1" /><div className="bg-glow bg-glow-2" /><div className="bg-glow bg-glow-3" />
      {!showPanel && <div className="lock-time-container"><div className="lock-time">{hours}:{minutes}</div><div className="lock-date">{dateStr}</div></div>}

      {showPanel && <div className="cloudos-lock-outer-frame" onClick={(event) => event.stopPropagation()}>
        <div className={`cloudos-glass-card ${mode !== 'login' ? 'recovery-mode' : ''}`}>
          <header className="card-header"><div className="cloudos-brand-logo">C</div><h1 className="card-title">{title}</h1><p className="card-subtitle">{subtitle}</p></header>

          {setupStatus === 'checking' && <div className="lock-system-state"><span className="spinner" /><div><strong>Verificando instalação</strong><p>Consultando o agente local antes de liberar o acesso.</p></div></div>}
          {setupStatus === 'unavailable' && <div className="lock-system-state unavailable"><div><strong>O agente local está indisponível</strong><p>{setupStatusMessage || 'Não foi possível saber se a instalação está configurada.'}</p><button type="button" onClick={() => checkSetupStatus()}>Tentar novamente</button></div></div>}
          {setupStatus === 'required' && <div className="lock-system-state unavailable"><div><strong>A instalação ainda não possui administrador</strong><p>Reinicie o fluxo de primeiro acesso para criar a conta real.</p></div></div>}

          {setupStatus === 'complete' && mode === 'login' && <form onSubmit={handleLogin} className="card-form" noValidate>
            <FormField id="login-username" label="Nome de usuário" value={username} onChange={setUsername} autoComplete="username" />
            <FormField id="login-password" label="Senha" type="password" value={password} onChange={setPassword} autoComplete="current-password" />
            {error && <Alert tone="error">{error}</Alert>}{successMsg && <Alert tone="success">{successMsg}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Entrando…' : 'Entrar'}</button>
            <button
              type="button"
              className="btn-recovery-link"
              disabled={recoveryAvailable === false}
              onClick={switchToRecovery}
            >
              {recoveryAvailable === null && !recoveryStatusMessage ? 'Verificando recuperação…' : 'Esqueci minha conta ou senha'}
            </button>
            {recoveryAvailable === false && <div className="lock-recovery-unavailable" role="status">Esta conta antiga ainda não possui um código. Entre uma vez com a senha e salve o código que será mostrado antes de acessar o desktop.</div>}
            {recoveryStatusMessage && <div className="lock-recovery-unavailable error" role="alert"><span>Não foi possível verificar se a recuperação está disponível.</span><button type="button" onClick={refreshRecoveryStatus}>Tentar novamente</button></div>}
          </form>}

          {setupStatus === 'complete' && mode === 'recovery' && <form onSubmit={handleRecovery} className="card-form recovery-form" noValidate>
            <p className="recovery-explanation">Use o código salvo no primeiro acesso. Se ele for válido, a senha e o nome de usuário serão substituídos e um novo código será gerado.</p>
            <FormField id="recovery-code" label="Código de recuperação" value={recoveryCode} onChange={setRecoveryCode} autoComplete="off" monospace />
            <FormField id="recovery-username" label="Novo nome de usuário (opcional)" value={username} onChange={setUsername} autoComplete="username" />
            <FormField id="recovery-display-name" label="Nome de exibição (opcional)" value={displayName} onChange={setDisplayName} autoComplete="name" />
            <div className="recovery-password-grid"><FormField id="recovery-password" label="Nova senha" type="password" value={password} onChange={setPassword} autoComplete="new-password" /><FormField id="recovery-confirm" label="Confirmar senha" type="password" value={confirmPassword} onChange={setConfirmPassword} autoComplete="new-password" /></div>
            <small className="recovery-password-hint">Use de 10 a 128 caracteres. Uma frase-senha longa também é aceita.</small>
            {error && <Alert tone="error">{error}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Recuperando…' : 'Recuperar conta'}</button>
            <button type="button" className="btn-recovery-link" onClick={switchToLogin}>Voltar para entrar</button>
          </form>}

          {mode === 'recovery-code' && <div className="recovery-result">
            <p>{oneTimeCodeOrigin === 'legacy-login' ? 'A recuperação desta conta antiga foi ativada. Este código será mostrado somente agora.' : 'O código antigo foi invalidado. Este novo código será mostrado somente agora.'}</p>
            <div className="lock-recovery-code"><code>{rotatedCode}</code><button type="button" onClick={copyRotatedCode}>{copiedCode ? 'Copiado!' : 'Copiar'}</button></div>
            <label><input type="checkbox" checked={recoverySaved} onChange={(event) => setRecoverySaved(event.target.checked)} /><span><strong>Confirmei que salvei o novo código</strong><small>Guarde-o fora deste computador.</small></span></label>
            {error && <Alert tone="error">{error}</Alert>}
            <button type="button" className="btn-primary-gradient" disabled={!recoverySaved} onClick={finishRecovery}>Entrar no CloudOS</button>
          </div>}

          {isDevEnvironment && mode === 'login' && <div className="advanced-options-container"><button type="button" className="btn-toggle-advanced" onClick={() => setShowAdvanced(!showAdvanced)}>Opções avançadas</button>{showAdvanced && <div className="advanced-panel"><button type="button" className="btn-dev-reset" onClick={handleResetDev} disabled={loading}>Redefinir instalação local (Dev)</button></div>}</div>}
        </div>
      </div>}
      {!showPanel && <div className="lock-hint">Clique ou pressione qualquer tecla para entrar</div>}
    </div>
  );
}

function FormField({ id, label, type = 'text', value, onChange, autoComplete, monospace = false }: { id: string; label: string; type?: string; value: string; onChange: (value: string) => void; autoComplete: string; monospace?: boolean }) {
  return <label className="form-group" htmlFor={id}><span className="form-label">{label}</span><input id={id} className={`form-input no-icon${monospace ? ' monospace' : ''}`} type={type} value={value} onChange={(event) => onChange(event.target.value)} autoComplete={autoComplete} maxLength={type === 'password' ? 128 : 80} disabled={false} /></label>;
}

function Alert({ tone, children }: { tone: 'error' | 'success'; children: React.ReactNode }) {
  return <div className={`alert-box alert-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>{children}</div>;
}
