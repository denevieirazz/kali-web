import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import { validateDisplayName, validateNewPassword, validateUsername } from '../../services/accountContract.js';
import kernel from '../../core/kernel';
import './SetupWizard.css';

type Step = 'welcome' | 'account' | 'theme' | 'recovery';
const STEPS: Step[] = ['welcome', 'account', 'theme', 'recovery'];

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
  const completedSetupHandoff = useRef(false);
  const createdAccountInThisFlow = useRef(false);
  const { setTheme } = useSystem();
  const { createAdmin, checkSetupStatus, confirmRecoveryCodeSaved, setupStatus, setupStatusMessage } = useUserStore();

  useEffect(() => {
    if (setupStatus === 'checking') void checkSetupStatus();
  }, [checkSetupStatus, setupStatus]);

  useEffect(() => {
    if (setupStatus !== 'complete' || createdAccountInThisFlow.current || completedSetupHandoff.current) return;
    completedSetupHandoff.current = true;
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    kernel.bootPhase = 'WINLOGON';
  }, [setupStatus]);

  const currentIndex = STEPS.indexOf(step);

  function goNext() {
    setError(null);
    if (step === 'welcome') return setStep('account');
    if (step === 'account') {
      const validation = validateDisplayName(displayName) || validateUsername(username) || validateNewPassword(password, confirmPassword);
      if (validation) return setError(validation);
      return setStep('theme');
    }
    if (step === 'theme') void createRealAccount();
  }

  async function createRealAccount() {
    if (loading) return;
    // Prevent the setup-status update produced by our own successful request
    // from being mistaken for an administrator that existed before this OOBE.
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
      if (refreshedStatus !== 'complete') {
        setError(result.message || 'Não foi possível criar a conta no agente local.');
      }
      return;
    }
    setLoading(false);
    setTheme({ accentColor });
    setRecoveryCode(result.recoveryCode);
    setRecoverySaved(false);
    setStep('recovery');
  }

  function finishSetup() {
    if (!recoveryCode || !recoverySaved) return;
    kernel.sysCreateUserHome(username.trim());
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    confirmRecoveryCodeSaved();
    setRecoveryCode(null);
    setRecoverySaved(false);
    useSystem.getState().unlock();
  }

  async function copyRecoveryCode() {
    if (!recoveryCode) return;
    try {
      await navigator.clipboard.writeText(recoveryCode);
    } catch {
      setError('Não foi possível copiar. Selecione o código e salve-o manualmente.');
    }
  }

  const unavailable = setupStatus === 'unavailable';

  return (
    <div className="setup-wizard">
      <div className="setup-bg-decorator" style={{ top: '-10%', right: '-10%' }} />
      <div className="setup-bg-decorator" style={{ bottom: '-10%', left: '-10%', background: 'radial-gradient(circle, var(--accent) 0%, transparent 70%)' }} />
      <motion.div initial={{ scale: .96, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="setup-container">
        <aside className="setup-left">
          <div className="setup-cloud-mark">C</div>
          <h2>CloudOS</h2>
          <p>{step === 'welcome' && 'Configure uma conta real protegida pelo agente local.'}{step === 'account' && 'Sua senha é enviada ao agente apenas para ser derivada e nunca é salva nesta interface.'}{step === 'theme' && 'Personalize o ambiente antes de concluir a criação.'}{step === 'recovery' && 'Este código é a única forma de recuperar a conta sem a senha.'}</p>
          <div className="setup-security-note"><strong>Conta local real</strong><span>Credenciais não ficam no navegador, kernel ou sistema de arquivos virtual.</span></div>
        </aside>

        <main className="setup-right">
          <div className="setup-step-indicator" aria-label={`Etapa ${currentIndex + 1} de ${STEPS.length}`}>
            {STEPS.map((item) => <div key={item} className={`step-dot ${item === step ? 'active' : ''}`} />)}
          </div>

          <div className="setup-content">
            <AnimatePresence mode="wait">
              {unavailable ? (
                <motion.section key="unavailable" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
                  <span className="setup-kicker">AGENTE INDISPONÍVEL</span>
                  <h1 className="setup-title">Não foi possível verificar a instalação</h1>
                  <p className="setup-description">O CloudOS não vai presumir que o primeiro acesso está livre. Reconecte o agente local para consultar o estado real.</p>
                  {setupStatusMessage && <div className="setup-alert error">{setupStatusMessage}</div>}
                  <button className="setup-btn setup-btn-primary inline" onClick={() => checkSetupStatus()}>Tentar novamente</button>
                </motion.section>
              ) : step === 'welcome' ? (
                <motion.section key="welcome" className="setup-step" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}>
                  <span className="setup-kicker">PRIMEIRO ACESSO</span>
                  <h1 className="setup-title">Sua conta começa aqui.</h1>
                  <p className="setup-description">Crie a conta administradora do CloudOS e receba uma chave de recuperação mostrada uma única vez.</p>
                  <ul className="setup-feature-list"><li>Senha armazenada somente como hash no agente</li><li>Sessão autenticada para recursos do computador</li><li>Código rotacionado depois de cada recuperação</li></ul>
                </motion.section>
              ) : step === 'account' ? (
                <motion.form key="account" className="setup-form" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }} onSubmit={(event: React.FormEvent<HTMLFormElement>) => { event.preventDefault(); goNext(); }}>
                  <span className="setup-kicker">CONTA ADMINISTRADORA</span>
                  <h1 className="setup-title compact">Identifique-se</h1>
                  <label className="setup-field">Nome de exibição<input className="setup-input" value={displayName} onChange={(event) => setDisplayName(event.target.value)} autoComplete="name" maxLength={80} placeholder="Como você quer ser chamado" /></label>
                  <label className="setup-field">Nome de usuário<input className="setup-input" value={username} onChange={(event) => setUsername(event.target.value)} autoComplete="username" maxLength={64} placeholder="exemplo.usuario" /></label>
                  <div className="setup-password-grid">
                    <label className="setup-field">Senha<input type="password" className="setup-input" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" maxLength={128} /></label>
                    <label className="setup-field">Confirmar senha<input type="password" className="setup-input" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} autoComplete="new-password" maxLength={128} /></label>
                  </div>
                  <small className="setup-field-help">Use de 10 a 128 caracteres. Uma frase-senha longa também é aceita.</small>
                  <button type="submit" hidden aria-hidden="true" />
                </motion.form>
              ) : step === 'theme' ? (
                <motion.section key="theme" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}>
                  <span className="setup-kicker">APARÊNCIA</span><h1 className="setup-title compact">Escolha uma cor</h1><p className="setup-description">A conta será criada no agente quando você continuar.</p>
                  <div className="setup-themes">{['#6366f1','#f43f5e','#10b981','#f59e0b','#8b5cf6','#06b6d4'].map((color) => <button type="button" aria-label={`Cor ${color}`} key={color} className={`theme-card ${accentColor === color ? 'selected' : ''}`} onClick={() => setAccentColor(color)}><span className="theme-preview" style={{ background: color }} /><span className="theme-name">{color}</span></button>)}</div>
                </motion.section>
              ) : (
                <motion.section key="recovery" className="setup-step" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
                  <span className="setup-kicker">MOSTRADO UMA ÚNICA VEZ</span><h1 className="setup-title compact">Salve seu código de recuperação</h1><p className="setup-description">Guarde-o fora deste computador. Depois de fechar esta tela, o CloudOS não conseguirá exibi-lo novamente.</p>
                  <div className="setup-recovery-code"><code>{recoveryCode}</code><button type="button" onClick={copyRecoveryCode}>Copiar</button></div>
                  <label className="setup-confirm-save"><input type="checkbox" checked={recoverySaved} onChange={(event) => setRecoverySaved(event.target.checked)} /><span><strong>Confirmei que salvei o código</strong><small>Sem ele, uma senha esquecida não poderá ser redefinida.</small></span></label>
                </motion.section>
              )}
            </AnimatePresence>
            {error && <div className="setup-alert error" role="alert">{error}</div>}
          </div>

          {!unavailable && <footer className="setup-footer">
            {currentIndex > 0 && step !== 'recovery' && <button className="setup-btn setup-btn-secondary" onClick={() => { setError(null); setStep(STEPS[currentIndex - 1]); }}>Voltar</button>}
            {step !== 'recovery' ? <button className="setup-btn setup-btn-primary" onClick={goNext} disabled={loading}>{loading ? 'Criando conta…' : step === 'theme' ? 'Criar conta' : 'Continuar'}</button> : <button className="setup-btn setup-btn-primary" onClick={finishSetup} disabled={!recoverySaved}>Entrar no CloudOS</button>}
          </footer>}
        </main>
      </motion.div>
    </div>
  );
}
