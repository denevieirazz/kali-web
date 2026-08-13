# Arquitetura técnica do CloudOS Unified

## Visão geral

O CloudOS é um shell desktop híbrido. A interface React representa desktop, janelas e aplicativos próprios dentro de WebView2; o agente Node.js conecta essa interface aos recursos reais do computador e o host WPF coordena o ciclo de vida e as janelas nativas.

O diagrama abaixo é a arquitetura-alvo já preparada no código. O fluxo padrão atual ainda inicia `CloudOS.Host` diretamente; `CloudOS.Bootstrap` só pode ser iniciado pela prévia opt-in `npm run preview:shell` e não foi ligado ao atalho padrão nem ao shell do Windows.

```text
CloudOS.Bootstrap WPF/.NET 8 (recuperação nativa)
    │
CloudOS.Host WPF/.NET 8 (usuário normal)
    ├── WebView2 restrito à origem verificada
    ├── bridge JSON v1 allowlisted
    └── NativeWindowManager / HWND
            │
CloudOS React/Vite (`http://cloudos.localhost/`, origem estável)
    │
    ├── HTTP autenticado para o loopback efêmero
    └── WebSocket PTY autenticado para o loopback efêmero
            │
CloudOS Local Agent (127.0.0.1, porta efêmera)
    ├── autenticação e primeiro acesso
    ├── inventário Windows / WSL / WSLg
    ├── catálogo opaco de aplicativos
    ├── operações de instalação acompanháveis
    ├── PowerShell e terminais WSL reais
    └── broker administrativo sob demanda
            │
Windows 10/11
    ├── aplicativos Windows
    └── WSL 2 + WSLg + distribuições Linux
```

## Camadas preparadas

### Host desktop

- Bootstrap nativo separado de React, Node e WebView2, preparado e testado, mas ainda inativo no fluxo padrão; observa o host e contém crash-loop sem modificar o shell do Windows.
- WPF/.NET 8 e WebView2, sempre sem elevação.
- Single-instance por usuário e ativação por named pipe local.
- Supervisor conserva o objeto `Process` que iniciou; não encerra PID lido de arquivo obsoleto.
- Lease autenticada por execução mantém o agente ligado à vida do host; um crash do host fecha a pipe e o agente se encerra.
- Manifest de sessão + health check com token de supervisor antes de navegar.
- Navegação, popups, permissões e downloads bloqueados fora da política local.
- Ponte versionada com métodos explícitos; nenhum host object, comando, caminho ou argv genérico.
- Gerenciador de janelas limita processos/sessões, valida PID + horário inicial + integridade e usa `WM_CLOSE` sem término forçado.

### Interface CloudOS

- React 19, TypeScript, Vite e Zustand.
- Kernel, gerenciadores de processos/janelas e sistema de arquivos virtual próprios.
- Central Windows + Linux para capacidades, distribuições, aplicativos e operações.
- Terminal xterm conectado a PowerShell ou Bash dentro de uma distribuição escolhida.

### Agente local

- Express em loopback, JWT e CORS limitado à origem estável do shell no modo nativo.
- WebSocket PTY com executáveis e argumentos definidos pelo servidor.
- Detecção estruturada de ausência do WSL, acesso negado, timeout e falha de comando.
- Catálogo de distribuições obtido por `wsl --list --online`.
- Instalação via broker PowerShell allowlisted e UAC somente quando necessário.
- Catálogo de programas Windows via Menu Iniciar e de programas Linux via arquivos `.desktop`.
- IDs opacos: a página nunca envia executável, caminho ou linha de comando arbitrária.

### Armazenamento

- `local://`: OPFS privado do navegador para o sistema de arquivos virtual.
- Estado cliente do host: perfil WebView2 em `%LOCALAPPDATA%\CloudOS\WebView2`, sob a origem fixa `http://cloudos.localhost`.
- Estado de autenticação, recuperação e operações no host: `%LOCALAPPDATA%\CloudOS\data\cloudos.json`.
- `cloudos.json.bak` é a cópia redundante atual; `cloudos.json.pre-v2.bak` é o snapshot único da migração v1→v2.
- Se principal e backup forem inválidos, o agente falha fechado e não cria uma instalação vazia.
- Em desenvolvimento, o diretório padrão depende do diretório de execução, salvo `CLOUDOS_DATA_DIR` ou `DATABASE_PATH` explícito.
- `windows://` e `linux://`: provedores reais planejados para a camada nativa.

## Limite da superfície gráfica

WSLg e Win32 produzem janelas nativas do Windows. Um navegador não pode anexar um HWND dentro de um elemento React nem controlar universalmente foco, captura e entrada dessas janelas. No modo atual, o CloudOS descobre e inicia os programas, que aparecem em janelas nativas.

O React já é hospedado em WebView2 e o host coordena janelas top-level atribuíveis, taskbar, foco, minimizar, maximizar e fechamento. Clipboard, drag-and-drop, providers de arquivos reais e correlação universal de brokers Windows/WSLg ainda pertencem às próximas fases. Consulte `NATIVE-HOST-ROADMAP.md`.

## Fronteiras de segurança

- O agente inteiro não deve executar elevado.
- Elevação ocorre apenas no broker, para verbos fixos de WSL.
- Instalação, atualização e conversão exigem papel administrador no CloudOS.
- O ambiente do terminal não herda segredos do processo do backend.
- Não há endpoint para `wsl --unregister`: remoção será implementada somente com backup opcional, reautenticação e confirmação destrutiva forte.
- Apps Linux/Windows são lançados apenas por IDs produzidos pelo catálogo do servidor.

## API de controle

- `GET /api/setup/status`
- `POST /api/setup/admin`
- `POST /api/auth/login`
- `GET /api/auth/session`
- `GET /api/auth/recovery/status`
- `POST /api/auth/recovery/reset`
- `POST /api/auth/recovery/rotate`
- `GET /api/host/capabilities`
- `GET /api/readiness?profile=hybrid-dev|shell-preview|shell-candidate`
- `GET /api/wsl/distributions`
- `GET /api/wsl/catalog`
- `POST /api/wsl/installations`
- `POST /api/wsl/update`
- `POST /api/wsl/distributions/:name/start`
- `POST /api/wsl/distributions/:name/stop`
- `POST /api/wsl/distributions/:name/set-default`
- `POST /api/wsl/distributions/:name/set-version`
- `GET /api/apps`
- `POST /api/apps/:id/launch`
- `GET /api/operations`
- `GET /api/operations/:id`
- `POST /api/operations/:id/cancel`

## Modo shell futuro

O CloudOS poderá ser associado a uma conta dedicada pelo Shell Launcher v2 numa edição compatível. Explorer continuará sendo o shell da conta administrativa de recuperação. Até pacote assinado, watchdog, last-known-good, rollback, WinRE e qualificação em VM estarem aprovados, nenhuma rota ou script habilita esse modo. A especificação está em `SHELL-MODE-PLAN.md`.
