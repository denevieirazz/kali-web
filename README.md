# CloudOS Unified

CloudOS Unified é um shell desktop híbrido para Windows que reúne a interface CloudOS, PowerShell, distribuições WSL e aplicativos gráficos Linux/WSLg. A interface React roda dentro de um host WPF/WebView2; um agente Node.js limitado ao loopback executa a integração real com o computador.

## O que já funciona

- Desktop web com boot, login, janelas, processos, taskbar, menu Iniciar e aplicativos CloudOS.
- Host desktop .NET 8/WebView2 com single-instance, fullscreen/kiosk, origem local verificada e recuperação de falha.
- Rastreamento allowlisted de janelas Win32 por HWND, com foco, minimizar, maximizar, restaurar e fechamento gracioso espelhados na taskbar.
- Primeiro acesso sem credenciais padrão, conta persistente, bcrypt, sessões JWT e recuperação por código mostrado uma única vez.
- Terminal real com perfis PowerShell e WSL, seleção de distribuição e PTY/WebSocket.
- Central Windows + Linux com:
  - inventário estruturado de Windows, WSL, kernel e WSLg;
  - distribuições instaladas, estado, versão e padrão;
  - catálogo oficial retornado por `wsl --list --online`;
  - instalação de distribuição com UAC sob demanda;
  - atualização de WSL/WSLg;
  - iniciar, parar, tornar padrão e converter uma distribuição para WSL 2;
  - operações assíncronas, saída técnica, cancelamento e atualização de progresso;
  - catálogo allowlisted de aplicativos do Menu Iniciar e arquivos `.desktop` Linux;
  - lançamento por IDs opacos, sem comandos ou caminhos enviados pela página.
- Sistema de arquivos virtual em OPFS, editor, upload/download e lixeira.
- API Express ligada apenas a `127.0.0.1`, CORS local e ambiente do terminal sem segredos do backend.

## Arquitetura

```text
CloudOS.Host / WPF / WebView2
        │ ponte JSON versionada e restrita
        ▼
React / Vite / Zustand
        │ HTTP + WebSocket autenticados para loopback
        ▼
CloudOS Local Agent / Node.js (porta efêmera)
        ├── Windows / PowerShell
        ├── WSL 2 / distribuições
        └── WSLg / apps Linux GUI
```

No host desktop, o documento React usa a origem fixa `http://cloudos.localhost/`, mapeada pelo WebView2 para o build local. Assim, `localStorage`, IndexedDB e OPFS continuam na mesma partição entre reinicializações. O agente usa uma porta efêmera em `127.0.0.1`; o host injeta somente os endpoints daquela execução, e CORS/WebSocket aceitam a origem fixa apenas no modo nativo. O fluxo Vite em `15173` permanece disponível para desenvolvimento web.

## Limite das janelas nativas e captured-surface POC

O host estável ainda possui infraestrutura legada que acompanha janelas top-level nativas atribuídas com segurança. Nessa arquitetura antiga, os pixels continuam sendo desenhados pelo Windows e a janela de origem continua sendo uma janela Win32 real.

A branch experimental `poc/cloudos-windows-captured-surface` existe para substituir esse modelo como apresentação final de aplicativos Windows. O contrato da POC é:

```text
processo Windows autorizado/correlacionado
        ↓
GraphicsCaptureItem do HWND
        ↓
Windows.Graphics.Capture + D3D11
        ↓
surface de apresentação pertencente ao CloudOS
```

O runtime experimental é genérico por classe de runtime, não por aplicativo. Não devem existir adapters específicos para Brave, Chrome, Discord ou programas individuais. O objetivo é que aplicativos Win32 convencionais instalados antes ou depois do CloudOS sejam descobertos, classificados e apresentados através do mesmo runtime.

A fronteira de segurança é **fail-closed**: se o CloudOS não conseguir correlacionar, conter, capturar ou apresentar um aplicativo com segurança, ele deve recusar a abertura e expor um diagnóstico. A POC **não pode** usar como fallback abrir a UI normalmente no desktop Windows. Apps elevados, DRM/protected capture, anti-cheat, exclusive fullscreen, brokers compartilhados, handoff de singleton e outros modelos incompatíveis podem permanecer explicitamente `UNSUPPORTED` até existir uma estratégia segura para aquela classe.

O gate físico atual da POC usa uma fixture WinForms convencional e compara três caminhos na mesma execução: HWND via activation factory WinRT em ABI cru (gate do produto), HWND pelo caminho projetado legado (controle) e HMONITOR via activation factory cru (controle de D3D/frame-pool/compositor). O caminho raw obtém `IGraphicsCaptureItemInterop` diretamente da activation factory `Windows.Graphics.Capture.GraphicsCaptureItem`, espelhando o contrato Win32 oficial em vez de depender do helper projetado como fronteira de fábrica.

### Evidência física isolada antes do raw activation-factory fix

No HEAD `7f1f561302e6fb24406de6c2e50814391b83e93d`, a mesma fixture WinForms animada mostrou:

- alvo HWND real `0x460A22`, título `CloudOS Windows Capture Fixture`, bounds nativos positivos;
- captura por janela: `CreateCaptureSession` falhou com `0x8007139F / ERROR_NOT_CORRECT_STATE`, `GraphicsCaptureItem.Size=0x0`;
- controle por monitor: **PASS**, 10 frames `2560x1440`, `EmptyFrameCount=0`, item e buffer iniciais `2560x1440`.

Essa prova isola o defeito anterior no caminho do `GraphicsCaptureItem` de janela: D3D11, bridge `IDXGIDevice → IDirect3DDevice`, frame pool, `GraphicsCaptureSession` e compositor WGC funcionaram no mesmo processo quando o target foi HMONITOR.

O HEAD atual substitui a fronteira de factory do gate HWND por ABI cru (`RoGetActivationFactory → IGraphicsCaptureItemInterop → CreateForWindow`) e mantém o caminho projetado anterior apenas como controle explícito, sem fallback silencioso.

O smoke está em `scripts/test-windows-capture-probe.ps1` e grava evidência estruturada em `poc1-physical-evidence/windows-captured-surface`, incluindo um resumo de matriz mesmo quando a sessão de captura falha durante setup.

Consulte [docs/NATIVE-HOST-ROADMAP.md](docs/NATIVE-HOST-ROADMAP.md) para a evolução do host nativo.

## Requisitos

- Node.js 18 ou superior; Node.js 22 LTS recomendado.
- Microsoft Edge WebView2 Runtime.
- .NET 8 SDK apenas para compilar/executar o host a partir do código; o instalador final será self-contained.
- Windows 10/11 para integração nativa.
- Windows 10 build 19044+ ou Windows 11, WSL 2 e driver de GPU compatível para WSLg.

O frontend pode ser aberto em Linux/macOS para desenvolvimento, mas PowerShell, WSL e aplicativos nativos ficam indisponíveis.

## Instalação e execução

```powershell
npm install
powershell.exe -ExecutionPolicy Bypass -File scripts/start-dev.ps1
```

Ou inicie as camadas separadamente:

```powershell
npm --prefix backend start
npm --prefix frontend run dev
```

Na primeira abertura, crie o administrador local e salve o código de recuperação mostrado uma única vez. Não existe usuário ou senha padrão. Uma conta de versão anterior recebe seu primeiro código após o próximo login válido.

Para executar o host desktop durante o desenvolvimento:

```powershell
npm run build
powershell.exe -ExecutionPolicy Bypass -File scripts/run-native-host.ps1 -NodePath C:\caminho\node.exe -Fullscreen
```

O host também aceita `--kiosk` e `--developer-mode`. O layout final empacota o Node em `runtime/node.exe`, dispensando `-NodePath`.

## Validação

```powershell
npm run lint
npm run build
npm run build:host
npm run build:bootstrap
npm run test:bootstrap
npm test
npm run test:e2e
```

Para a POC de captured surface no Windows físico:

```powershell
pwsh -NoProfile -File scripts/test-windows-capture-probe.ps1 -ExpectedHeadSha <SHA_EXATO>
```

O smoke exige a branch correta e o SHA exato, compila a fixture/probe, executa a matriz `window/raw`, `window/projected` e `monitor/raw`, grava os três relatórios mais `fixture-wgc-matrix-summary.json`, e falha se o gate `window/raw-activation-factory` não entregar o mínimo de frames solicitado. Controles diagnósticos não podem transformar um gate de janela falho em PASS.

Os runners de teste definem `NODE_ENV=test` e usam um diretório temporário; a suíte não deve redefinir o banco local de desenvolvimento.

## Segurança das operações nativas

- Instalação, atualização e conversão de WSL exigem administrador CloudOS.
- O backend permanece sem elevação; somente o broker de verbos fixos pede UAC.
- O catálogo de apps guarda alvos no servidor e entrega IDs opacos ao frontend.
- Não existe endpoint genérico para executar comando, arquivo ou argumentos enviados pelo navegador.
- Remoção destrutiva de distribuições ainda não é exposta. Ela só será adicionada com exportação/backup, reautenticação e confirmação forte.

Consulte [SECURITY.md](SECURITY.md) e [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Futuro modo shell do computador

O destino arquitetural é o CloudOS substituir a experiência visual do Explorer para uma conta dedicada, mantendo o Windows por baixo para kernel, drivers, Win32, segurança e WSLg. Nesta versão isso está apenas em preparação: nenhum script altera o shell, o Registro ou o boot do computador.

Execute o diagnóstico somente leitura:

```powershell
npm run shell:check
```

Ele mostra edição compatível, pacote, WebView2, Explorer de recuperação, WinRE, assinatura e requisitos manuais sem ativar nada. O plano de fases, recuperação e limites está em [docs/SHELL-MODE-PLAN.md](docs/SHELL-MODE-PLAN.md).

Quando o bootstrap publicado estiver presente, a prévia supervisionada pode ser aberta manualmente com `npm run preview:shell`. Isso apenas inicia o CloudOS em tela cheia com proteção contra crash-loop; não altera o shell, o Registro ou o boot do Windows. O atalho `Iniciar CloudOS.cmd` continua usando o fluxo estável anterior.
