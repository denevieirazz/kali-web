// ============================================
// Process Context - Per-Process Sandbox
// ============================================
import React, { createContext, useContext, useMemo } from 'react';
import type { Process } from '../types';
import { useProcessManager } from '../stores/processManager';

interface ProcessContextType {
  pid: number;
  process: Process | undefined;
  env: Record<string, string>; // Environment variables
  terminate: () => void;
}

const ProcessContext = createContext<ProcessContextType | undefined>(undefined);

// @refresh reset
export function ProcessProvider({ pid, children }: { pid: number; children: React.ReactNode }) {
  const { getProcess, terminateProcess } = useProcessManager();
  const process = getProcess(pid);
  
  const value = useMemo(() => ({
    pid,
    process,
    env: {
      OS: 'ObsidianOS_NT',
      USERNAME: 'User',
      APPDATA: 'C:\\Users\\User\\AppData\\Roaming',
      TEMP: 'C:\\Users\\User\\AppData\\Local\\Temp',
    },
    terminate: () => terminateProcess(pid),
  }), [pid, process, terminateProcess]);

  return (
    <ProcessContext.Provider value={value}>
      {children}
    </ProcessContext.Provider>
  );
}

export function useProcess() {
  const context = useContext(ProcessContext);
  if (context === undefined) {
    throw new Error('useProcess must be used within a ProcessProvider');
  }
  return context;
}
