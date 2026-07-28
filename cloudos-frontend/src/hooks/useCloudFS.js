import { useState, useCallback } from 'react';

const API_BASE = 'http://localhost:8080';
const token = () => localStorage.getItem('cloudos_token');

export const useCloudFS = () => {
  const [path, setPath] = useState('');
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const fetchFiles = useCallback(async (newPath) => {
    setLoading(true); setError(null); setPath(newPath);
    try {
      const res = await fetch(`${API_BASE}/api/files?path=${encodeURIComponent(newPath)}`, {
        headers: { 'Authorization': `Bearer ${token()}` }
      });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      setItems(data.items || []);
    } catch (e) { setError(e.message); } 
    finally { setLoading(false); }
  }, []);

  const action = useCallback(async (endpoint, body) => {
    const res = await fetch(`${API_BASE}/api/files/${endpoint}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token()}` },
      body: JSON.stringify(body)
    });
    return res.json();
  }, []);

  return { path, items, loading, error, fetchFiles, action };
};
