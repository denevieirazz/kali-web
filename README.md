# 🛡️ CloudOS - Kali Linux Web Interface & Operating System

**CloudOS** é um sistema operacional web completo e responsivo rodando no navegador, alimentado por um subsistema **Kali Linux** via WSL 2 no backend com suporte a ferramentas de Pentest, OpSec, gerenciamento de arquivos e editor de código.

---

## 🤖 Guia Completo para IAs e Desenvolvedores (Contexto & Arquitetura)

Se você é um agente de IA ou desenvolvedor trabalhando neste repositório, consulte esta seção para entender a arquitetura técnica completa, os módulos implementados e o estado do sistema.

### 🏗️ Arquitetura do Sistema
```
┌────────────────────────────────┐         WebSocket (ws://) + JWT       ┌──────────────────────────────────────┐
│  cloudos-frontend (React/Vite) │ ────────────────────────────────────> │   cloudos-backend (Node.js/Express)  │
│  Porta: 5173                   │                                       │   Porta: 8080                        │
└────────────────────────────────┘                                       └──────────────────┬───────────────────┘
                                                                                            │ WSL Exec (-u root)
                                                                                            ▼
                                                                         ┌──────────────────────────────────────┐
                                                                         │       WSL 2 (Kali Linux Kernel)      │
                                                                         │  Tmux, Tor, Privoxy, Macchanger, Ext4│
                                                                         └──────────────────────────────────────┘
```

### 📁 Estrutura de Arquivos e Componentes

- **`cloudos-backend/`**: Servidor Node.js (Express + WebSocket + Node-PTY + JWT)
  - `server.js`:
    - **SubsystemManager (Enterprise Layer)**: Classe orientada a objetos que encapsula todos os comandos WSL via Promises `async/await`, gerenciamento de sessões Tmux, controle de processos do sistema e leitura/escrita assíncrona.
    - **Autenticação JWT & Bcrypt**: Autenticação com hash bcrypt e validação de tokens JWT para rotas REST e conexões WebSocket.
    - **Leitura/Escrita de Arquivos**: APIs de listagem (`ls`), ações (`mv`, `mkdir`, `rename`, `delete` com suporte à lixeira `/root/.trash`), upload (`multer`) e leitura/salvamento do Code Editor.
    - **Módulo Tático OpSec**: APIs `/api/tactical/anon` e `/api/tactical/status` para controle do serviço Tor, Privoxy e mascaramento de MAC (`macchanger`).
    - **APIs de Gerenciamento do Subsistema**: Endpoints `/api/subsystem/restart` e `/api/subsystem/processes` para controle de sessão Tmux e monitor de tarefas.
    - **Chaves de Inteligência OSINT**: Armazenamento seguro de chaves de API em `~/.config/cloudos_osint.json`.
    - **Hardware Pass-through (USB)**: Integração com `usbipd-win` (`usbipd.exe`) para acoplar adaptadores Wi-Fi ou pendrives do Windows diretamente no Kali Linux.
- **`cloudos-frontend/`**: Aplicação Web React 18 + Vite + Monaco Editor
  - `src/main.jsx`: Ponto de entrada com polyfill `window.process`.
  - `src/App.jsx`: Gerenciador da área de trabalho estilo Windows 11, alinhamento de ícones em grade (`grid`), seleção visual, efeito de atualização *flash* sem recarregar e controle de estado do login.
  - `src/LoginScreen.jsx`: Tela de bloqueio e login (Windows 11 Glassmorphism style) com autenticação JWT.
  - `src/BootScreen.jsx`: Tela de boot cinemática com efeito CRT Scanlines, Logo Glitch RGB e barra de progresso neon com proteção contra o *React 18 Strict Mode*.
  - `src/apps.jsx`: 
    - `TerminalApp`: Terminal interativo xterm.js conectado via WebSocket autenticado com suporte a redimensionamento de janela.
    - `FileManagerApp`: Gerenciador de arquivos completo com visualização em grade/lista, migalhas de pão (*breadcrumbs*), upload, lixeira e menu de contexto teletransportado via React Portal (`document.body`).
    - `CodeEditorApp`: Editor de código baseado no Monaco Editor com suporte a destaque de sintaxe e atalho `Ctrl+S`.
    - `SettingsApp`: Centro de Controle Tático de 4 abas (Aparência, Anonimato OpSec em tempo real, OSINT APIs e Hardware USB).
    - `NotepadApp`: Bloco de notas com salvamento local.
  - `src/Window.jsx`: Componente de janela arrastável e maximizável baseado em `react-rnd` envolvido por um `WindowErrorBoundary`.
  - `src/index.css`: Sistema de design visual completo com glassmorphism, scanlines CRT, efeito de brilho neon e temas táticos.

---

## 📋 Pré-requisitos do Sistema

Para rodar o projeto no Windows:

1. **WSL 2 (Windows Subsystem for Linux) com Kali Linux**
   - Instale a distribuição Kali Linux via PowerShell (Administrador):
     ```powershell
     wsl --install -d kali-linux
     ```
2. **Pacotes OpSec no Kali Linux**
   - Executados via terminal ou instalados automaticamente pelo backend:
     ```bash
     sudo apt update && sudo apt install -y tor privoxy macchanger
     ```
3. **usbipd-win (Opcional para Hardware USB)**
   - Para compartilhar dispositivos USB do Windows com o WSL:
     ```powershell
     winget install usbipd
     ```
4. **Node.js (v18+)**
   - Baixe e instale o [Node.js](https://nodejs.org/).

---

## 🚀 Como Executar

### Opção 1: Execução Automática (Silenciosa em Segundo Plano)
Basta dar **duplo clique** no atalho:
👉 `iniciar-cloudos.bat`

---

### Opção 2: Execução Manual pelo Terminal

#### 1. Iniciar o Backend
```bash
cd cloudos-backend
npm install
node server.js
```
*O backend estará rodando na porta `8080`.*

#### 2. Iniciar o Frontend
```bash
cd cloudos-frontend
npm install
npm run dev
```
*O frontend estará acessível em `http://localhost:5173`.*

---

## 🔑 Credenciais Padrão
- **Usuário**: `admin`
- **Senha**: `admin123`

---

## 🛠️ Módulos e Histórico de Desenvolvimento

1. **Autenticação JWT & Lock Screen**: Proteção de endpoints e sessões de WebSocket com tokens JWT e tela de bloqueio estilizada.
2. **Centro de Controle Tático OpSec**: Leitura de temperatura do Kali em tempo real (Tor status e MAC real ativo).
3. **Monaco Code Editor**: Editor de código integrado para scripts de pentest e configurações no Kali.
4. **Boot Screen Cinemática**: Efeitos visuais CRT scanlines, logo glitch RGB e temporizador seguro contra re-renders.
5. **Gerenciador de Arquivos SaaS**: Manipulação remota de arquivos no WSL com suporte a lixeira `/root/.trash` e upload.
6. **Regra de Autonomia de IA**: Arquivo `.agents/AGENTS.md` definindo execução direta e autônoma de tarefas para agentes de IA.

---

## 📜 Licença
Este projeto é de uso livre para fins educacionais, de pesquisa e de estudo.
