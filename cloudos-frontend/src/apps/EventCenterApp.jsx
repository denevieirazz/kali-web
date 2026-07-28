import { useState, useEffect } from 'react';
import { Activity, AlertCircle, Info, Save } from 'lucide-react';

export const EventCenterApp = () => {
  const [events, setEvents] = useState([]);

  const fetchEvents = () => {
    fetch('http://localhost:8080/api/events', {
      headers: { 'Authorization': `Bearer ${localStorage.getItem('cloudos_token')}` }
    })
      .then(res => res.json())
      .then(data => setEvents(Array.isArray(data) ? data : []))
      .catch(console.error);
  };

  useEffect(() => {
    fetchEvents();
    const interval = setInterval(fetchEvents, 5000);
    return () => clearInterval(interval);
  }, []);

  const getIcon = (type) => {
    if (type && type.includes('error')) return <AlertCircle size={16} color="#f87171" />;
    if (type && (type.includes('snapshot') || type.includes('workspace'))) return <Save size={16} color="#60a5fa" />;
    return <Info size={16} color="#9ca3af" />;
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#0d1117', color: '#c9d1d9' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '15px', borderBottom: '1px solid #30363d' }}>
        <h2 style={{ fontSize: '16px', fontWeight: 'bold', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
          <Activity size={20} color="#58a6ff" /> Event Center
        </h2>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '15px', fontFamily: 'monospace', fontSize: '12px' }}>
        {events.length === 0 ? (
          <div style={{ color: '#6e7681', textAlign: 'center', marginTop: '40px' }}>Nenhum evento registrado.</div>
        ) : (
          events.map(ev => (
            <div key={ev.id} style={{ display: 'flex', alignItems: 'flex-start', gap: '12px', padding: '10px', background: '#161b22', borderRadius: '6px', border: '1px solid #30363d', marginBottom: '8px' }}>
              <div style={{ marginTop: '2px' }}>{getIcon(ev.event_type)}</div>
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: '#58a6ff', fontWeight: 'bold' }}>{ev.event_type}</span>
                  <span style={{ color: '#6e7681', fontSize: '10px' }}>{new Date(ev.created_at).toLocaleString()}</span>
                </div>
                <div style={{ color: '#8b949e', marginTop: '4px' }}>{ev.details}</div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
