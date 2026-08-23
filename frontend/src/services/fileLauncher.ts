// ============================================
// CloudOS File Launcher & Execution Bridge
// ============================================
import { useWindowManager } from '../stores/windowManager';
import { useProcessManager } from '../stores/processManager';
import { useAppRegistry } from '../core/appRegistry';
import { getDefaultAppForFile, getCompatibleApps, getFileExtension, type AppAssociation } from './mimeRegistry';
import { openOpenWithModal } from '../components/OpenWithModal/OpenWithModal';

export interface OpenFileOptions {
  filePath: string;
  fileName: string;
  targetAppId?: string;
  fileContent?: string;
  openWith?: boolean;
  linuxApps?: Array<any>;
}

export function openFile(options: OpenFileOptions): void {
  const { filePath, fileName, targetAppId, fileContent, openWith = false, linuxApps = [] } = options;

  if (openWith) {
    const compatible = getCompatibleApps(fileName, linuxApps);
    openOpenWithModal({
      fileName,
      filePath,
      fileContent,
      compatibleApps: compatible,
      onSelectApp: (selectedAppId) => {
        openFile({ ...options, openWith: false, targetAppId: selectedAppId });
      }
    });
    return;
  }

  const { openWindow } = useWindowManager.getState();
  const { createProcess } = useProcessManager.getState();
  const registeredApps = useAppRegistry.getState().apps;

  let selectedApp: AppAssociation;

  if (targetAppId) {
    const compatible = getCompatibleApps(fileName, linuxApps);
    const found = compatible.find(a => a.id === targetAppId || a.linuxAppId === targetAppId);
    if (found) {
      selectedApp = found;
    } else {
      const reg = registeredApps[targetAppId];
      selectedApp = {
        id: targetAppId,
        name: reg?.name || targetAppId,
        icon: reg?.icon || '📦',
        isLinux: targetAppId.startsWith('linux-app-'),
        linuxAppId: targetAppId.replace(/^linux-app-/, '')
      };
    }
  } else {
    selectedApp = getDefaultAppForFile(fileName, linuxApps);
  }

  const title = `${fileName} - ${selectedApp.name}`;

  // 1. Linux Application execution via contained Xpra
  if (selectedApp.isLinux || selectedApp.id.startsWith('linux-app-')) {
    const linuxId = selectedApp.linuxAppId || selectedApp.id.replace(/^linux-app-/, '');
    const pid = createProcess('linux-app-runner', selectedApp.name, selectedApp.icon);
    openWindow({
      title,
      icon: selectedApp.icon,
      appId: 'linux-app-runner',
      width: 1020,
      height: 680,
      minWidth: 480,
      minHeight: 320,
      isResizable: true,
      processId: pid,
      params: {
        appId: linuxId,
        app: linuxId,
        filePath,
        title,
        icon: selectedApp.icon
      }
    });
    return;
  }

  // 2. Native CloudOS Application execution
  const appId = selectedApp.id;

  const richOfficeExtensions = ['docx', 'doc', 'xlsx', 'xls', 'pptx', 'ppt', 'odt', 'ods', 'odp'];
  const ext = getFileExtension(fileName);
  if (richOfficeExtensions.includes(ext) && appId === 'notepad' && !targetAppId) {
    const compatible = getCompatibleApps(fileName, linuxApps);
    openOpenWithModal({
      fileName,
      filePath,
      fileContent,
      compatibleApps: compatible,
      onSelectApp: (chosenId) => {
        openFile({ ...options, openWith: false, targetAppId: chosenId });
      }
    });
    return;
  }

  if (appId === 'notepad') {
    const pid = createProcess('notepad', 'Bloco de Notas', '📝');
    openWindow({
      title,
      icon: '📝',
      appId: 'notepad',
      width: 680,
      height: 480,
      minWidth: 320,
      minHeight: 200,
      isResizable: true,
      processId: pid,
      params: { filePath, content: fileContent }
    });
    return;
  }

  if (appId === 'media-player') {
    const pid = createProcess('media-player', 'Player Multimídia', '🎬');
    openWindow({
      title,
      icon: '🎬',
      appId: 'media-player',
      width: 720,
      height: 520,
      minWidth: 400,
      minHeight: 300,
      isResizable: true,
      processId: pid,
      params: { filePath, content: fileContent }
    });
    return;
  }

  if (appId === 'browser') {
    const pid = createProcess('browser', 'Navegador', '🌐');
    openWindow({
      title,
      icon: '🌐',
      appId: 'browser',
      width: 960,
      height: 640,
      minWidth: 500,
      minHeight: 350,
      isResizable: true,
      processId: pid,
      params: { filePath, url: filePath }
    });
    return;
  }

  if (appId === 'obsidian-code') {
    const pid = createProcess('obsidian-code', 'Obsidian Code', '💻');
    openWindow({
      title,
      icon: '💻',
      appId: 'obsidian-code',
      width: 980,
      height: 640,
      minWidth: 520,
      minHeight: 350,
      isResizable: true,
      processId: pid,
      params: { filePath }
    });
    return;
  }

  if (appId === 'file-explorer') {
    const pid = createProcess('file-explorer', 'Explorador de Arquivos', '📁');
    openWindow({
      title: 'Explorador de Arquivos',
      icon: '📁',
      appId: 'file-explorer',
      width: 840,
      height: 540,
      minWidth: 450,
      minHeight: 300,
      isResizable: true,
      processId: pid,
      params: { initialPath: filePath }
    });
    return;
  }

  // Fallback to registered generic app or Notepad
  const fallback = registeredApps[appId] || registeredApps['notepad'];
  if (fallback) {
    const pid = createProcess(fallback.id, fallback.name, fallback.icon);
    openWindow({
      title,
      icon: fallback.icon,
      appId: fallback.id,
      width: fallback.defaultWidth || 700,
      height: fallback.defaultHeight || 500,
      isResizable: true,
      processId: pid,
      params: { filePath, content: fileContent }
    });
  }
}
