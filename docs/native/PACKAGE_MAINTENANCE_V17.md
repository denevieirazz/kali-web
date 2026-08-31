# Package Maintenance V17

## Objetivo

V17 completa o lifecycle básico iniciado pela integração V16: o app **Aplicativos** passa a oferecer atualização explícita de software instalado, além de abrir, instalar, remover e recarregar o catálogo.

A autoridade continua dividida de forma deliberada:

- descoberta/instalação/remoção Windows+Linux: `native_integration_v16.*`;
- construção segura de comandos de **upgrade**: `native_package_maintenance_v17.h`;
- consentimento e UX: `native_apps_window.*`;
- execução visível: Terminal first-party/ConPTY.

V17 não cria daemon de package management, não roda update em background e não cria uma segunda fonte de inventário.

## Windows — WinGet

Ao selecionar um aplicativo Windows reconhecido pelo inventário instalado, **Atualizar app** prepara:

```text
winget upgrade --name <nome-exato> --exact --accept-package-agreements --accept-source-agreements
```

O comando só é aberto depois de confirmação `MB_YESNO`. A execução ocorre no Terminal do CloudOS. UAC, prompts do instalador e políticas do WinGet continuam visíveis e válidos.

V17 deliberadamente não usa `winget upgrade --all`: manutenção em massa exige uma experiência separada com revisão clara do conjunto de alterações.

## Linux / WSL

A seleção Linux usa o package manager já conhecido pela V16 quando o `.desktop` publica identidade suficiente:

- Flatpak → `flatpak update <app-id>`;
- Snap → `sudo snap refresh <package>`;
- apt conhecido → `sudo apt install --only-upgrade -- <package>`.

Quando um `.desktop` apt não publica package id, V17 **não adivinha pelo nome visível**. O comando executado no WSL resolve o dono de `/usr/share/applications/<desktop-id>.desktop` com `dpkg-query -S`; somente depois executa `apt --only-upgrade` sobre o pacote resolvido.

`desktop-id`, package ids e managers passam por allowlist/token validation antes de entrar no comando. Managers fora de `apt`, `snap` e `flatpak` são recusados.

## Experiência no app Aplicativos

A barra superior fica com cinco ações:

1. **Abrir**;
2. **Instalar...**;
3. **Atualizar app**;
4. **Remover**;
5. **Recarregar**.

`Recarregar` continua significando apenas reconstruir o catálogo. Isso evita a ambiguidade antiga do botão `Atualizar`, que era refresh e não software update.

O botão **Atualizar app** só fica habilitado para:

- entrada `InstalledWindows` com WinGet disponível;
- entrada `LinuxGui` com WSL disponível e identidade de manutenção segura.

Apps first-party CloudOS e executáveis encontrados apenas no `PATH` não são enviados cegamente ao WinGet.

## Segurança

V17 preserva as fronteiras V13–V16:

- nenhuma escrita nova em HKLM;
- nenhuma alteração de Winlogon;
- nenhuma default-app/file-association mutation;
- nenhuma senha sudo armazenada;
- nenhum bypass de UAC;
- nenhum update automático no carregamento do catálogo;
- nenhum `upgrade --all`, `apt upgrade`, `dist-upgrade`, `full-upgrade` ou `autoremove`;
- package managers desconhecidos são recusados;
- atualização é sempre iniciada por clique e confirmada pelo usuário;
- Terminal permanece visível durante WinGet/apt/Snap/Flatpak.

## Hosted CI

`test-package-maintenance-v17-contract.ps1` protege a estrutura e as fronteiras de segurança.

`run-native-package-maintenance-smoke-v17.ps1` é propositalmente **não mutante**. Hosted CI verifica:

- binário nativo compilado presente;
- builder de WinGet upgrade;
- builders apt/Snap/Flatpak;
- resolução apt via `dpkg-query -S`;
- ação explícita na UI;
- disponibilidade observada de WinGet/WSL;
- Winlogon real do runner idêntico antes/depois.

Hosted CI **não atualiza pacotes reais**. Ela também não aprova UAC/sudo nem afirma que um upgrade WSL foi executado quando o runner não possui distro apropriada.

## Matriz manual/VM recomendada

1. selecionar um app Windows que tenha update disponível no WinGet e confirmar o fluxo;
2. selecionar um app Windows sem correspondência no WinGet e confirmar falha visível/segura;
3. atualizar um app apt cujo `.desktop` precise de resolução por `dpkg-query -S`;
4. atualizar um Snap;
5. atualizar um Flatpak;
6. cancelar cada confirmação e verificar que nenhum comando é executado;
7. testar sem WinGet;
8. testar sem WSL;
9. testar package id inválido/manipulado e confirmar recusa;
10. confirmar que Winlogon, V13 deployment e V14 rollback não mudam.

## Próximos passos

V17 não tenta resolver todos os aspectos de software distribution. Evoluções coerentes incluem inventário estruturado de updates disponíveis, progresso/eventos first-party sem parsing frágil de terminal, MSIX/AppX/PackageDeploymentManager e políticas de update por workspace/dispositivo. Essas features devem continuar respeitando consentimento explícito e rollback/recovery existentes.
