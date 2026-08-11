// ============================================
// Terminal App
// ============================================
import { useState, useRef, useEffect, useCallback } from 'react';
import kernel from '../../core/kernel';
import './Terminal.css';

interface TerminalLine {
  type: 'input' | 'output' | 'error' | 'system';
  content: string;
}

export default function TerminalApp({ windowId }: { windowId: string }) {
  const [lines, setLines] = useState<TerminalLine[]>([]);
  const [input, setInput] = useState('');
  const [commandHistory, setCommandHistory] = useState<string[]>([]);
  const [historyIndex, setHistoryIndex] = useState(-1);
  
  const inputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollRef.current?.scrollTo(0, scrollRef.current.scrollHeight);
  }, [lines]);

  const [shellPid, setShellPidState] = useState<number | null>(null);
  const shellPidRef = useRef<number | null>(null);

  const setShellPid = (pid: number | null) => {
    shellPidRef.current = pid;
    setShellPidState(pid);
  };

  const addOutput = useCallback((content: string, type: TerminalLine['type'] = 'output') => {
    setLines(prev => [...prev, { type, content }]);
  }, []);

  // Spawn Shell on startup
  useEffect(() => {
    // We must generate a local PID or store the intended PID if we could, 
    // but since createProcess returns the PID synchronously, we can temporarily allow 
    // ALL outputs from this exact moment until we know the PID.
    // Even better, createProcess doesn't emit until inside, but we can't know the PID beforehand.
    let createdPid: number | null = null;

    const unsubOut = kernel.on('process:stdout', (data: { pid: number, message: string }) => {
      if (createdPid !== null && data.pid !== createdPid) return;
      if (createdPid === null || data.pid === createdPid) {
        addOutput(data.message, 'output');
      }
    });
    
    const unsubErr = kernel.on('process:stderr', (data: { pid: number, message: string }) => {
      if (createdPid !== null && data.pid !== createdPid) return;
      if (createdPid === null || data.pid === createdPid) {
        addOutput(data.message, 'error');
      }
    });

    const unsubExit = kernel.on('process:terminated', (pid: number) => {
      if (pid === createdPid) {
        addOutput('\nProcesso encerrado.', 'system');
        setShellPid(null);
      }
    });

    createdPid = kernel.createProcess('cmd.osl', 'ObsidianOS Shell', '🐚', windowId, 'C:\\ObsidianOS\\System32\\cmd.osl');
    setShellPid(createdPid);

    return () => {
      unsubOut();
      unsubErr();
      unsubExit();
      if (createdPid !== null) kernel.terminateProcess(createdPid);
    };
  }, [windowId, addOutput]);

  const executeCommand = useCallback((cmd: string) => {
    if (shellPid === null) return;
    
    // Deixar o comando salvo na tela anexando-o à última linha (o prompt)
    setLines(prev => {
      const newLines = [...prev];
      if (newLines.length > 0 && newLines[newLines.length - 1].content.endsWith('> ')) {
        newLines[newLines.length - 1].content += cmd;
      }
      return newLines;
    });

    // Send command to shell
    kernel.writeStdin(shellPid, cmd);
    setCommandHistory(prev => [...prev, cmd]);
    setHistoryIndex(-1);
  }, [shellPid]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      executeCommand(input);
      setInput('');
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (commandHistory.length > 0) {
        const newIndex = historyIndex === -1 ? commandHistory.length - 1 : Math.max(0, historyIndex - 1);
        setHistoryIndex(newIndex);
        setInput(commandHistory[newIndex]);
      }
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (historyIndex >= 0) {
        const newIndex = historyIndex + 1;
        if (newIndex >= commandHistory.length) {
          setHistoryIndex(-1);
          setInput('');
        } else {
          setHistoryIndex(newIndex);
          setInput(commandHistory[newIndex]);
        }
      }
    } else if (e.key === 'Tab') {
      e.preventDefault();
      // Tab completion would now need to be handled by the shell
    }
  };

  const isLastLinePrompt = lines.length > 0 && lines[lines.length - 1].type === 'output' && lines[lines.length - 1].content.endsWith('> ');

  const inputElement = (
    <input
      ref={inputRef}
      type="text"
      className="terminal-input"
      value={input}
      onChange={(e) => setInput(e.target.value)}
      onKeyDown={handleKeyDown}
      autoFocus
      spellCheck={false}
    />
  );

  return (
    <div className="terminal" onClick={() => inputRef.current?.focus()}>
      <div className="terminal-output" ref={scrollRef}>
        {lines.map((line, i) => {
          const isPromptLine = i === lines.length - 1 && isLastLinePrompt;

          if (isPromptLine) {
            return (
              <div key={i} className={`terminal-line ${line.type} terminal-input-line`}>
                <span className="terminal-prompt">{line.content}</span>
                {inputElement}
              </div>
            );
          }

          return (
            <div key={i} className={`terminal-line ${line.type}`}>
              {line.content}
            </div>
          );
        })}
        {!isLastLinePrompt && (
          <div className="terminal-input-line">
            {inputElement}
          </div>
        )}
      </div>
    </div>
  );
}
