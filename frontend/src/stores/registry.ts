// ============================================
// Registry Store — Espelho do Kernel
// ============================================
// Este store é um ESPELHO READ-ONLY do sistema de registro do kernel.
// As mutações são injetadas diretamente no kernel e o resultado reflete aqui.
// ============================================

import { create } from 'zustand';
import kernel from '../core/kernel';
import type { RegistryEntry, RegistryValue } from '../core/defaultRegistry';

interface RegistryState {
  hives: Record<string, Record<string, RegistryEntry>>;

  // Thin wrappers
  getValue: (path: string) => RegistryValue | undefined;
  setValue: (path: string, type: RegistryEntry['type'], value: RegistryValue) => void;
  deleteValue: (path: string) => void;
  getSubKeys: (path: string) => string[];
  keyExists: (path: string) => boolean;
}

export const useRegistry = create<RegistryState>((set, get) => {

  // Atualiza com a snapshot sempre que o kernel persiste o registry
  kernel.on('registry:snapshot', (hives: Record<string, Record<string, RegistryEntry>>) => {
    set({ hives });
  });

  // Atualiza no boot reset
  kernel.on('reset', () => {
    set({ hives: kernel.regGetSnapshot() });
  });

  return {
    // Estado inicial
    hives: kernel.regGetSnapshot(),

    // Seletores (leem do estado espelhado localmente)
    getValue: (path: string) => {
      const parts = path.split('\\');
      const valueName = parts.pop()!;
      const keyPath = parts.join('\\');
      const key = get().hives[keyPath];
      return key?.[valueName]?.value;
    },

    getSubKeys: (path: string) => {
      const keys = Object.keys(get().hives);
      return keys.filter(k => k.startsWith(path + '\\') && k !== path);
    },

    keyExists: (path: string) => {
      return path in get().hives;
    },

    // Wrappers para modificações no Kernel
    setValue:    (path, type, value) => kernel.regSetValue(path, type, value),
    deleteValue: (path)              => kernel.regDeleteValue(path),
  };
});
