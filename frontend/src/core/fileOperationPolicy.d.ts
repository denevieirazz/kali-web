export function validatePastePath(input?: {
  sourcePath?: unknown[];
  entryName?: string;
  kind?: 'file' | 'directory';
  destinationPath?: unknown[];
  action?: 'copy' | 'cut';
}): { ok: boolean; sameDirectory: boolean; reason: string };
