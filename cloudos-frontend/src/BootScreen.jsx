import { useState, useEffect, useRef } from 'react';

const bootLogs = [
  "Booting CloudOS Kernel 6.8.0-kali-cloud...",
  "Initializing Ryzen 7 5700G Architecture...",
  "Mounting WSL Kali Linux Subsystem...",
  "Starting Docker Engine Proxy...",
  "Loading Persistent Virtual File System (ext4)...",
  "Setting up Tmux Sessions for User 'root'...",
  "Initializing Network Interfaces (NET_ADMIN enabled)...",
  "Loading Pentest Tools Module...",
  "Starting CloudOS Desktop Environment...",
  "Welcome to CloudOS. Access granted."
];

export default function BootScreen({ onBootComplete }) {
  const [logs, setLogs] = useState([]);
  const [progress, setProgress] = useState(0);
  const completedRef = useRef(false);

  useEffect(() => {
    let i = 0;
    
    const interval = setInterval(() => {
      if (i < bootLogs.length) {
        setLogs(prev => [...prev, bootLogs[i]]);
        setProgress(((i + 1) / bootLogs.length) * 100);
        i++;
      } else {
        clearInterval(interval);
        if (!completedRef.current) {
          completedRef.current = true;
          setTimeout(() => onBootComplete(), 800);
        }
      }
    }, 180);

    return () => clearInterval(interval);
  }, [onBootComplete]);

  return (
    <div className="boot-screen">
      <div className="boot-logo">CLOUD<span>OS</span></div>
      <div className="boot-terminal">
        {logs.map((log, i) => (
          <div key={i} className="boot-line">
            <span className="boot-ok">[ OK ]</span> {log}
          </div>
        ))}
      </div>
      <div className="boot-progress-bar-container">
        <div className="boot-progress-bar" style={{ width: `${progress}%` }}></div>
      </div>
    </div>
  );
}
