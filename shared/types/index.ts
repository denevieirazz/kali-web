export type AppCategory = 
  | 'system'
  | 'utilities'
  | 'development'
  | 'security'
  | 'productivity'
  | 'media';

export type AppPermission = 
  | 'local-files'
  | 'remote-files'
  | 'terminal'
  | 'system-metrics'
  | 'notifications'
  | 'settings'
  | 'admin-operation';

export interface WindowDimensions {
  width: number;
  height: number;
  minWidth?: number;
  minHeight?: number;
  maxWidth?: number;
  maxHeight?: number;
  x?: number;
  y?: number;
}

export interface AppManifest {
  id: string;
  name: string;
  description: string;
  icon: string;
  category: AppCategory;
  permissions: AppPermission[];
  singleton: boolean;
  defaultWindow: {
    title: string;
    dimensions: WindowDimensions;
    resizable?: boolean;
    maximizable?: boolean;
  };
}

export type OperationStatus = 
  | 'pending'
  | 'running'
  | 'waiting_user'
  | 'reboot_required'
  | 'completed'
  | 'cancelled'
  | 'failed';

export interface OperationRecord {
  id: string;
  type: string;
  status: OperationStatus;
  progress: number;
  step: string;
  message: string;
  errorCode?: string;
  createdAt: string;
  updatedAt: string;
}

export interface UserSession {
  username: string;
  role: 'admin' | 'user';
  authenticated: boolean;
  token?: string;
}

export type FileSystemProviderType = 'local' | 'cloudos' | 'linux';

export interface UnifiedFileEntry {
  id: string;
  name: string;
  path: string;
  provider: FileSystemProviderType;
  isDirectory: boolean;
  size: number;
  updatedAt: string;
  mimeType?: string;
}
