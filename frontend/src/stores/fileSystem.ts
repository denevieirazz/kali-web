// ============================================
// File System Store — Espelho do Kernel
// ============================================
// Este store é um ESPELHO READ-ONLY do sistema de arquivos do kernel.
// As mutações são injetadas diretamente no kernel e o resultado reflete aqui.
// ============================================

import { create } from 'zustand';
import kernel from '../core/kernel';
import type { FileSystemNode } from '../types';

interface FileSystemState {
  nodes: Record<string, FileSystemNode>;

  // Thin wrappers
  getNode: (path: string) => FileSystemNode | undefined;
  getChildren: (path: string) => FileSystemNode[];
  createFile: (path: string, name: string, content?: string, extension?: string) => void;
  createDirectory: (path: string, name: string) => void;
  deleteNode: (path: string) => void;
  renameNode: (path: string, newName: string) => void;
  moveNode: (fromPath: string, toPath: string) => void;
  updateFileContent: (path: string, content: string) => void;
  getPathParts: (path: string) => string[];
  exists: (path: string) => boolean;
  repairSystemFiles: () => void;
}

export const useFileSystem = create<FileSystemState>((set, get) => {

  // Atualiza com a snapshot sempre que o kernel persiste
  kernel.on('fs:snapshot', (nodes: Record<string, FileSystemNode>) => {
    set({ nodes });
  });

  // Atualiza no boot reset
  kernel.on('reset', () => {
    set({ nodes: kernel.fsGetSnapshot() });
  });

  return {
    // Estado inicial
    nodes: kernel.fsGetSnapshot(),

    // Seletores (leem do estado espelhado)
    getNode: (path) => get().nodes[path],
    getChildren: (path) => Object.values(get().nodes).filter(n => n.parentPath === path),
    getPathParts: (path) => path.split('\\').filter(Boolean),
    exists: (path) => path in get().nodes,

    // Wrappers para modificações no Kernel
    createFile:        (p, n, c, e) => kernel.fsCreateFile(p, n, c, e),
    createDirectory:   (p, n)       => kernel.fsCreateDirectory(p, n),
    deleteNode:        (p)          => kernel.fsDeleteNode(p),
    renameNode:        (p, n)       => kernel.fsRenameNode(p, n),
    moveNode:          (f, t)       => kernel.fsMoveNode(f, t),
    updateFileContent: (p, c)       => kernel.fsUpdateFileContent(p, c),
    repairSystemFiles: ()           => kernel.fsRepairSystemFiles(),
  };
});
