import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useUserStore } from '../../stores/userStore';
import { useSystem } from '../../stores/systemStore';
import kernel from '../../core/kernel';
import './SetupWizard.css';

const steps = [
  { id: 'welcome', title: 'Bem-vindo ao ObsidianOS' },
  { id: 'user', title: 'Quem vai usar este PC?' },
  { id: 'theme', title: 'Personalize seu estilo' },
  { id: 'finalizing', title: 'Quase pronto...' },
];

export default function SetupWizard() {
  const [currentStep, setCurrentStep] = useState(0);
  const { createProfile } = useUserStore();
  const { setTheme } = useSystem();
  
  // Form State
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [accentColor, setAccentColor] = useState('#6366f1');

  const nextStep = () => {
    if (currentStep < steps.length - 1) {
      setCurrentStep(currentStep + 1);
      
      // If moving to the final step, simulate processing and then finish
      if (currentStep + 1 === steps.length - 1) {
        handleFinish();
      }
    }
  };

  const handleFinish = async () => {
    // Simulate setup processing
    await new Promise(r => setTimeout(r, 2500));
    
    // 1. Create the profile data
    const newProfile = {
      username: username || 'User',
      displayName: displayName || username || 'Obsidian User',
      password: password,
      avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${username || 'Admin'}`,
      isAdmin: true,
      lastLogin: Date.now()
    };

    // 2. Create profile and set as current in store
    createProfile(newProfile);
    useUserStore.setState({ currentUser: newProfile, isAuthenticated: false });

    // 3. Update Kernel's user state (This is critical for LockScreen to see the right user)
    (kernel as any)._user = newProfile;
    (kernel as any).sysCreateUserHome(username);
    (kernel as any)._persistSystemState();

    // 4. Set the chosen theme
    setTheme({ accentColor });

    // 5. Mark setup as completed — zero the registry flag so it never shows again
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\SetupInProgress', 'REG_DWORD', 0);
    kernel.regSetValue('HKEY_LOCAL_MACHINE\\SYSTEM\\Setup\\OOBEInProgress', 'REG_DWORD', 0);
    localStorage.setItem('obsidianos-setup-completed', 'true');
    
    // 6. Boot into login
    (kernel as any).bootPhase = 'WINLOGON';
  };

  const renderStep = () => {
    switch (steps[currentStep].id) {
      case 'welcome':
        return (
          <motion.div 
            initial={{ opacity: 0, x: 20 }} 
            animate={{ opacity: 1, x: 0 }} 
            exit={{ opacity: 0, x: -20 }}
            className="setup-step"
          >
            <h1 className="setup-title">Olá, vamos começar.</h1>
            <p className="setup-description" style={{ color: 'var(--text-secondary)', marginBottom: '32px' }}>
              Parabéns por escolher o ObsidianOS. Estamos felizes em ter você aqui.
              Vamos configurar algumas coisas básicas para deixar o sistema pronto para você.
            </p>
            <div className="setup-illustration-small" style={{ fontSize: '48px' }}>✨</div>
          </motion.div>
        );

      case 'user':
        return (
          <motion.div 
            initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}
            className="setup-form"
          >
            <h1 className="setup-title">Sua Conta</h1>
            <div className="setup-field">
              <label>Nome Completo</label>
              <input 
                className="setup-input" 
                placeholder="Ex: João da Silva" 
                value={displayName}
                onChange={e => setDisplayName(e.target.value)}
              />
            </div>
            <div className="setup-field">
              <label>Nome de Usuário</label>
              <input 
                className="setup-input" 
                placeholder="Ex: joao123" 
                value={username}
                onChange={e => setUsername(e.target.value)}
              />
            </div>
            <div className="setup-field">
              <label>Senha (opcional)</label>
              <input 
                type="password" 
                className="setup-input" 
                placeholder="••••••••" 
                value={password}
                onChange={e => setPassword(e.target.value)}
              />
            </div>
          </motion.div>
        );

      case 'theme':
        return (
          <motion.div 
            initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }}
          >
            <h1 className="setup-title">Escolha uma Cor</h1>
            <div className="setup-themes">
              {['#6366f1', '#f43f5e', '#10b981', '#f59e0b', '#8b5cf6', '#06b6d4'].map(color => (
                <div 
                  key={color}
                  className={`theme-card ${accentColor === color ? 'selected' : ''}`}
                  onClick={() => setAccentColor(color)}
                >
                  <div className="theme-preview" style={{ background: color }} />
                  <span className="theme-name">{color}</span>
                </div>
              ))}
            </div>
          </motion.div>
        );

      case 'finalizing':
        return (
          <motion.div 
            initial={{ opacity: 0 }} animate={{ opacity: 1 }}
            className="finalizing-container"
          >
            <div className="loading-spinner" />
            <h1 className="setup-title">Preparando tudo...</h1>
            <p style={{ color: 'var(--text-secondary)' }}>Isso levará apenas alguns segundos. Não desligue o seu PC.</p>
          </motion.div>
        );

      default:
        return null;
    }
  };

  return (
    <div className="setup-wizard">
      <div className="setup-bg-decorator" style={{ top: '-10%', right: '-10%' }} />
      <div className="setup-bg-decorator" style={{ bottom: '-10%', left: '-10%', background: 'radial-gradient(circle, var(--accent) 0%, transparent 70%)' }} />
      
      <motion.div 
        initial={{ scale: 0.9, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="setup-container"
      >
        <div className="setup-left">
          <div className="setup-illustration">
            {currentStep === 0 && '👋'}
            {currentStep === 1 && '👤'}
            {currentStep === 2 && '🎨'}
            {currentStep === 3 && '🚀'}
          </div>
          <h2>Obsidian OS</h2>
          <p>
            {currentStep === 0 && 'Uma experiência fluida, moderna e poderosa direto no seu navegador.'}
            {currentStep === 1 && 'Sua conta será usada para sincronizar arquivos e configurações com o LiveMode.'}
            {currentStep === 2 && 'O sistema se adapta ao seu estilo. Escolha a cor que mais combina com você.'}
            {currentStep === 3 && 'Estamos configurando seu perfil, registro de sistema e área de trabalho.'}
          </p>
        </div>

        <div className="setup-right">
          <div className="setup-step-indicator">
            {steps.map((_, i) => (
              <div key={i} className={`step-dot ${i === currentStep ? 'active' : ''}`} />
            ))}
          </div>

          <div className="setup-content">
            <AnimatePresence mode="wait">
              {renderStep()}
            </AnimatePresence>
          </div>

          {currentStep < steps.length - 1 && (
            <div className="setup-footer">
              {currentStep > 0 && (
                <button className="setup-btn setup-btn-secondary" onClick={() => setCurrentStep(s => s - 1)}>
                  Voltar
                </button>
              )}
              <button 
                className="setup-btn setup-btn-primary" 
                onClick={nextStep}
                disabled={currentStep === 1 && !username}
              >
                Próximo
              </button>
            </div>
          )}
        </div>
      </motion.div>
    </div>
  );
}
