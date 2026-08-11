import kernel from '../core/kernel';
import type { FileSystemNode } from '../types';

/**
 * useFileSystemAPI - Process-Level File System Access
 * 
 * Provides official System Call wrappers for filesystem IO. 
 * All IO operations, permission validation and physical storage logic 
 * are handled within the Kernel (kernel.ts).
 * 
 * Apps use this hook for raw IO operations.
 */
export function useFileSystemAPI() {
  
  const readFile = (path: string): string | undefined => {
    const node = kernel.fsGetNode(path);
    return node?.type === 'file' ? node.content : undefined;
  };

  const writeFile = (path: string, content: string) => {
    kernel.fsUpdateFileContent(path, content);
  };

  const createFile = (parentPath: string, name: string, content = '', extension = 'txt') => {
    kernel.fsCreateFile(parentPath, name, content, extension);
  };

  const createDirectory = (parentPath: string, name: string) => {
    kernel.fsCreateDirectory(parentPath, name);
  };

  const deleteNode = (path: string) => {
    kernel.fsDeleteNode(path);
  };

  const exists = (path: string): boolean => {
    return kernel.fsExists(path);
  };

  const getChildren = (path: string): FileSystemNode[] => {
    return kernel.fsGetChildren(path);
  };

  const getMetadata = (path: string) => {
    const node = kernel.fsGetNode(path);
    return node?.metadata;
  };

  return {
    readFile,
    writeFile,
    createFile,
    createDirectory,
    deleteNode,
    exists,
    getChildren,
    getMetadata
  };
}
