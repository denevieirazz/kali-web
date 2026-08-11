# 🖥️ ObsidianOS

> Um sistema operacional completo rodando inteiramente no navegador, construído com React, TypeScript e Vite. Simula fielmente a experiência de um OS moderno — com BIOS real, kernel executável, disco virtual OPFS, sistema de arquivos persistente, registro, processos, janelas, BSOD, Recovery Mode, linguagem de script própria (OSL) e muito mais.

---

## 📋 Índice

1. [Visão Geral](#-visão-geral)
2. [Stack Tecnológica](#-stack-tecnológica)
3. [Estrutura do Projeto](#-estrutura-do-projeto)
4. [Como Rodar](#-como-rodar)
5. [Arquitetura do Sistema](#-arquitetura-do-sistema)
6. [Fluxo de Boot](#-fluxo-de-boot)
7. [Componentes da Interface](#-componentes-da-interface)
8. [Aplicativos Integrados](#-aplicativos-integrados)
9. [OSL — ObsidianOS Scripting Language](#-osl--obsidianos-scripting-language)
10. [SDK de Aplicativos](#-sdk-de-aplicativos)
11. [Processos e Drivers do Sistema](#-processos-e-drivers-do-sistema)
12. [Mecânicas de Realismo](#-mecânicas-de-realismo)
13. [Como Adicionar um Novo Aplicativo](#-como-adicionar-um-novo-aplicativo)

---

## 🎯 Visão Geral

**ObsidianOS** é uma simulação completa de um sistema operacional moderno (inspirado no Windows 11), rodando 100% no navegador. Não é apenas uma casca visual:

- **BIOS + Boot Manager reais** — o kernel executa `bootmgr.exe` como um binário JavaScript real dentro de um sandbox
- **Kernel singleton** com sistema de eventos, logging, gerenciamento de recursos e execution engine
- **Disco virtual OPFS** — persistência real via Origin Private File System do navegador, com fallback para `localStorage`
- **Sistema de arquivos virtual** com permissões, atributos, metadados e suporte a executáveis JS
- **Registro do sistema** completo com hives reais: `HKEY_LOCAL_MACHINE`, `HKEY_CURRENT_USER`, `HKEY_CLASSES_ROOT`
- **OSL (ObsidianOS Scripting Language)** — linguagem de script própria com lexer, parser e interpreter completos
- **13 aplicativos completos** incluindo Terminal (20+ comandos), IDE com syntax highlighting, Gravador de tela, App Store e mais

---

## 🛠️ Stack Tecnológica

| Categoria | Tecnologia | Versão |
|-----------|-----------|--------|
| Framework UI | React | 19.2+ |
| Linguagem | TypeScript | 5.9+ |
| Build Tool | Vite | 8.0+ |
| Estado Global | Zustand | 5.0+ |
| Animações | Framer Motion | 12.38+ |
| Ícones | React Icons | 5.6+ |
| IDs únicos | uuid | 13.0+ |
| Datas | date-fns | 4.1+ |
| Linting | ESLint + typescript-eslint | 9+ / 8+ |

---

## 📁 Estrutura do Projeto

```
ObsidianOS/
├── public/
│   ├── favicon.svg
│   ├── icons.svg
│   └── Wallpapers/
└── src/
    ├── main.tsx                  # Ponto de entrada React
    ├── App.tsx                   # Orquestrador do OS (BSOD, atalhos, monitoramento)
    ├── index.css                 # CSS global + variáveis + temas
    ├── types/index.ts            # Todas as interfaces TypeScript
    ├── core/
    │   ├── kernel.ts             # Kernel singleton — coração do sistema
    │   ├── appRegistry.ts        # Registro dinâmico de aplicativos
    │   ├── defaultFileSystem.ts  # Filesystem padrão + binários executáveis
    │   ├── defaultRegistry.ts    # Registro padrão do sistema
    │   ├── opfsDriver.ts         # Driver OPFS com fallback localStorage
    │   ├── osl/                  # ObsidianOS Scripting Language
    │   │   ├── lexer.ts          # Tokenizador OSL
    │   │   ├── parser.ts         # Parser (AST)
    │   │   ├── interpreter.ts    # Interpreter com syscalls
    │   │   ├── environment.ts    # Escopos de variáveis
    │   │   └── types.ts          # Tipos do AST
    │   └── fs/                   # Módulos do filesystem
    │       ├── binaries.ts       # Binários executáveis (.exe)
    │       ├── system.ts         # Arquivos de sistema (dlls, drivers)
    │       ├── apps.ts           # Manifests de aplicativos
    │       ├── dirs.ts           # Estrutura de diretórios padrão
    │       ├── drivers.ts        # Drivers do sistema
    │       ├── sdk.ts            # SDK e documentação
    │       ├── osl.ts            # Scripts OSL padrão
    │       ├── user.ts           # Arquivos do usuário
    │       └── helpers.ts        # Utilitários do FS
    ├── stores/
    │   ├── fileSystem.ts         # Mirror reativo do FS do kernel
    │   ├── registry.ts           # Mirror reativo do registry do kernel
    │   ├── processManager.ts     # Mirror reativo dos processos do kernel
    │   ├── windowManager.ts      # Mirror reativo das janelas do kernel
    │   ├── systemStore.ts        # Estado de UI (bootPhase, tema, notificações)
    │   └── contextMenuStore.ts   # Estado do menu de contexto global
    ├── contexts/
    │   └── ProcessContext.tsx    # Contexto de processo por janela
    ├── components/
    │   ├── Boot/                 # BootScreen + BSOD + RecoveryMode
    │   ├── LockScreen/           # Tela de bloqueio / login
    │   ├── Desktop/              # Desktop com ícones e wallpaper
    │   ├── Taskbar/              # Barra de tarefas (posicionável)
    │   ├── StartMenu/            # Menu Iniciar com busca
    │   ├── Window/               # Janela arrastável + WindowRenderer
    │   ├── ContextMenu/          # Menu de contexto global
    │   ├── Notifications/        # Sistema de notificações
    │   └── Setup/                # OOBE — configuração inicial
    └── apps/
        ├── Terminal/
        ├── FileExplorer/
        ├── TaskManager/
        ├── Notepad/
        ├── Calculator/
        ├── Browser/
        ├── Settings/
        ├── Regedit/
        ├── ObsidianCode/         # IDE com syntax highlighting
        ├── ObsidianStore/        # App Store integrada
        ├── ObsRecord/            # Gravador de tela/câmera
        ├── MediaPlayer/          # Player de vídeo
        └── SdkAppRunner/         # Executor de apps SDK instalados
```

---

## 🚀 Como Rodar

```bash
# Instale as dependências
npm install

# Inicie o servidor de desenvolvimento
npm run dev
```

Acesse `http://localhost:5173`. O sistema inicia o boot automaticamente.

```bash
# Build de produção
npm run build
```

SPA pura sem backend — pode ser hospedada em qualquer CDN estático (Vercel, Netlify, GitHub Pages).

---

## 🏗️ Arquitetura do Sistema

```
┌─────────────────────────────────────────┐
│           CAMADA DE APLICATIVOS         │
│  Terminal | Explorer | TaskManager | …  │
├─────────────────────────────────────────┤
│           CAMADA DE COMPONENTES         │
│  Desktop | Taskbar | StartMenu | Window │
├─────────────────────────────────────────┤
│         CAMADA DE STORES (Mirrors)      │
│  fileSystem | registry | processManager │
│  windowManager | systemStore            │
├─────────────────────────────────────────┤
│         CAMADA DO KERNEL (Singleton)    │
│  kernel.ts — fonte da verdade de tudo   │
└─────────────────────────────────────────┘
```

Todos os Zustand stores operam como **mirrors reativos** do kernel. A fonte da verdade do estado e da lógica vive inteiramente no `Kernel` singleton. Os stores refletem o estado via eventos (`kernel.on('system:snapshot', ...)`, `kernel.on('fs:snapshot', ...)`).

---

### Kernel (`src/core/kernel.ts`)

Singleton clássico — uma única instância em toda a aplicação.

#### Responsabilidades

| Sistema | Função |
|---------|--------|
| **BIOS / Boot** | Executa `powerOn()`, roda `bootmgr.exe` como binário real |
| **Execution Engine** | Executa arquivos `.exe` e `.osl` do filesystem como scripts em sandbox |
| **Logging** | 6 níveis: `DEBUG`, `INFO`, `WARN`, `ERROR`, `CRITICAL`, `FATAL` |
| **Recursos** | CPU, RAM e disco em tempo real |
| **Drivers** | Registra e consulta drivers carregados |
| **Serviços** | Registra e atualiza status de serviços |
| **BSOD** | Dispara tela azul com stop code e informações técnicas |
| **Eventos** | Sistema pub/sub interno (`on`, `once`, `emit`, `off`) |
| **Filesystem** | CRUD completo do filesystem virtual |
| **Registry** | CRUD completo do registro do sistema |
| **Processos** | Criação, encerramento, suspensão de processos |
| **Janelas** | Abertura, fechamento, foco, resize, maximizar de janelas |
| **App Discovery** | Varre `System32` por manifestos JSON e registra apps |

#### Fases do Boot (`BootPhase`)

```
OFF → BIOS_POST → BIOS_HARDWARE → BOOTLOADER → KERNEL_INIT → DRIVER_LOAD
    → SERVICE_INIT → SHELL_INIT → DESKTOP_READY
    → BOOT_FAILURE | BSOD
```

#### API pública principal

```typescript
kernel.powerOn()                   // Inicia o boot (BIOS → bootmgr.exe)
kernel.finalizeBoot()              // Chamado pelo bootmgr.exe ao terminar
kernel.loadShell()                 // Carrega explorer.exe + descobre apps
kernel.on(event, callback)         // Subscrição de eventos
kernel.emit(event, ...args)        // Emissão de eventos
kernel.log(level, source, message) // Logging (FATAL → BSOD automático)
kernel.triggerBSOD(info)           // Dispara BSOD
kernel.allocateMemory(mb, name)    // Aloca RAM
kernel.freeMemory(mb)              // Libera RAM
kernel.createProcess(...)          // Cria processo
kernel.terminateProcess(pid)       // Encerra processo
kernel.openWindow(config)          // Abre janela
kernel.closeWindow(id)             // Fecha janela
kernel.fsGetNode(path)             // Lê nó do filesystem
kernel.fsCreateFile(...)           // Cria arquivo
kernel.fsDeleteNode(path)          // Deleta arquivo/pasta
kernel.regGetValue(path)           // Lê valor do registro
kernel.regSetValue(path, ...)      // Escreve valor no registro
kernel.scanSystemApps(fs, reg)     // Descobre e registra apps
kernel.reset()                     // Reseta estado (reboot)
```

---

### Execution Engine

O kernel possui um **execution engine** que executa arquivos `.exe` do filesystem como scripts JavaScript reais dentro de um sandbox (`new Function`).

Cada binário recebe o objeto `OS` com a API do sistema:

```javascript
OS.addBootLog(msg)       // Escreve no log de boot
OS.setBootPhase(phase)   // Muda fase do boot
OS.finalizeBoot()        // Sinaliza fim do boot
OS.triggerBSOD(info)     // Dispara BSOD
OS.readFile(path)        // Lê arquivo do FS
OS.writeFile(path, c)    // Escreve arquivo no FS
OS.listFiles(path)       // Lista arquivos
OS.createProcess(...)    // Cria processo
OS.allocateMemory(mb, n) // Aloca RAM
OS.registerDriver(entry) // Registra driver
OS.registerService(entry)// Registra serviço
OS.terminate(exitCode)   // Encerra o processo
OS.wait(ms)              // Aguarda (async)
```

O SDK em `C:\ObsidianOS\SDK\lib\obsidian.js` é automaticamente injetado antes de cada execução.

---

### Fluxo de Boot

O boot é inteiramente orquestrado pelo kernel — não existe mais um `bootSequence.ts` separado.

```
1. BootScreen monta → kernel.powerOn()
2. kernel.powerOn():
   - fsRepairSystemFiles()        → garante que bootmgr.exe está atualizado
   - createProcess('bootmgr.exe') → cria processo
   - executeBinary(bootmgr.exe)   → executa o script do bootmgr
3. bootmgr.exe (script JS):
   - Lê boot.ini, valida ARC path
   - Carrega ntoskrnl.exe (verifica existência)
   - Registra drivers (ntfs.sys, disk.sys, display.sys, hid.sys, netio.sys)
   - OS.finalizeBoot()            → emite 'boot:finished'
4. BootScreen recebe 'boot:finished':
   - Exibe logo + spinner por 2s
   - kernel.loadShell()
5. kernel.loadShell():
   - scanSystemApps()             → descobre e registra apps do System32
   - createProcess('explorer.exe', 'dwm.exe', 'SearchHost.exe')
   - bootPhase = 'DESKTOP_READY'
6. BootScreen → setBootPhase('login') → LockScreen aparece
7. Usuário faz login → kernel.sysLogin() → bootPhase = 'desktop'
```

**Auto-Repair:** Se `bootmgr.exe` não for encontrado, o kernel chama `fsDeepReformat()` e tenta novamente antes de falhar.

---

### Sistema de Arquivos Virtual

Estado gerido internamente pelo kernel, persistido no `localStorage` sob `obsidianos-filesystem-v2`. O Zustand store (`fileSystem.ts`) é apenas um mirror reativo.

#### Tipos de nó

```typescript
{
  id: string;           // Igual ao path
  name: string;
  type: 'file' | 'directory' | 'shortcut';
  path: string;         // Separador \\
  parentPath: string;
  size: number;
  extension?: string;
  content?: string;
  createdAt: number;
  modifiedAt: number;
  accessedAt: number;
  permissions: FilePermissions;
  attributes: FileAttributes;
  metadata?: Record<string, string>;
}
```

#### Tipos de executáveis

| Tipo | `content` | Uso |
|------|-----------|-----|
| `makeSysExe` | String descritiva PE32+ | Arquivos de sistema (ntoskrnl, dlls) |
| `makeAppExe` | JSON manifest com `appId`, `name`, `icon` | Apps descobertos pelo kernel |
| `makeBinaryExe` | Código JavaScript | Executáveis reais (bootmgr.exe, ping.exe, etc.) |

---

### Registro do Sistema

Gerido pelo kernel, persistido em `obsidianos-registry-v2`. Suporta todos os tipos reais do Windows:

`REG_SZ` · `REG_DWORD` · `REG_BINARY` · `REG_MULTI_SZ` · `REG_EXPAND_SZ` · `REG_QWORD`

Hives: `HKEY_LOCAL_MACHINE` · `HKEY_CURRENT_USER` · `HKEY_CLASSES_ROOT` · `HKEY_USERS` · `HKEY_CURRENT_CONFIG`

---

### App Registry (`src/core/appRegistry.ts`)

Começa vazio. Populado por `kernel.scanSystemApps()` durante o `loadShell()`, que varre `C:\ObsidianOS\System32` e `C:\Program Files\ObsidianOS Apps` procurando `.exe` com manifesto JSON (`type: "executable"`).

Os componentes React são lazy-loaded estaticamente:

| appId | Componente |
|-------|-----------|
| `terminal` | `apps/Terminal/Terminal` |
| `notepad` | `apps/Notepad/Notepad` |
| `calculator` | `apps/Calculator/Calculator` |
| `file-explorer` | `apps/FileExplorer/FileExplorer` |
| `settings` | `apps/Settings/Settings` |
| `task-manager` | `apps/TaskManager/TaskManager` |
| `browser` | `apps/Browser/Browser` |
| `regedit` | `apps/Regedit/Regedit` |
| `obsidian-code` | `apps/ObsidianCode/ObsidianCode` |
| `obsidian-store` | `apps/ObsidianStore/ObsidianStore` |
| `obs-record` | `apps/ObsRecord/ObsRecord` |
| `media-player` | `apps/MediaPlayer/MediaPlayer` |
| `sdk-runner` | `apps/SdkAppRunner/SdkAppRunner` |

---

## 🖼️ Componentes da Interface

### Boot Screen
Modo texto (BIOS/drivers): fundo preto, fonte monospace, log ao vivo via `kernel.on('bootLog')`.
Modo gráfico (shell init): logo 4 quadrados + spinner de 5 pontos.

### BSOD
Fiel ao Windows 11. Barra de progresso do memory dump baseada na RAM real do kernel. Cria `.DMP` em `C:\ObsidianOS\System32\Minidump\`. Reinicia após 3s via `window.location.reload()`.

### Lock Screen
Duas fases: relógio/data → campo de senha. Senha em branco = acesso direto.

### Desktop
Ícones fixos com double-click para abrir. Menu de contexto com opções de exibição e novo arquivo. Só renderiza se `explorer.exe` estiver rodando.

### Taskbar
`[Iniciar] [Pesquisa]` · `[janelas abertas]` · `[WiFi] [Volume] [Bateria] [Relógio]`

Posição configurável via Registro: `HKEY_CURRENT_USER\Software\ObsidianOS\Taskbar\Position` → `bottom | top | left | right`

### Start Menu
Busca em tempo real nos apps registrados. Seção "Fixados" (primeiros 6 apps). Context menu por app.

### Window
Title bar com drag, double-click para maximizar, right-click para context menu. 8 resize handles. Conteúdo envolto em `ProcessProvider` + `Suspense`.

### Context Menu
Global, singleton, gerenciado pelo `contextMenuStore`. Suporta separadores, items desabilitados e sub-menus.

---

## 📦 Aplicativos Integrados

| App | appId | Descrição |
|-----|-------|-----------|
| Terminal | `terminal` | 20+ comandos, histórico (↑↓), autocompletar (Tab) |
| Explorador de Arquivos | `file-explorer` | Navegação, criação, renomeação, exclusão |
| Gerenciador de Tarefas | `task-manager` | Gráficos CPU/RAM em tempo real, lista de processos |
| Bloco de Notas | `notepad` | Editor de texto com save no filesystem virtual |
| Calculadora | `calculator` | Operações básicas e avançadas |
| Navegador | `browser` | Iframe com barra de endereço |
| Configurações | `settings` | Tema, wallpaper, volume, rede, posição da taskbar |
| Editor do Registro | `regedit` | Navegação e edição do registro do sistema |
| **Obsidian Code** | `obsidian-code` | IDE completa para SDK (.obx) e OSL (.osl) com syntax highlighting, file tree, console integrado e execução em tempo real |
| **Obsidian Store** | `obsidian-store` | App Store com busca, categorias e instalação de apps via filesystem virtual |
| **ObS Record** | `obs-record` | Gravador de tela/câmera com preview ao vivo, pausa, qualidade ajustável, download e save no VFS |
| **Media Player** | `media-player` | Player de vídeo com suporte a blob URLs e base64, integrado ao File Explorer |
| **SDK App Runner** | `sdk-runner` | Executor sandbox para apps instalados via Obsidian Store |

### Comandos do Terminal

`help` · `dir`/`ls` · `cd` · `cls`/`clear` · `echo` · `type`/`cat` · `mkdir`/`md` · `touch` · `del`/`rm` · `rename` · `move` · `copy` · `tasklist` · `taskkill` · `ping` · `ipconfig` · `systeminfo` · `reg` · `regedit` · `calc` · `notepad` · `explorer` · `start` · `shutdown`/`reboot`

---

## 🔷 OSL — ObsidianOS Scripting Language

O OSL é uma linguagem de script interpretada, criada especificamente para o ObsidianOS. Os arquivos têm extensão `.osl` e são executados diretamente pelo kernel via interpreter próprio.

### Pipeline de execução

```
Código fonte (.osl)
    ↓ Lexer         → stream de tokens
    ↓ Parser        → AST (Abstract Syntax Tree)
    ↓ Interpreter   → execução + syscalls
```

### Sintaxe

```osl
// Variáveis
let nome = "Developer";

// Funções
fn saudacao(usuario) {
    system::log("Bem-vindo, " + usuario + "!");
}

// Estruturas de controle
if (nome == "Developer") {
    saudacao(nome);
} else {
    system::log("Acesso negado.");
}

// Loop
let i = 0;
while (i < 5) {
    system::log("Iteração: " + i);
    i = i + 1;
}
```

### Syscalls disponíveis (`system::`)

| Syscall | Descrição |
|---------|-----------|
| `system::log(msg)` | Imprime no console do processo |
| `system::fs_read(path)` | Lê conteúdo de um arquivo |
| `system::fs_write(path, content)` | Escreve em um arquivo |
| `system::fs_exists(path)` | Verifica se um nó existe |
| `system::fs_delete(path)` | Deleta um arquivo/pasta |
| `system::fs_list(path)` | Lista filhos de um diretório |
| `system::fs_getcwd()` | Retorna diretório atual do processo |
| `system::fs_chdir(path)` | Muda diretório do processo |
| `system::reg_get(path)` | Lê valor do registro |
| `system::get_resource(type)` | Retorna `ram` ou `cpu` em uso |
| `system::stdin()` | Lê input do usuário (async) |
| `system::panic(code, msg)` | Dispara BSOD |

### Funções built-in

| Função | Descrição |
|--------|-----------|
| `print(...)` | Loga via kernel |
| `wait(ms)` | Aguarda N milissegundos (async) |
| `rand(max)` | Número aleatório de 0 a max |

---

## 🔧 SDK de Aplicativos

Apps SDK são scripts JavaScript (`.obx`) que rodam via `SdkAppRunner` ou diretamente pelo kernel execution engine. Têm acesso à API `OS.*`:

```javascript
// Globals SDK disponíveis
OS.addBootLog(msg)
OS.readFile(path)
OS.writeFile(path, content)
OS.listFiles(path)
OS.createProcess(name, title, icon)
OS.allocateMemory(mb, name)
OS.getResources()    // { usedMemory, totalMemory, cpuUsage }
OS.terminate(code)
OS.wait(ms)

// StdIO
StdIO.print(msg)
StdIO.error(msg)

// Proc
Proc.pid
Proc.exit(code)
Proc.wait(ms)
```

Apps da **Obsidian Store** são instalados em `C:\Program Files\ObsidianOS Apps\` e têm acesso à API `OS.User32` para criar elementos DOM dentro da janela do SdkAppRunner.

---

## 🔥 Mecânicas de Realismo

### BSOD por arquivos críticos deletados
Deletar estes arquivos dispara BSOD automaticamente:

| Arquivo | Stop Code |
|---------|-----------| 
| `gdi32.dll` | `WIN32K_CRITICAL_FAILURE` (com corrupção visual por 4s antes) |
| `user32.dll` | `CLIENT_SERVER_RUNTIME_ISSUE` (sistema fica não-responsivo por 5s) |

### BSOD por processos críticos encerrados

| Processo | Stop Code |
|----------|-----------|
| `System` | `CRITICAL_PROCESS_DIED` |
| `csrss.exe` | `CRITICAL_PROCESS_DIED` |
| `lsass.exe` | `CRITICAL_PROCESS_DIED` |
| `dwm.exe` | `DESKTOP_WINDOW_MANAGER_DIED` |
| `smss.exe`, `wininit.exe`, `services.exe` | `CRITICAL_PROCESS_DIED` |

### Auto-Repair
Se `bootmgr.exe` não for encontrado no boot, o kernel executa `fsDeepReformat()` e tenta restaurar antes de falhar com BSOD.

### Recovery Mode
Após 3 crashes consecutivos (contados em `obsidianos_crash_count`), o sistema entra em Recovery Mode ao invés de tentar bootar normalmente.

### Monitoramento de recursos
CPU calculada a partir da soma dos processos ativos + ruído orgânico. RAM alocada/liberada dinamicamente pelo kernel via `allocateMemory`/`freeMemory`. Overload de RAM dispara BSOD `MEMORY_MANAGEMENT`.

### Atalhos de teclado
`Ctrl+Shift+Esc` → Gerenciador de Tarefas

---

## 🔧 Como Adicionar um Novo Aplicativo

**1. Crie o componente React:**
```
src/apps/MeuApp/MeuApp.tsx
src/apps/MeuApp/MeuApp.css
```

O componente recebe `{ windowId: string }` como prop.

**2. Registre o lazy import em `appRegistry.ts`:**
```typescript
const components: Record<string, any> = {
  // ...existentes
  'meu-app': lazy(() => import('../apps/MeuApp/MeuApp')),
};
```

**3. Adicione o executável no `defaultFileSystem.ts`:**
```typescript
// Na array appExes:
[
  'C:\\ObsidianOS\\System32\\meuapp.exe',
  'meuapp.exe',
  'C:\\ObsidianOS\\System32',
  'meu-app',        // appId
  '🚀',             // icon
  'utilities',      // category
  'Meu Aplicativo'  // displayName
],
```

O kernel vai descobrir o app automaticamente no próximo boot via `scanSystemApps()`.

**4. (Opcional) Adicione ao Desktop em `Desktop.tsx`:**
```typescript
const defaultIcons: DesktopIconData[] = [
  // ...existentes
  { id: 'meu-app', name: 'Meu Aplicativo', icon: '🚀', appId: 'meu-app' },
];
```

---

## 📦 Scripts

```bash
npm run dev      # Servidor de desenvolvimento
npm run build    # Build de produção (tsc + vite)
npm run lint     # ESLint
npm run preview  # Preview do build
```
