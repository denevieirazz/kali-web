import { createContext, useState, useEffect, useContext, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';
const CloudOSContext = createContext();

export const useCloudOS = () => useContext(CloudOSContext);

export const CloudOSProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [settings, setSettings] = useState({ wallpaper: 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070' });
  const [desktopState, setDesktopState] = useState({ icon_positions: {}, open_windows: [], taskbar_pins: [] });
  const [notifications, setNotifications] = useState([]);
  const [pinnedApps, setPinnedApps] = useState([]);
  const [isLocked, setIsLocked] = useState(false);
  const token = localStorage.getItem('cloudos_token');

  const fetchState = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_BASE}/api/user/state`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await res.json();
      
      if (data.settings) setSettings(data.settings);
      if (data.desktop) {
        setDesktopState({
          icon_positions: JSON.parse(data.desktop.icon_positions || '{}'),
          open_windows: JSON.parse(data.desktop.open_windows || '[]'),
          taskbar_pins: JSON.parse(data.desktop.taskbar_pins || '[]')
        });
      }
    } catch (e) { console.error("Erro ao buscar estado", e); }
  }, [token]);

  const fetchNotifications = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_BASE}/api/notifications`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await res.json();
      if (Array.isArray(data)) setNotifications(data);
    } catch (e) {}
  }, [token]);

  const fetchPinnedApps = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetch(`${API_BASE}/api/apps`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await res.json();
      if (Array.isArray(data)) {
        setPinnedApps(data.filter(a => a.is_pinned).map(a => a.app_id));
      }
    } catch (e) {}
  }, [token]);

  useEffect(() => {
    fetchState();
    fetchNotifications();
    fetchPinnedApps();
  }, [fetchState, fetchNotifications, fetchPinnedApps]);

  const togglePin = async (appId, isPinned) => {
    setPinnedApps(prev => isPinned ? [...prev, appId] : prev.filter(id => id !== appId));
    if (!token) return;
    try {
      await fetch(`${API_BASE}/api/apps/toggle`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify({ app_id: appId, is_pinned: isPinned })
      });
    } catch (e) {}
  };

  const saveDesktopState = async (newState) => {
    setDesktopState(newState);
    if (!token) return;
    try {
      await fetch(`${API_BASE}/api/user/desktop`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify(newState)
      });
    } catch (e) {}
  };

  const lockSystem = () => setIsLocked(true);

  return (
    <CloudOSContext.Provider value={{ 
      user, settings, setSettings, desktopState, saveDesktopState, 
      notifications, fetchNotifications, pinnedApps, togglePin, isLocked, lockSystem 
    }}>
      {children}
    </CloudOSContext.Provider>
  );
};
