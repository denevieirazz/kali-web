# CloudOS Workspace Studio V2

## Objetivo

O Workspace Studio V2 transforma as quatro áreas já gerenciadas pelo `CloudOSNativeWindowManager` em ambientes configuráveis e automatizáveis. O recurso continua operando sobre janelas Win32 top-level normais; ele não cria um segundo compositor, não usa `SetParent` entre processos e não depende de desktops virtuais privados do Explorer.

A arquitetura foi desenhada para manter o Windows/DWM como autoridade de composição e o CloudOS como autoridade do modelo de workspace.

## Componentes

A implementação é dividida em cinco camadas:

1. `native_workspace_studio_model.h/.cpp`: modelo e persistência versionada;
2. `native_workspace_automation.h/.cpp`: regras, layouts, snapshots, transições e histórico de foco;
3. `native_workspace_studio_service.h/.cpp`: serviço residente com `HWND_MESSAGE`, timer e hotkeys;
4. `native_workspace_studio_window.h/.cpp`: interface Win32/WebSkin de cinco páginas;
5. `native_window_manager_workspace_studio.cpp`: integração mínima com o Window Manager.

O projeto MSVC compila todos esses módulos no mesmo `CloudOS.exe`.

## Perfis por workspace

Cada uma das quatro áreas possui um `WorkspaceProfile` persistente com:

- nome personalizado;
- wallpaper próprio;
- preset de layout;
- aplicação automática de layout ao entrar;
- inicialização automática de aplicativos ao entrar;
- aplicação automática de wallpaper ao entrar.

Os nomes padrão continuam sendo `Área 1`, `Área 2`, `Área 3` e `Área 4`.

O perfil é configuração do shell, não uma alteração do desktop virtual do Windows.

## Layouts disponíveis

### Livre

Não força organização das janelas e desliga o tiling automático do manager para a área atual.

### Mestre + pilha

Reutiliza o tiling autoritativo do `CloudOSNativeWindowManager`: uma janela mestre ocupa aproximadamente metade da área e as demais formam a pilha.

### Colunas

Distribui todas as janelas gerenciadas da área atual em colunas iguais.

### Grade

Calcula linhas e colunas de acordo com a quantidade de janelas e usa toda a `rcWork` disponível.

### Foco

Mantém a primeira janela em destaque, centralizada com margem, e minimiza as demais.

Presets só posicionam janelas da área atualmente visível. Essa regra evita que uma ação de layout revele por acidente uma janela escondida por outro workspace.

## Snapshots de layout

Um snapshot registra, para cada janela da área:

- processo;
- classe Win32;
- trecho do título;
- dispositivo/monitor;
- posição normalizada;
- estado flutuante;
- comando de exibição (normal, maximizado ou minimizado).

A geometria é normalizada numa escala de 0 a 10000 em relação à `rcWork` do monitor. Assim, um snapshot pode ser restaurado depois de mudança de resolução e é adaptado à área útil do monitor atual.

Na restauração, o CloudOS tenta casar as janelas existentes por processo + classe + dica de título. O V2 não relança automaticamente aplicativos ausentes só porque estavam presentes no snapshot; ele restaura janelas que existem no momento da operação. A inicialização de aplicativos é tratada separadamente pelos presets de Inicialização.

## Regras automáticas de janela

Uma `WorkspaceRule` pode observar um destes campos:

- nome do processo;
- título da janela;
- classe Win32.

Há quatro modos de correspondência:

- contém;
- exato;
- prefixo;
- wildcard com `*` e `?`.

Uma regra pode:

- enviar a janela para Área 1..4;
- deixar a janela flutuante ou gerenciada;
- maximizar quando o destino é a área atual.

O motor usa o primeiro match habilitado. Cada HWND é processado apenas uma vez durante o fluxo normal para evitar reposicionamento contínuo. O comando **Reaplicar em todas as janelas** limpa esse cache e reavalia o conjunto inteiro.

Nenhuma regra injeta código no processo de destino. O CloudOS consulta metadados com APIs Win32 e opera sobre o HWND existente.

## Inicialização por workspace

A página Inicialização aceita dois tipos de entrada:

- ID de aplicativo CloudOS, executado por `NativeAppLauncher::LaunchById`;
- programa Windows, executado como processo top-level normal via Shell API.

As entradas possuem área de destino, argumentos e estado habilitado.

Quando `auto_launch` está habilitado no perfil, o conjunto daquele workspace é disparado na primeira entrada na área durante a sessão atual. Voltar para a mesma área não relança tudo de novo. O botão **Executar área agora** continua disponível para execução manual.

O campo `delay_ms` existe no formato persistente para evolução posterior, mas o V2 atual executa as entradas habilitadas imediatamente. Ele não deve ser apresentado ao usuário como agendamento implementado.

## Histórico de foco

O serviço mantém até 64 janelas recentemente focadas durante a sessão.

Cada registro contém:

- HWND;
- PID;
- processo;
- título;
- workspace;
- horário do último foco.

A página Atividade permite selecionar um registro e voltar diretamente à janela. Se ela estiver em outra área, o manager troca de workspace antes de focá-la.

O histórico de foco é propositalmente volátil no V2; ele não é persistido entre reinicializações do CloudOS.

## Serviço residente

`NativeWorkspaceStudioService` é um singleton de processo. Quando o `CloudOSNativeWindowManager` é construído, ele registra sua instância no serviço.

O serviço cria uma janela message-only:

`CloudOS.NativeShell.WorkspaceStudioEngine.v2`

Ela não aparece na Taskbar, não é uma superfície visual e existe para:

- receber timer;
- receber hotkeys;
- executar o loop de automação;
- manter o Studio independente de a janela visual estar aberta ou fechada.

O intervalo atual é 850 ms. Em cada tick o motor:

1. reconcilia o Window Manager;
2. aplica regras a HWNDs ainda não processados;
3. atualiza histórico de foco;
4. detecta mudança de workspace;
5. aplica perfil quando necessário;
6. remove HWNDs mortos do cache.

## Hotkeys globais

| Atalho | Ação |
| --- | --- |
| `Ctrl+Alt+G` | abrir Workspace Studio |
| `Ctrl+Alt+Shift+S` | salvar snapshot rápido da área atual |
| `Ctrl+Alt+Shift+R` | restaurar snapshot mais recente da área atual |
| `Ctrl+Alt+Shift+A` | reaplicar todas as regras |

O registro é feito com `RegisterHotKey` e `MOD_NOREPEAT`. Caso outro programa reserve uma combinação, o Windows pode recusar aquele registro; as demais funções continuam acessíveis pela interface.

## Interface do Workspace Studio

A superfície é uma janela Win32/WebSkin `CloudOS.NativeShell.WorkspaceStudio.v2` com cinco páginas.

### Perfis

Configura nome, wallpaper, layout e automações de entrada da área selecionada.

### Regras

Mostra todas as regras, permite adicionar, ativar/desativar, excluir e reaplicar.

### Layouts

Mostra snapshots persistidos, captura estado atual, restaura/exclui snapshots e aplica presets instantâneos.

### Inicialização

Gerencia aplicativos CloudOS e programas Windows associados às áreas.

### Atividade

Exibe histórico recente de foco e permite retornar diretamente a uma janela ainda existente.

A janela usa controles Win32, ListView, TabControl, Common Dialog e os tokens WebSkin já usados pelo restante do shell. Não usa HTML, React ou WebView2.

## Persistência

O arquivo autoritativo é:

`%LOCALAPPDATA%\CloudOS\workspace_studio_v2.dat`

Formato:

- magic `CLDWST2`;
- versão `2`;
- strings UTF-16 com comprimento;
- limites explícitos para strings e coleções;
- quatro perfis;
- regras;
- entradas de inicialização;
- snapshots;
- contadores de identidade.

A gravação usa arquivo temporário e `MoveFileExW` com `MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`.

Antes da substituição, o arquivo anterior é copiado para `.bak`. Se o arquivo principal não puder ser lido, o Store tenta recuperar o backup.

## Relação com o Window Manager

O V2 adiciona duas APIs explícitas:

- `SetTilingEnabled(bool)`;
- `MoveWindowToWorkspace(HWND, int)`.

A segunda opera sobre uma janela arbitrária já gerenciada, diferente de `MoveActiveToWorkspace`, que depende da janela ativa.

Ao mover uma janela para outra área, o manager marca `CloudOS.Native.WorkspaceHidden.v1` e usa `SW_HIDE`, inclusive quando a janela estava minimizada. Isso preserva o isolamento dos workspaces.

## Multi-monitor

Snapshots guardam o nome do dispositivo do monitor. Na restauração:

1. o CloudOS procura o mesmo monitor pelo `NativeMonitorManager`;
2. se ele existir, usa sua `work` atual;
3. se ele não existir, usa o monitor da janela como fallback;
4. a geometria normalizada é convertida para pixels na área útil atual.

Isso evita persistir coordenadas absolutas frágeis.

## Limites deliberados do V2

O Workspace Studio V2 não promete:

- reabrir automaticamente aplicações ausentes de um snapshot;
- persistir histórico de foco;
- armazenar senhas ou credenciais;
- controlar desktops virtuais privados do Explorer;
- reparentar aplicativos externos;
- garantir registro de hotkey se outro software já registrou a combinação;
- aplicar múltiplas regras em cadeia à mesma janela: o primeiro match vence;
- respeitar `delay_ms` como agenda; o campo está reservado no modelo e ainda não é executado como atraso.

Esses limites são intencionais para manter o V2 previsível e reversível.

## Contrato de regressão

`scripts/native/test-workspace-studio-contract.ps1` protege:

- modelo persistente;
- backup/gravação atômica;
- regras por processo/título/classe;
- wildcard;
- snapshots normalizados e monitor-aware;
- presets;
- serviço residente;
- hotkeys;
- cinco páginas nativas;
- APIs novas do Window Manager;
- presença de todos os módulos no grafo MSVC;
- ausência de WebView2/HTML/React/SetParent na superfície.

O contrato entra no `build-cloudos-native.cmd` antes da compilação MSVC.
