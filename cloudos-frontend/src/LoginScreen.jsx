import { useState, useEffect } from 'react';
import { User, Lock, ArrowRight, Power } from 'lucide-react';

export default function LoginScreen({ onLogin }) {
  const [time, setTime] = useState(new Date());
  const [showLogin, setShowLogin] = useState(false);
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // Ler usuario salvo do instalador (se houver)
    const savedUser = localStorage.getItem('cloudos_username');
    if (savedUser) setUsername(savedUser);
  }, []);

  const handleLogin = (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    
    // Tentar login no backend via API
    fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    })
      .then(res => res.json())
      .then(data => {
        if (data.token) {
          localStorage.setItem('cloudos_token', data.token);
          onLogin();
        } else {
          // Entrar diretamente no sistema (Auto-Login / Modo Convidado)
          localStorage.setItem('cloudos_token', 'session_active_' + Date.now());
          onLogin();
        }
      })
      .catch(() => {
        // Se o backend nao responder, faz login direto sem travar o usuario
        localStorage.setItem('cloudos_token', 'session_active_' + Date.now());
        onLogin();
      });
  };

  return (
    <div className={`login-screen ${showLogin ? 'show-login' : ''}`} onClick={() => !showLogin && setShowLogin(true)}>
      {!showLogin ? (
        <div className="lock-screen-info">
          <div className="lock-time">{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>
          <div className="lock-date">{time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
          <div className="lock-hint">Clique em qualquer lugar para acessar a Área de Trabalho</div>
        </div>
      ) : (
        <div className="login-box" onClick={(e) => e.stopPropagation()}>
          <div className="login-avatar">
            <User size={48} color="white" />
          </div>
          <div className="login-name">{username || 'Operador CloudOS'}</div>
          <form onSubmit={handleLogin} className="login-form">
            <div className="login-input-group">
              <User size={16} className="login-icon" />
              <input 
                type="text" 
                placeholder="Usuário" 
                value={username} 
                onChange={(e) => setUsername(e.target.value)} 
              />
            </div>
            <div className="login-input-group">
              <Lock size={16} className="login-icon" />
              <input 
                type="password" 
                placeholder="Senha (ou pressione Enter)" 
                value={password} 
                onChange={(e) => setPassword(e.target.value)} 
                autoFocus 
              />
              <button type="submit" className="login-submit-btn" disabled={loading}>
                <ArrowRight size={18} />
              </button>
            </div>
            {error && <div className="login-error">{error}</div>}
            {loading && <div className="login-loading">Acessando sistema...</div>}
          </form>
          <button 
            type="button" 
            style={{ marginTop: '12px', background: 'transparent', border: '1px solid rgba(255,255,255,0.2)', color: '#a0aec0', padding: '6px 14px', borderRadius: '6px', cursor: 'pointer', fontSize: '12px' }}
            onClick={() => {
              localStorage.setItem('cloudos_token', 'session_active_' + Date.now());
              onLogin();
            }}
          >
            ⚡ Entrar no CloudOS (Modo Direto)
          </button>
        </div>
      )}
      <div className="login-power-btn" onClick={(e) => { e.stopPropagation(); setShowLogin(false); }}>
        <Power size={20} />
      </div>
    </div>
  );
}
