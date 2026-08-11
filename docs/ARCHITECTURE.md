# Arquitetura Técnica — CloudOS-Unified

## 1. Visão Geral
CloudOS-Unified une três camadas fundamentais em uma arquitetura monorepo limpa:

- **Frontend (React 19 + TypeScript + Vite 6 + Zustand 5)**:
  - Sistema de janelas com arraste, snap e redimensionamento (`react-rnd`).
  - Terminal com renderização de alta performance (`xterm.js`).
  - Armazenamento em sandbox privado do navegador via `OPFS` (`opfsDriver.ts`).
- **Backend (Node.js + Express + WebSockets + PTY)**:
  - Servidor REST e WebSockets rodando em `127.0.0.1:5000`.
  - Sessões de terminal reais isoladas por PTY e token JWT.
  - Métricas de host em tempo real com `systeminformation`.
- **Shared**:
  - Contrato formal de TypeScript (`AppManifest`, `WindowDimensions`, `OperationRecord`).

---

## 2. Provedores de Sistema de Arquivos (Storage)
1. `local://`: Origin Private File System (OPFS) privado do navegador.
2. `cloudos://`: Espaço gerenciado pelo backend remoto.
3. `linux://`: Ponte futura para WSL isolado.
