export const FILE_VISUAL_KINDS = Object.freeze([
  'folder', 'text', 'markdown', 'code', 'json', 'pdf', 'image', 'audio', 'video', 'archive', 'executable', 'symlink', 'unknown'
]);

const EXTENSIONS = Object.freeze({
  markdown: new Set(['md', 'mdx', 'markdown']),
  json: new Set(['json', 'jsonc', 'geojson']),
  pdf: new Set(['pdf']),
  image: new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'avif', 'ico']),
  audio: new Set(['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus']),
  video: new Set(['mp4', 'webm', 'mov', 'mkv', 'avi', 'm4v']),
  archive: new Set(['zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'zst']),
  executable: new Set(['exe', 'msi', 'com', 'appimage', 'deb', 'rpm', 'apk']),
  code: new Set(['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py', 'go', 'rs', 'java', 'c', 'h', 'cpp', 'hpp', 'cs', 'php', 'rb', 'swift', 'kt', 'kts', 'sh', 'bash', 'zsh', 'ps1', 'bat', 'cmd', 'html', 'css', 'scss', 'sass', 'less', 'xml', 'yaml', 'yml', 'toml', 'ini', 'sql']),
  text: new Set(['txt', 'log', 'csv', 'tsv', 'rtf'])
});

function extensionOf(name) {
  const normalized = String(name || '').toLowerCase();
  const lastDot = normalized.lastIndexOf('.');
  return lastDot > -1 && lastDot < normalized.length - 1 ? normalized.slice(lastDot + 1) : '';
}

export function classifyFileVisual(entry, mimeType = '') {
  if (entry?.kind === 'directory') return 'folder';
  if (entry?.kind === 'symlink' || entry?.isSymlink === true) return 'symlink';
  const extension = extensionOf(entry?.originalName || entry?.name);
  for (const kind of ['markdown', 'json', 'pdf', 'image', 'audio', 'video', 'archive', 'executable', 'code', 'text']) {
    if (EXTENSIONS[kind].has(extension)) return kind;
  }
  const mime = String(mimeType || '').toLowerCase();
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime.startsWith('video/')) return 'video';
  if (mime === 'application/pdf') return 'pdf';
  if (mime === 'application/json' || mime.endsWith('+json')) return 'json';
  if (mime.startsWith('text/')) return 'text';
  return 'unknown';
}

export function canGenerateImageThumbnail(entry, mimeType = '') {
  return classifyFileVisual(entry, mimeType) === 'image' && entry?.kind !== 'symlink' && entry?.isSymlink !== true;
}

export function fileVisualLabel(kind) {
  return ({
    folder: 'Pasta', text: 'Texto', markdown: 'Markdown', code: 'Código', json: 'JSON', pdf: 'PDF', image: 'Imagem', audio: 'Áudio', video: 'Vídeo', archive: 'Compactado', executable: 'Executável', symlink: 'Link simbólico', unknown: 'Arquivo'
  })[kind] || 'Arquivo';
}
