# Unified Start/Search V17

## Objetivo

V17 fecha a lacuna entre o catálogo Windows+Linux entregue pela V16 e o Start/Search nativo. O Start não ganha um segundo inventário Linux: `NativeIntegrationV16` continua sendo a autoridade de descoberta e launch para WSL/WSLg, e `NativeStartIndex` passa apenas a consumir essa fonte junto com Menu Iniciar, AppsFolder e Windows Search.

Fluxo principal:

```text
NativeIntegrationV16::EnumerateLinuxGuiApps()
        |
        v
NativeIntegrationV16::EnsureLinuxLauncherShortcut()
        |
        v
NativeStartIndex::BuildIndex()
        |
        +--> Todos os aplicativos
        +--> pesquisa do Start
        +--> pins Start/taskbar via alvo .lnk gerenciado
```

## 1. Uma única fonte Linux

A descoberta permanece em `native_integration_v16.*`:

- `wsl.exe --list --quiet` identifica distros;
- `\\wsl.localhost\<distro>\usr\share\applications\*.desktop` fornece apps GUI;
- parsing de `.desktop`, distro, desktop id e metadados continua centralizado na V16;
- launch real continua sendo WSLg por `gtk-launch`.

`native_start_index.cpp` não executa `wsl.exe`, não parseia `.desktop` e não monta `gtk-launch`. Ele recebe `UnifiedAppV16` e converte apps launchable em entradas do índice.

## 2. Launcher gerenciado compartilhado

Desktop e Start precisam de um alvo Windows que ShellExecute, cache de ícone e pin store entendam. V17 centraliza essa adaptação em `native_integration_v16_launchers.h`.

O launcher fica em:

```text
%LOCALAPPDATA%\CloudOS\IntegrationV16\LinuxShortcuts\<distro>__<desktop-id>.lnk
```

O `.lnk` aponta para:

```text
wsl.exe -d <distro> -- gtk-launch <desktop-id>
```

A criação usa `IShellLinkW` + `IPersistFile`, nome seguro e mutex compartilhado para impedir duas gravações simultâneas quando Desktop e Start reindexam ao mesmo tempo. O `.lnk` é um adaptador gerenciado; não transforma o binário Linux em executável Windows e não modifica `/usr/share/applications`.

## 3. Start/Search unificado

`NativeStartIndexKind` agora possui `LinuxApp`.

Durante `BuildIndex()` o worker agrega:

1. Start Menu do usuário;
2. Start Menu comum;
3. `shell:AppsFolder`;
4. aplicativos Linux fornecidos por `NativeIntegrationV16`.

Linux recebe prioridade de aplicativo no mesmo ranking de `PackagedApp`. A entrada usa título visual com sufixo `· Linux` e subtítulo `WSL · <distro>` para distinguir nomes iguais existentes nos dois sistemas sem criar uma segunda identidade de pacote.

O caminho de launch no Start permanece o mesmo: `NativeStartIndex::Launch()` usa ShellExecute no alvo. Para Linux, esse alvo é o `.lnk` gerenciado da V16.

## 4. Pins

A pin store existente já aceita alvos Shell do Windows. Como Linux possui um `.lnk` estável, V17 reutiliza o mesmo contrato em vez de criar `LinuxPin`, outro formato persistente ou outro launcher.

Consequências:

- um resultado Linux pode ser fixado no Start;
- pode ser fixado na taskbar conforme a boundary atual de pins;
- a identidade persistida é o launcher gerenciado estável;
- Desktop e Start apontam para o mesmo arquivo.

## 5. Atualização event-driven

`NativeDesktopModelV12` já é o worker residente que observa namespaces de atalhos. V17 amplia a semântica de cada watch com dois efeitos independentes:

- `reload_desktop`;
- `refresh_start_index`.

Para distros existentes no momento em que o worker inicia, mudanças em `usr/share/applications` disparam ambos. Assim instalar/remover um `.desktop` numa distro já observada atualiza Desktop e Start sem timer global e sem polling de 1 segundo.

Start Menu Windows continua atualizando apenas o índice; Desktop usuário/Public Desktop continuam atualizando o Desktop.

### Nova distro durante a sessão

A lista de diretórios WSL observados é construída quando o worker inicia. Se uma distro completamente nova for adicionada depois disso, F5/reindex ou reinício do shell pode ser necessário para descoberta inicial; após o diretório estar observado, mudanças nele são event-driven. V17 não adiciona polling global para esconder essa limitação.

## 6. Segurança

V17 não amplia privilégios da V16:

- não instala nem remove pacotes automaticamente;
- não escreve HKLM;
- não altera default apps/file associations;
- não altera Winlogon;
- não armazena senha sudo;
- não contorna UAC;
- não cria watchdog/recovery paralelo;
- não coloca filesystem/WSL discovery dentro de `WM_PAINT`.

O índice é construído em worker e a UI do Start só consulta estado preparado.

## 7. Hosted CI

O contrato é `scripts/native/test-unified-start-search-v17-contract.ps1`.

O smoke não destrutivo é `scripts/native/run-native-unified-start-search-smoke-v17.ps1`.

A hosted CI prova:

- estrutura compilada/consumo do catálogo V16;
- launcher gerenciado compartilhado entre Desktop e Start;
- refresh Linux event-driven;
- ausência de comando WSL direto no Start index;
- `CloudOS.Supervisor.exe --self-test` continua saudável;
- HKCU Winlogon de produção permanece idêntico antes/depois;
- nenhuma operação mutável de package management foi executada.

A hosted CI não deve ser descrita como prova de WSLg real quando o runner não possui uma distro GUI configurada. Ela também não instala pacote, não digita sudo/UAC e não faz logoff/reboot.

## 8. Matriz VM/manual

Para validar integração Linux real:

1. iniciar CloudOS com uma distro WSLg configurada;
2. instalar um aplicativo GUI via apt e confirmar que o `.desktop` aparece;
3. confirmar atualização automática do Desktop e do Start sem F5 na distro já observada;
4. pesquisar o app pelo nome e pelo texto `Linux`/distro;
5. abrir pelo resultado e confirmar janela WSLg real;
6. fixar/desafixar no Start e confirmar persistência após reiniciar CloudOS;
7. remover o pacote e confirmar desaparecimento após notification/reindex;
8. testar apps Windows e Linux com o mesmo nome;
9. adicionar uma distro nova durante a sessão e registrar a limitação de descoberta inicial;
10. repetir sem WSL para garantir degradação segura.

Sem essa evidência física/VM, o milestone deve ser descrito como integração automatizada estrutural/hosted, não como teste WSLg completo.
