// ============================================
// CloudOS Download Manager Store & Service
// ============================================
import { create } from 'zustand';
import kernel from '../core/kernel';
import { useUserStore } from './userStore';
import { getFileExtension, getMimeTypeForFile } from '../services/mimeRegistry';

export interface DownloadItem {
  id: string;
  name: string;
  size: number;
  progress: number;
  status: 'pending' | 'downloading' | 'completed' | 'failed';
  filePath: string;
  mimeType: string;
  url?: string;
  startedAt: number;
  completedAt?: number;
  error?: string;
}

interface DownloadManagerState {
  downloads: DownloadItem[];
  isModalOpen: boolean;
  addDownload: (item: { name: string; size?: number; content?: string; url?: string; mimeType?: string }) => string;
  removeDownload: (id: string) => void;
  clearCompleted: () => void;
  openDownloadModal: () => void;
  closeDownloadModal: () => void;
}

const STORAGE_KEY = 'cloudos_download_manager_history_v1';

function getStoredDownloads(): DownloadItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return [];
}

function persistDownloads(items: DownloadItem[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(items.slice(0, 50)));
  } catch {}
}

export const useDownloadManager = create<DownloadManagerState>((set, get) => ({
  downloads: getStoredDownloads(),
  isModalOpen: false,

  openDownloadModal: () => set({ isModalOpen: true }),
  closeDownloadModal: () => set({ isModalOpen: false }),

  addDownload: ({ name, size = 1024, content, url, mimeType }) => {
    const id = `dl-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const ext = getFileExtension(name);
    const resolvedMime = mimeType || getMimeTypeForFile(name);

    // Save into CloudOS Downloads directory
    const user = useUserStore.getState().currentUser?.username || 'User';
    const downloadsDir = `C:\\Users\\${user}\\Downloads`;
    const filePath = `${downloadsDir}\\${name}`;

    try {
      // Ensure Downloads directory exists and create file
      if (!kernel.fsExists(downloadsDir)) {
        kernel.fsCreateDirectory(`C:\\Users\\${user}`, 'Downloads');
      }
      kernel.fsCreateFile(downloadsDir, name, content || '', ext);
    } catch {}

    const newItem: DownloadItem = {
      id,
      name,
      size: content ? content.length : size,
      progress: 0,
      status: 'downloading',
      filePath,
      mimeType: resolvedMime,
      url,
      startedAt: Date.now()
    };

    set(state => {
      const next = [newItem, ...state.downloads];
      persistDownloads(next);
      return { downloads: next };
    });

    // Simulate progress cleanly
    let currentProgress = 0;
    const interval = setInterval(() => {
      currentProgress += 25;
      if (currentProgress >= 100) {
        clearInterval(interval);
        set(state => {
          const next = state.downloads.map(item =>
            item.id === id
              ? { ...item, progress: 100, status: 'completed' as const, completedAt: Date.now() }
              : item
          );
          persistDownloads(next);
          return { downloads: next };
        });
        window.dispatchEvent(new CustomEvent('cloudos:download-completed', { detail: { id, name, filePath } }));
      } else {
        set(state => ({
          downloads: state.downloads.map(item =>
            item.id === id ? { ...item, progress: currentProgress } : item
          )
        }));
      }
    }, 120);

    return id;
  },

  removeDownload: (id) => {
    set(state => {
      const next = state.downloads.filter(item => item.id !== id);
      persistDownloads(next);
      return { downloads: next };
    });
  },

  clearCompleted: () => {
    set(state => {
      const next = state.downloads.filter(item => item.status !== 'completed');
      persistDownloads(next);
      return { downloads: next };
    });
  }
}));
