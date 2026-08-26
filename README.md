# CloudOS Unified

CloudOS Unified é um shell desktop híbrido para Windows que reúne a interface CloudOS, PowerShell, distribuições WSL e aplicativos gráficos Linux/WSLg. A interface React roda dentro de um host WPF/WebView2; um agente Node.js limitado ao loopback executa a integração real com o computador.

## O que já funciona

- Desktop web com boot, login, janelas, processos, taskbar e menu Iniciar unificado para aplicativos CloudOS, Windows e Linux/WSL.
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
  - catálogo allowlisted de aplicativos do Menu Iniciar e arquivos `.desktop` Linux, pesquisável diretamente no menu Iniciar do CloudOS;
  - lançamento por IDs opacos em uma janela CloudOS dedicada, sem comandos ou caminhos enviados pela página;
  - encaixe visual, foco, ocultação ao minimizar e fechamento sincronizados para janelas que o host consegue atribuir com segurança.
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

## Limite das janelas nativas

Programas Windows e WSLg criam janelas top-level nativas. O host CloudOS acompanha as janelas que consegue atribuir com segurança e as posiciona sobre a área de conteúdo da janela CloudOS correspondente; os pixels continuam sendo desenhados pelo Windows, não por uma `<div>`. Isso preserva compatibilidade, GPU, áudio, IME e desempenho enquanto mantém o fluxo visual dentro do CloudOS.

Apps elevados, DRM, anti-cheat, secure desktop e brokers compartilhados do WSLg podem exigir fallback como janela nativa não gerenciada. Captura literal dentro do canvas é uma fase experimental. Consulte [docs/NATIVE-HOST-ROADMAP.md](docs/NATIVE-HOST-ROADMAP.md).

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
