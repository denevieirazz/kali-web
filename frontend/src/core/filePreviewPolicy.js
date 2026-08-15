export const PREVIEW_LIMITS = Object.freeze({
  text: 2 * 1024 * 1024,
  image: 25 * 1024 * 1024,
  pdf: 50 * 1024 * 1024,
  audio: 100 * 1024 * 1024,
  video: 150 * 1024 * 1024,
});

const TEXT_EXTENSIONS = new Set(['txt', 'md', 'json', 'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'css', 'html', 'htm', 'log', 'csv', 'xml', 'yaml', 'yml', 'ini', 'conf', 'toml', 'env', 'sql', 'py', 'ps1', 'sh', 'bat', 'cmd']);
const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif']);
const AUDIO_EXTENSIONS = new Set(['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus']);
const VIDEO_EXTENSIONS = new Set(['mp4', 'webm', 'ogv', 'mov', 'm4v']);

export function fileExtension(name) {
  const safe = typeof name === 'string' ? name.trim().toLowerCase() : '';
  const index = safe.lastIndexOf('.');
  return index > 0 && index < safe.length - 1 ? safe.slice(index + 1) : '';
}

export function classifyPreview({ name = '', type = '', size = 0 } = {}) {
  const extension = fileExtension(name);
  const mime = String(type || '').toLowerCase();
  let kind = 'unsupported';

  // SVG is intentionally treated as text. Rendering arbitrary SVG markup inside
  // the privileged Shell would create a larger attack surface than plain text.
  if (extension === 'svg' || mime === 'image/svg+xml') kind = 'text';
  else if (mime.startsWith('text/') || TEXT_EXTENSIONS.has(extension)) kind = 'text';
  else if (mime === 'application/pdf' || extension === 'pdf') kind = 'pdf';
  else if (mime.startsWith('image/') || IMAGE_EXTENSIONS.has(extension)) kind = 'image';
  else if (mime.startsWith('audio/') || AUDIO_EXTENSIONS.has(extension)) kind = 'audio';
  else if (mime.startsWith('video/') || VIDEO_EXTENSIONS.has(extension)) kind = 'video';

  const limit = PREVIEW_LIMITS[kind] ?? 0;
  const numericSize = Number.isFinite(Number(size)) ? Math.max(0, Number(size)) : 0;
  if (kind === 'unsupported') return { kind, allowed: false, limit: 0, reason: 'Formato sem preview seguro.' };
  if (numericSize > limit) return { kind, allowed: false, limit, reason: `Arquivo excede o limite de preview (${limit} bytes).` };
  return { kind, allowed: true, limit, reason: '' };
}
