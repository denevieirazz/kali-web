import type { NativeApp } from '../../services/systemHubClient';

export interface CloudStartMenuApp {
  id: string;
  name: string;
  icon: string;
  defaultWidth?: number;
  defaultHeight?: number;
  minWidth?: number;
  minHeight?: number;
  isResizable?: boolean;
  binaryPath?: string;
}

export type StartMenuApp =
  | (CloudStartMenuApp & { launcher: 'cloud'; source: 'cloudos' })
  | (NativeApp & {
      launcher: 'native';
      defaultWidth: number;
      defaultHeight: number;
      minWidth: number;
      minHeight: number;
      isResizable: true;
    });

export function mergeStartMenuCatalog(
  cloudApps: CloudStartMenuApp[],
  nativeApps: NativeApp[],
): StartMenuApp[];

export function searchStartMenuCatalog(apps: StartMenuApp[], query: string): StartMenuApp[];

