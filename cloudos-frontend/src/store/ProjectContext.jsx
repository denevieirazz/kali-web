import { createContext, useContext, useState, useEffect } from 'react';

const ProjectContext = createContext();

export function ProjectProvider({ children }) {
  const [activeProject, setActiveProject] = useState(null);
  const [scopes, setScopes] = useState([]);

  const token = localStorage.getItem('cloudos_token');
  const headers = { 'Authorization': `Bearer ${token}` };

  useEffect(() => {
    const savedProjectId = localStorage.getItem('cloudos_active_project');
    if (savedProjectId) {
      fetch(`http://localhost:8080/api/projects/${savedProjectId}`, { headers })
        .then(res => res.ok ? res.json() : null)
        .then(data => {
          if (data) {
            setActiveProject(data);
            fetch(`http://localhost:8080/api/projects/${data.id}/scopes`, { headers })
              .then(res => res.ok ? res.json() : [])
              .then(setScopes)
              .catch(() => setScopes([]));
          }
        })
        .catch(() => {});
    }
  }, []);

  const switchProject = async (projectId) => {
    const res = await fetch(`http://localhost:8080/api/projects/${projectId}`, { headers });
    if (res.ok) {
      const data = await res.json();
      setActiveProject(data);
      localStorage.setItem('cloudos_active_project', data.id);
      
      const scopeRes = await fetch(`http://localhost:8080/api/projects/${data.id}/scopes`, { headers });
      if (scopeRes.ok) setScopes(await scopeRes.json());
    }
  };

  return (
    <ProjectContext.Provider value={{ activeProject, switchProject, scopes, setActiveProject }}>
      {children}
    </ProjectContext.Provider>
  );
}

export function useProject() {
  return useContext(ProjectContext);
}
