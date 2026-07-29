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
    - **Camada de Banco de Dados (SQLite)**: Tabelas `users`, `user_settings`, `desktop_state`, `workspaces`, `snapshots`, `system_events`, `file_metadata`, `installed_apps` e `notifications` em modo WAL.
  - `server.js`:
    - **SubsystemManager (Enterprise Security Layer)**:
      - **Acesso Nativo ao Sistema de Arquivos (Node FS)**: Acesso direto ao sistema de arquivos do WSL2 via caminho UNC de rede (`\\\\wsl.localhost\\kali-linux\\home\\cloudos_users\\...`), eliminando concatenações de shell.
      - **Proteção contra Path Traversal**: Validação estrita via `getSecurePath()` impedindo acessos fora do diretório do usuário.
      - **Isolamento de Usuário Não-Root**: Execução dos comandos e sessões Tmux como usuário `cloudos` (não-root).
      - **Mascaramento Automático de MAC**: Mascaramento por padrão de endereços físicos para proteção OpSec.
    - **Persistência de Estado SaaS & Workspaces**: APIs `/api/workspaces`, `/api/snapshots`, `/api/events`, `/api/files/favorites`, `/api/apps` e `/api/kali/tools` para gestão de ambientes de pentest, fixação de apps, catálogo tático e auditoria em tempo real.
    - **Proteção e Compatibilidade de Token**: Middleware com resolução inteligente de IDs legados para os registros do banco de dados SQLite, eliminando erros 500 por tokens expirados/desincronizados.
    - **Streaming de Arquivos & ZIP**: APIs `/api/files/properties` para metadados e `/api/files/download` para geração e streaming de ZIP nativo via WSL sem sobrecarga de memória.
    - **Autenticação JWT & Registro**: Autenticação com hash bcrypt, registro de usuários (`/api/auth/register`) e validação de tokens JWT.
- **`cloudos-frontend/`**: Aplicação Web React 18 + Vite + Monaco Editor (Arquitetura SaaS Enterprise Multi-Dispositivo)
  - `src/main.jsx`: Ponto de entrada com polyfill `window.process`.
  - `src/hooks/useCloudFS.js`: Custom Hook que isola a lógica de rede do gerenciador de arquivos (Single Responsibility Principle).
  - `src/store/CloudOSContext.jsx`: Provedor global de estado sincronizado com o banco SQLite (papel de parede, ícones, janelas, apps fixados e notificações).
  - `src/components/CommandPalette.jsx`: Overlay de busca e comandos instantâneos acionado pelo atalho `Ctrl+Shift+P`.
  - `src/registry.jsx`: Registro centralizado de aplicativos (`AppRegistry`).
  - `src/App.jsx`: Área de trabalho interativa com detecção de modo Mobile (`isMobile < 768px`), janelas full-screen responsivas, taskbar customizável por usuário e navegação.
  - `src/Window.jsx`: Componente de janela com suporte a telas cheias responsivas e limites adaptativos para smartphones/tablets.
  - `src/LoginScreen.jsx`: Tela de bloqueio e login (Windows 11 Glassmorphism style) com autenticação JWT.
  - `src/BootScreen.jsx`: Tela de boot cinemática com efeito CRT Scanlines, Logo Glitch RGB e proteção contra re-renders assíncronos (`onBootCompleteRef`).
  - `src/apps/KaliHubApp.jsx`: Central de ferramentas Kali Linux com checagem de status no WSL em tempo real, busca por tags/categorias, gerenciamento de favoritos e lançamento seguro no Terminal.
  - `src/apps/FileManagerApp.jsx`: Gerenciador de arquivos premium com layout de 2 colunas (sidebar VS Code Explorer + grid), status bar inferior com indicador WSL isolado, carregamento com spinner animated, XMLHttpRequest upload progress bar, download de pastas em ZIP via stream, menu contextual React Portal e lixeira nativa.
  - `src/apps/AppStoreApp.jsx`: Loja interna de aplicativos com filtro de busca e opção de fixar/desfixar ferramentas na barra de tarefas.
  - `src/apps/EventCenterApp.jsx`: Central de eventos e logs de auditoria do sistema em tempo real (`/api/events`).
  - `src/apps/SettingsApp.jsx`: Control Center com abas (Aparência, Armazenamento WSL, Snapshots & Backups, Informações do Sistema, Sobre) integrado com o `CloudOSContext`.

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
7. **Ajustes de Terminal & Validação de APIs**: Correção na renderização de dados UTF-8 no xterm WebSocket do `TerminalApp` e tratamentos defensivos no backend (`POST /api/snapshots/create`).
8. **Kali Tool Runner (GUI Dinâmica)**: Arquitetura Enterprise baseada em Schemas JSON (`kali_tools_schema.js`), servindo rotas `/api/kali/tools/:id/schema`, renderizador de formulário automático (`ToolRunnerApp.jsx`) e integração com `KaliHubApp` para montagem e envio seguro de comandos para o terminal.
9. **Favicon & Suporte Offline**: Criação dos arquivos `favicon.ico` e `favicon.svg` na pasta `public/` e substituição dos papéis de parede remotos por gradientes CSS nativos para suporte offline sem erros de DNS.
10. **Resiliência de Arquivos & Permissões WSL**: Atualização do endpoint `/api/files/mkdir` com log de diagnóstico, sanitização de valores legados `http://test/` no SQLite e concessão de permissões `777` em `/home/cloudos_users` no Kali Linux.
11. **Exclusão Permanente & Esvaziar Lixeira**: Método `deleteFile` no backend atualizado para apagar permanentemente arquivos/pastas dentro de `.trash`, botão "Esvaziar Lixeira" condicional adicionado ao `FileManagerApp.jsx` e estilo `.fmp-btn-danger` incorporado ao `index.css`.
12. **Kali Auto Runner (Streaming & Presets)**: Implementação de execução com streaming HTTP Chunked no backend (`POST /api/kali/tools/:id/run`), suporte a Presets de scan no `kali_tools_schema.js` e console virtual em tempo real integrado ao `ToolRunnerApp.jsx`.
13. **Navegação & Hub Interno do Tool Runner**: Adicionada tela inicial de seleção de ferramentas no `ToolRunnerApp.jsx` quando aberto sem payload, botão de navegação "Voltar" e repasse da prop `setPayload` no `App.jsx`.
14. **Validação & Preenchimento Automático para Iniciantes**: Adicionada validação de campos obrigatórios (`required`) com banner de aviso, preenchimento de valores padrão (`default`) em todas as ferramentas no `kali_tools_schema.js` e presets de 1-clique para Nmap, Gobuster, Nikto e SQLMap.
15. **Blindagem de Shell, Botão Stop & Arsenal de 11 Ferramentas**: Adicionada sanitização `escapeShellArg` no backend para prevenir injeção de comandos, verificação prévia de instalação com dica de `apt install`, controle de processos com rota `/api/kali/tools/stop` e expansão do catálogo de GUIs para 11 ferramentas (`nmap`, `masscan`, `gobuster`, `ffuf`, `whatweb`, `wpscan`, `nikto`, `nuclei`, `hydra`, `sqlmap`, `john`).
16. **Suíte Red Team & Execução Segura via Spawn Array**: Implementação da montagem de argumentos via Array no `spawn('wsl.exe', args)` anulando injeções RCE no shell e expansão do catálogo para o ciclo completo de pentesting com `subfinder`, `httpx`, `theHarvester`, `commix`, `searchsploit` e `hashcat`.
17. **Sidebar de Categorias & Busca Dinâmica**: Adicionadas abas laterais de categorias (`Recon & OSINT`, `Web Scanning`, `Exploits`, `Cracking`), barra de pesquisa por nome/descrição e expansão de campos avançados (`-A`, `--os-shell`, `-x`, `-t`) no `ToolRunnerApp.jsx` e `kali_tools_schema.js`.
18. **Campos Textarea & Geração Automática de Arquivos Temporários**: Suporte ao tipo `textarea` no `ToolRunnerApp.jsx` para colar listas (ex: múltiplos URLs no `Httpx`), com criação automática de arquivos temporários isolados por usuário em `.cloudos_temp` e conversão dinâmica de caminhos para o WSL Kali no backend.
19. **Fase 1 Enterprise (Escopos, Relatórios & HTTP Repeater)**: Novas tabelas SQLite (`projects`, `reports`, `repeater_history`), suporte a rotas `/api/projects` para escopo de testes e aplicativo visual `RepeaterApp.jsx` com proxy de requisições HTTP cruas e utilitários de decodificação CyberChef (`Base64`, `URL Encode/Decode`).
20. **Fase 2 Enterprise (Chain Runner & App de Escopos)**: App de Automação Encadeada (`PipelineApp.jsx`), rotas `/api/pipeline/recon` (executa `subfinder` ➔ `httpx` ➔ `nmap` de 1-clique), App de Projetos (`ProjectsApp.jsx`) para gerenciar escopos ativos no CloudOS Context e endpoints de relatórios (`/api/reports`).
21. **Report Builder (Gerador de Relatórios em Markdown)**: App `ReportBuilderApp.jsx` com Live Preview de relatórios de pentest em tempo real, adição dinâmica de achados de vulnerabilidade com nível de severidade e exportação em 1-clique para arquivo `.md`.
22. **Roadmap V2 Completo (Relatórios DB, System Monitor SVG, Snapshots & Ferramentas Arjun/Metasploit)**: Persistência completa de relatórios via `/api/v2/reports`, suporte a `arjun` e scripts `.rc` de `metasploit` com sanitização, telemetria do WSL 2 via WebSocket em tempo real com gráfico SVG em `LineChart.jsx`, e gerenciador visual de Snapshots (`SnapshotManagerApp.jsx`).
23. **Tratamento Defensivo de Auth JWT & Array Mapping**: Verificação prévia de existência de token em `CloudOSContext.jsx`, desativação de requisições não autenticadas evitando erros 403 desnecessários, remoção de tokens expirados no status 403 e prevenção total contra crash por `.map()` através de verificações `Array.isArray(data)`.
24. **Menu Iniciar Estilo Windows 11 & Auditoria de Endpoints**: Componente `StartMenu.jsx` responsivo com busca de apps em tempo real, grid de ícones, opções de bloqueio/desligar, overlay flutuante no desktop e adaptação full-screen no mobile (<768px). Auditoria automatizada realizada em 10/10 endpoints principais com 100% de aprovação.
25. **Interface Burp Suite & VS Code para Tool Runner**: Nova interface no `ToolRunnerApp.jsx` com tema GitHub Dark (`#0d1117`), painel de configurações fixo à esquerda (320px), visualização de comando CLI em tempo real no topo, terminal isolado com auto-scroll inteligente e layout responsivo adaptável.

---

## 📜 Licença
Este projeto é de uso livre para fins educacionais, de pesquisa e de estudo.
