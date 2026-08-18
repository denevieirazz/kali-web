import { createStoreZip } from '../core/zipStore.js';
import { buildWorkspaceExport } from './workflowWorkspaceTransfer';
import type { WorkspaceRecord } from './workflowWorkspace';

function portableName(name: string) {
  return name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80) || 'workspace';
}

function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

export async function downloadWorkspaceZip(workspace: WorkspaceRecord) {
  const bundle = await buildWorkspaceExport(workspace);
  const zipEntries: Array<{ name: string; data: Uint8Array | string; modified?: number | string }> = [
    {
      name: 'Metadata/workspace.json',
      data: JSON.stringify({ ...bundle.workspace, schema: bundle.schema, exportedAt: bundle.exportedAt }, null, 2),
    },
    {
      name: 'Metadata/export.json',
      data: JSON.stringify({
        format: 'CloudOS Workspace ZIP',
        schema: bundle.schema,
        exportedAt: bundle.exportedAt,
        included: ['Notes', 'Evidence', 'Metadata'],
        cloud: false,
        upload: false,
      }, null, 2),
    },
  ];

  for (const entry of bundle.entries) {
    if (entry.kind !== 'file' || !entry.contentBase64) continue;
    const root = entry.path[0];
    if (root !== 'Notes' && root !== 'Evidence') continue;
    zipEntries.push({
      name: entry.path.join('/'),
      data: base64ToBytes(entry.contentBase64),
      modified: entry.modified,
    });
  }

  const bytes = createStoreZip(zipEntries);
  const blob = new Blob([bytes], { type: 'application/zip' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `${portableName(workspace.name)}.cloudos-workspace.zip`;
  anchor.rel = 'noopener';
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
  return { bytes: blob.size, entries: zipEntries.length, format: 'zip' as const };
}
