export type FileVisualKind = 'folder' | 'text' | 'markdown' | 'code' | 'json' | 'pdf' | 'image' | 'audio' | 'video' | 'archive' | 'executable' | 'symlink' | 'unknown';
export const FILE_VISUAL_KINDS: readonly FileVisualKind[];
export function classifyFileVisual(entry: { name?: string; originalName?: string; kind?: string; isSymlink?: boolean } | null | undefined, mimeType?: string): FileVisualKind;
export function canGenerateImageThumbnail(entry: { name?: string; originalName?: string; kind?: string; isSymlink?: boolean } | null | undefined, mimeType?: string): boolean;
export function fileVisualLabel(kind: FileVisualKind): string;
