import { useEffect, useState, useRef } from 'react';
import { useSystem } from '../../stores/systemStore';
import kernel from '../../core/kernel';
import './Boot.css';

export default function BootScreen() {
  const { bootPhase, setBootPhase } = useSystem();
  const [logs, setLogs] = useState<string[]>([]);
  const [showLogo, setShowLogo] = useState(false);
  const [kernelPhase, setKernelPhase] = useState<string>('OFF');
  const logEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Only run this once when the component mounts and the system is off
    if (bootPhase !== 'off') return;
    
    // Reset local state in case of reboot
    setKernelPhase('OFF');
    setLogs([]);
    setShowLogo(false);
    
    // Subscribe to kernel events
    const unsubscribePhase = kernel.on('bootPhaseChange', (phase: string) => {
      setKernelPhase(phase);
    });

    const unsubscribeLog = kernel.on('bootLog', (msg: string) => {
      setLogs(prev => [...prev.slice(-40), msg]);
      if (logEndRef.current) {
        logEndRef.current.scrollIntoView({ behavior: 'smooth' });
      }
    });

    const onBootFinished = async () => {
      // Transition to graphical boot
      setShowLogo(true);
      // Let user see the logo for a bit
      await new Promise(r => setTimeout(r, 2000));
      // Load shell (Kernel will emit the correct next boot phase: setup or login)
      await kernel.loadShell();
    };

    const runBoot = async () => {
      // Small visual delay before BIOS POST
      await new Promise(r => setTimeout(r, 500));

      // If boot already finished (e.g. StrictMode remount), run directly
      if (kernel.isBootFinished) {
        onBootFinished();
        return;
      }

      // Register listener BEFORE powerOn to avoid race condition
      kernel.once('boot:finished', onBootFinished);

      // Only trigger powerOn if not already booting
      if (!kernel.isBooting) {
        kernel.powerOn();
      }
    };

    runBoot();

    return () => {
      unsubscribePhase();
      unsubscribeLog();
    };
  }, [bootPhase, setBootPhase]);

  // Determine if we are showing text logs or graphical logo
  const isGraphicalPhase = showLogo || ['WINLOGON', 'SHELL_INIT', 'DESKTOP_READY'].includes(kernelPhase);

  return (
    <div className={`boot-screen ${!isGraphicalPhase ? 'text-mode' : ''}`}>
      {!isGraphicalPhase ? (
        <div className="boot-terminal-log">
          <div>ObsidianOS(TM) BIOS POST v1.0.4</div>
          <div>Copyright (C) Obsidian Corporation</div>
          <br/>
          {logs.map((log, i) => (
            <div key={i} className="boot-log-line">{log}</div>
          ))}
          <div ref={logEndRef} />
        </div>
      ) : (
        <div className="boot-content">
          {/* Logo */}
          <div className="boot-logo visible">
            <div className="boot-logo-icon">
              <svg viewBox="0 0 88 88" fill="none" xmlns="http://www.w3.org/2000/svg">
                <rect x="2" y="2" width="38" height="38" rx="4" fill="#6366f1" opacity="0.9"/>
                <rect x="48" y="2" width="38" height="38" rx="4" fill="#818cf8" opacity="0.8"/>
                <rect x="2" y="48" width="38" height="38" rx="4" fill="#818cf8" opacity="0.8"/>
                <rect x="48" y="48" width="38" height="38" rx="4" fill="#a5b4fc" opacity="0.7"/>
              </svg>
            </div>
            <span className="boot-logo-text">ObsidianOS</span>
          </div>

          {/* Loading Spinner */}
          <div className="boot-spinner">
            <div className="spinner-ring">
              <div className="spinner-dot" style={{ '--i': 0 } as React.CSSProperties}></div>
              <div className="spinner-dot" style={{ '--i': 1 } as React.CSSProperties}></div>
              <div className="spinner-dot" style={{ '--i': 2 } as React.CSSProperties}></div>
              <div className="spinner-dot" style={{ '--i': 3 } as React.CSSProperties}></div>
              <div className="spinner-dot" style={{ '--i': 4 } as React.CSSProperties}></div>
            </div>
          </div>
          
          <div className="boot-status">
            Iniciando serviços...
          </div>
        </div>
      )}
    </div>
  );
}
