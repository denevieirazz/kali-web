# Plano de empacotamento Windows

## Decisão

O alvo recomendado é um host Windows em .NET 8 com WinUI 3 (ou WPF, caso a prioridade seja maturidade) e WebView2. Essa combinação preserva o frontend React e permite criar a ponte nativa necessária para janelas Windows/WSLg, UAC, reinício e integração de arquivos.

Electron continua sendo uma alternativa para uma embalagem rápida, mas não resolve sozinho rastreamento de HWND, captura, integridade/UIPI ou broker elevado. Também aumenta o tamanho do instalador ao incluir outro Chromium.

## Componentes do pacote

```text
CloudOS-Setup.msix / .exe
  ├── CloudOS.Bootstrap.exe     guardião e UI WPF de recuperação
  ├── CloudOS.Host.exe          WebView2, shell e supervisor
  ├── CloudOS.Broker.exe        pequeno, assinado, elevado sob demanda
  ├── runtime/node.exe          runtime Node.js fixado
  ├── agent/backend/            agente local
  ├── web/                      build estático do frontend
  └── assets/                   ícones e recursos
```

Todo código executável dessa árvore, inclusive JavaScript do agente e do frontend,
é coberto por um catálogo assinado de hashes. Binários ficam em uma área de
instalação protegida. Dados mutáveis ficam em `%LOCALAPPDATA%\CloudOS\`:

- banco JSON v2, backups de recuperação e segredo JWT;
- journal de operações;
- logs com redação de segredos;
- preferências e cache;
- arquivos de runtime com PID, horário inicial e nonce.

## Inicialização

1. O bootstrap garante uma instância por usuário e inicia somente o host esperado.
2. O host valida arquivos e versão do runtime.
3. O host inicia o agente em `127.0.0.1` e porta dinâmica.
4. Host e agente autenticam uma lease privada; perder o host encerra o agente.
5. O host aguarda health check autenticado do agente.
6. O host mapeia o build React para `http://cloudos.localhost/` e injeta os endpoints efêmeros da API/WS antes do bundle.
7. Depois que o bundle React monta, a ponte faz o handshake e o host sinaliza prontidão ao bootstrap; HTTP 200 ou navegação concluída não bastam.
8. O bootstrap observa a saída e interrompe crash loops numa UI sem WebView2.
9. O CloudOS reconcilia operações interrompidas e sessões nativas.

O host valida executável, horário de início e nonce antes de encerrar um PID registrado. Um arquivo de runtime obsoleto nunca é motivo suficiente para matar um processo.

## Broker e elevação

- Executado apenas para ações que realmente exigem administrador.
- IPC por named pipe com ACL limitada ao SID da sessão atual.
- Mensagens versionadas, nonce de uso único, expiração e verbos allowlisted.
- Nenhum `command`, PowerShell ou argv arbitrário atravessa a ponte do frontend.
- UAC negado volta como estado de operação recuperável.

## Instalação e atualização

- MSIX assinado quando possível; instalador `.exe` assinado como fallback.
- WebView2 Evergreen bootstrapper ou requisito verificado no setup.
- Atualização atômica com rollback.
- Desinstalação preserva dados por padrão e pergunta antes de removê-los.
- WSL e distribuições nunca são removidos junto com o CloudOS sem fluxo separado e confirmação explícita.

## Estado da primeira POC

- Implementado: abrir CloudOS em WebView2; iniciar/supervisionar o agente; origem local verificada; bridge restrita; fullscreen/kiosk; tracking por PID; focar, maximizar, minimizar, restaurar e fechar; espelhar sessões atribuídas na taskbar.
- Implementado e disponível somente na prévia opt-in: bootstrap WPF independente, handshake de prontidão, backoff, journal por usuário e tela de recuperação após crash loop. Ele não altera o Registro nem substitui o shell atual; o atalho padrão continua direto no host.
- Validado automaticamente: build Release sem avisos, frontend de produção, health autenticado, origem estável do documento, agente em porta efêmera e shutdown gracioso.
- Pendente para produto: correlação de janelas de brokers StartApps/WSLg, mover/redimensionar pela taskbar, retomada após reboot, matriz DPI/multi-monitor, fixture gráfica e instalador assinado.

Veja [NATIVE-HOST-ROADMAP.md](NATIVE-HOST-ROADMAP.md) para as fases completas.
