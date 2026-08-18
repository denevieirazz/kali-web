import { getActiveWorkspace, saveWorkspaceEvidenceFile, saveWorkspaceEvidenceText, type WorkspaceRecord } from './workflowWorkspace';

export async function captureClipboardToActiveEvidence(workspaceOverride?: WorkspaceRecord | null) {
  const workspace = workspaceOverride || getActiveWorkspace();
  if (!workspace) throw new Error('Ative um Workspace antes de capturar evidência.');
  if (workspace.status === 'archived') throw new Error('Workspace arquivado não aceita novas evidências.');

  if (navigator.clipboard?.read) {
    try {
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const imageType = item.types.find(type => type.startsWith('image/'));
        if (!imageType) continue;
        const blob = await item.getType(imageType);
        const extension = imageType.split('/')[1]?.replace('jpeg', 'jpg') || 'png';
        const file = new File([blob], `clipboard-${new Date().toISOString().replace(/[:.]/g, '-')}.${extension}`, { type: imageType });
        const name = await saveWorkspaceEvidenceFile(workspace, file);
        return { workspace, kind: 'image' as const, name };
      }
    } catch {
      // Fallback explícito para texto abaixo; nenhum dado é enviado para fora do CloudOS.
    }
  }

  if (!navigator.clipboard?.readText) throw new Error('Clipboard indisponível nesta sessão.');
  const text = (await navigator.clipboard.readText()).trim();
  if (!text) throw new Error('Clipboard não contém texto ou imagem utilizável.');
  const name = await saveWorkspaceEvidenceText(workspace, 'note', text);
  return { workspace, kind: 'text' as const, name };
}
