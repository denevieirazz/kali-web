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
→ abre dentro do CloudOS

UNSUPPORTED / PROTECTED / BROKER_UNSAFE / SINGLETON_UNSAFE / RENDER_FAILED
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

A evidência física no HEAD `7f1f561302e6fb24406de6c2e50814391b83e93d` isolou o bloqueador anterior:

```text
mesma fixture WinForms animada
mesmo processo
mesmo device D3D11
mesmo frame-pool code

HWND / projected factory
→ CreateCaptureSession FAIL 0x8007139F
→ item.Size = 0x0

HMONITOR
→ PASS
→ 10 frames 2560x1440
→ EmptyFrameCount = 0
```

Portanto D3D11, bridge DXGI→WinRT, frame pool, `GraphicsCaptureSession` e compositor WGC estão funcionalmente provados no ambiente físico; o defeito restante foi isolado na fronteira do `GraphicsCaptureItem` de janela.

O gate seguinte usa três lanes em uma única execução:

1. `window/raw-activation-factory` — gate do produto. Obtém `IGraphicsCaptureItemInterop` diretamente via `RoGetActivationFactory` e chama `CreateForWindow` no ABI COM oficial;
2. `window/projected-factory` — controle do caminho legado anterior;
3. `monitor/raw-activation-factory` — controle das camadas abaixo do item de janela.

O probe inicializa explicitamente o apartment WinRT para a prova, registra o estágio de setup (`item-factory`, `item-metadata`, `initial-size`, `d3d-device`, `frame-pool`, `capture-session`, `start-capture`) e grava JSON mesmo quando a sessão não chega a iniciar. O smoke consolida as três lanes em `fixture-wgc-matrix-summary.json`. Nenhum controle pode mascarar um gate de janela falho.

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
