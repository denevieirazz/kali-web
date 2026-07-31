import { createContext, useState, useEffect, useContext, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';
const CloudOSContext = createContext();

export const useCloudOS = () => useContext(CloudOSContext);

export const CloudOSProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [settings, setSettings] = useState({ wallpaper: 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)' });
  const [desktopState, setDesktopState] = useState({ icon_positions: {}, open_windows: [], taskbar_pins: [] });
  const [notifications, setNotifications] = useState([]);
  const [pinnedApps, setPinnedApps] = useState([]);
  const [isLocked, setIsLocked] = useState(false);
  const [activeProject, setActiveProject] = useState(null);

  const fetchAll = useCallback(async () => {
    const currentToken = localStorage.getItem('cloudos_token');
    if (!currentToken) {
      setLoading(false);
      setIsAuthenticated(false);
      return;
    }

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${currentToken}`
    };

    try {
      // 1. Fetch State
      const stateRes = await fetch(`${API_BASE}/api/user/state`, { headers });
      if (stateRes.status === 403 || stateRes.status === 401) {
        localStorage.removeItem('cloudos_token');
        setIsAuthenticated(false);
        setLoading(false);
        return;
      }

      if (stateRes.ok) {
        const data = await stateRes.json();
        if (data.user) setUser(data.user);
        if (data.settings) setSettings(data.settings);
        if (data.desktop) {
          setDesktopState({
            icon_positions: JSON.parse(data.desktop.icon_positions || '{}'),
            open_windows: JSON.parse(data.desktop.open_windows || '[]'),
            taskbar_pins: JSON.parse(data.desktop.taskbar_pins || '[]')
          });
        }
        setIsAuthenticated(true);
      }

      // 2. Fetch Notifications
      const notifRes = await fetch(`${API_BASE}/api/notifications`, { headers });
      if (notifRes.ok) {
        const notifData = await notifRes.json();
        setNotifications(Array.isArray(notifData) ? notifData : []);
      }

      // 3. Fetch Apps
      const appsRes = await fetch(`${API_BASE}/api/apps`, { headers });
      if (appsRes.ok) {
        const appsData = await appsRes.json();
        if (Array.isArray(appsData)) {
          setPinnedApps(appsData.filter(a => a.is_pinned).map(a => a.app_id));
        }
      }
    } catch (e) {
      console.error("Erro ao carregar dados iniciais", e);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  const togglePin = async (appId, isPinned) => {
    setPinnedApps(prev => isPinned ? [...prev, appId] : prev.filter(id => id !== appId));
    const token = localStorage.getItem('cloudos_token');
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
    const token = localStorage.getItem('cloudos_token');
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
      user, isAuthenticated, loading, settings, setSettings, desktopState, saveDesktopState, 
      notifications, fetchNotifications: fetchAll, pinnedApps, togglePin, isLocked, lockSystem,
      activeProject, setActiveProject
    }}>
      {children}
    </CloudOSContext.Provider>
  );
};
