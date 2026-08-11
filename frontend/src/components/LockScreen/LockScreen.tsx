// ============================================
// Lock Screen / Login / Primeiro Acesso — CloudOS-Unified
// ============================================
import { useState, useEffect } from 'react';
import { useSystem } from '../../stores/systemStore';
import { useUserStore } from '../../stores/userStore';
import './LockScreen.css';

export default function LockScreen() {
  const { bootPhase, unlock } = useSystem();
  const { currentUser, setupRequired, login, createAdmin, checkSetupStatus, resetLocalInstallation } = useUserStore();

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [showPanel, setShowPanel] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [time, setTime] = useState(new Date());
  const [isUnlocking, setIsUnlocking] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const isDevEnvironment = import.meta.env.DEV || import.meta.env.MODE === 'development';

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    checkSetupStatus();
  }, [checkSetupStatus]);

  if (bootPhase !== 'login') return null;

  const hours = time.getHours().toString().padStart(2, '0');
  const minutes = time.getMinutes().toString().padStart(2, '0');
  const dateStr = time.toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });

  const handleCreateAdmin = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setError(null);
    setSuccessMsg(null);
    const cleanUser = username.trim();

    // Validações no frontend sem chamar a API desnecessariamente
    if (!cleanUser) {
      setError('Por favor, preencha o nome de usuário.');
      return;
    }
    if (cleanUser.length < 3) {
      setError('O nome de usuário deve conter pelo menos 3 caracteres.');
      return;
    }
    if (!/^[a-zA-Z0-9._-]+$/.test(cleanUser)) {
      setError('O nome de usuário contem caracteres inválidos.');
      return;
    }
    if (!password) {
      setError('Por favor, digite a senha.');
      return;
    }
    if (password.length < 6) {
      setError('A senha deve conter pelo menos 6 caracteres.');
      return;
    }
    if (password !== confirmPassword) {
      setError('A confirmação de senha não confere.');
      return;
    }

    setLoading(true);
    const res = await createAdmin(cleanUser, password, confirmPassword);
    setLoading(false);

    if (res.success) {
      setSuccessMsg('Administrador criado com sucesso! Abrindo o sistema...');
      setIsUnlocking(true);
      setTimeout(() => unlock(), 900);
    } else {
      setError(res.message || 'Falha ao criar a conta de administrador.');
    }
  };

  const handleLogin = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setError(null);
    setSuccessMsg(null);
    const cleanUser = username.trim();

    if (!cleanUser || !password) {
      setError('Preencha os campos de usuário e senha.');
      return;
    }

    setLoading(true);
    const res = await login(cleanUser, password);
    setLoading(false);

    if (res.success) {
      setSuccessMsg('Autenticado com sucesso!');
      setIsUnlocking(true);
      setTimeout(() => unlock(), 800);
    } else {
      setError('Credenciais inválidas.');
      setPassword('');
    }
  };

  const handleResetDev = async () => {
    if (window.confirm('Tem certeza que deseja redefinir a instalação local do CloudOS-Unified? Todo o banco local será zerado.')) {
      setLoading(true);
      const ok = await resetLocalInstallation();
      setLoading(false);
      if (ok) {
        setUsername('');
        setPassword('');
        setConfirmPassword('');
        setError(null);
        setSuccessMsg('Instalação local redefinida com sucesso.');
        setTimeout(() => setSuccessMsg(null), 3000);
      }
    }
  };

  return (
    <div
      className={`cloudos-lock-screen ${isUnlocking ? 'unlocking' : ''}`}
      onClick={() => !showPanel && setShowPanel(true)}
    >
      {/* Luzes de Fundo Tecnológicas em Roxo e Azul */}
      <div className="bg-glow bg-glow-1" />
      <div className="bg-glow bg-glow-2" />
      <div className="bg-glow bg-glow-3" />

      {/* Relógio em Standby */}
      {!showPanel && (
        <div className="lock-time-container">
          <div className="lock-time">{hours}:{minutes}</div>
          <div className="lock-date">{dateStr}</div>
        </div>
      )}

      {/* Moldura Externa Translúcida e Painel Glassmorphism Central */}
      {showPanel && (
        <div className="cloudos-lock-outer-frame" onClick={(e) => e.stopPropagation()}>
          <div className="cloudos-glass-card">
            
            {/* Header: Logo CloudOS, Título e Subtítulo */}
            <div className="card-header">
              <div className="cloudos-brand-logo">
                <svg width="36" height="36" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z" fill="url(#cloudos-grad)" />
                  <defs>
                    <linearGradient id="cloudos-grad" x1="0" y1="4" x2="22" y2="20" gradientUnits="userSpaceOnUse">
                      <stop stopColor="#818cf8" />
                      <stop offset="1" stopColor="#c084fc" />
                    </linearGradient>
                  </defs>
                </svg>
              </div>
              
              <h1 className="card-title">
                {setupRequired ? 'Primeiro Acesso' : 'Bem-vindo ao CloudOS'}
              </h1>
              <p className="card-subtitle">
                {setupRequired ? 'Criar Administrador' : 'Autenticação do Sistema'}
              </p>
            </div>

            {/* Formulário com labels visíveis e navegação por teclado */}
            <form onSubmit={setupRequired ? handleCreateAdmin : handleLogin} className="card-form" noValidate>
              
              {/* Campo: Nome de Usuário */}
              <div className="form-group">
                <label htmlFor="input-username" className="form-label">
                  Nome de usuário
                </label>
                <div className="input-wrapper">
                  <span className="input-icon">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                      <circle cx="12" cy="7" r="4" />
                    </svg>
                  </span>
                  <input
                    id="input-username"
                    type="text"
                    className="form-input"
                    placeholder="Digite o nome de usuário"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    disabled={loading}
                    autoFocus
                    autoComplete="username"
                  />
                </div>
              </div>

              {/* Campo: Senha */}
              <div className="form-group">
                <label htmlFor="input-password" className="form-label">
                  Senha
                </label>
                <div className="input-wrapper">
                  <span className="input-icon">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                    </svg>
                  </span>
                  <input
                    id="input-password"
                    type="password"
                    className="form-input"
                    placeholder="Digite a senha"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    disabled={loading}
                    autoComplete={setupRequired ? 'new-password' : 'current-password'}
                  />
                </div>
              </div>

              {/* Campo: Confirmar Senha (Apenas em Primeiro Acesso) */}
              {setupRequired && (
                <div className="form-group">
                  <label htmlFor="input-confirm-password" className="form-label">
                    Confirmar senha
                  </label>
                  <div className="input-wrapper">
                    <span className="input-icon">
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
                      </svg>
                    </span>
                    <input
                      id="input-confirm-password"
                      type="password"
                      className="form-input"
                      placeholder="Repita a senha para confirmar"
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      disabled={loading}
                      autoComplete="new-password"
                    />
                  </div>
                </div>
              )}

              {/* Caixa de Erro de Validação */}
              {error && (
                <div className="alert-box alert-error" role="alert">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <circle cx="12" cy="12" r="10" />
                    <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                  <span>{error}</span>
                </div>
              )}

              {/* Caixa de Sucesso */}
              {successMsg && (
                <div className="alert-box alert-success" role="status">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                    <polyline points="22 4 12 14.01 9 11.01" />
                  </svg>
                  <span>{successMsg}</span>
                </div>
              )}

              {/* Botão Principal com Gradiente Violeta */}
              <button
                type="submit"
                className={`btn-primary-gradient ${loading ? 'loading' : ''}`}
                disabled={loading}
              >
                {loading ? (
                  <span className="btn-spinner-wrapper">
                    <span className="spinner" />
                    <span>{setupRequired ? 'Criando Administrador...' : 'Entrando...'}</span>
                  </span>
                ) : (
                  <span>{setupRequired ? 'Criar Administrador' : 'Entrar'}</span>
                )}
              </button>
            </form>

            {/* Opções Avançadas para Ambiente de Desenvolvimento */}
            {isDevEnvironment && (
              <div className="advanced-options-container">
                <button
                  type="button"
                  className="btn-toggle-advanced"
                  onClick={() => setShowAdvanced(!showAdvanced)}
                >
                  <span>Opções Avançadas</span>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ transform: showAdvanced ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }}>
                    <polyline points="6 9 12 15 18 9" />
                  </svg>
                </button>

                {showAdvanced && (
                  <div className="advanced-panel">
                    <button
                      type="button"
                      className="btn-dev-reset"
                      onClick={handleResetDev}
                      disabled={loading}
                    >
                      Redefinir instalação local (Dev)
                    </button>
                  </div>
                )}
              </div>
            )}

          </div>
        </div>
      )}

      {/* Rodapé / Dica para entrar */}
      {!showPanel && (
        <div className="lock-hint">
          {setupRequired ? 'Clique para configurar a conta de Administrador' : 'Clique ou pressione qualquer tecla para entrar'}
        </div>
      )}
    </div>
  );
}
