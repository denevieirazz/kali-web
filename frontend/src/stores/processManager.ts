// ============================================
// Process Manager Store — Espelho do Kernel
// ============================================
// Este store é um ESPELHO READ-ONLY do estado de processos do kernel.
// Mutações NUNCA acontecem aqui — elas vão ao kernel via kernel.createProcess() etc.
// O store subscreve aos eventos do kernel e reflete as mudanças para o React.
// ============================================

import { create } from 'zustand';
import kernel from '../core/kernel';
import type { Process } from '../types';

interface ProcessManagerState {
  processes: Process[];

  // Thin wrappers → delegam ao kernel (mantém compatibilidade com componentes existentes)
  createProcess: (name: string, title: string, icon: string, windowId?: string) => number;
  terminateProcess: (pid: number) => void;
  suspendProcess: (pid: number) => void;
  resumeProcess: (pid: number) => void;
  updateProcessCpu: (pid: number, cpu: number) => void;
  updateProcessMemory: (pid: number, memory: number) => void;

  // Seletores (leem do estado local para reatividade React)
  getProcess: (pid: number) => Process | undefined;
  getProcessByWindowId: (windowId: string) => Process | undefined;
  getRunningProcesses: () => Process[];
}

export const useProcessManager = create<ProcessManagerState>((set, get) => {

  // ── Subscreve aos eventos do kernel ──────────────────────────────────────────
  // Cada evento atualiza apenas o slice afetado, mantendo o restante intacto.

  kernel.on('process:created', (process: Process) => {
    set(state => ({ processes: [...state.processes, process] }));
  });

  kernel.on('process:terminated', (pid: number) => {
    set(state => ({ processes: state.processes.filter(p => p.pid !== pid) }));
  });

  kernel.on('process:updated', (process: Process) => {
    set(state => ({
      processes: state.processes.map(p => p.pid === process.pid ? process : p),
    }));
  });

  // Kernel reset → reinicia o espelho com o estado base recém-carregado
  kernel.on('reset', () => {
    set({ processes: kernel.getProcesses() });
  });

  // ── Estado inicial = snapshot do kernel ──────────────────────────────────────
  return {
    processes: kernel.getProcesses(),

    // Thin wrappers — toda a lógica está no kernel
    createProcess:      (name, title, icon, windowId) => kernel.createProcess(name, title, icon, windowId),
    terminateProcess:   (pid)          => kernel.terminateProcess(pid),
    suspendProcess:     (pid)          => kernel.suspendProcess(pid),
    resumeProcess:      (pid)          => kernel.resumeProcess(pid),
    updateProcessCpu:   (pid, cpu)     => kernel.updateProcessCpu(pid, cpu),
    updateProcessMemory:(pid, memory)  => kernel.updateProcessMemory(pid, memory),

    // Seletores locais (reatividade via Zustand, sem chamar o kernel desnecessariamente)
    getProcess:          (pid)      => get().processes.find(p => p.pid === pid),
    getProcessByWindowId:(windowId) => get().processes.find(p => p.windowId === windowId),
    getRunningProcesses: ()         => get().processes.filter(p => p.status === 'running'),
  };
});
