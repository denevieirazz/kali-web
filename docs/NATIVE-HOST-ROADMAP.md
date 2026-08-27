# Roadmap do host nativo CloudOS

## Objetivo

Transformar o CloudOS em um shell desktop Windows que mantém a interface web existente, mas coordena programas Windows e Linux/WSLg como parte do mesmo ambiente.

## Por que um host é necessário

Aplicativos Win32, UWP e WSLg criam janelas nativas. O sandbox do navegador não oferece APIs para enumerar HWNDs, controlar foco, reservar área de trabalho, encaminhar entrada ou incorporar outra janela dentro do DOM. WSLg integra os aplicativos ao desktop do Windows; ele não oferece uma superfície HTML.

O produto final deve usar WebView2 dentro de um host WinUI 3 ou WPF. O frontend React permanece praticamente igual.

## Arquitetura alvo

```text
CloudOS.Host (usuário normal)
  ├── WebView2 com origem exclusiva CloudOS
  ├── supervisor do agente Node.js
  ├── catálogo e sessões nativas
  ├── WinEventHook / rastreamento de HWND
  ├── Windows captured-surface runtime
  ├── taskbar e workspace CloudOS
  ├── clipboard, arquivos e drag-and-drop
  └── IPC autenticado
          │
CloudOS.Broker (elevado apenas sob UAC)
  ├── EnableWsl
  ├── UpdateWsl
  ├── InstallDistro
  └── ConvertDistro
```

Antes do host, `CloudOS.Bootstrap` fornece uma superfície nativa mínima de recuperação e limita reinícios em caso de falha precoce. Ele permanece inerte em relação ao Registro e ao shell do Windows durante o desenvolvimento.

O broker aceita verbos e esquemas de argumentos fixos. Ele nunca aceita PowerShell, executável, caminho ou argumentos livres vindos do JavaScript.

## Estratégia de janelas

### Infraestrutura legada: top-level gerenciado

O host já consegue iniciar alguns apps, identificar suas janelas, acompanhar criação/fechamento e espelhar a sessão na taskbar CloudOS. Essa infraestrutura continua útil para correlação, lifecycle e contenção, mas **não é a apresentação final desejada para aplicativos Windows** porque a janela de origem continua sendo um HWND top-level real do Windows.

### Alvo do produto: Windows captured-surface runtime

O runtime Windows alvo separa processo, origem visual e apresentação:

```text
app instalado / shortcut autorizado
        ↓
discovery + classificação de runtime
        ↓
processo controlado / identidade / Job quando aplicável
        ↓
HWND autorizado e correlacionado
        ↓
Windows.Graphics.Capture + D3D11
        ↓
surface de apresentação pertencente ao CloudOS
        ↓
input/focus/DPI/lifecycle mediados pelo CloudOS
```

`SetParent` entre processos não será a base do produto: há conflitos de DPI, estilos, foco, integridade e estabilidade. PNG/JPEG por frame através da bridge web também não é renderer final aceitável.

O runtime é genérico por classe de execução, não por nome de app. A matriz alvo inclui Win32 direct, singleton, Chromium/Electron, UWP/MSIX, brokered, elevated e unsupported/protected. Não devem existir adapters específicos para Brave, Chrome, Discord ou outro aplicativo individual.

### Regra fail-closed

A experiência final não possui fallback automático para uma janela solta no desktop Windows. Se correlação, containment, captura, apresentação ou input não puderem ser estabelecidos com segurança, o runtime deve classificar a sessão e recusar a abertura:

```text
CAPTURE_SUPPORTED
→ abre dentro do CloudOS somente depois dos demais gates de apresentação/input

UNSUPPORTED / PROTECTED / BROKER_UNSAFE / SINGLETON_UNSAFE / CAPTURE_BLOCKED / RENDER_FAILED
→ bloqueia e explica o motivo
```

O comportamento legado top-level pode permanecer disponível apenas como infraestrutura de desenvolvimento/diagnóstico durante a migração; não pode transformar uma falha do captured-surface runtime em sucesso de produto.

## Windows Universal Runtime — fases

1. discovery universal de apps instalados;
2. launch classification;
3. process/Job containment;
4. HWND discovery e identidade por PID/start-time/session;
5. GPU captured surface;
6. CloudOS-owned presentation surface;
7. mouse/keyboard/focus/DPI;
8. resize/minimize/maximize/multiwindow;
9. singleton/broker handling;
10. installer detection + live catalog refresh;
11. compatibility matrix;
12. fail-closed para classes incompatíveis.

A POC `poc/cloudos-windows-captured-surface` está focada primeiro nos gates 4–6.

### Gate de captura atual

A evidência física isolou a fronteira atual usando uma fixture WinForms convencional, visível e animada:

```text
mesma máquina
mesma fixture
mesmo lower-layer D3D11/WGC

HWND
→ GraphicsCaptureItem.Size = 0x0
→ buffer bootstrap nativo válido 642x452
→ CreateCaptureSession FAIL 0x8007139F
→ 0 frames

HMONITOR
→ PASS
→ 10 frames 2560x1440
→ EmptyFrameCount = 0
→ item.Size = 2560x1440
```

Portanto D3D11, bridge DXGI→WinRT, frame pool, `GraphicsCaptureSession` e compositor WGC estão fisicamente provados para monitor. O defeito restante está restrito à qualificação do item/sessão de janela; a causa ainda não é considerada provada.

#### Matriz C# de cinco lanes

Uma única execução física futura separa activation factory, projection e ABI lifetime:

1. `window/raw/marshal-interface/hold` — **PRODUCT CANDIDATE**;
2. `window/raw/marshal-interface/release` — lifetime control;
3. `window/raw/projected-type/hold` — projection control;
4. `window/projected-factory/marshal-interface/hold` — factory control;
5. `monitor/raw/marshal-interface/hold` — lower-layer control.

Somente a lane 1 pode aprovar o gate do produto. Todas as outras são controles e nunca funcionam como fallback silencioso.

O candidate mantém a referência ABI original do `GraphicsCaptureItem` viva até o dispose da capture session e usa ownership single-owner para impedir double-release em erro.

#### Diagnóstico HWND

Antes de criar a sessão, o probe registra:

- HWND/título/classe/retângulo;
- visible/iconic/hung;
- DWM cloak;
- style/exstyle;
- owner/root-owner;
- HMONITOR;
- thread/PID;
- DPI;
- display affinity quando disponível.

#### Controle nativo independente C++/WinRT

`CloudOS.WindowsCapture.NativeReference` usa o padrão nativo:

```text
get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()
→ CreateForWindow(HWND, IID_IGraphicsCaptureItem, put_abi(item))
→ GraphicsCaptureItem.Size / DisplayName
```

Ele não compartilha CsWinRT C#, marshaling C#, TerraFX nem o frame-pool do produto. O executável gera JSON de sucesso/erro com `verdict`, `stage`, HWND, dimensões do item e HRESULT.

A matriz física usa o **mesmo HWND escolhido pelo probe C#** para esse controle nativo. Se a toolchain C++ não estiver instalada na máquina física, o summary registra `NOT_AVAILABLE`; isso não aprova nem reprova o gate do produto.

Interpretação:

```text
C++ item válido + C# item inválido
→ forte suspeita de projection/lifetime C#

C++ item também inválido/0x0
→ Windows/session/eligibility do target ganha peso

C++ CreateForWindow falha por HRESULT
→ falha existe abaixo da projection C#
```

#### Harness genérico para app real

Depois que a fixture passar, `scripts/test-windows-capture-app.ps1` permite qualificar um executável Windows real sem adapter específico.

Contrato:

- resolve executável diretamente, sem shell;
- lança por `ProcessStartInfo.ArgumentList` com `UseShellExecute=false`;
- exige janela top-level do mesmo PID;
- launcher que encerra antes de publicar janela própria é `BROKER_OR_SINGLETON_UNSAFE`;
- executa `window/raw/marshal-interface/hold`;
- executa o controle C++ no mesmo HWND quando disponível;
- grava summary/log antes de falhar;
- não transforma ausência de captura em janela solta do Windows.

Classificações de captura atuais:

```text
CAPTURE_SUPPORTED
CAPTURE_BLOCKED
RENDER_FAILED
BROKER_OR_SINGLETON_UNSAFE
```

`CAPTURE_SUPPORTED` nesta fase prova somente captura/frame delivery. Ainda não prova presentation surface, input, isolamento de Alt+Tab ou compatibilidade final.

#### CI sem desktop interativo

`Windows Captured Surface CI` valida:

- build do runtime/probe C#;
- CLI de factory/projection/lifetime;
- parser/contrato da matriz física;
- parser/security contract do harness genérico de app real;
- build da fixture WinForms;
- build x64 do C++/WinRT reference;
- CLI do reference;
- contrato JSON de erro usando HWND inválido `0x1`, exigindo exit `3`, `verdict=ERROR` e `stage=target-validation`.

CI não substitui a qualificação física do HWND real.

## Etapas gerais do host

1. **Controle web local — implementado**
   - capacidades reais de Windows/WSL/WSLg;
   - catálogo e instalação de distribuições;
   - operações acompanháveis e canceláveis;
   - terminal por distribuição;
   - catálogo/lançamento allowlisted de apps Windows e Linux.

2. **Host WebView2 — baseline implementada**
   - iniciar, autenticar e encerrar o agente em porta efêmera;
   - mapear o build React para uma origem WebView2 estável, injetar endpoints efêmeros de API/WebSocket e restringir a navegação;
   - single-instance, fullscreen, kiosk, recuperação de agente/WebView2 e bridge JSON v1;
   - abrir apps por ID opaco e gerenciar HWNDs atribuídos por PID com foco, minimizar, maximizar, restaurar e fechar;
   - espelhar sessões gerenciadas na taskbar CloudOS.

   A preparação de recuperação inclui `CloudOS.Bootstrap`, um executável WPF independente de WebView2/Node que aguarda o carregamento da origem local confiável, aplica backoff e interrompe crash loops em uma UI de recuperação. Ele ainda não é registrado como shell nem modifica configurações do Windows.

   A correlação de janelas entregues a brokers compartilhados (StartApps/UWP e WSLg) e a retomada completa depois de UAC/reinício permanecem na próxima etapa. O host não registra o processo compartilhado inteiro, porque isso concederia controle sobre janelas que não pertencem ao lançamento CloudOS.

3. **Shell nativo — expansão**
   - diagnóstico de prontidão por perfil e supervisor de recuperação independente;
   - proteção contra crash-loop, last-known-good e health contínuo;
   - correlação segura de AUMID/StartApps e sessões WSLg;
   - retomar journal depois de UAC/reinício;
   - múltiplos monitores, DPI, Alt+Tab e áreas de trabalho;
   - lease de vida para garantir encerramento do agente se o host morrer;
   - ativação reversível e testada somente em VM, mantendo recuperação fora do host.

4. **Arquivos reais**
   - provider `windows://` com raízes concedidas;
   - provider `linux://` via `\\wsl.localhost\Distro`;
   - tradução segura de caminhos e prevenção de traversal/reparse points;
   - clipboard e drag-and-drop entre CloudOS, Windows e Linux.

5. **Distribuição**
   - MSIX/instalador assinado;
   - atualização automática;
   - broker assinado e named pipe limitado ao SID atual;
   - telemetria opt-in, logs redigidos e recuperação após reboot.

6. **Shell principal — somente após qualificação**
   - Shell Launcher v2 por usuário numa edição Windows compatível;
   - Explorer preservado para uma conta administrativa de recuperação;
   - primeira ativação exclusivamente em VM descartável;
   - Custom Logon/Unbranded Boot somente depois de rollback e recuperação comprovados;
   - nenhuma remoção ao vivo de componentes do Windows.

## Limites que a interface deve comunicar

- UAC e reinicialização não podem ser ocultados com segurança; o CloudOS os conduz e retoma o fluxo.
- O primeiro acesso de algumas distribuições exige criar usuário/senha Linux.
- WSLg requer WSL 2 e Windows 10 build 19044+ ou Windows 11.
- Drivers, anti-cheat, DRM, secure desktop, capture-protected content, apps elevados e brokers compartilhados podem ser classificados como incompatíveis até existir uma estratégia segura para aquela classe; isso não autoriza spill de UI para o desktop Windows.
