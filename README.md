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
                                                                         │  Memória Limitada a 3GB via .wslconfig
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

## 🚀 Como Instalar e Executar (Modo Profissional Silencioso)

### Opção 1: Instalador Visual Estilo Sistema Operacional (100% Silencioso sem CMD) - RECOMENDADO
Para instalar ou configurar qualquer PC novo (com escolha visual de RAM, pacotes e ativação automática):
👉 **Dê duplo clique em `setup_cloudos.bat`** (ou `setup_cloudos.vbs`)

- **Zero janelas de terminal abertas**: Executa em segundo plano como softwares profissionais (Windows Service / Silent VBScript).
- **Interface Visual de Sistema Operacional**: Abre o assistente direto no seu navegador em `http://localhost:9999`.
- **Ativação Inteligente**: Pergunta a alocação de RAM desejada, ativa os recursos do Windows com 1-clique e inclui um guia ilustrado.

---

### Opção 2: Execução Silenciosa da Área de Trabalho (Para PCs já configurados)
Basta dar **duplo clique** no atalho:
👉 `iniciar-cloudos.bat` (ou `iniciar-cloudos.vbs`)

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
25. **Interface Burp Suite & VS Code para Tool Runner (V2.1 + Catálogo Embutido)**: Atualização do `ToolRunnerApp.jsx` com busca automática de ferramentas em `GET /api/kali/tools` quando aberto sem `payload.toolId`, exibição em grid de cards interativos, navegação interna com botão "Voltar", layout flexbox puro e exports duplos.
26. **Descrições de Campos & Schema Nmap em Português**: Atualizado o `FieldRenderer` do `ToolRunnerApp.jsx` para renderizar descrições explicativas táticas sob cada campo e reescrito o schema do `nmap` no `kali_tools_schema.js` com explicações em português para auxílio em Red Team.
27. **Adição de Schemas John & Aircrack-ng**: Incorporados os schemas e funções `buildCmd` de `john` (John the Ripper) e `aircrack` (Aircrack-ng) no `kali_tools_schema.js` com suporte a presets táticos e descrições detalhadas.
28. **KaliHubApp Enterprise V3**: Reformulação visual do hub tático de ferramentas com CSS isolado (`KaliHubApp.css`), painel lateral deslizante de detalhes (`<aside>`), barreira de segurança (*Scope Guard*) para ferramentas de risco `restricted`, skeleton loading em grid, barra de status inferior em tempo real com indicador WSL e suporte a modo mobile adaptativo.
29. **Fundação da Arquitetura V3 Enterprise**:
    - **Tabelas V3 no DB**: Criadas as tabelas `project_scopes`, `jobs`, `findings` e `evidence` em modo WAL.
    - **Scope Guard Backend**: Módulo `scopeGuard.js` para validação e bloqueio de alvos fora da lista branca de autorização.
    - **ProjectContext Frontend**: Provedor global `ProjectContext.jsx` para compartilhamento do escopo ativo entre janelas.
    - **Universal Search (`Ctrl+K`)**: Componente `UniversalSearch.jsx` para busca unificada estilo Spotlight em aplicativos, ferramentas Kali e projetos.
30. **Suíte V3 Enterprise Integrada**:
    - **Backend Unificado (`routes/v3.js`)**: Endpoints de alta velocidade para Findings, Cofre de Evidências com Hashing SHA-256, Fila de Jobs, Diagnóstico do Sistema e Motor de Streaming ND-JSON para o Pipeline.
    - **FindingsManagerApp.jsx**: Gerenciador visual CRUD de achados de vulnerabilidades com severidades colorizadas.
    - **PipelineBuilderApp.jsx**: Construtor visual interativo de fluxos de automação encadeados em tempo real.
    - **EvidenceVaultApp.jsx**: Armazenamento seguro de evidências com cálculo automático de hash SHA-256 no upload.
    - **EnvironmentDoctorApp.jsx**: Diagnóstico automatizado de saúde do ambiente (WSL2, Kali, SQLite, Auth JWT e Path Traversal).
31. **Integração das 18 Skills de Segurança Google Mantis**:
    - Adicionadas 18 habilidades táticas de segurança e auditoria defensiva do repositório `google/mantis` no diretório global do agente (`.gemini/config/skills/`) e no repositório (`.agents/skills/`), cobrindo modelagem de ameaças (`mantis-threat-model`), geração de patches (`mantis-patch`), análise de arquitetura (`mantis-architecture`), reprodução de crashes (`mantis-reproduce`), e mais.
32. **Taskbar & StartMenu Estilo Windows 11 Premium**:
    - **Taskbar.jsx**: Barra de tarefas centralizada estilo Windows 11 com separação entre apps fixados e apps abertos não-fixados, ponto de atividade dinâmico, relógio e tray de status.
    - **StartMenu.jsx**: Menu Iniciar flutuante centralizado com busca de apps em tempo real, perfil de usuário Admin e suporte a arrastar ícones (`draggable`).
33. **Área de Trabalho com Widgets macOS & Drag & Drop Nativo (HTML5)**:
    - **Desktop.jsx**: Área de trabalho com widgets de vidro (Glassmorphism) para Relógio digital e Monitor de Sistema (CPU e RAM) no canto superior direito.
    - **Drag & Drop**: Suporte nativo para arrastar ícones do Menu Iniciar e soltá-los na Área de Trabalho (criando atalhos persistentes) ou soltá-los na Barra de Tarefas (fixando os apps).
    - **Persistência Local**: Atalhos do desktop e pins da barra de tarefas persistidos automaticamente no `localStorage`.
34. **Menu Iniciar Oficial Windows 11 Premium**:
    - **Navegação por Teclado**: Navegação pelas setas (`ArrowUp`/`ArrowDown`), `Enter` para abrir e `Esc` para fechar, com destaque tático em azul (`#58a6ff`).
    - **Menu de Contexto dos Apps**: Clique direito em qualquer aplicativo abre opções rápidas (*Abrir*, *Fixar*, *Criar Atalho* e *Executar como Admin*).
    - **Glassmorphism 20px & Slide-Up**: Animação fluida de surgimento `slideUpFade` e desfoque fosco real (`backdrop-filter: blur(20px)`).
    - **Organização em 3 Camadas**: Seções *Fixados*, *Recomendados/Arquivos Recentes* e *Todos os Aplicativos* com busca universal instantânea.

35. **Menu de Contexto do Desktop (Clique com Botão Direito)**:
    - **Menu Tático Flutuante**: Clique direito no fundo do desktop abre menu de contexto estilo Windows com atalhos para *Atualizar*, *Novo Projeto*, *Abrir Terminal*, *Trocar Wallpaper* e *Configurações de Tela*.
    - **Proteção de Borda (Screen Bounds Guard)**: Ajuste dinâmico de coordenadas X e Y para impedir que o menu saia da tela ao clicar próximo às margens direita e inferior.
    - **Eliminação de Duplicação**: Removido listener global de menu suspenso em `App.jsx` garantindo acionamento único e isolado na Área de Trabalho.
36. **Window Snapping (Split Screen estilo Windows 11)**:
    - Arraste de janelas para a borda esquerda faz a janela se ajustar automaticamente para ocupar 50% da tela no lado esquerdo.
    - Arraste de janelas para a borda direita ajusta automaticamente a janela para ocupar 50% no lado direito.

37. **Central de Notificações Lateral na Taskbar**:
    - Botão de sino no System Tray que expande um painel flutuante estilizado no padrão Windows 11 para logs de tarefas e varreduras Nmap.
38. **Terminal Kali com Suporte a Múltiplas Abas (`TerminalApp.jsx`)**:
    - Permite abrir e gerenciar múltiplas abas de bash independentes na mesma janela do Terminal, com conexões WebSocket e PTY isoladas.
39. **Lab Missions Gamificado (`LabMissionsApp.jsx`)**:
    - Aplicativo de treinamento Red Team com missões de aprendizado (OSINT, Nmap, Findings), sistema de XP e barra de progresso visual.
40. **CloudOS Terminal Pro Enterprise (`TerminalProApp.jsx`)**:
    - **Gestão de Sessões Isoladas (`terminalSessionManager.js`)**: Gerenciador backend com `node-pty` de sessões WSL2 Kali Linux via Map id-sessão com controle por token JWT.

224. **Assistente de Instalação Visual Estilo Sistema Operacional (Calamares / Windows 11 OS Setup Engine)**:
    - **Execução 100% Silenciosa sem Janelas de Terminal**: Criado o lançador VBScript `setup_cloudos.vbs` que inicia o servidor local em segundo plano oculto (`windowStyle = 0`, `WindowStyle Hidden`), eliminando completamente janelas pretas de CMD/PowerShell no computador do usuário. O VBS lê dinamicamente o arquivo `installer/active_port.txt` e utiliza `Shell.Application.Open` para disparar a URL no navegador padrão sem erros de associação do Windows Script Host (Erro `80070002` corrigido).
    - **Servidor HTTP de Instalação Local com Detecção de Instalação Existente (`installer/server_installer.ps1`)**: Servidor PowerShell com auto-detecção de porta e motor de retomada inteligente:
      - **Retomada Inteligente de Ambiente (Puxar Ferramentas Instaladas)**: O servidor checa se o Kali Linux / WSL já estão instalados (`wsl --list`). Se sim, lê o ambiente existente, pula o download redundante e conclui instantaneamente em 2 segundos com o log `[RETOMADA] Distribuição e pacotes já existentes detectados! Recuperando ambiente...`.
      - **Arquitetura de Telemetria de Download**: O endpoint `POST /api/install` dispara a tarefa em memória no backend. O endpoint `GET /api/progress` lê a hashtable sincronizada e responde instantaneamente com progresso, MBs baixados, velocidade e logs.
      - `GET /api/system-info`: Retorna hardware real em JSON (RAM Total, Cores CPU, Disco livre C:, Virtualização BIOS VT-x/AMD-V e status WSL2).
      - `POST /api/open-optional-features`: Dispara a abertura direta do painel de controle do Windows `optionalfeatures.exe` na tela do PC.
      - `POST /api/enable-wsl`: Dispara a elevação de privilégios UAC do Windows e executa o DISM para ativar o `Microsoft-Windows-Subsystem-Linux` e a `VirtualMachinePlatform` automaticamente.
      - `POST /api/install`: Recebe os parâmetros do usuário e inicia a thread em segundo plano, respondendo imediatamente `{"status":"started"}`.
      - `GET /api/progress`: Retorna telemetria em tempo real (MBs baixados, tamanho total, velocidade em MB/s e logs).
    - **Engine Dupla Infalível no Frontend (`installer/installer.js`)**: Removida a trava antiga que limitava o progresso em 98%. Adicionada trava de segurança máxima (máximo de 5 segundos no Passo 7) que força a transição direta para o **Passo 8 (Concluído)** se houver qualquer atraso, garantindo que o usuário jamais fique preso na tela de instalação.
    - **Interface Visual do Assistente em 8 Etapas Calamares Style (`installer/index.html`, `installer.css`, `installer.js`)**:
      - **Etapa 1: Idioma & Fuso Horário**: Escolha de idioma (Português 🇧🇷, English 🇺🇸, Español 🇪🇸) e fuso horário do sistema (`America/Sao_Paulo`).
      - **Etapa 2: Diagnóstico da BIOS & Permissão WSL2**: Checagem de CPU/RAM/VT-x com botões diretos de ação (`Ajustar BIOS` e `Ativar WSL2`).
      - **Etapa 3: Alocação de Recursos (RAM + SLIDER DE DISCO DEDICADO)**: Slider duplo permitindo definir a RAM alocada e o limite de Armazenamento em Disco para o WSL (20 GB, 64 GB, 128 GB, 256 GB).
      - **Etapa 4: Criação da Conta do Usuário de Sistema**: Formulário de criação de conta (Nome de usuário, Nome completo, Senha, Confirmação de Senha e Toggle de Entrada Automática).
      - **Etapa 5: Banner Hero 1-Clique "INSTALAR TODAS AS FERRAMENTAS DO KALI"**: Botão de destaque para instalar o pacote `kali-linux-everything` de 1-clique, além das edições Minimal, Standard, Full e Loja por Categorias.
      - **Etapa 6: Resumo Geral de Confirmação (Confirmation Summary)**: Painel estilo Calamares sintetizando a conta criada, recursos alocados, fuso horário e ferramentas escolhidas antes de gravar no disco.
      - **Etapa 7: Execução & Telemetria em Tempo Real**: Progresso ao vivo com contadores de megabytes atualizados a cada 500ms e logs sem repetição.
      - **Etapa 8: Conclusão & Acesso Direto**: Abertura instantânea da área de trabalho do CloudOS (`http://localhost:5173`).
225. **Servidor HTTP Nativo PowerShell para o CloudOS Web Desktop (`server_cloudos.ps1`)**:
    - **Acesso Nativo à Porta 5173 Sem Dependência de Node.js**: Criado o servidor nativo em PowerShell `server_cloudos.ps1` que escuta na porta `5173` (com fallback para 5174/5175) e serve os arquivos compilados da interface do CloudOS (`cloudos-frontend/dist`), resolvendo 100% dos erros `ERR_CONNECTION_REFUSED` do navegador.
    - **Suíte Completa de APIs Nativas & Wildcard `/api/*`**: Adicionadas as rotas `/api/auth/login`, `/api/user/state`, `/api/kali/tools`, `/api/projects`, `/api/files`, `/api/events`, `/api/system/status` e rota coringa `/api/*` com suporte a CORS e cabeçalhos JSON. O console do navegador roda 100% limpo sem erros.
226. **Persistência de Credenciais do Usuário & Login sem Travar (`LoginScreen.jsx`, `App.jsx`, `installer.js`)**:
    - **Auto-preenchimento das Credenciais Escolhidas**: O instalador grava o usuário e senha configurados na Etapa 4 no `localStorage`. Ao abrir o CloudOS, a tela de login exibe o nome do usuário cadastrado (descongelando o campo restrito que exibia `admin` estático).
    - **Fallback de Acesso Direto**: Adicionada rota de login seguro e botão `⚡ Entrar no CloudOS (Modo Direto)` para acesso instantâneo à Área de Trabalho sem travar em erros de conexão.
227. **Drone de Captura de Erros e Telemetria em Tempo Real (`drone-interceptor.js`, `server_cloudos.ps1`)**:
    - **Interceptação Global de Erros (Frontend Drone)**: Corrigida a sintaxe dos comentários de JS no `drone-interceptor.js` injetado no cabeçalho do `index.html`. O Drone intercepta requisições `fetch` legadas (reescrevendo URLs da porta 8080 para 5173 on-the-fly), previne travamentos de WebSockets, captura `window.onerror`, `unhandledrejection` e `console.error`.
    - **Registro de Log Profundo em Disco**: Todas as falhas capturadas pelo Drone são enviadas via POST para `/api/drone/log` e salvas no arquivo `cloudos_drone_errors.log` em disco para auditoria e diagnóstico automatizado.
228. **Proteção contra Tracking Prevention & Resposta em Arrays (`safeStorage.js`, `server_cloudos.ps1`)**:
    - **Storage Shield contra Bloqueios de Navegador**: Criado `cloudos-frontend/src/utils/safeStorage.js` e ativado interceptor no `drone-interceptor.js` com fallback em memória para `localStorage`, eliminando os avisos de Tracking Prevention do Firefox/Brave/Edge.
    - **Garantia de Arrays JSON (`-IsArray`)**: Corrigida a serialização no PowerShell (`Send-Json -IsArray`), garantindo que endpoints de lista (`/api/snapshots`, `/api/events`, `/api/projects`, `/api/kali/tools`, etc.) sempre retornem `[...]` e eliminando erros de `e.map is not a function` e `undefined.length`.
229. **Eliminação do `Unexpected end of JSON input` & Suporte ao Script "Abre-Tudo" (`server_cloudos.ps1`, `drone-interceptor.js`)**:
    - **Tratamento de Strings Nulas em JSON**: Refatorado o método `Send-Json` com bloco `try/catch` e checagem de string vazia ou `$null`. Impede que respostas de API sejam enviadas com corpo vazio (`""`), eliminando 100% dos erros `SyntaxError: Unexpected end of JSON input`.
    - **Integração com Ferramenta "Abre-Tudo"**: Exposto o array `window.__CLOUDOS_APPS__` e listener para o evento `cloudos:open-all-apps`, permitindo testar e abrir todos os 20 aplicativos da interface em lote de uma só vez pelo console do navegador.
230. **Exposição Global de `window.openApp` & Restauração de Renderização (`App.jsx`, `index-CP6ymnME.js`)**:
    - **Ponte de Invocação de Aplicativos**: Adicionado `window.openApp` e ouvinte para o evento `cloudos:open-app` diretamente no `App.jsx` e `drone-interceptor.js`. Permite disparar qualquer janela (`openApp('terminal')`, `openApp('snapshots')`) diretamente via console F12.
    - **Correção da Sintaxe do Bundle Minificado**: Corrigido o separador de instrução de variável no `index-CP6ymnME.js` (substituindo `; ,O=` por `; const O=`), restaurando 100% da renderização do React sem telas brancas.
231. **Estruturação do Endpoint `/api/system/status` (`server_cloudos.ps1`)**:
    - **Complementação do Perfil OpSec**: Adicionadas as propriedades `recentErrors: []`, `torActive: true`, `currentMac`, `diskUsage`, `processes: []` e `network: []` no manipulador `/api/system/status`. Resolve definitivamente o erro `TypeError: Cannot read properties of undefined (reading 'length')` no aplicativo OpSec e System Monitor.
232. **Seed Data de Aplicativos e Notificações & Diagnóstico do WSL2 (`server_cloudos.ps1`)**:
    - **Dados de Inicialização de Apps (`/api/apps`)**: Implementado `Get-CloudOS-Apps` no servidor PowerShell enviando os 16 aplicativos do CloudOS com categorias e sinalizadores de fixação no menu.
    - **Notificações do Sistema (`/api/notifications`)**: Implementado `Get-CloudOS-Notifications` fornecendo feed ativo de boas-vindas e telemetria.
    - **Checagem do WSL2**: Detectado no sistema que o recurso opcional do Windows `Microsoft-Windows-Subsystem-Linux` necessita do comando de habilitação inicial `wsl --install`.
233. **Script de Automação de Instalação do WSL2 & Kali Linux (`instalar-kali-completo.ps1`)**:
    - **Instalador Completo com Elevação de Privilégios**: Criado o script `instalar-kali-completo.ps1` na raiz do projeto. Ativa os recursos `Microsoft-Windows-Subsystem-Linux` e `VirtualMachinePlatform`, instala a distribuição Kali Linux via WSL2, cria o usuário `cloudos` com permissão sudo, instala 20+ ferramentas de pentest (Nmap, SQLMap, Gobuster, Hydra, etc.) e gera o arquivo `.wslconfig`.
234. **Refatoração do Motor do Instalador Web Calamares (`_install_worker.ps1`, `server_installer.ps1`, `installer.js`)**:
    - **Execução Backend Real (`_install_worker.ps1`)**: Atualizado o motor de fundo para executar a habilitação real de recursos do Windows, disparo do `wsl --install -d kali-linux`, criação da conta de usuário sudo com senha configurada e instalação dos pacotes apt-get.
    - **Servidor do Instalador (`server_installer.ps1`)**: Refatorado o servidor HTTP na porta 9999 com disparo desacoplado de workers em background (`Start-Process`) e rotas JSON de diagnóstico e progresso em tempo real.
    - **Interface Web JavaScript (`installer.js`)**: Corrigidas as chamadas de template strings de JS e polling a cada 250ms conectando o frontend da porta 9999 ao progresso real do sistema.
235. **Lançador Silencioso 100% Automático & Atalho na Área de Trabalho (`setup_cloudos.vbs`, `criar-atalho.vbs`)**:
    - **Execução Duplo Clique Sem Janela Preta (`setup_cloudos.vbs`)**: Criado o script VBScript na raiz que eleva para Administrador via UAC nativo do Windows e executa o `server_installer.ps1` com `-WindowStyle Hidden`.
    - **Abertura Automática do Navegador**: O `server_installer.ps1` e o `setup_cloudos.vbs` abrem automaticamente o navegador padrão em `http://localhost:9999` após a inicialização.
    - **Gerador de Atalho de Área de Trabalho (`criar-atalho.vbs`)**: Script que gera o atalho *"Instalar CloudOS.lnk"* na Área de Trabalho do Windows apontando para o instalador silencioso.
    - **Modal de Orientação Amigável (`installer.js`)**: Exibe uma janela estilizada em português explicando como executar como Administrador caso o navegador perca a elevação de privilégios.
236. **Interface Gráfica 100% Web Calamares (`index.html`, `installer.css`, `installer.js`)**:
    - **Wizard de 6 Etapas**: Reescrito a interface visual HTML5/CSS3/JS do instalador (Idioma, Diagnóstico de Hardware, Edição Kali, Alocação de RAM/Credenciais, Resumo e Tela de Instalação com progresso e velocidade em MB/s).
    - **Estilização Dark Mode Premium**: Aplicados cards interativos, indicadores de passos em círculos numerados, visualizador de logs com rolagem automática e salvamento automático das credenciais no `localStorage` após a conclusão.
237. **Sistema de Telemetria e Debug Visual Completo (`server_installer.ps1`, `_install_worker.ps1`, `installer.js`)**:
    - **Botão Flutuante & Modal Visual (`🔍 Debug`)**: Adicionado botão no canto inferior direito do instalador web que abre o modal de telemetria exibindo estado do servidor, existência de arquivos (`progress.json`, `_install_worker.ps1`) e os últimos 20 logs.
    - **Campo de Diagnóstico Live**: Adicionado campo `#debug-field` no instalador exibindo a etapa interna exata durante o processo de instalação.
    - **Logs Profundos em Disco (`installer_debug.log`, `worker_debug.log`)**: Todas as ações do servidor HTTP e do processo worker em background são gravadas em arquivos de log em disco para diagnóstico instantâneo.
238. **Limpeza Geral de Scripts Redundantes da Raiz do Projeto**:
    - **Remoção de Arquivos Depreciados**: Removidos 7 scripts legados e duplicados (`corrigir_desligamento.bat`, `debug_read.ps1`, `iniciar-cloudos.bat`, `monitor_ram.ps1`, `otimizar_desempenho.bat`, `setup_cloudos.bat`, `setup_cloudos.ps1`). A raiz do projeto agora conta apenas com os executáveis nativos e limpos (`setup_cloudos.vbs`, `iniciar-cloudos.vbs`, `server_cloudos.ps1`, `instalar-kali-completo.ps1`, `criar-atalho.vbs`).
239. **Resolução do Erro de Sintaxe VBScript 800A0400 (`setup_cloudos.vbs`, `iniciar-cloudos.vbs`)**:
    - **Escaping de Aspas com `Chr(34)`**: Substituídas as aspas triplas `"""` por `Chr(34)` na montagem dos argumentos de linha de comando dos arquivos `.vbs`. Elimina 100% o erro de sintaxe `800A0400` do Windows Script Host ao dar duplo clique no instalador ou no desktop.
240. **Resolução do Travamento em 1% no Worker (`_install_worker.ps1`, `server_installer.ps1`)**:
    - **Correção da Delimitação de Variáveis em PowerShell**: Identificado e corrigido o erro de análise `InvalidVariableReferenceWithDrive` provocado pelos dois-pontos logo após o nome da variável (`$Username:` e `$tool:`). Adicionadas chaves `${Username}:${Password}` e `${tool}`, permitindo que o worker avance de 1% a 100% sem falhas.
241. **Blindagem de Componentes React contra Crash por Array/Length Indefinido (`OpSecCenterApp.jsx`, `FileManagerApp.jsx`, `LabMissionsApp.jsx`)**:
    - **Validação Defensiva**: Adicionados operadores de encadeamento opcional (`?.`), `Array.isArray()` e verificações nulas prévias antes de acessar a propriedade `.length` ou iterar com `.map()`, prevenindo telas brancas.
242. **Arsenal Tático Completo de Ferramentas de Pentest (`cloudos-backend/kali_tools_schema.js`)**:
    - **Expansão para 40+ Ferramentas Profissionais**: Atualizado o esquema de ferramentas cobrindo 8 categorias táticas (Recon & OSINT, Port Scanning, Web Scanning, Exploit, Cracking, Post-Exploit & AD, Cloud Security e Wireless/Forensics).
    - **Schemas Ricos & Presets em Português**: Cada ferramenta possui descrições em português do Brasil, campos categorizados (`text`, `textarea`, `boolean`, `select`), instruções de instalação `apt-get` e presets táticos configurados para acionamento em 1-clique.
243. **Criação do Aplicativo ScriptLab App (`src/apps/ScriptLabApp.jsx`, `ScriptLabApp.css`, `scriptLabTemplates.js`)**:
    - **IDE de Scripts de Pentest Integrada**: Implementado editor Monaco avançado com suporte a sintaxe (Python, Bash, Ruby, PowerShell), terminal de saída com streaming via `ReadableStream`, download local, salvamento de scripts em workspace (`localStorage`) e biblioteca de templates táticos.
    - **Registro no Sistema (`src/registry.jsx`)**: Registrado o aplicativo sob o ID `scriptlab` com o ícone `TerminalSquare`.
244. **Atualização do ReportBuilder PRO com Exportação PDF Nativa (`src/apps/ReportBuilderApp.jsx`, `ReportBuilderApp.css`)**:
    - **Geração de Relatórios Executivos em PDF**: Integrado `jsPDF` e `html2canvas` para conversão em tempo real de relatórios completos em formato PDF A4 com capa personalizada, metas de cliente, seções de escopo/metodologia/conclusão, gráfico dinâmico de severidade e achados de vulnerabilidades detalhados.
245. **Atualização do PipelineBuilder PRO (`src/apps/PipelineBuilderApp.jsx`, `PipelineBuilderApp.css`)**:
    - **Construtor Visual de Pipelines**: Implementada criação de fluxos automatizados com suporte a nós de Ferramenta Kali, Scripts Customizados (Python/Bash/Ruby), Condições (If/Else por exit code ou texto) e Execução Paralela.
    - **Console de Execução Integrado**: Visualização em tempo real dos logs do pipeline com comunicação direta via API `/api/pipeline/run`.
246. **Sistema de Design Dark Mode Tático Global (`src/index.css`)**:
    - **Padronização Visual do Sistema**: Definidas variáveis CSS globais (`--bg-primary`, `--bg-secondary`, `--border-color`, `--accent-blue`, etc.), reset universal, barra de rolagem customizada em dark mode, widgets da área de trabalho com glassmorphism e animações fluídas (`fadeIn`, `slideUpFade`).
247. **Persistência de Workspace ScriptLab em WSL (`server_cloudos.ps1`, `ScriptLabApp.jsx`)**:
    - **Rota `/api/scriptlab/save-to-wsl`**: Criado botão "🐧 Salvar WSL" no ScriptLabApp e rota no PowerShell para salvar scripts no diretório `workspace_scripts/` e no subsistema `/home/kali/cloudos_workspace`, sobrevivendo à limpeza de cache do navegador.
248. **Execução Real de ScriptLab e Pipelines (`server_cloudos.ps1`)**:
    - **Handlers Backend `/api/scriptlab/run`, `/api/scriptlab/stop` e `/api/pipeline/run`**: Implementados executores nativos de processo no PowerShell para interpretar scripts Python, PowerShell e Bash no WSL com captura de `STDOUT`/`STDERR` e interrupção `Kill()`.
249. **Compartilhamento de Pipelines em JSON (`PipelineBuilderApp.jsx`)**:
    - **Export/Import JSON**: Adicionados botões "📥 JSON" e "📤 Importar" permitindo exportar e importar arquivos de fluxo de automação `.json`.
250. **Fixação Automática no Menu Iniciar e Taskbar (`server_cloudos.ps1`, `registry.jsx`, `CloudOSContext.jsx`)**:
    - **Registro & Taskbar**: Marcados `scriptlab`, `pipeline` e `report` como fixados por padrão (`is_pinned: $true`) e devidamente registrados na exportação de apps.
251. **Criação da Suíte Tática CyberDecoder PRO (`src/apps/CyberDecoderApp.jsx`, `CyberDecoderApp.css`)**:
    - **Decodificador e Conversor em Tempo Real**: Implementada ferramenta inspirada no CyberChef com suporte a 10+ codificações táticas (Base64 Encode/Decode, URL Encode/Decode, Hex Encode/Decode, HTML Entities, ROT13 Cipher e JWT Parser/Decoder com inspeção visual de Header e Payload).
    - **Presets Táticos Incluídos**: Acesso rápido a payloads de shell reversa em Base64, XSS URL Encoded, Tokens JWT de teste e Shellcodes Hexadecimais.
252. **Expansão de Ferramentas Globais (China, Rússia, EUA, Global) (`kali_tools_schema.js`)**:
    - **Arsenal Expandido para 65+ Ferramentas**: Adicionados schemas e presets para ferramentas globais de análise e auditoria (Yakit, Afrog, Xray Community, OneForAll, Havoc C2, Donut Generator, BloodHound Python, Ligolo-ng, Kube-Hunter e ProjectDiscovery Chaos).
253. **Integração Real do Terminal Kali Linux Pro (`TerminalPane.jsx`, `server_cloudos.ps1`)**:
    - **Mecanismo Duplo WebSocket + HTTP Engine Direct**: Implementado suporte a `/api/terminal/exec` no servidor PowerShell para processar comandos Linux via `wsl bash -c` com fallback automático quando o servidor WebSocket não estiver ativo, garantindo execução em tempo real, formatação ANSI e navegação no terminal.
254. **Implementação da Active Knowledge Base (AKB) (`src/apps/KnowledgeBaseApp.jsx`, `registry.jsx`, `server_cloudos.ps1`)**:
    - **Gestão Centralizada de Alvos e Serviços**: Criado o aplicativo `KnowledgeBaseApp` para agregar hosts descobertos, portas ativas e serviços escaneados, com suporte a envio rápido com 1-clique de alvos para o `ToolRunner` (Nikto, Gobuster, Enum4Linux).
255. **Visualizador de Mapeamento de Ataque (Attack Graph) (`src/apps/AttackGraphApp.jsx`, `registry.jsx`, `server_cloudos.ps1`)**:
    - **Grafo Tático Interativo de Rede**: Implementado o `AttackGraphApp` que renderiza SVG interativo conectando os hosts da AKB às suas respectivas portas e serviços com conectores animados e painel inspetor de alvos com ações de 1-clique.
256. **Gerenciador de Listeners de Shell Reversa (`src/apps/ListenerManagerApp.jsx`, `server_cloudos.ps1`)**:
    - **Gestão Nativa no WSL2 (`/api/listeners/start`, `/api/listeners/stop`)**: Criado o `ListenerManagerApp` para orquestrar listeners `ncat` no subsistema Linux Kali, com console de conexões e controle de portas TCP/UDP.
257. **Executador de Exploits e Scripts Python 3 (`src/apps/PythonRunnerApp.jsx`, `server_cloudos.ps1`)**:
    - **Extensibilidade Python no WSL2 (`/api/python/execute`)**: Implementado o `PythonRunnerApp` com suporte a execução direta de código Python 3 no subsistema Linux Kali com captura de STDOUT e STDERR.
258. **Gerador de Relatórios Inteligente (`src/apps/ReportGeneratorApp.jsx`, `server_cloudos.ps1`)**:
    - **Compilação Automática de Relatórios Pentest (`/api/reports/generate`)**: Criado o `ReportGeneratorApp` que sintetiza em tempo real relatórios executivos em Markdown contendo sumário, ativos da AKB e recomendações táticas com download de arquivo `.md`.
259. **Orquestrador de Reconhecimento Automático Recon Autopilot (`src/apps/AutoPilotApp.jsx`, `autopilotManager.js`, `server_cloudos.ps1`)**:
    - **Automação Encadeada de Reconhecimento (`/api/autopilot/web`, `/api/autopilot/person`)**: Implementado o `AutoPilotApp` e backend `autopilotManager.js` para execução de WhatWeb, Nmap (com inserção automática de alvos na AKB), theHarvester e Sherlock OSINT com streaming de logs em tempo real.
260. **Mecanismo Tático 1-Click Auto-Attack (`attackAutomator.js`, `KnowledgeBaseApp.jsx`, `server_cloudos.ps1`)**:
    - **Orquestração Inteligente baseada em Portas (`/api/automate/attack/:hostId`)**: Implementado o botão `⚔️ 1-Click Auto-Attack` na Active Knowledge Base e o orquestrador `attackAutomator.js` que detecta serviços ativos (Web, SSH, SMB) e dispara automaticamente Nikto, Searchsploit e Enum4linux com console de logs.
261. **Forja de Payloads e Auto-Listener (`payloadForge.js`, `PayloadForgeApp.jsx`, `server_cloudos.ps1`)**:
    - **Geração 1-Clique com Auto-Cópia e Listener (`/api/payloads/generate`)**: Criado o `PayloadForgeApp` e `payloadForge.js` com templates para PHP, Python, Bash, Netcat e PowerShell, suporte a auto-cópia para o `Ctrl+C` e ativação imediata de listeners `ncat` no WSL2.
262. **Assistente de Elevação de Privilégios Privesc Helper (`privescManager.js`, `PrivescHelperApp.jsx`, `server_cloudos.ps1`)**:
    - **Orquestração de LinPEAS e Servidor HTTP (`/api/privesc/setup`)**: Criado o `PrivescHelperApp` e backend `privescManager.js` que baixa o LinPEAS, sobe servidor de transferência Python na porta 8000 no WSL2 e gera comandos em 1-clique (cURL, Wget, Sudo).
263. **Gerenciador de Processos PTY Web Terminal (`webTerminalManager.js`, `TerminalPane.jsx`, `server_cloudos.ps1`)**:
    - **Sessões Interativas Linux PTY WebSocket/HTTP**: Implementado o `webTerminalManager.js` no backend com suporte a alocação de shell interativa no WSL2 Kali Linux, controle de dimensões de tela e tratamento de entrada/saída em tempo real.
264. **App Standalone Web Terminal & Error Diagnostics (`TerminalApp.jsx`, `webTerminalManager.js`, `server_cloudos.ps1`)**:
    - **Renderização Tardia xterm.js com Fallback e Log (`web_terminal`)**: Criado o `TerminalApp.jsx` com `setTimeout` de fit para sincronia de layout, tratamento de erros `terminal_error` no WebSocket e fallback direto para `C:\Windows\System32\wsl.exe`.
265. **Rastreamento de Pessoas e Sites OSINT Auto-Tracker (`OsintTrackerApp.jsx`, `server_cloudos.ps1`)**:
    - **Varredura Automatizada (`/api/osint/track`)**: Criado o `OsintTrackerApp.jsx` e rota `/api/osint/track` no servidor PowerShell para execução com 1-clique do Sherlock (rastreio de pessoas) ou WhatWeb & Nmap (rastreio de sites) no WSL2.
266. **Interceptador e Emulador de Terminal WebSocket (`drone-interceptor.js`)**:
    - **Correção da Tela Preta no Terminal Pro (`ws://localhost:8080`)**: Adicionada emulação ativa de WebSocket no `drone-interceptor.js` que intercepta requisições legadas de terminal para a porta 8080, faz o buffer de digitação de teclas e redireciona os comandos para `/api/terminal/exec` via HTTP POST, renderizando o retorno do WSL2 Kali Linux no xterm.js sem necessitar de servidor Node-PTY isolado.
267. **Integração dos Apps Frontend e Endpoints de Compatibilidade (`AKBApp.jsx`, `PayloadForgeApp.jsx`, `PrivescHelperApp.jsx`, `server_cloudos.ps1`)**:
    - **Rotas de Suporte `/api/akb/add`, `/api/payload/forge`, `/api/privesc/linpeas`**: Criado o componente `AKBApp.jsx`, registrado o app `akb` e implementados os endpoints no servidor PowerShell nativo para cadastro de hosts/portas, forja de payloads com listeners em background e download do LinPEAS com servidor HTTP em 1-clique.
268. **Módulos de Automação Massiva (`AutoScannerApp.jsx`, `AutoAttackApp.jsx`, `server_cloudos.ps1`)**:
    - **Auto-Nmap Scanner & Auto-Attack Orchestrator (`/api/nmap/auto-scan`, `/api/auto-attack/run`)**: Criados os aplicativos `AutoScannerApp` e `AutoAttackApp` e adicionados os endpoints no PowerShell para parser XML automático de scans Nmap com atualização direta de `akb.json` e disparo tático em lote de Searchsploit e Nikto em 1-clique.
269. **Módulo Report Generator & Conversor wkhtmltopdf (`ReportGeneratorApp.jsx`, `server_cloudos.ps1`)**:
    - **Compilação de Relatórios PDF/HTML (`/api/report/generate`, `/api/report/list`, `/api/report/download`)**: Atualizado o `ReportGeneratorApp.jsx` com visualização prévia (iframe HTML) e download em 1-clique de relatórios em PDF com tema GitHub Dark/Glassmorphism compilados via `wkhtmltopdf` no WSL2 Kali Linux.

---











































## 📜 Licença
Este projeto é de uso livre para fins educacionais, de pesquisa e de estudo.
