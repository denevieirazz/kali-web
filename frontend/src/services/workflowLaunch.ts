import { useAppRegistry } from '../core/appRegistry';
import { terminalHereCapability, workflowFileOpenMode, type WorkflowProvider } from '../core/workflowCore.js';
import { useProcessManager } from '../stores/processManager';
import { useWindowManager } from '../stores/windowManager';
import { nativeHostBridge } from './nativeHostBridge';
import type { AppDefinition } from '../types';
import type { WorkspaceRecord } from './workflowWorkspace';

export type WorkflowTextFileTarget = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
};

export function appLaunchUnavailableReason(app: AppDefinition): string | null {
  if (app.launchable === false || app.launchMode === 'unavailable') {
    return app.catalogSource === 'windows'
      ? 'Este aplicativo Windows exige o Host nativo gerenciado do CloudOS. Nenhuma janela externa será aberta.'
      : 'Este aplicativo Linux não possui uma superfície Xpra contida disponível.';
  }
  if (app.catalogSource === 'linux' || app.isLinux) {
    if (!app.linuxAppId || app.launchMode !== 'xpra-contained') {
      return 'O lançamento Linux foi bloqueado porque a superfície Xpra contida não foi confirmada.';
    }
  }
  if (app.catalogSource === 'windows' || app.isNative) {
    if (!nativeHostBridge.available || app.launchMode !== 'native-managed') {
      return 'Este aplicativo Windows exige o Host nativo gerenciado do CloudOS. Nenhuma janela externa será aberta.';
    }
  }
  if (app.id === 'browser' && !nativeHostBridge.available) {
    return 'O Browser CloudOS exige o modo Full com Host nativo.';
  }
  return null;
}

export function launchWorkflowApp(appId: string, params?: Record<string, unknown>) {
  const app = useAppRegistry.getState().getApp(appId);
  if (!app) throw new Error(`Aplicativo “${appId}” não está registrado.`);

  const unavailableReason = appLaunchUnavailableReason(app);
  if (unavailableReason) throw new Error(unavailableReason);

  const windowManager = useWindowManager.getState();
  if (app.isSingleInstance) {
    const existing = windowManager.windows.find(item => item.appId === appId && !item.isSystem);
    if (existing) {
      windowManager.restoreWindow(existing.id);
      windowManager.focusWindow(existing.id);
      return existing.id;
    }
  }

  if (app.catalogSource === 'linux' || app.isLinux) {
    const linuxAppId = app.linuxAppId!;
    const pid = useProcessManager.getState().createProcess('linux-app-runner', app.name, app.icon);
    return windowManager.openWindow({
      title: app.name,
      icon: app.icon,
      appId: 'linux-app-runner',
      width: app.defaultWidth,
      height: app.defaultHeight,
      minWidth: app.minWidth,
      minHeight: app.minHeight,
      isResizable: app.isResizable,
      processId: pid,
      params: { ...params, appId: linuxAppId, app: linuxAppId, distribution: app.distribution, title: app.name, icon: app.icon },
    });
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
    throw new Error('Browser CloudOS disponível apenas no modo Full. Nenhuma janela externa foi aberta.');
  }
  return launchWorkflowApp('browser');
}

export function openSettings() {
  return launchWorkflowApp('settings');
}
