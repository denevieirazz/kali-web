import { useEffect, useRef, useState } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import { validateDisplayName, validateNewPassword, validateUsername } from '../../services/accountContract.js';
import kernel from '../../core/kernel';
import './LockScreen.css';

type PanelMode = 'login' | 'create-account' | 'recovery' | 'recovery-code';
type CreateAccountStage = 'authorize' | 'details';
type OneTimeCodeOrigin = 'legacy-login' | 'recovery-reset' | 'account-creation';

export default function LockScreen() {
  const { bootPhase, unlock } = useSystem();
  const {
    currentUser,
    setupStatus,
    setupStatusMessage,
    recoveryAvailable,
    recoveryStatusMessage,
    login,
    createAccount,
    recoverAccount,
    checkSetupStatus,
    checkRecoveryStatus,
    confirmRecoveryCodeSaved,
    logout,
    resetLocalInstallation
  } = useUserStore();
  const [showPanel, setShowPanel] = useState(false);
  const [mode, setMode] = useState<PanelMode>('login');
  const [createAccountStage, setCreateAccountStage] = useState<CreateAccountStage>('authorize');
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [rotatedCode, setRotatedCode] = useState<string | null>(null);
  const [oneTimeCodeOrigin, setOneTimeCodeOrigin] = useState<OneTimeCodeOrigin>('recovery-reset');
  const [recoverySaved, setRecoverySaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [time, setTime] = useState(new Date());
  const [isUnlocking, setIsUnlocking] = useState(false);
  const [loading, setLoading] = useState(false);
  const [checkingRecovery, setCheckingRecovery] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const recoveryCheckInFlight = useRef(false);
  const isDevEnvironment = import.meta.env.DEV || import.meta.env.MODE === 'development';

  useEffect(() => {
    const timer = window.setInterval(() => setTime(new Date()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (showPanel) return;
    const revealLogin = (event: KeyboardEvent) => {
      if (event.ctrlKey || event.altKey || event.metaKey) return;
      setShowPanel(true);
    };
    window.addEventListener('keydown', revealLogin);
    return () => window.removeEventListener('keydown', revealLogin);
  }, [showPanel]);

  useEffect(() => {
    if (setupStatus === 'checking') void checkSetupStatus();
  }, [checkSetupStatus, setupStatus]);

  useEffect(() => {
    if (bootPhase === 'login' && setupStatus === 'required') kernel.bootPhase = 'OOBE';
  }, [bootPhase, setupStatus]);

  useEffect(() => {
    if (setupStatus === 'complete' && mode === 'login' && recoveryAvailable === null && !recoveryStatusMessage && !recoveryCheckInFlight.current) {
      recoveryCheckInFlight.current = true;
      void checkRecoveryStatus().finally(() => { recoveryCheckInFlight.current = false; });
    }
  }, [checkRecoveryStatus, mode, recoveryAvailable, recoveryStatusMessage, setupStatus]);

  useEffect(() => {
    if (mode === 'create-account') return;
    if (currentUser?.username && !username) setUsername(currentUser.username);
    if (currentUser?.displayName && !displayName) setDisplayName(currentUser.displayName);
  }, [currentUser, displayName, mode, username]);

  if (bootPhase !== 'login') return null;

  const hours = time.getHours().toString().padStart(2, '0');
  const minutes = time.getMinutes().toString().padStart(2, '0');
  const dateStr = time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });

  function resetMessages() {
    setError(null);
    setSuccessMsg(null);
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
    if (!recoveryCode.trim()) return setError('Informe o código de recuperação.');
    const validation = validateUsername(username) || validateDisplayName(displayName) || validateNewPassword(password, confirmPassword);
    if (validation) return setError(validation);
    setLoading(true);
    const result = await recoverAccount(recoveryCode, username.trim(), displayName.trim(), password, confirmPassword);
    setLoading(false);
    setPassword('');
    setConfirmPassword('');
    setRecoveryCode('');
    if (!result.success || !result.recoveryCode) return setError(result.message || 'Não foi possível recuperar a conta.');
    setRotatedCode(result.recoveryCode);
    setOneTimeCodeOrigin('recovery-reset');
    setRecoverySaved(false);
    setMode('recovery-code');
  }

  function openCreateAccount() {
    resetMessages();
    setMode('create-account');
    setCreateAccountStage('authorize');
    setUsername('');
    setDisplayName('');
    setPassword('');
    setConfirmPassword('');
  }

  async function handleAuthorizeAccountCreation(event: React.FormEvent) {
    event.preventDefault();
    resetMessages();
    const usernameError = validateUsername(username);
    if (usernameError || !password) return setError(usernameError || 'Informe a senha do administrador.');
    setLoading(true);
    const result = await login(username.trim(), password);
    setLoading(false);
    setPassword('');
    if (!result.success) return setError(result.message || 'Não foi possível autorizar a criação da conta.');
    if (useUserStore.getState().currentUser?.isAdmin !== true) {
      await logout();
      return setError('A criação de contas exige uma conta administradora do CloudOS.');
    }
    if (result.recoveryCode) {
      setRotatedCode(result.recoveryCode);
      setOneTimeCodeOrigin('account-creation');
      setRecoverySaved(false);
      setMode('recovery-code');
      return;
    }
    setUsername('');
    setDisplayName('');
    setConfirmPassword('');
    setCreateAccountStage('details');
    setSuccessMsg('Administrador confirmado. Agora informe os dados da nova conta.');
  }

  async function handleCreateAccount(event: React.FormEvent) {
    event.preventDefault();
    resetMessages();
    const validation = validateUsername(username) || validateDisplayName(displayName) || validateNewPassword(password, confirmPassword);
    if (validation) return setError(validation);
    const newUsername = username.trim();
    setLoading(true);
    const result = await createAccount(newUsername, displayName.trim(), password, confirmPassword);
    if (result.success) await logout();
    setLoading(false);
    setPassword('');
    setConfirmPassword('');
    if (!result.success) return setError(result.message || 'Não foi possível criar a conta.');
    setMode('login');
    setCreateAccountStage('authorize');
    setUsername(newUsername);
    setDisplayName('');
    setSuccessMsg('Conta criada. Entre com a senha que você acabou de definir.');
  }

  async function cancelCreateAccount() {
    if (createAccountStage === 'details' && useUserStore.getState().isAuthenticated) await logout();
    resetMessages();
    setMode('login');
    setCreateAccountStage('authorize');
    setUsername('');
    setDisplayName('');
    setPassword('');
    setConfirmPassword('');
  }

  function finishRecovery() {
    if (!recoverySaved) return;
    confirmRecoveryCodeSaved();
    setRotatedCode(null);
    setRecoverySaved(false);
    if (oneTimeCodeOrigin === 'account-creation') {
      setMode('create-account');
      setCreateAccountStage('details');
      setUsername('');
      setDisplayName('');
      setPassword('');
      setConfirmPassword('');
      setSuccessMsg('Código confirmado. Agora informe os dados da nova conta.');
      return;
    }
    setSuccessMsg('Conta recuperada. Abrindo o CloudOS…');
    setIsUnlocking(true);
    window.setTimeout(() => unlock(), 650);
  }

  async function copyRotatedCode() {
    if (!rotatedCode) return;
    try { await navigator.clipboard.writeText(rotatedCode); }
    catch { setError('Selecione e salve o código manualmente.'); }
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

  async function openRecovery() {
    setShowPanel(true);
    resetMessages();
    setPassword('');
    setConfirmPassword('');
    if (setupStatus !== 'complete') return;

    let available = recoveryAvailable;
    if (available !== true) {
      setCheckingRecovery(true);
      recoveryCheckInFlight.current = true;
      available = await checkRecoveryStatus();
      recoveryCheckInFlight.current = false;
      setCheckingRecovery(false);
    }

    if (available === true) {
      setMode('recovery');
      return;
    }

    if (available === false) {
      setError('A recuperação ainda não foi ativada nesta conta. Em contas antigas, entre uma vez com a senha atual para receber e salvar o primeiro código.');
      return;
    }
    setError('Não foi possível consultar a recuperação agora. Verifique o agente local e tente novamente.');
  }

  const title = mode === 'recovery'
    ? 'Recuperar conta'
    : mode === 'recovery-code'
      ? 'Novo código de recuperação'
      : mode === 'create-account'
        ? 'Criar outra conta'
        : 'Bem-vindo ao CloudOS';
  const subtitle = mode === 'login'
    ? 'Entre com sua conta local'
    : mode === 'recovery'
      ? 'Redefina a conta com segurança'
      : mode === 'create-account'
        ? createAccountStage === 'authorize' ? 'Confirme um administrador' : 'Dados da nova conta local'
        : 'Etapa única e obrigatória de segurança';

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
            <FormField id="login-username" label="Nome de usuário" value={username} onChange={setUsername} autoComplete="username" autoFocus />
            <FormField id="login-password" label="Senha" type="password" value={password} onChange={setPassword} autoComplete="current-password" />
            {error && <Alert tone="error">{error}</Alert>}{successMsg && <Alert tone="success">{successMsg}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Entrando…' : 'Entrar'}</button>
            <button type="button" className="btn-recovery-link" disabled={loading} onClick={openCreateAccount}>Criar outra conta</button>
            <button
              type="button"
              className="btn-recovery-link"
              disabled={loading || checkingRecovery}
              onClick={() => void openRecovery()}
            >
              {checkingRecovery ? 'Verificando recuperação…' : 'Esqueci minha conta ou senha'}
            </button>
            {recoveryAvailable === null && !recoveryStatusMessage && <div className="lock-recovery-status" role="status">Verificando se esta conta já possui recuperação…</div>}
            {recoveryAvailable === false && <div className="lock-recovery-unavailable" role="status">Esta conta antiga ainda não possui um código. Entre uma vez com a senha e salve o código que será mostrado antes de acessar o desktop.</div>}
            {recoveryStatusMessage && <div className="lock-recovery-unavailable error" role="alert"><span>Não foi possível verificar se a recuperação está disponível.</span><button type="button" onClick={refreshRecoveryStatus}>Tentar novamente</button></div>}
          </form>}

          {setupStatus === 'complete' && mode === 'create-account' && createAccountStage === 'authorize' && <form onSubmit={handleAuthorizeAccountCreation} className="card-form" noValidate>
            <p className="recovery-explanation">Para impedir cadastros anônimos, confirme primeiro o nome de usuário e a senha de um administrador. O desktop continuará bloqueado.</p>
            <FormField id="create-admin-username" label="Administrador" value={username} onChange={setUsername} autoComplete="username" autoFocus />
            <FormField id="create-admin-password" label="Senha do administrador" type="password" value={password} onChange={setPassword} autoComplete="current-password" />
            {error && <Alert tone="error">{error}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Confirmando…' : 'Autorizar criação'}</button>
            <button type="button" className="btn-recovery-link" disabled={loading} onClick={() => void cancelCreateAccount()}>Voltar para entrar</button>
          </form>}

          {setupStatus === 'complete' && mode === 'create-account' && createAccountStage === 'details' && <form onSubmit={handleCreateAccount} className="card-form recovery-form" noValidate>
            <div className="lock-security-step" role="status"><strong>Administrador confirmado</strong><span>A nova conta será comum e não poderá criar outras contas.</span></div>
            <FormField id="create-username" label="Nome de usuário" value={username} onChange={setUsername} autoComplete="username" autoFocus />
            <FormField id="create-display-name" label="Nome de exibição" value={displayName} onChange={setDisplayName} autoComplete="name" />
            <div className="recovery-password-grid"><FormField id="create-password" label="Senha" type="password" value={password} onChange={setPassword} autoComplete="new-password" /><FormField id="create-confirm" label="Confirmar senha" type="password" value={confirmPassword} onChange={setConfirmPassword} autoComplete="new-password" /></div>
            <small className="recovery-password-hint">Use de 10 a 128 caracteres.</small>
            {error && <Alert tone="error">{error}</Alert>}{successMsg && <Alert tone="success">{successMsg}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Criando…' : 'Criar conta local'}</button>
            <button type="button" className="btn-recovery-link" disabled={loading} onClick={() => void cancelCreateAccount()}>Cancelar</button>
          </form>}

          {setupStatus === 'complete' && recoveryAvailable === true && mode === 'recovery' && <form onSubmit={handleRecovery} className="card-form recovery-form" noValidate>
            <p className="recovery-explanation">Use o código salvo no primeiro acesso. Se ele for válido, a senha e o nome de usuário serão substituídos e um novo código será gerado.</p>
            <FormField id="recovery-code" label="Código de recuperação" value={recoveryCode} onChange={setRecoveryCode} autoComplete="off" monospace autoFocus />
            <FormField id="recovery-username" label="Novo nome de usuário" value={username} onChange={setUsername} autoComplete="username" />
            <FormField id="recovery-display-name" label="Nome de exibição" value={displayName} onChange={setDisplayName} autoComplete="name" />
            <div className="recovery-password-grid"><FormField id="recovery-password" label="Nova senha" type="password" value={password} onChange={setPassword} autoComplete="new-password" /><FormField id="recovery-confirm" label="Confirmar senha" type="password" value={confirmPassword} onChange={setConfirmPassword} autoComplete="new-password" /></div>
            <small className="recovery-password-hint">Use de 10 a 128 caracteres. Uma frase-senha longa também é aceita.</small>
            {error && <Alert tone="error">{error}</Alert>}
            <button type="submit" className="btn-primary-gradient" disabled={loading}>{loading ? 'Recuperando…' : 'Recuperar conta'}</button>
            <button type="button" className="btn-recovery-link" onClick={() => { resetMessages(); setPassword(''); setConfirmPassword(''); setRecoveryCode(''); setMode('login'); }}>Voltar para entrar</button>
          </form>}

          {mode === 'recovery-code' && <div className="recovery-result">
            <div className="lock-mandatory-step" role="status"><strong>Sua senha foi aceita</strong><span>Esta etapa acontece uma única vez em contas administradoras antigas. O CloudOS não travou.</span></div>
            <p>{oneTimeCodeOrigin === 'recovery-reset' ? 'O código antigo foi invalidado. Este novo código será mostrado somente agora.' : 'A recuperação desta conta antiga foi ativada. Este código será mostrado somente agora.'}</p>
            <div className="lock-recovery-code"><code>{rotatedCode}</code><button type="button" onClick={copyRotatedCode}>Copiar</button></div>
            <label><input type="checkbox" checked={recoverySaved} onChange={(event) => setRecoverySaved(event.target.checked)} /><span><strong>Confirmei que salvei o novo código</strong><small>Guarde-o fora deste computador.</small></span></label>
            {error && <Alert tone="error">{error}</Alert>}
            <button type="button" className="btn-primary-gradient" disabled={!recoverySaved} onClick={finishRecovery}>{oneTimeCodeOrigin === 'account-creation' ? 'Continuar criação da conta' : 'Entrar no CloudOS'}</button>
          </div>}

          {isDevEnvironment && mode === 'login' && <div className="advanced-options-container"><button type="button" className="btn-toggle-advanced" onClick={() => setShowAdvanced(!showAdvanced)}>Opções avançadas</button>{showAdvanced && <div className="advanced-panel"><button type="button" className="btn-dev-reset" onClick={handleResetDev} disabled={loading}>Redefinir instalação local (Dev)</button></div>}</div>}
        </div>
      </div>}
      {!showPanel && <div className="lock-entry-actions">
        <button type="button" className="lock-entry-primary" onClick={() => setShowPanel(true)}>Entrar</button>
        <button type="button" className="lock-entry-recovery" onClick={() => void openRecovery()}>Esqueci minha conta ou senha</button>
        <span>Clique ou pressione qualquer tecla para continuar</span>
      </div>}
    </div>
  );
}

function FormField({ id, label, type = 'text', value, onChange, autoComplete, monospace = false, autoFocus = false }: { id: string; label: string; type?: string; value: string; onChange: (value: string) => void; autoComplete: string; monospace?: boolean; autoFocus?: boolean }) {
  return <label className="form-group" htmlFor={id}><span className="form-label">{label}</span><input id={id} className={`form-input no-icon${monospace ? ' monospace' : ''}`} type={type} value={value} onChange={(event) => onChange(event.target.value)} autoComplete={autoComplete} maxLength={type === 'password' ? 128 : 80} autoFocus={autoFocus} /></label>;
}

function Alert({ tone, children }: { tone: 'error' | 'success'; children: React.ReactNode }) {
  return <div className={`alert-box alert-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>{children}</div>;
}
