import { useAppRegistry } from '../core/appRegistry';
import { terminalHereCapability, workflowFileOpenMode, type WorkflowProvider } from '../core/workflowCore.js';
import { useProcessManager } from '../stores/processManager';
import { useWindowManager } from '../stores/windowManager';
import { nativeHostBridge } from './nativeHostBridge';
import type { WorkspaceRecord } from './workflowWorkspace';

export type WorkflowTextFileTarget = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
};

export function launchWorkflowApp(appId: string, params?: Record<string, unknown>) {
  const app = useAppRegistry.getState().getApp(appId);
  if (!app) throw new Error(`Aplicativo “${appId}” não está registrado.`);

  const windowManager = useWindowManager.getState();
  if (app.isSingleInstance) {
    const existing = windowManager.windows.find(item => item.appId === appId && !item.isSystem);
    if (existing) {
      windowManager.restoreWindow(existing.id);
      windowManager.focusWindow(existing.id);
      return existing.id;
    }
  }

  const pid = useProcessManager.getState().createProcess(app.id, app.name, app.icon);
  return windowManager.openWindow({
    title: app.name,
    icon: app.icon,
    appId: app.id,
    width: app.defaultWidth,
    height: app.defaultHeight,
    minWidth: app.minWidth,
    minHeight: app.minHeight,
    isResizable: app.isResizable,
    processId: pid,
    params,
  });
}

export function openWorkspace(workspaceId?: string, noteFileName?: string) {
  return launchWorkflowApp('workflow-workspace', {
    ...(workspaceId ? { workspaceId } : {}),
    ...(noteFileName ? { noteFileName } : {}),
  });
}

export function openTextFileInNotes(target: WorkflowTextFileTarget) {
  if (workflowFileOpenMode(target.name, 'file', false) !== 'notes') throw new Error('Este tipo de arquivo não é aberto automaticamente no Notes.');
  return launchWorkflowApp('workflow-workspace', {
    externalTextFile: {
      provider: target.provider,
      path: [...target.path],
      name: target.name,
    },
  });
}

export function openFilesAt(provider: WorkflowProvider, path: string[], selectName?: string) {
  return launchWorkflowApp('cloudos-files', {
    workflowSource: provider,
    workflowPath: [...path],
    ...(selectName ? { workflowSelectName: selectName } : {}),
  });
}

export function openWorkspaceFiles(workspace: WorkspaceRecord, child = 'Files') {
  return openFilesAt(workspace.provider, [...workspace.root, child]);
}

export function openTerminalHere(provider: WorkflowProvider, path: string[]) {
  const capability = terminalHereCapability(provider);
  if (!capability.supported || provider !== 'wsl') throw new Error(capability.reason || 'Terminal aqui indisponível nesta origem.');
  return launchWorkflowApp('cloudos-terminal', {
    profile: 'wsl',
    initialDirectory: { provider: 'wsl', path: [...path] },
  });
}

export function openWorkspaceTerminal(workspace: WorkspaceRecord) {
  return openTerminalHere(workspace.provider, [...workspace.root, 'Terminal']);
}

export function openExistingBrowser() {
  if (!nativeHostBridge.available) {
    const openDefault = window.confirm('Browser CloudOS disponível apenas no modo Full. Abrir o navegador padrão nesta sessão WebOnly?');
    return openDefault ? openDefaultBrowser() : null;
  }
  return launchWorkflowApp('browser');
}

export function openDefaultBrowser() {
  const opened = window.open('about:blank', '_blank', 'noopener,noreferrer');
  if (!opened) throw new Error('O navegador bloqueou a nova guia. Permita pop-ups para abrir o navegador padrão.');
  return opened;
}

export function openSettings() {
  return launchWorkflowApp('settings');
}
