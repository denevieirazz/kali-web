# Unified Windows + Linux Integration V16

## Objetivo

V16 transforma o CloudOS de um shell que apenas lança ferramentas do Windows/WSL em uma experiência integrada onde operações comuns continuam dentro do CloudOS: baixar arquivos, escolher destinos, encontrar aplicativos, instalar/remover software e usar apps Linux/Windows no mesmo Desktop/Start/Files.

CloudOS continua sendo um shell C++/Win32 sobre Windows; ele não substitui kernel, drivers, DWM, Win32 nem o kernel Linux do WSL. A integração é construída sobre APIs suportadas do Windows, WebView2, WSL/WSLg e package managers existentes.

## Fontes oficiais usadas no desenho

- WebView2 DownloadStarting/ResultFilePath: https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2downloadstartingeventargs?view=webview2-1.0.4078.44
- WinGet install/list/uninstall: https://learn.microsoft.com/en-us/windows/package-manager/winget/
- WSL GUI/WSLg: https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps
- Windows ↔ Linux filesystem interoperability: https://learn.microsoft.com/en-us/windows/wsl/filesystems
- Windows default apps/file associations: https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-default-apps-settings
- Windows App SDK PackageDeploymentManager: https://learn.microsoft.com/en-us/windows/package-manager/package-deployment-manager/

## 1. Navegador → CloudOS Files

`native_browser_window.cpp` registra `ICoreWebView2::DownloadStarting`.

Fluxo:

```text
site inicia download
  ↓
WebView2 DownloadStarting
  ↓
CloudOSNativeFolderPickerV16
  ├─ Downloads
  ├─ Desktop
  ├─ Documentos
  ├─ qualquer pasta Windows
  └─ \\wsl.localhost\...
  ↓
ResultFilePath definido pelo CloudOS
  ↓
WebView2 grava no destino escolhido
```

O picker é first-party. O usuário não é empurrado para Explorer para escolher a pasta. Cancelar no picker cancela o download de forma explícita. Colisões recebem um nome não destrutivo (`arquivo (1).ext`, etc.).

O CloudOS não baixa bytes por conta própria e não duplica o download engine: WebView2 continua responsável por rede/segurança/download; CloudOS controla a experiência e o destino.

## 2. Files como namespace Windows + Linux

Files V5 já expõe:

- perfil Windows;
- Desktop, Documents e Downloads;
- CloudOS Drive;
- disco do sistema;
- `\\wsl.localhost\` para arquivos Linux.

Isso significa que o picker do Browser e o app Files compartilham o mesmo namespace de caminhos. Um download pode ser salvo diretamente em uma pasta WSL quando isso for desejado.

Para projetos executados principalmente por ferramentas Linux, prefira arquivos dentro do filesystem Linux da distro; a documentação oficial do WSL recomenda manter arquivos no filesystem do sistema operacional que fará a maior parte do trabalho para melhor desempenho.

## 3. Catálogo unificado de aplicativos

`native_integration_v16.*` é a boundary de integração V16.

### Windows

O CloudOS lê, sem modificar, as chaves padrão de inventário de uninstall em:

- HKCU;
- HKLM 64-bit;
- HKLM 32-bit.

Ele combina esse inventário com:

- Start Menu do usuário;
- Start Menu comum;
- executáveis conhecidos via PATH;
- apps first-party CloudOS.

Assim um programa pode aparecer no gerenciador do CloudOS mesmo quando não foi instalado pelo próprio CloudOS.

### Linux / WSL

Para cada distro retornada por `wsl.exe --list --quiet`, V16 examina:

```text
\\wsl.localhost\<distro>\usr\share\applications\*.desktop
```

Entradas válidas `Type=Application`, não Hidden/NoDisplay, entram no catálogo como `Linux / WSL`.

Launch usa:

```text
wsl.exe -d <distro> -- gtk-launch <desktop-id>
```

Com WSLg habilitado, a aplicação Linux recebe uma janela desktop normal integrada ao DWM/Alt-Tab/taskbar do Windows, que o Window Manager do CloudOS pode observar como qualquer outro top-level HWND.

## 4. Desktop integrado

`NativeDesktopModelV12` agora agrega:

1. Desktop do usuário;
2. Public Desktop do Windows;
3. aplicativos GUI Linux encontrados nas distros WSL.

Windows installers que criam um `.lnk` no Desktop do usuário ou Public Desktop aparecem automaticamente porque o modelo usa change notifications, não polling.

Para Linux, V16 cria apenas um launcher gerenciado em:

```text
%LOCALAPPDATA%\CloudOS\IntegrationV16\LinuxShortcuts
```

Esse `.lnk` aponta para `wsl.exe ... gtk-launch ...`. Ele existe como adaptação de launch/icon para a UI do CloudOS; não altera `/usr/share/applications` e não finge que o app Linux é um executável Windows.

## 5. Start após instalação

O DesktopModel observa de forma event-driven:

- `FOLDERID_Programs` recursivamente;
- `FOLDERID_CommonPrograms` recursivamente.

Quando um instalador Windows adiciona/remove atalhos ali, ele chama `NativeStartIndex::RefreshAsync()`.

Não existe timer de 1 segundo para procurar instalações.

Apps Linux permanecem disponíveis no catálogo unificado e no Desktop. Uma integração direta deles no índice visual do Start pode evoluir depois sem criar uma segunda fonte de verdade: o catálogo V16 deve continuar sendo a fonte de descoberta Linux.

## 6. Instalar pelo CloudOS

A janela **Aplicativos** é o gerenciador unificado.

### Windows

O usuário digita o nome do pacote/aplicativo e escolhe `Instalar no Windows via WinGet`.

V16 executa no Terminal first-party:

```text
winget install --name <nome> --exact --accept-package-agreements --accept-source-agreements
```

O Terminal fica visível. Ele não captura credenciais e não esconde UAC/elevation.

WinGet é preferido porque também consegue inventariar muitos aplicativos instalados por outros meios e fornece install/upgrade/uninstall padronizado.

### Linux

O usuário escolhe `Instalar no Linux via apt / WSL`.

V16 usa a distro padrão configurada no CloudOS, ou a primeira distro válida, e executa no Terminal:

```text
wsl.exe -d <distro> -- sudo apt install <pacote>
```

O nome do pacote é limitado a um token seguro. Senha sudo, quando necessária, é digitada diretamente no Terminal/WSL.

V16 não tenta guardar senha Linux.

### Escopo desta versão

Instalação Linux V16 é orientada a `apt`. Detecção/removal também reconhece Flatpak e Snap quando os `.desktop` publicam IDs apropriados. Busca/instalação first-party em catálogos Flatpak/Snap fica como evolução posterior.

## 7. Remover pelo CloudOS

### Windows

Prioridade:

1. `UninstallString`/`QuietUninstallString` registrado pelo aplicativo;
2. fallback para `winget uninstall --name <nome> --exact`;
3. se nenhum mecanismo existir, o CloudOS informa que não consegue remover com segurança.

Nunca se apaga arbitrariamente a pasta de um programa como substituto de uninstall.

### Linux

V16 resolve o gerenciador do pacote:

- `X-Flatpak` → `flatpak uninstall`;
- `X-SnapInstanceName` → `sudo snap remove`;
- senão tenta mapear o `.desktop` com `dpkg-query -S`, depois usa `sudo apt remove`.

Se o mapeamento não for seguro, CloudOS recusa a remoção automática em vez de adivinhar.

## 8. Integração que V16 deliberadamente NÃO faz

### Default apps / file associations

CloudOS não toma associações do Windows silenciosamente. Windows moderno exige uma experiência orientada pelo usuário para defaults. Quando essa feature entrar, CloudOS deve abrir/encaminhar para a UI suportada de Default Apps ou registrar capacidades e deixar o usuário escolher.

### Winlogon

V16 não altera Winlogon. Ativação do shell continua exclusivamente sob V14.

### Machine-wide mutation

O módulo V16 lê inventário HKLM, mas não escreve HKLM, policies, serviços, tarefas, Run/RunOnce ou associações.

### Instalação silenciosa irrestrita

UAC, prompts do instalador, licença, sudo e políticas de cada package manager continuam visíveis/aplicáveis. CloudOS coordena; ele não tenta contornar o modelo de segurança do Windows/Linux.

## 9. Matriz de integração atual

| Experiência | Windows | Linux/WSL | CloudOS V16 |
|---|---|---|---|
| Navegar arquivos | Win32/Shell | `\\wsl.localhost` | Files V5 |
| Escolher destino de download | pasta Windows | pasta WSL | Folder Picker V16 |
| Download | WebView2 | destino UNC WSL possível | Browser V16 |
| Descobrir apps | Start + uninstall inventory | `.desktop` | Apps V16 |
| Abrir app | Shell/Win32 | WSLg `gtk-launch` | Apps/Desktop |
| Instalar | WinGet | apt | Apps + Terminal |
| Remover | registered uninstall/WinGet | apt/snap/flatpak | Apps + Terminal |
| Desktop shortcut | user/Public Desktop | managed CloudOS launcher | DesktopModel |
| Atualização de Start | change notification | catálogo Linux | event-driven |
| Janelas | HWND/DWM | WSLg HWND/DWM | Window Manager |
| Clipboard | Windows | WSLg | plataforma |

## 10. Próximas integrações possíveis

V16 cria a boundary para próximas etapas, sem precisar espalhar `wsl.exe`, WinGet e registry parsing por várias surfaces.

Prioridades futuras úteis:

1. usar APIs/COM oficiais do Windows Package Manager ou PackageDeploymentManager para operações estruturadas/progresso em vez de depender somente de CLI;
2. gerenciamento MSIX/AppX completo, inclusive repair/update/status;
3. busca e instalação Flatpak/Snap;
4. conversão de caminho Windows↔WSL (`wslpath`) first-party em Files/Terminal;
5. Open With unificado Windows/Linux;
6. drag/drop Windows↔WSL com tratamento explícito de cópia e performance;
7. share/print/open-uri bridges;
8. Settings de Default Apps abrindo a UI suportada do Windows, sem hijack;
9. associação entre processo WSLg e `.desktop` para ícone/nome ainda melhores;
10. install progress/event stream no Apps sem polling global;
11. atualização/upgrade unificada (`winget upgrade`, apt update/upgrade com confirmação);
12. inventory de Store/MSIX com PackageDeploymentManager/PackageManager;
13. integrações de dispositivos, removable media e mount/unmount no Files/System Center.

## 11. Segurança e performance

- nada de rede/filesystem dentro de `WM_PAINT`;
- discovery Linux/Windows fica fora do paint;
- mudanças de Desktop/Start usam filesystem notifications;
- nenhum password store;
- nenhum comando destrutivo sem confirmação;
- package names Linux são validados;
- uninstall Windows usa mecanismo registrado/WinGet, não delete de pasta;
- registry Windows de inventário é read-only;
- V9/V10/V11/V12/V13/V14 continuam invariantes independentes.

## 12. Validação

`test-unified-integration-v16-contract.ps1` protege o grafo e as fronteiras de segurança.

A hosted CI pode provar build/contratos e integração não destrutiva, mas não deve ser descrita como prova de:

- WSLg real abrindo GUI Linux em uma máquina sem distro/WSLg;
- instalação real de pacote Windows/Linux;
- prompt UAC/sudo;
- comportamento de todos os installers de terceiros.

Matriz manual/VM recomendada:

1. baixar arquivo no Browser e salvar em Downloads/Desktop/Documents;
2. salvar diretamente em `\\wsl.localhost\<distro>\home\...`;
3. instalar app WinGet que cria Start shortcut e confirmar atualização do Start;
4. instalar app que cria Public Desktop shortcut e confirmar Desktop CloudOS;
5. instalar GUI Linux via apt e confirmar Apps/Desktop + WSLg launch;
6. remover o app Linux pelo CloudOS e confirmar desaparecimento após notification/refresh;
7. remover Windows app pelo uninstall registrado e por WinGet fallback;
8. testar duas distros WSL;
9. testar sem WinGet e sem WSL: a UI deve degradar com opções desabilitadas, não quebrar o shell.
