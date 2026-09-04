# CloudOS — guia para agentes de IA

Este arquivo é a porta de entrada para qualquer agente que vá analisar ou alterar o repositório. Leia nesta ordem antes de escrever código:

1. `README.md` — visão atual do produto e comandos principais.
2. `docs/native/ARCHITECTURE.md` — processos, autoridades e fronteiras de segurança.
3. `docs/native/CODEMAP.md` — mapa de módulos para arquivos.
4. `docs/native/VALIDATION.md` — qual contrato/smoke prova cada camada.
5. `docs/native/DESKTOP_SYSTEM_ROADMAP.md` — estado dos marcos e próximos gates.
6. `docs/native/UNIFIED_INTEGRATION_V16.md` — boundary Windows+Linux, downloads, package management e WSLg.
7. `docs/native/UNIFIED_START_SEARCH_V17.md` — Start/Search consumindo o catálogo V16 sem criar inventário Linux paralelo.

## Modo de operação com o mantenedor

Estas regras definem como interpretar pedidos curtos do mantenedor. Elas não dispensam segurança, revisão de diff, testes ou os gates técnicos descritos neste arquivo.

- O mantenedor pode estar longe do PC. Quando houver acesso ao GitHub/CI, prefira executar o trabalho remotamente de ponta a ponta em vez de apenas explicar como ele faria no computador local.
- Em uma tarefa já contextualizada, mensagens como **“cria aí”**, **“faz”**, **“continua”**, **“pode fazer”**, **“ok”** ou equivalentes significam: prossiga e execute o máximo possível da tarefa completa, sem pedir confirmação repetitiva para cada etapa rotineira.
- Se o mantenedor enviar um bloco grande de código, log, relatório ou instruções durante uma tarefa, trate o bloco como material de trabalho e aja sobre ele. Não responda apenas com um resumo quando houver uma ação clara a executar.
- Não repita perguntas cuja resposta já esteja no histórico, no repositório ou nos resultados das ferramentas. Resolva ambiguidades pequenas pelo contexto e siga em frente.
- Para mudanças no repositório, prefira o fluxo completo: inspecionar estado atual → criar branch quando necessário → implementar → revisar diff → executar/observar testes e CI → corrigir falhas → abrir/atualizar PR → mergear somente quando os gates obrigatórios estiverem verdes. Não pare em “código pronto” se ainda houver validação acessível.
- **“manda pra minha IA testar aqui”** significa: produza instruções completas para a IA local do mantenedor executar testes reais na máquina dele. O pacote de instruções deve dizer o que executar, em qual diretório, quais resultados coletar, como relatar falhas e, quando apropriado, corrigir e repetir os testes. Considere esses testes locais como validação física complementar ao CI hospedado.
- **“manda pra eu testar”**, **“quero testar”** ou equivalente significa: mude para modo guiado para o próprio mantenedor. Forneça comandos de PowerShell passo a passo, explique brevemente o objetivo e o resultado esperado de cada comando e use a saída retornada para decidir o próximo passo. Não despeje uma sequência enorme sem necessidade quando o diagnóstico depende do resultado intermediário.
- Quando o mantenedor disser apenas **“ok”** depois de um plano/diagnóstico que já contém uma ação pendente clara, interprete como autorização para continuar a execução daquela ação, não como pedido de mero acknowledgement.
- Se uma operação real não puder ser executada com as ferramentas disponíveis, faça o máximo verificável possível e deixe explícito exatamente o que resta. Não invente execução local, teste físico ou resultado de CI que não ocorreu.

## Fonte de verdade atual

O desktop atual do CloudOS é o **CloudOS Native Shell C++/Win32**.

Autoridades:

- Shell/UI: `desktop/CloudOS.NativeShell` → `CloudOS.exe`.
- Entrada/orquestração do shell: `desktop/CloudOS.NativeShell/src/main_shell_v2.cpp`.
- Runtime nativo: `desktop/CloudOS.NativeRuntime` → `CloudOS.NativeRuntime.dll`.
- Recovery/supervisão externa: `desktop/CloudOS.NativeRecovery` → `CloudOS.Supervisor.exe`.
- Protocolo compartilhado: `desktop/CloudOS.NativeCommon`.
- Deploy versionado/rollback: `scripts/native/CloudOS.Deployment.V13.psm1`.
- Ativação opt-in do shell/rollback exato: `scripts/native/CloudOS.ShellActivation.V14.psm1`.
- Integração Windows+Linux/WSL: `desktop/CloudOS.NativeShell/src/native_integration_v16.*`.
- Adaptador compartilhado de launch Linux para Shell/Start/Desktop: `desktop/CloudOS.NativeShell/src/native_integration_v16_launchers.h`.
- Picker first-party de pastas: `desktop/CloudOS.NativeShell/src/native_folder_picker_v16.*`.
- Índice Start/Search Windows+Linux V17: `desktop/CloudOS.NativeShell/src/native_start_index.*`.
- Build oficial: `scripts/native/build-cloudos-native.cmd`.
- Suite de contratos: `scripts/native/test-native-contract-suite.ps1`.
- CI Full-System: `.github/workflows/cloudos-native-full-system.yml`.

`frontend/`, `backend/`, `desktop/CloudOS.Host` e componentes WPF/WebView2 continuam no repositório por compatibilidade, testes e referência histórica/visual. **Eles não são a autoridade do desktop nativo atual.** WebView2 permanece permitido no Navegador CloudOS, não como desktop principal.

## Fluxo de processo

```text
launcher normal
    └─ CloudOS.Supervisor.exe
         └─ CloudOS.exe --supervised
              └─ CloudOS.NativeRuntime.dll

V13 instalado
    └─ versão ativa em versions/<id>/

V14 ativado explicitamente
    └─ HKCU Winlogon Shell
         └─ shell-v14/CloudOS.ShellEntry.V14.cmd
              └─ resolve a versão V13 ativa
                   └─ CloudOS.Supervisor.exe
                        └─ CloudOS.exe --supervised

V16 integração
    ├─ Browser DownloadStarting -> CloudOS Folder Picker -> Windows/WSL path
    ├─ Apps -> Windows inventory/WinGet + Linux .desktop/apt/snap/flatpak
    ├─ Desktop -> user/Public Desktop + launchers Linux gerenciados
    └─ Files -> Windows + CloudOS Drive + \\wsl.localhost

V17 Start/Search
    └─ NativeStartIndex
         ├─ Start Menu / AppsFolder / Windows Search
         └─ NativeIntegrationV16::EnumerateLinuxGuiApps()
              └─ native_integration_v16_launchers.h -> .lnk gerenciado -> WSLg
```

O V14 **não é ativado automaticamente** por instalação/update. Testes hospedados usam apenas subchave HKCU sandbox; logon real exige VM/piloto.

## Invariantes que não devem ser quebrados

- `main` não é branch de trabalho para marcos experimentais/validação.
- Não criar uma segunda autoridade de recovery concorrendo com `CloudOS.Supervisor.exe`.
- Em modo `--supervised`, o watchdog embutido não deve competir com o Supervisor V11.
- Health V9 mantém ABI fixa de 96 bytes e os nomes compartilhados protegidos pelos contratos.
- Desktop autoritativo: `CloudOS.NativeShell.Desktop.v2`.
- Taskbar autoritativa: `CloudOS.NativeShell.Taskbar.v4`.
- Start autoritativo: `CloudOS.NativeShell.Start.v4`.
- Quick Settings autoritativo: `CloudOS.NativeShell.QuickSettings.v4`.
- Notification Center autoritativo: `CloudOS.NativeShell.NotificationCenter.v2`.
- V13 publica uma versão somente depois de manifesto/SHA256 e Supervisor self-test.
- V14 deve preservar exatamente o valor `Shell` anterior, inclusive ausência e tipo, e deve recusar drift externo por padrão.
- Não escrever HKLM, `Userinit`, `Run`, `RunOnce`, políticas, serviço ou tarefa agendada como atalho para ativação V14.
- V16 pode **ler** inventário HKLM do Windows, mas não deve usá-lo para escrita de configuração/package state.
- Não espalhar chamadas ad-hoc de WinGet/`wsl.exe`/parsing de uninstall registry por surfaces; estender `native_integration_v16.*` quando a responsabilidade for integração Windows+Linux.
- V17 não cria outro catálogo Linux no Start/Search. `NativeStartIndex` consome `NativeIntegrationV16` e usa `native_integration_v16_launchers.h` para o alvo Shell compartilhado.
- Não construir `wsl.exe -d ... gtk-launch` diretamente em `native_start_index.*` ou no Desktop; essa adaptação pertence à boundary V16.
- Não sequestrar default apps/file associations. Defaults modernos do Windows devem permanecer escolha explícita do usuário.
- Não armazenar senha sudo/Linux nem tentar ocultar/contornar UAC.
- Não remover software apagando pasta arbitrariamente; use mecanismo registrado, package manager ou recuse com segurança.
- Não remover rollback/recovery em uma alteração de UX.
- Não recolocar React/WebView2 como desktop principal.
- Não fazer I/O pesado, enumeração de filesystem ou carregamento de ícones dentro de `WM_PAINT`.
- Não transformar timers de 1 segundo em game loop global do shell.

## Onde editar por assunto

| Assunto | Comece aqui |
|---|---|
| boot, ciclo principal, superfícies | `desktop/CloudOS.NativeShell/src/main_shell_v2.cpp` |
| Desktop | `native_desktop_window_v2.*`, `native_desktop_model_v12.h`, `native_desktop_surface.*` |
| Taskbar | `native_taskbar_appbar_v4.*`, `native_taskbar_hover_preview.*` |
| Start/Search | `native_start_menu_window.*`, `native_start_index.*`, `native_search_engine.*`; Linux deve vir de `native_integration_v16.*`/`native_integration_v16_launchers.h` |
| Quick Settings/System Center | `native_quick_settings_window_v4.*`, `native_control_plane_service.*`, `native_system_control_*` |
| janelas/workspaces | `native_window_manager*`, `native_workspace_*` |
| Files | `native_files_*`, `native_file_*` |
| Browser/downloads | `native_browser_window.*`, `native_folder_picker_v16.*` |
| Apps Windows+Linux/install/remove | `native_apps_window.*`, `native_integration_v16.*` |
| launch adapter Linux compartilhado | `native_integration_v16_launchers.h` |
| WSL runtime baixo nível | `desktop/CloudOS.NativeRuntime`, `cloudos_native_wsl.*` |
| lifecycle/session | `native_lifecycle_v10.h`, `native_session_*` |
| health/readiness | `native_health_bootstrap_v9.h`, `native_health_v9.h` |
| supervisor/recovery | `desktop/CloudOS.NativeRecovery/main.cpp` |
| deploy/update/rollback | `CloudOS.Deployment.V13.psm1` |
| ativação Explorer/CloudOS | `CloudOS.ShellActivation.V14.psm1` |
| Flutter Shell & Native Bridge V20 | `desktop/CloudOS.FlutterShell/`, `desktop/CloudOS.FlutterShell/native_bridge/` |
| System Broker & Event Bus V21 | `desktop/CloudOS.SystemBroker/`, `desktop/CloudOS.BrokerProbe/`, `desktop/CloudOS.FlutterShell/native_bridge/cloudos_broker_client_v21.*` |
| release/package | `write-native-build-manifest.ps1`, `verify-native-build-manifest.ps1`, `package-cloudos-native.ps1` |

Veja o mapa completo em `docs/native/CODEMAP.md`.

## Regra para código novo

Antes de criar `native_<feature>_vN.*`, procure implementação equivalente. Um sufixo de versão deve representar contrato/ABI/comportamento deliberadamente versionado, não ser usado para evitar entender o arquivo existente.

Prefira:

- função pequena com responsabilidade explícita;
- estado pertencendo ao módulo que o produz;
- UI thread apenas para UI;
- worker para filesystem/Shell/WMI/rede/COM demorado;
- cache explícito em vez de consulta dentro de paint;
- mensagens/eventos em vez de polling global;
- comentários explicando **por que** uma regra existe, não traduzindo a linha seguinte.

Não faça reorganização física em massa sem necessidade. Mover dezenas de `.cpp` somente para “ficar bonito” aumenta churn de include, projeto e histórico. Use o mapa lógico e, quando uma fronteira estiver estável, mova um subsistema por vez com contrato verde.

## Scripts legados

`scripts/native/configure-cloudos-shell-launcher.ps1` é um caminho **legado/administrativo** baseado no recurso Windows Shell Launcher (`WESL_UserSetting`). Ele não é o mecanismo V14 e não deve ser chamado pelo fluxo normal de instalar/atualizar/ativar CloudOS.

Quando encontrar documentação antiga dizendo que React/WPF é o desktop atual ou que substituição do Explorer “ainda não existe”, trate como histórico e confirme contra `docs/native/` e os contratos atuais.

## Validação obrigatória

Para qualquer alteração nativa relevante:

```powershell
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1
scripts\native\build-cloudos-native.cmd Release
```

Depois rode/observe o Full-System CI. Mudanças em estabilidade, lifecycle, supervisor, performance, deploy ou ativação devem manter os smokes V9–V14 verdes. Integração V16 deve manter `test-unified-integration-v16-contract.ps1` verde; Start/Search V17 deve manter `test-unified-start-search-v17-contract.ps1` e seu smoke não mutável verdes.

Não declare teste físico que não ocorreu. Hosted CI não prova suspend físico, transporte RDP, hotplug real, logoff/login real, reboot, boot recovery, instalação real de terceiros ou WSLg real sem uma distro/ambiente apropriado.

## Padrão de branch de validação

Para um marco novo:

```text
base verde exata
├─ work/<marco>
└─ validation/<marco>-base

PR draft: work/<marco> -> validation/<marco>-base
```

Corrija o `work/*` até CI verde. Não faça merge na `main` como efeito colateral da validação.
