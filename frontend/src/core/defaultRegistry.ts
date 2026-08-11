// ============================================
// Registry Store - Windows-like Registry System
// ============================================
export type RegistryValue = string | number | boolean | string[];

export interface RegistryEntry {
  type: 'REG_SZ' | 'REG_DWORD' | 'REG_BINARY' | 'REG_MULTI_SZ' | 'REG_EXPAND_SZ' | 'REG_QWORD';
  value: RegistryValue;
}
export const defaultRegistry: Record<string, Record<string, RegistryEntry>> = {
  'HKEY_CURRENT_USER\\Software\\ObsidianOS\\Desktop': {
    Wallpaper: { type: 'REG_SZ', value: 'default' },
    WallpaperStyle: { type: 'REG_DWORD', value: 2 },
    IconSize: { type: 'REG_DWORD', value: 48 },
    ShowDesktopIcons: { type: 'REG_DWORD', value: 1 },
  },
  'HKEY_CURRENT_USER\\Software\\ObsidianOS\\Themes': {
    CurrentTheme: { type: 'REG_SZ', value: 'dark' },
    AccentColor: { type: 'REG_SZ', value: '#6366f1' },
    TransparencyEnabled: { type: 'REG_DWORD', value: 1 },
    AnimationSpeed: { type: 'REG_SZ', value: 'normal' },
  },
  'HKEY_CURRENT_USER\\Software\\ObsidianOS\\Taskbar': {
    Position: { type: 'REG_SZ', value: 'bottom' },
    Alignment: { type: 'REG_SZ', value: 'center' },
    AutoHide: { type: 'REG_DWORD', value: 0 },
    ShowSearch: { type: 'REG_DWORD', value: 1 },
    ShowWidgets: { type: 'REG_DWORD', value: 1 },
    ShowTaskView: { type: 'REG_DWORD', value: 1 },
    Size: { type: 'REG_SZ', value: 'medium' },
  },
  'HKEY_CURRENT_USER\\Software\\ObsidianOS\\Explorer': {
    ShowHiddenFiles: { type: 'REG_DWORD', value: 0 },
    ShowFileExtensions: { type: 'REG_DWORD', value: 1 },
    DefaultView: { type: 'REG_SZ', value: 'details' },
  },
  'HKEY_LOCAL_MACHINE\\SOFTWARE\\ObsidianOS\\CurrentVersion': {
    ProductName: { type: 'REG_SZ', value: 'ObsidianOS' },
    DisplayVersion: { type: 'REG_SZ', value: '24H2' },
    CurrentBuild: { type: 'REG_SZ', value: '26100' },
    BuildLabEx: { type: 'REG_SZ', value: '26100.1.amd64fre.ge_release.240331-1435' },
    EditionID: { type: 'REG_SZ', value: 'Professional' },
    InstallationType: { type: 'REG_SZ', value: 'Client' },
    RegisteredOwner: { type: 'REG_SZ', value: 'User' },
  },
  'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment': {
    OS: { type: 'REG_SZ', value: 'ObsidianOS_NT' },
    PROCESSOR_ARCHITECTURE: { type: 'REG_SZ', value: 'AMD64' },
    NUMBER_OF_PROCESSORS: { type: 'REG_SZ', value: '8' },
    PATH: { type: 'REG_EXPAND_SZ', value: 'C:\\ObsidianOS\\System32;C:\\ObsidianOS;C:\\ObsidianOS\\System32\\Wbem' },
    TEMP: { type: 'REG_EXPAND_SZ', value: 'C:\\Users\\User\\AppData\\Local\\Temp' },
    TMP: { type: 'REG_EXPAND_SZ', value: 'C:\\Users\\User\\AppData\\Local\\Temp' },
  },
  'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management': {
    PhysicalMemoryMB: { type: 'REG_DWORD', value: 8192 },
    PagingFileLimit: { type: 'REG_DWORD', value: 16384 },
    VirtualMemoryEnabled: { type: 'REG_DWORD', value: 1 },
  },
  'HKEY_CLASSES_ROOT\\.txt': {
    ContentType: { type: 'REG_SZ', value: 'text/plain' },
    DefaultApp: { type: 'REG_SZ', value: 'notepad' },
  },
  'HKEY_CLASSES_ROOT\\.html': {
    ContentType: { type: 'REG_SZ', value: 'text/html' },
    DefaultApp: { type: 'REG_SZ', value: 'browser' },
  },
  'HKEY_CLASSES_ROOT\\.js': {
    ContentType: { type: 'REG_SZ', value: 'application/javascript' },
    DefaultApp: { type: 'REG_SZ', value: 'notepad' },
  },
  'HKEY_CLASSES_ROOT\\.webm': {
    ContentType: { type: 'REG_SZ', value: 'video/webm' },
    DefaultApp: { type: 'REG_SZ', value: 'media-player' },
  },
  'HKEY_CLASSES_ROOT\\.mp4': {
    ContentType: { type: 'REG_SZ', value: 'video/mp4' },
    DefaultApp: { type: 'REG_SZ', value: 'media-player' },
  },
  'HKEY_LOCAL_MACHINE\\SYSTEM\\LiveMode': {
    ApiUrl: { type: 'REG_SZ', value: '' },
    CloudSyncEnabled: { type: 'REG_DWORD', value: 1 },
    LastSync: { type: 'REG_SZ', value: '' },
  },
  'HKEY_LOCAL_MACHINE\\SYSTEM\\Setup': {
    SetupInProgress: { type: 'REG_DWORD', value: typeof window !== 'undefined' && localStorage.getItem('obsidianos-setup-completed') === 'true' ? 0 : 1 },
    OOBEInProgress:  { type: 'REG_DWORD', value: typeof window !== 'undefined' && localStorage.getItem('obsidianos-setup-completed') === 'true' ? 0 : 1 },
  },
};

