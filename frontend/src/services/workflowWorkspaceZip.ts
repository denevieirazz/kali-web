import { fileSourceFacade } from '../apps/CloudOSFiles/fileSourceFacade';
import { buildWorkspaceManifest } from '../core/workflowCore.js';
import { createStoreZip } from '../core/zipStore.js';
import { getWorkspace, type WorkspaceRecord } from './workflowWorkspace';
import {
  MAX_WORKSPACE_EXPORT_BYTES,
  MAX_WORKSPACE_EXPORT_ENTRIES,
  MAX_WORKSPACE_EXPORT_FILE_BYTES,
} from './workflowWorkspaceTransfer';

type ZipEntry = { name: string; data: Uint8Array | string; modified?: number | string };

function portableName(name: string) {
  return name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80) || 'workspace';
}

async function collectFolder(
  workspace: WorkspaceRecord,
  relativePath: string[],
  output: ZipEntry[],
  budget: { entries: number; bytes: number },
) {
  const sourcePath = [...workspace.root, ...relativePath];
  const entries = await fileSourceFacade.list(workspace.provider, sourcePath, false);
  for (const entry of entries) {
    if (entry.symlink || entry.kind === 'symlink') {
      throw new Error(`Exportação ZIP interrompida: “${entry.name}” é link simbólico e não será seguido.`);
    }
    budget.entries += 1;
    if (budget.entries > MAX_WORKSPACE_EXPORT_ENTRIES) {
      throw new Error(`Workspace excede o limite de exportação de ${MAX_WORKSPACE_EXPORT_ENTRIES} itens.`);
    }
    const nextRelative = [...relativePath, entry.name];
    if (entry.kind === 'directory') {
      await collectFolder(workspace, nextRelative, output, budget);
      continue;
    }
    if (entry.size > MAX_WORKSPACE_EXPORT_FILE_BYTES) {
      throw new Error(`“${entry.name}” excede o limite de ${MAX_WORKSPACE_EXPORT_FILE_BYTES} bytes por arquivo.`);
    }
    budget.bytes += entry.size;
    if (budget.bytes > MAX_WORKSPACE_EXPORT_BYTES) {
      throw new Error(`Notes + Evidence excedem o limite agregado de ${MAX_WORKSPACE_EXPORT_BYTES} bytes.`);
    }
    const file = await fileSourceFacade.readFile(workspace.provider, sourcePath, entry, MAX_WORKSPACE_EXPORT_FILE_BYTES);
    output.push({
      name: nextRelative.join('/'),
      data: new Uint8Array(await file.arrayBuffer()),
      modified: file.lastModified || entry.modified,
    });
  }
}

export async function downloadWorkspaceZip(workspace: WorkspaceRecord) {
  const current = getWorkspace(workspace.id);
  if (!current) throw new Error('Workspace não encontrado.');
  const runtime = await fileSourceFacade.runtime(current.provider);
  if (!runtime.available || !runtime.mounted) throw new Error(`${runtime.label} não está disponível para exportação.`);

  const exportedAt = new Date().toISOString();
  const zipEntries: ZipEntry[] = [
    {
      name: 'Metadata/workspace.json',
      data: JSON.stringify(buildWorkspaceManifest(current), null, 2),
    },
    {
      name: 'Metadata/export.json',
      data: JSON.stringify({
        format: 'CloudOS Workspace ZIP',
        schema: 'cloudos-workspace-zip/v1',
        exportedAt,
        workspaceId: current.id,
        included: ['Notes', 'Evidence', 'Metadata'],
        cloud: false,
        upload: false,
      }, null, 2),
    },
  ];

  const budget = { entries: 0, bytes: 0 };
  await collectFolder(current, ['Notes'], zipEntries, budget);
  await collectFolder(current, ['Evidence'], zipEntries, budget);

  const bytes = createStoreZip(zipEntries);
  const blob = new Blob([bytes.buffer as ArrayBuffer], { type: 'application/zip' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `${portableName(current.name)}.cloudos-workspace.zip`;
  anchor.rel = 'noopener';
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
  return { bytes: blob.size, entries: zipEntries.length, sourceEntries: budget.entries, format: 'zip' as const };
}
