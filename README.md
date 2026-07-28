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

- **`cloudos-backend/`**: Servidor Node.js (Express + WebSocket + Node-PTY + JWT + SQLite)
  - `database.js`:
    - **Camada de Banco de Dados (SQLite)**: Inicialização das tabelas `users`, `user_settings`, `desktop_state`, `notifications` e `system_events` com modo WAL e chaves estrangeiras.
  - `server.js`:
    - **SubsystemManager (Enterprise Security Layer)**:
      - **Acesso Nativo ao Sistema de Arquivos (Node FS)**: Acesso direto ao sistema de arquivos do WSL2 via caminho UNC de rede (`\\\\wsl.localhost\\kali-linux\\home\\cloudos_users\\...`), eliminando concatenações de shell.
      - **Proteção contra Path Traversal**: Validação estrita via `getSecurePath()` impedindo acessos fora do diretório do usuário.
      - **Isolamento de Usuário Não-Root**: Execução dos comandos e sessões Tmux como usuário `cloudos` (não-root).
      - **Mascaramento Automático de MAC**: Mascaramento por padrão de endereços físicos para proteção OpSec.
    - **Persistência de Estado SaaS**: APIs `/api/user/state`, `/api/user/settings` e `/api/user/desktop` para salvamento e restauração da área de trabalho, janelas abertas e ícones por usuário.
    - **Streaming de Arquivos & ZIP**: APIs `/api/files/properties` para metadados e `/api/files/download` para geração e streaming de ZIP nativo via WSL sem sobrecarga de memória.
    - **Autenticação JWT & Registro**: Autenticação com hash bcrypt, registro de usuários (`/api/auth/register`) e validação de tokens JWT.
- **`cloudos-frontend/`**: Aplicação Web React 18 + Vite + Monaco Editor (Arquitetura SaaS Enterprise)
  - `src/main.jsx`: Ponto de entrada com polyfill `window.process`.
  - `src/hooks/useCloudFS.js`: Custom Hook que isola a lógica de rede do gerenciador de arquivos (Single Responsibility Principle).
  - `src/store/CloudOSContext.jsx`: Provedor global de estado sincronizado com o banco SQLite (papel de parede, ícones, janelas e notificações).
  - `src/components/CommandPalette.jsx`: Overlay de busca e comandos instantâneos acionado pelo atalho `Ctrl+Shift+P`.
  - `src/registry.jsx`: Registro centralizado de aplicativos (`AppRegistry`).
  - `src/App.jsx`: Área de trabalho interativa conectada ao `CloudOSProvider`, com Command Palette, Notification Center lateral, bloqueio de tela e navegação.
  - `src/LoginScreen.jsx`: Tela de bloqueio e login (Windows 11 Glassmorphism style) com autenticação JWT.
  - `src/BootScreen.jsx`: Tela de boot cinemática com efeito CRT Scanlines e Logo Glitch RGB.
  - `src/apps/FileManagerApp.jsx`: Gerenciador de arquivos premium com XMLHttpRequest upload progress bar, download de pastas em ZIP via stream, menu contextual React Portal ("Abrir Terminal Aqui", "Editar Código", "Baixar ZIP") e lixeira nativa.
  - `src/apps/SettingsApp.jsx`: Painel de configurações estilo Windows 11/macOS com abas (Aparência, Conta/Planos, Armazenamento WSL, Terminal, Sobre) integrado com o `CloudOSContext`.

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
