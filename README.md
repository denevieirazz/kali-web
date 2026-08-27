# CloudOS Unified

CloudOS Unified é um shell desktop híbrido para Windows que reúne a interface CloudOS, PowerShell, distribuições WSL e aplicativos gráficos Linux/WSLg. A interface React roda dentro de um host WPF/WebView2; um agente Node.js limitado ao loopback executa a integração real com o computador.

## O que já funciona

- Desktop web com boot, login, janelas, processos, taskbar, menu Iniciar e aplicativos CloudOS.
- Host desktop .NET 8/WebView2 com single-instance, fullscreen/kiosk, origem local verificada e recuperação de falha.
- Rastreamento allowlisted de janelas Win32 por HWND, com foco, minimizar, maximizar, restaurar e fechamento gracioso espelhados na taskbar.
- Primeiro acesso sem credenciais padrão, conta persistente, bcrypt, sessões JWT e recuperação por código mostrado uma única vez.
- Terminal real com perfis PowerShell e WSL, seleção de distribuição e PTY/WebSocket.
- Central Windows + Linux com inventário estruturado, operações WSL, catálogo allowlisted e lançamento por IDs opacos.
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

## Windows captured-surface POC

A branch experimental `poc/cloudos-windows-captured-surface` substitui o `anchored-overlay` como direção de apresentação final para apps Windows compatíveis:

```text
processo autorizado/correlacionado
        ↓
GraphicsCaptureItem do HWND
        ↓
Windows.Graphics.Capture + D3D11
        ↓
surface de apresentação pertencente ao CloudOS
```

O runtime é genérico por classe, não por aplicativo. Não devem existir adapters específicos para Brave, Chrome, Discord ou programas individuais.

A fronteira é **fail-closed**. Se correlação, containment, captura, apresentação ou input não puderem ser estabelecidos com segurança, o CloudOS deve bloquear a sessão e expor diagnóstico. A POC não pode usar como fallback uma janela solta no desktop Windows.

### Evidência física isolada

No HEAD `7f1f561302e6fb24406de6c2e50814391b83e93d`, a mesma fixture WinForms animada mostrou:

- HWND real com bounds nativos positivos;
- `window/projected`: `CreateCaptureSession` falhou com `0x8007139F / ERROR_NOT_CORRECT_STATE`, `GraphicsCaptureItem.Size=0x0`;
- `monitor`: PASS, 10 frames `2560x1440`, `EmptyFrameCount=0`.

Isso isolou o bloqueador na fronteira do `GraphicsCaptureItem` de janela: D3D11, bridge `IDXGIDevice → IDirect3DDevice`, frame pool, `GraphicsCaptureSession` e compositor WGC funcionaram no mesmo processo para HMONITOR.

### Gate físico atual

O runtime agora possui dois caminhos explícitos de factory:

1. `RawActivationFactory`: `RoGetActivationFactory("Windows.Graphics.Capture.GraphicsCaptureItem") → IGraphicsCaptureItemInterop → CreateForWindow/CreateForMonitor` usando ABI COM direto;
2. `ProjectedFactory`: caminho legado mantido somente como controle diagnóstico.

O probe inicializa explicitamente o apartment WinRT e registra falhas por estágio: `item-factory`, `item-metadata`, `initial-size`, `d3d-device`, `frame-pool`, `capture-session` ou `start-capture`.

O smoke físico executa três lanes no mesmo processo/fixture:

```text
window/raw       # PRODUCT GATE
window/projected # legacy control
monitor/raw      # lower-layer control
```

Ele sempre tenta as três lanes, mesmo quando a primeira falha, e grava:

```text
poc1-physical-evidence/windows-captured-surface/
├── fixture-window-wgc-smoke.json
├── fixture-window-projected-control.json
├── fixture-monitor-wgc-control.json
├── fixture-wgc-matrix-summary.json
└── fixture-wgc-smoke.log
```

O gate só passa se `window/raw` produzir o mínimo de frames configurado. Nenhum controle pode mascarar uma falha do gate de produto.

## Validação

Validação geral:

```powershell
npm run lint
npm run build
npm run build:host
npm run build:bootstrap
npm run test:bootstrap
npm test
npm run test:e2e
```

Prova física captured-surface:

```powershell
pwsh -NoProfile -File scripts/test-windows-capture-probe.ps1 -ExpectedHeadSha <SHA_EXATO>
```

O script exige branch e SHA exatos, compila fixture/probe, executa a matriz completa e persiste evidência mesmo quando a sessão falha durante setup.

## Segurança das operações nativas

- Instalação, atualização e conversão de WSL exigem administrador CloudOS.
- O backend permanece sem elevação; somente o broker de verbos fixos pede UAC.
- O catálogo de apps guarda alvos no servidor e entrega IDs opacos ao frontend.
- Não existe endpoint genérico para executar comando, arquivo ou argumentos enviados pelo navegador.
- A captured-surface POC não enfraquece a política de containment nem autoriza spill de UI em caso de falha.

Consulte [SECURITY.md](SECURITY.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) e [docs/NATIVE-HOST-ROADMAP.md](docs/NATIVE-HOST-ROADMAP.md).

## Futuro modo shell do computador

O destino arquitetural é o CloudOS substituir a experiência visual do Explorer para uma conta dedicada, mantendo o Windows por baixo para kernel, drivers, Win32, segurança e WSLg. Nesta versão isso está apenas em preparação: nenhum script altera o shell, o Registro ou o boot do computador.
