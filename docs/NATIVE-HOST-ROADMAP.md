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

### Padrão: janelas top-level gerenciadas

O host inicia o app, identifica suas janelas, acompanha criação/fechamento e espelha a sessão na taskbar CloudOS. Ele controla foco, posição, tamanho, minimizar, maximizar e fechar. Essa abordagem preserva desempenho e compatibilidade de Win32/WSLg.

### Superfície embutida experimental

Para aplicativos compatíveis, uma fase posterior pode usar Windows Graphics Capture e encaminhamento de entrada. Sempre haverá fallback top-level, porque conteúdo protegido, elevação, múltiplas janelas, DPI, IME e alguns apps de GPU não podem ser tratados universalmente.

`SetParent` entre processos não será a base do produto: há conflitos de DPI, estilos, foco, integridade e estabilidade.

## Etapas

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

   A preparação de recuperação inclui `CloudOS.Bootstrap`, um executável WPF
   independente de WebView2/Node que aguarda o carregamento da origem local confiável, aplica
   backoff e interrompe crash loops em uma UI de recuperação. Ele ainda não é
   registrado como shell nem modifica configurações do Windows.

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
- Drivers, anti-cheat, DRM, secure desktop e apps elevados podem exigir fallback nativo.
