import { useState } from 'react';
import { Trophy, CheckCircle, Circle, Lock, BookOpen } from 'lucide-react';

export function LabMissionsApp({ openApp }) {
  const [missions, setMissions] = useState([
    { id: 1, title: 'O que é OSINT?', desc: 'Abra o aplicativo Kali Hub e procure por ferramentas de OSINT.', xp: 100, done: false, unlocked: true },
    { id: 2, title: 'Seu primeiro Nmap', desc: 'Use o Tool Runner para rodar um scan básico na sua máquina local (127.0.0.1).', xp: 150, done: false, unlocked: true },
    { id: 3, title: 'Reportando um Finding', desc: 'Abra o Findings Manager e registre uma vulnerabilidade teórica.', xp: 200, done: false, unlocked: true },
  ]);

  const toggleMission = (id) => {
    setMissions(missions.map(m => m.id === id ? { ...m, done: !m.done } : m));
  };

  const totalXP = (Array.isArray(missions) ? missions : []).filter(m => m.done).reduce((acc, m) => acc + m.xp, 0);
  const progress = missions && missions.length > 0 ? ((missions.filter(m => m.done).length / missions.length) * 100) : 0;

  return (
    <div className="flex flex-col h-full bg-[#0d1117] text-gray-300 p-6 overflow-y-auto" style={{ padding: '24px', background: '#0d1117', height: '100%', overflowY: 'auto' }}>
      <header className="mb-6" style={{ marginBottom: '24px' }}>
        <h2 className="text-2xl font-bold text-white flex items-center" style={{ fontSize: '20px', fontWeight: 'bold', color: '#fff', display: 'flex', alignItems: 'center', margin: 0 }}>
          <Trophy className="mr-2 text-yellow-500" size={24} color="#eab308" style={{ marginRight: '8px' }} /> Lab Missions
        </h2>
        <p className="text-sm text-gray-400 mt-1" style={{ fontSize: '13px', color: '#8b949e', marginTop: '4px' }}>Complete missões para aprender Red Team e ganhar XP.</p>
        
        <div className="mt-4 bg-[#161b22] p-4 rounded-lg border border-[#30363d]" style={{ marginTop: '16px', background: '#161b22', padding: '16px', borderRadius: '8px', border: '1px solid #30363d' }}>
          <div className="flex justify-between text-xs mb-2" style={{ display: 'flex', justifyContent: 'space-between', fontSize: '12px', marginBottom: '8px' }}>
            <span style={{ color: '#8b949e' }}>Progresso do Curso</span>
            <span className="text-blue-400 font-bold" style={{ color: '#58a6ff', fontWeight: 'bold' }}>{totalXP} XP</span>
          </div>
          <div className="w-full h-2 bg-[#0d1117] rounded-full overflow-hidden" style={{ width: '100%', height: '8px', background: '#0d1117', borderRadius: '4px', overflow: 'hidden' }}>
            <div className="h-full bg-gradient-to-r from-blue-500 to-purple-500 transition-all duration-500" style={{ width: `${progress}%`, height: '100%', background: 'linear-gradient(to right, #3b82f6, #a855f7)', transition: 'width 0.5s ease' }}></div>
          </div>
        </div>
      </header>

      <div className="space-y-4" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        {missions.map(mission => (
          <div 
            key={mission.id} 
            className={`p-4 rounded-lg border flex items-start ${mission.unlocked ? 'bg-[#161b22] border-[#30363d] hover:border-blue-500 cursor-pointer' : 'bg-[#161b22]/50 border-[#21262d] opacity-50 cursor-not-allowed'}`}
            style={{ padding: '16px', borderRadius: '8px', border: '1px solid #30363d', background: mission.unlocked ? '#161b22' : 'rgba(22, 27, 34, 0.5)', display: 'flex', alignItems: 'flex-start', cursor: mission.unlocked ? 'pointer' : 'not-allowed' }}
            onClick={() => mission.unlocked && toggleMission(mission.id)}
          >
            <div className="mr-4 mt-1" style={{ marginRight: '16px', marginTop: '4px' }}>
              {mission.done ? <CheckCircle className="text-green-500" color="#22c55e" size={20} /> : mission.unlocked ? <Circle className="text-gray-500" color="#8b949e" size={20} /> : <Lock className="text-gray-600" color="#484f58" size={20} />}
            </div>
            <div className="flex-1" style={{ flex: 1 }}>
              <h3 className="font-bold text-white text-sm flex items-center justify-between" style={{ fontWeight: 'bold', color: '#fff', fontSize: '14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', margin: 0 }}>
                {mission.title} 
                <span className="text-xs bg-[#30363d] text-blue-300 px-2 py-0.5 rounded-full" style={{ fontSize: '11px', background: '#30363d', color: '#93c5fd', padding: '2px 8px', borderRadius: '12px' }}>+{mission.xp} XP</span>
              </h3>
              <p className="text-xs text-gray-400 mt-1 flex items-center" style={{ fontSize: '12px', color: '#8b949e', marginTop: '6px', display: 'flex', alignItems: 'center' }}>
                <BookOpen size={12} className="mr-1" style={{ marginRight: '4px' }} /> {mission.desc}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default LabMissionsApp;
