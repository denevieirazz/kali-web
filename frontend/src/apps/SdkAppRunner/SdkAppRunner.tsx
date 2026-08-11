import { useState, useEffect, useRef } from 'react';
import { useFileSystem } from '../../stores/fileSystem';
import kernel from '../../core/kernel';
import './SdkAppRunner.css';

interface SdkAppRunnerProps {
  windowId: string;
  binaryPath: string; // O caminho do .exe no VFS
}

export default function SdkAppRunner({ windowId, binaryPath }: SdkAppRunnerProps) {
  const [output, setOutput] = useState<string[]>([]);
  const { getNode } = useFileSystem();
  const containerRef = useRef<HTMLDivElement>(null);

  const log = (msg: string) => setOutput(prev => [...prev, msg]);

  useEffect(() => {
    const run = async () => {
      const node = getNode(binaryPath);
      if (!node || !node.content) {
        log("Erro: Binário não encontrado ou corrompido.");
        return;
      }

      log(`Iniciando ${node.name}...`);

      try {
        // Sandboxing básico via novo Function
        // Injetamos a API 'OS' para o app interagir com o sistema
        const appCode = node.content;
        
        const OSProxy = {
          User32: {
            CreateElement: (tag: string, id: string, props: any) => {
                if (!containerRef.current) return;
                const el = document.createElement(tag);
                el.id = id;
                Object.assign(el.style, props.style || {});
                if (props.innerText) el.innerText = props.innerText;
                if (props.className) el.className = props.className;
                containerRef.current.appendChild(el);
            },
            OnMessage: (id: string, event: string, cb: Function) => {
                const el = document.getElementById(id);
                if (el) el.addEventListener(event, (e) => cb(e));
            },
            UpdateStyle: (id: string, style: any) => {
                const el = document.getElementById(id);
                if (el) Object.assign(el.style, style);
            },
            SetText: (id: string, text: string) => {
                const el = document.getElementById(id);
                if (el) el.innerText = text;
            },
            AddEventListener: (type: string, cb: Function) => {
                window.addEventListener(type, (e) => cb(e));
                // Clean up on unmount would be better but let's keep it simple for now
            }
          },
          Kernel: {
            Log: (msg: string) => kernel.log('INFO', node.name, msg),
            Exit: () => {
                const proc = kernel.getProcessByWindowId(windowId);
                if (proc) kernel.terminateProcess(proc.pid);
            }
          },
          Print: (msg: any) => log(String(msg))
        };

        const runner = new Function('OS', 'print', `
            return (async () => {
                ${appCode}
            })()
        `);

        await runner(OSProxy, log);
      } catch (err: any) {
        log(`CRASH: ${err.message}`);
        kernel.log('ERROR', 'SdkRunner', `App ${node.name} falhou: ${err.message}`);
      }
    };

    run();
  }, [binaryPath]);

  return (
    <div className="sdk-app-runner" ref={containerRef}>
      {output.length > 0 && output[output.length-1].startsWith('CRASH') && (
        <div className="sdk-terminal-overlay">
          {output.map((line, i) => <div key={i}>{line}</div>)}
        </div>
      )}
    </div>
  );
}
