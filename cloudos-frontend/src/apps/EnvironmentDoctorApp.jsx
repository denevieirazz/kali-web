import { useState, useEffect } from 'react';
import { Stethoscope, CheckCircle, XCircle, Loader } from 'lucide-react';

export function EnvironmentDoctorApp() {
  const [checks, setChecks] = useState([]);
  const [loading, setLoading] = useState(true);

  const token = localStorage.getItem('cloudos_token');

  const runCheck = async () => {
    setLoading(true);
    try {
      const res = await fetch('http://localhost:8080/api/v3/doctor', { headers: { 'Authorization': `Bearer ${token}` } });
      if (res.ok) setChecks(await res.json());
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { runCheck(); }, []);

  return (
    <div style={{ position: 'absolute', inset: 0, padding: 24, background: '#0d1117', color: '#c9d1d9', overflowY: 'auto', fontFamily: 'Inter, sans-serif' }}>
      <h2 style={{ fontSize: 16, marginBottom: 24, display: 'flex', alignItems: 'center', gap: 8 }}>
        <Stethoscope size={16} color="#58a6ff" /> Environment Doctor
      </h2>
      
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, maxWidth: 400 }}>
        {loading ? (
          <div style={{ color: '#8b949e', display: 'flex', alignItems: 'center', gap: 8 }}><Loader size={16} /> Diagnosticando ambiente...</div>
        ) : (
          checks.map(c => (
            <div key={c.name} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontSize: 13, fontWeight: 500 }}>{c.name}</span>
              {c.status === 'ok' ? <CheckCircle size={18} color="#3fb950" /> : <XCircle size={18} color="#f85149" />}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default EnvironmentDoctorApp;
