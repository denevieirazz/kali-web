import { useEffect, useRef, useState } from 'react';
import { useFileSystem } from '../../stores/fileSystem';
import kernel, { type BSODInfo } from '../../core/kernel';
import './BSOD.css';

interface BSODProps {
  info: BSODInfo;
}

export default function BSOD({ info }: BSODProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    let isMounted = true;
    let dumped = 0;
    const totalMemoryMB = Math.max(1, kernel.resources.usedMemory);
    const chunkMB = Math.max(0.5, totalMemoryMB / 50);
    const fs = useFileSystem.getState();

    const dumpDir = 'C:\\ObsidianOS\\System32\\Minidump';
    if (!fs.exists(dumpDir)) fs.createDirectory('C:\\ObsidianOS\\System32', 'Minidump');

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const dumpFile = `MEMORY_${timestamp}.DMP`;
    let dumpContent = `=== ObsidianOS Kernel Dump ===\nSTOP_CODE: ${info.stopCode}\nFAILED_COMPONENT: ${info.failedComponent}\n\n`;

    const iterateDump = () => {
      if (!isMounted) return;
      dumped += chunkMB;
      const hexLine = Array.from({ length: 8 }, () =>
        Math.floor(Math.random() * 0xffffffff).toString(16).padStart(8, '0')
      ).join(' ');
      dumpContent += `${Math.floor(dumped * 1024).toString(16).padStart(8, '0')}  ${hexLine}\n`;

      if (dumped >= totalMemoryMB) {
        setProgress(100);
        fs.createFile(dumpDir, dumpFile, dumpContent, 'DMP');
        const prev = parseInt(localStorage.getItem('obsidianos_crash_count') ?? '0', 10);
        localStorage.setItem('obsidianos_crash_count', String(prev + 1));
        if (isMounted) {
          setTimeout(() => window.location.reload(), 3000);
        }
      } else {
        setProgress(Math.floor((dumped / totalMemoryMB) * 100));
        setTimeout(iterateDump, 50);
      }
    };

    setTimeout(iterateDump, 500);
    return () => { isMounted = false; };
  }, [info]);

  // GDI Canvas Renderer loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Handle screen resize
    const resize = () => {
       canvas.width = window.innerWidth;
       canvas.height = window.innerHeight;
       draw();
    };
    window.addEventListener('resize', resize);
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    const draw = () => {
       // Solid Blue Screen Fill (GDI Style)
       ctx.fillStyle = '#0078D7';
       ctx.fillRect(0, 0, canvas.width, canvas.height);

       // Text Settings
       ctx.fillStyle = '#ffffff';
       
       // Face
       ctx.font = '120px "Segoe UI", Arial, sans-serif';
       ctx.fillText(':(', canvas.width * 0.15, canvas.height * 0.3);

       // Main Error Text
       ctx.font = '32px "Segoe UI", Arial, sans-serif';
       ctx.fillText('Seu componente ObsidianOS encontrou um problema e', canvas.width * 0.15, canvas.height * 0.45);
       ctx.fillText('precisa ser reiniciado.', canvas.width * 0.15, canvas.height * 0.5);

       ctx.font = '24px "Segoe UI", Arial, sans-serif';
       ctx.fillText('Estamos coletando algumas informações sobre o erro e, em seguida,', canvas.width * 0.15, canvas.height * 0.6);
       ctx.fillText('reiniciaremos para você.', canvas.width * 0.15, canvas.height * 0.64);
       
       ctx.font = '28px "Segoe UI", Arial, sans-serif';
       ctx.fillText(`${progress}% concluído`, canvas.width * 0.15, canvas.height * 0.72);

       // Technical Box
       ctx.font = '16px "Segoe UI", Consolas, monospace';
       const startY = canvas.height * 0.82;
       ctx.fillText('*** TECHNICAL INFORMATION ***', canvas.width * 0.15, startY);
       ctx.fillText(`STOP_CODE: ${info.stopCode || 'CRITICAL_PROCESS_DIED'}`, canvas.width * 0.15, startY + 25);
       ctx.fillText(`FAILED_COMPONENT: ${info.failedComponent || 'Unknown System Component'}`, canvas.width * 0.15, startY + 50);
       ctx.fillText(`BUG CHECK CODE: ${info.bugCheckCode || '0x00000000'}`, canvas.width * 0.15, startY + 75);
       ctx.fillText(`PARAMETERS: ${info.parameters?.join(', ') || '0x0, 0x0, 0x0, 0x0'}`, canvas.width * 0.15, startY + 100);

       // Draw a fake QR code square (GDI rectangles)
       const qrRootX = canvas.width * 0.15 + 600;
       const qrRootY = startY;
       ctx.fillStyle = '#ffffff';
       ctx.fillRect(qrRootX, qrRootY, 110, 110);
       ctx.fillStyle = '#0078D7';
       ctx.fillRect(qrRootX + 10, qrRootY + 10, 30, 30);
       ctx.fillRect(qrRootX + 70, qrRootY + 10, 30, 30);
       ctx.fillRect(qrRootX + 10, qrRootY + 70, 30, 30);
       
       ctx.fillStyle = '#ffffff';
       ctx.font = '14px "Segoe UI", Arial, sans-serif';
       ctx.fillText('Para obter mais informações,', qrRootX + 140, qrRootY + 20);
       ctx.fillText('visite: obsidianos.org/stopcode', qrRootX + 140, qrRootY + 40);
    };

    draw();

    // Re-draw periodically to update progress
    const interval = setInterval(draw, 100);
    
    return () => {
       window.removeEventListener('resize', resize);
       clearInterval(interval);
    };
  }, [info, progress]);

  return (
    <div className="bsod-container" style={{ margin: 0, padding: 0, overflow: 'hidden' }}>
      <canvas ref={canvasRef} style={{ display: 'block', width: '100vw', height: '100vh', cursor: 'none' }} />
    </div>
  );
}
