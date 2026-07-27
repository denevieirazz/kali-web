import { useState, useEffect, useRef } from 'react';

const bootSequence = [
  { text: "CLOUDOS BIOS v2.1.7 - Copyright (C) 2024 Red Team Systems", color: "#94a3b8" },
  { text: "CPU: AMD Ryzen 7 5700G | ARCH: x86_64 | CORES: 8", color: "#94a3b8" },
  { text: "Memory Test: 32768M OK", color: "#94a3b8" },
  { text: "Initializing Quantum Cryptography Module... [ OK ]", color: "#4ade80" },
  { text: "Mounting WSL 2 Kali Linux Subsystem (ext4)... [ OK ]", color: "#4ade80" },
  { text: "Starting Docker Engine Proxy... [ OK ]", color: "#4ade80" },
  { text: "Establishing Tor Circuit (Routing via 5 hops)... [ OK ]", color: "#4ade80" },
  { text: "Spoofing MAC Address: 00:1A:2B:3C:4D:5E... [ OK ]", color: "#4ade80" },
  { text: "Loading Kernel Modules: netfilter, pcap, usbip... [ OK ]", color: "#4ade80" },
  { text: "Syncing /root directory with Virtual FS... [ OK ]", color: "#4ade80" },
  { text: "WARNING: Unauthorized access is strictly prohibited.", color: "#fbbf24" },
  { text: "Bypassing Firewall Rules... [ OK ]", color: "#4ade80" },
  { text: "Starting CloudOS Desktop Environment (Wayland)...", color: "#60a5fa" },
  { text: "Welcome to CloudOS. Access Granted.", color: "#60a5fa" }
];

export default function BootScreen({ onBootComplete }) {
  const [logs, setLogs] = useState([]);
  const [progress, setProgress] = useState(0);
  const [glitching, setGlitching] = useState(true);
  const completedRef = useRef(false);
  const intervalRef = useRef(null);

  useEffect(() => {
    let i = 0;
    
    if (intervalRef.current) clearInterval(intervalRef.current);

    intervalRef.current = setInterval(() => {
      if (i < bootSequence.length) {
        const currentLog = bootSequence[i];
        if (currentLog) {
          setLogs(prev => [...prev, currentLog]);
          setProgress(Math.round(((i + 1) / bootSequence.length) * 100));
        }
        i++;
      } else {
        clearInterval(intervalRef.current);
        if (!completedRef.current) {
          completedRef.current = true;
          setGlitching(false);
          setTimeout(() => onBootComplete(), 1800);
        }
      }
    }, 220);

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [onBootComplete]);

  return (
    <div className="boot-cinema">
      <div className="boot-scanlines"></div>
      <div className="boot-content">
        <div className={`boot-logo-cinema ${glitching ? 'glitch' : ''}`} data-text="CLOUDOS">
          CLOUDOS
        </div>
        
        <div className="boot-terminal-cinema">
          {logs.map((log, i) => {
            if (!log) return null;
            return (
              <div 
                key={i} 
                className="boot-line-cinema" 
                style={{ color: log.color || '#fff', animationDelay: `${i * 0.05}s` }}
              >
                <span className="boot-prompt">[{ String(i + 1).padStart(2, '0') }]</span> {log.text}
              </div>
            );
          })}
        </div>

        <div className="boot-loader">
          <div className="boot-progress-shell">
            <div className="boot-progress-fill" style={{ width: `${progress}%` }}></div>
          </div>
          <div className="boot-percent">{progress}%</div>
        </div>
      </div>
    </div>
  );
}
