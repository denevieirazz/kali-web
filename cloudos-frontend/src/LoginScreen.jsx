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
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  const handleLogin = (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    
    fetch('http://localhost:8080/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) {
          setError(data.error);
          setLoading(false);
        } else {
          localStorage.setItem('cloudos_token', data.token);
          onLogin();
        }
      })
      .catch(() => {
        setError('Erro de conexão com o Backend.');
        setLoading(false);
      });
  };

  return (
    <div className={`login-screen ${showLogin ? 'show-login' : ''}`} onClick={() => !showLogin && setShowLogin(true)}>
      {!showLogin ? (
        <div className="lock-screen-info">
          <div className="lock-time">{time.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</div>
          <div className="lock-date">{time.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</div>
          <div className="lock-hint">Clique em qualquer lugar para logar</div>
        </div>
      ) : (
        <div className="login-box" onClick={(e) => e.stopPropagation()}>
          <div className="login-avatar">
            <User size={48} color="white" />
          </div>
          <div className="login-name">Admin</div>
          <form onSubmit={handleLogin} className="login-form">
            <div className="login-input-group">
              <User size={16} className="login-icon" />
              <input 
                type="text" 
                placeholder="Usuário" 
                value={username} 
                onChange={(e) => setUsername(e.target.value)} 
                readOnly 
              />
            </div>
            <div className="login-input-group">
              <Lock size={16} className="login-icon" />
              <input 
                type="password" 
                placeholder="Senha" 
                value={password} 
                onChange={(e) => setPassword(e.target.value)} 
                autoFocus 
              />
              <button type="submit" className="login-submit-btn" disabled={loading}>
                <ArrowRight size={18} />
              </button>
            </div>
            {error && <div className="login-error">{error}</div>}
            {loading && <div className="login-loading">Autenticando...</div>}
          </form>
          <div className="login-hint-bottom">Senha padrão: admin123</div>
        </div>
      )}
      <div className="login-power-btn" onClick={(e) => { e.stopPropagation(); setShowLogin(false); }}>
        <Power size={20} />
      </div>
    </div>
  );
}
