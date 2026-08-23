// ============================================
// CloudOS MIME Registry & File Associations Engine
// ============================================

export interface AppAssociation {
  id: string;
  name: string;
  icon: string;
  isLinux?: boolean;
  linuxAppId?: string;
  description?: string;
  category?: string;
}

export interface MimeDefinition {
  mime: string;
  extensions: string[];
  category: string;
  icon: string;
  label: string;
  defaultAppId: string;
  compatibleAppIds: string[];
}

export const MIME_DEFINITIONS: MimeDefinition[] = [
  // Documentos de Texto e Rich Text
  {
    mime: 'text/plain',
    extensions: ['txt', 'log', 'ini', 'cfg', 'conf', 'env'],
    category: 'documents',
    icon: '📝',
    label: 'Documento de Texto',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'linux-app-mousepad', 'obsidian-code']
  },
  {
    mime: 'text/markdown',
    extensions: ['md', 'markdown', 'mdown', 'mkd'],
    category: 'documents',
    icon: '📄',
    label: 'Documento Markdown',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-obsidian', 'linux-app-geany', 'obsidian-code']
  },
  {
    mime: 'application/pdf',
    extensions: ['pdf'],
    category: 'documents',
    icon: '📕',
    label: 'Documento PDF',
    defaultAppId: 'browser',
    compatibleAppIds: ['browser', 'linux-app-firefox-esr', 'linux-app-firefox']
  },
  {
    mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    extensions: ['docx', 'doc', 'odt', 'rtf'],
    category: 'documents',
    icon: '📘',
    label: 'Documento Word / Texto Formatado',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'linux-app-mousepad', 'linux-app-obsidian']
  },
  {
    mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    extensions: ['xlsx', 'xls', 'ods', 'csv', 'tsv'],
    category: 'spreadsheets',
    icon: '📗',
    label: 'Planilha / Tabela de Dados',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'cloudos-files']
  },
  {
    mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    extensions: ['pptx', 'ppt', 'odp'],
    category: 'presentations',
    icon: '📙',
    label: 'Apresentação de Slides',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany']
  },

  // Código Fonte e Scripts
  {
    mime: 'text/javascript',
    extensions: ['js', 'mjs', 'cjs', 'jsx'],
    category: 'code',
    icon: '📜',
    label: 'Código JavaScript',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'linux-app-code', 'obsidian-code']
  },
  {
    mime: 'text/typescript',
    extensions: ['ts', 'tsx'],
    category: 'code',
    icon: '🔷',
    label: 'Código TypeScript',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'linux-app-code', 'obsidian-code']
  },
  {
    mime: 'text/x-python',
    extensions: ['py', 'pyw'],
    category: 'code',
    icon: '🐍',
    label: 'Script Python',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'linux-app-code', 'obsidian-code']
  },
  {
    mime: 'application/json',
    extensions: ['json'],
    category: 'code',
    icon: '📋',
    label: 'Arquivo JSON',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'obsidian-code']
  },
  {
    mime: 'text/html',
    extensions: ['html', 'htm', 'xhtml'],
    category: 'code',
    icon: '🌐',
    label: 'Página HTML',
    defaultAppId: 'browser',
    compatibleAppIds: ['browser', 'notepad', 'linux-app-firefox-esr', 'linux-app-geany']
  },
  {
    mime: 'text/css',
    extensions: ['css', 'scss', 'sass', 'less'],
    category: 'code',
    icon: '🎨',
    label: 'Folha de Estilos CSS',
    defaultAppId: 'notepad',
    compatibleAppIds: ['notepad', 'linux-app-geany', 'obsidian-code']
  },
  {
    mime: 'application/x-sh',
    extensions: ['sh', 'bash', 'zsh'],
    category: 'code',
    icon: '💻',
    label: 'Shell Script',
    defaultAppId: 'cloudos-terminal',
    compatibleAppIds: ['cloudos-terminal', 'terminal', 'notepad', 'linux-app-geany']
  },

  // Imagens
  {
    mime: 'image/png',
    extensions: ['png'],
    category: 'images',
    icon: '🖼️',
    label: 'Imagem PNG',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player', 'browser', 'linux-app-gimp']
  },
  {
    mime: 'image/jpeg',
    extensions: ['jpg', 'jpeg', 'jpe'],
    category: 'images',
    icon: '🖼️',
    label: 'Imagem JPEG',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player', 'browser', 'linux-app-gimp']
  },
  {
    mime: 'image/svg+xml',
    extensions: ['svg'],
    category: 'images',
    icon: '📐',
    label: 'Gráfico Vetorial SVG',
    defaultAppId: 'browser',
    compatibleAppIds: ['browser', 'media-player', 'notepad', 'linux-app-gimp']
  },
  {
    mime: 'image/gif',
    extensions: ['gif'],
    category: 'images',
    icon: '🎞️',
    label: 'Imagem GIF Animada',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player', 'browser']
  },
  {
    mime: 'image/webp',
    extensions: ['webp'],
    category: 'images',
    icon: '🖼️',
    label: 'Imagem WebP',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player', 'browser']
  },

  // Arquivos Compactados
  {
    mime: 'application/zip',
    extensions: ['zip'],
    category: 'archives',
    icon: '📦',
    label: 'Arquivo Compactado ZIP',
    defaultAppId: 'file-explorer',
    compatibleAppIds: ['file-explorer', 'cloudos-files']
  },
  {
    mime: 'application/x-tar',
    extensions: ['tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar'],
    category: 'archives',
    icon: '📦',
    label: 'Pacote Comprimido',
    defaultAppId: 'file-explorer',
    compatibleAppIds: ['file-explorer', 'cloudos-files', 'cloudos-terminal']
  },

  // Áudio & Vídeo
  {
    mime: 'audio/mpeg',
    extensions: ['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'],
    category: 'multimedia',
    icon: '🎵',
    label: 'Arquivo de Áudio',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player']
  },
  {
    mime: 'video/mp4',
    extensions: ['mp4', 'webm', 'mkv', 'avi', 'mov'],
    category: 'multimedia',
    icon: '🎬',
    label: 'Arquivo de Vídeo',
    defaultAppId: 'media-player',
    compatibleAppIds: ['media-player', 'browser']
  },
];

const NATIVE_APP_DETAILS: Record<string, { name: string; icon: string; description: string }> = {
  'notepad': { name: 'Bloco de Notas', icon: '📝', description: 'Editor de texto do CloudOS' },
  'browser': { name: 'Navegador Web', icon: '🌐', description: 'Navegador e visualizador de documentos' },
  'media-player': { name: 'Player Multimídia', icon: '🎬', description: 'Visualizador de imagens, áudio e vídeo' },
  'obsidian-code': { name: 'Obsidian Code', icon: '💻', description: 'Ambiente de desenvolvimento integrado' },
  'file-explorer': { name: 'Explorador de Arquivos', icon: '📁', description: 'Navegador de pastas e arquivos' },
  'cloudos-files': { name: 'CloudOS Files', icon: '☁️', description: 'Gerenciador com pontes POSIX / OPFS' },
  'cloudos-terminal': { name: 'CloudOS Terminal', icon: '⚡', description: 'Terminal de comandos e scripts' },
  'terminal': { name: 'Terminal Offline', icon: '💻', description: 'Terminal local protegido' },
};

const USER_ASSOCIATIONS_STORAGE_KEY = 'cloudos_file_associations_v1';

export function getFileExtension(filename: string): string {
  const clean = filename.trim();
  const lastDot = clean.lastIndexOf('.');
  if (lastDot <= 0 || lastDot === clean.length - 1) return '';
  return clean.slice(lastDot + 1).toLowerCase();
}

export function getMimeTypeForFile(filename: string): string {
  const ext = getFileExtension(filename);
  if (!ext) return 'application/octet-stream';
  const def = MIME_DEFINITIONS.find(d => d.extensions.includes(ext));
  return def ? def.mime : 'application/octet-stream';
}

export function getFileIconForExtension(filename: string): string {
  const ext = getFileExtension(filename);
  if (!ext) return '📄';
  const def = MIME_DEFINITIONS.find(d => d.extensions.includes(ext));
  return def ? def.icon : '📄';
}

export function getUserAssociations(): Record<string, string> {
  try {
    const raw = localStorage.getItem(USER_ASSOCIATIONS_STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return {};
}

export function setUserDefaultApp(extension: string, appId: string): void {
  try {
    const current = getUserAssociations();
    current[extension.toLowerCase()] = appId;
    localStorage.setItem(USER_ASSOCIATIONS_STORAGE_KEY, JSON.stringify(current));
  } catch {}
}

export function getCompatibleApps(filename: string, linuxApps: Array<any> = []): AppAssociation[] {
  const ext = getFileExtension(filename);
  const mime = getMimeTypeForFile(filename);
  const def = MIME_DEFINITIONS.find(d => d.extensions.includes(ext));

  const result: AppAssociation[] = [];
  const addedIds = new Set<string>();

  // 1. Native compatible apps from definition
  if (def) {
    for (const appId of def.compatibleAppIds) {
      if (NATIVE_APP_DETAILS[appId] && !addedIds.has(appId)) {
        addedIds.add(appId);
        result.push({
          id: appId,
          name: NATIVE_APP_DETAILS[appId].name,
          icon: NATIVE_APP_DETAILS[appId].icon,
          description: NATIVE_APP_DETAILS[appId].description,
          isLinux: false,
        });
      }
    }
  }

  // 2. Discover compatible Linux apps by MIME or category
  for (const linuxApp of linuxApps) {
    const rawId = linuxApp.id || linuxApp.linuxAppId || '';
    const cleanId = rawId.startsWith('linux-app-') ? rawId : `linux-app-${rawId}`;
    if (addedIds.has(cleanId)) continue;

    const matchesMime = Array.isArray(linuxApp.mimeTypes) && linuxApp.mimeTypes.includes(mime);
    const isEditor = ['geany', 'mousepad', 'code', 'obsidian', 'vim', 'edit'].some(ed => rawId.includes(ed));
    const isImageViewer = ['gimp', 'display', 'view', 'stego'].some(im => rawId.includes(im));
    const isBrowser = ['firefox', 'chromium'].some(br => rawId.includes(br));

    let compatible = matchesMime;
    if (!compatible && def) {
      if (def.category === 'documents' || def.category === 'code' || def.category === 'spreadsheets' || def.category === 'presentations') {
        compatible = isEditor;
      } else if (def.category === 'images') {
        compatible = isImageViewer;
      } else if (def.category === 'documents' && ext === 'pdf') {
        compatible = isBrowser;
      }
    }

    if (compatible) {
      addedIds.add(cleanId);
      result.push({
        id: cleanId,
        linuxAppId: linuxApp.linuxAppId || linuxApp.id,
        name: linuxApp.name,
        icon: linuxApp.icon || linuxApp.emojiFallback || '🐧',
        description: linuxApp.comment || linuxApp.description || 'Aplicativo Linux',
        isLinux: true,
      });
    }
  }

  // 3. Fallback to Notepad if nothing else
  if (!result.length && NATIVE_APP_DETAILS['notepad']) {
    result.push({
      id: 'notepad',
      name: NATIVE_APP_DETAILS['notepad'].name,
      icon: NATIVE_APP_DETAILS['notepad'].icon,
      description: NATIVE_APP_DETAILS['notepad'].description,
      isLinux: false,
    });
  }

  return result;
}

export function getDefaultAppForFile(filename: string, linuxApps: Array<any> = []): AppAssociation {
  const ext = getFileExtension(filename);
  const userAssoc = getUserAssociations();

  // User override
  if (ext && userAssoc[ext]) {
    const targetId = userAssoc[ext];
    const compatible = getCompatibleApps(filename, linuxApps);
    const found = compatible.find(a => a.id === targetId || a.linuxAppId === targetId);
    if (found) return found;
  }

  const def = MIME_DEFINITIONS.find(d => d.extensions.includes(ext));
  const defaultId = def ? def.defaultAppId : 'notepad';
  const compatible = getCompatibleApps(filename, linuxApps);

  const matched = compatible.find(a => a.id === defaultId);
  if (matched) return matched;

  return compatible[0] || {
    id: 'notepad',
    name: 'Bloco de Notas',
    icon: '📝',
    isLinux: false,
    description: 'Editor de texto padrão'
  };
}
