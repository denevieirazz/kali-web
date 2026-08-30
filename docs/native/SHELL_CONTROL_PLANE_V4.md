# CloudOS Shell Control Plane V4

## Objetivo

O Shell Control Plane V4 une três linhas que antes eram validadas separadamente:

1. **System Center V1** — WLAN, Core Audio, brilho DDC/CI + WMI, energia, rede, discos, processos e serviços.
2. **Workspace Studio V2** — perfis, regras, layouts, inicialização e histórico de foco.
3. **Session Continuity V3** — ledger transacional, checkpoints por workspace, journal e recovery conservador.

O V4 adiciona uma camada de interação diária por cima dessa base: **Quick Settings operacional, tray first-party, live toasts, health service e appearance persistente**.

## Invariantes de arquitetura

- O shell continua C++/Win32 nativo.
- WebView2 continua restrito ao Navegador CloudOS.
- O frontend React antigo é apenas referência de design.
- Aplicações externas continuam HWNDs top-level controlados pelo Windows/DWM.
- Nenhum módulo do Control Plane usa `SetParent`, `WriteProcessMemory` ou `CreateRemoteThread`.
- A tray V4 é **first-party CloudOS**. Ela não finge capturar `Shell_NotifyIcon` de Discord/Steam/OneDrive enquanto Explorer for o host da Notification Area do Windows.
- Wi-Fi só conecta diretamente uma rede que já possui perfil salvo no Windows. Quando a rede exige credencial nova, o CloudOS abre o fluxo oficial `ms-settings:network-wifi`.
- Bluetooth ainda usa o fluxo oficial do Windows para descoberta/pareamento; o V4 não armazena chaves nem credenciais.
- Brilho tenta o hardware real: DDC/CI para monitores compatíveis e WMI para painéis integrados. Se nenhum backend existe, o slider fica desabilitado e a UI informa o motivo.
- Recovery não relança arbitrariamente processos externos e não repete operações de arquivos.

## 1. Merge-base real

`work/shell-control-plane-v4` contém um merge commit de dois pais:

- Session Continuity V3 / Workspace Studio V2
- System Center V1

A integração não substitui o launcher validado do ramo Continuity por uma cópia antiga. O System Center é compilado como subsistema e exposto diretamente por Quick Settings e pela tray.

## 2. NativeSystemControlBackend

Backend compartilhado entre System Center, Quick Settings e Control Plane.

### Wi-Fi

- WLAN API oficial.
- Enumeração de interfaces.
- Scan de SSIDs.
- Intensidade de sinal.
- Segurança.
- Perfil salvo.
- Rede conectada.
- Conectar perfil conhecido.
- Desconectar interface.
- Fallback oficial para senha nova.

### Áudio

- Endpoint padrão via MMDevice/Core Audio.
- Nome do endpoint.
- Volume master 0–100.
- Mute/unmute.

### Tela

- DDC/CI para monitor físico.
- WMI `WmiMonitorBrightness` como fallback.
- Fonte do controle informada à UI.

### Energia

- Estado AC/bateria.
- Percentual e autonomia quando expostos pelo Windows.
- Plano ativo.
- Equilibrado.
- Economia.
- Alto desempenho.

### Sistema

- Adaptadores/IP Helper.
- IPv4/IPv6/MAC/link.
- Volumes e espaço livre.
- Processos e memória.
- Serviços essenciais.

## 3. Quick Settings V4

Classe: `CloudOS.NativeShell.QuickSettings.v4`.

A janela continua um popup nativo ancorado à AppBar, mas agora usa o mesmo backend da Central do Sistema.

### Controles

- volume master;
- mute;
- endpoint atual;
- lista de SSIDs;
- sinal de cada SSID;
- conectar rede com perfil conhecido;
- desconectar rede conectada;
- botão de pareamento Bluetooth oficial;
- brilho real;
- fonte do brilho (DDC/CI ou WMI);
- bateria/AC;
- plano atual;
- aplicar Equilibrado;
- aplicar Economia;
- aplicar Alto desempenho;
- abrir Central do Sistema;
- alternar preset de accent do Control Plane.

O popup faz refresh periódico e publica resultado das operações no histórico de notificações e no toast overlay.

## 4. CloudOS first-party tray

A tray não tenta substituir a Notification Area do Explorer.

Ela usa `SetWindowSubclass` nos HWNDs `CloudOS.NativeShell.Taskbar.v4` e repinta **somente o retângulo de status que já pertencia ao CloudOS**.

### Indicadores

- áudio/mute;
- Wi-Fi conectado/desconectado;
- bateria;
- severidade de saúde.

### Gestos

- clique esquerdo continua abrindo Quick Settings pela AppBar existente;
- roda do mouse na área de status ajusta volume em ±5;
- clique do meio alterna mute;
- botão direito abre a Central do Sistema.

A descoberta dos HWNDs da taskbar é periódica, portanto AppBars reconstruídas após hotplug de monitor voltam a receber a tray sem reiniciar o shell.

## 5. Live Toast Overlay

Classe: `CloudOS.NativeShell.Toast.v4`.

### Regras

- `WS_EX_NOACTIVATE`;
- `WS_EX_TOOLWINDOW`;
- `WS_EX_TOPMOST`;
- `WS_EX_LAYERED`;
- `MA_NOACTIVATE`;
- nunca chama `SetForegroundWindow`;
- fila limitada;
- auto-dismiss;
- fade final;
- monitor escolhido a partir da janela foreground;
- posicionamento sobre `rcWork`, portanto não cobre a AppBar;
- clique descarta o toast e avança a fila.

## 6. Control Plane Health Service

Serviço residente em `HWND_MESSAGE`.

A cada ciclo ele agrega:

- áudio;
- brilho;
- energia;
- Wi-Fi;
- monitores/processos;
- espaço em disco.

### Alertas atuais

- bateria <= 15% fora da tomada: warning;
- bateria <= 7%: crítico;
- menor volume <= 10% livre: warning;
- menor volume <= 5% livre: crítico;
- conexão Wi-Fi estabelecida: toast informativo.

Alertas entram tanto no Notification Center quanto no toast overlay quando aplicável.

## 7. Appearance V4

Persistência:

`HKCU\\Software\\CloudOS\\AppearanceV4`

Valores:

- `Accent`
- `Transparency`
- `CompactStatus`

Presets iniciais:

- Indigo
- Blue
- Teal
- Rose
- Amber
- Purple

No V4, accent dinâmico é garantido nas novas superfícies Control Plane/tray/toasts. O restante do WebSkin legado ainda usa os tokens estáticos existentes; não é correto afirmar tema global claro/escuro completo neste estágio.

## 8. Ciclo de vida

`CloudOSNativeQuickSettingsWindow::Create` inicializa:

1. Toast host.
2. Control Plane Health Service.
3. CloudOS Tray Service.

Quick Settings é criado durante a inicialização normal do shell, portanto os serviços existem mesmo antes do primeiro clique no flyout.

## 9. Validação

Contrato dedicado:

`scripts/native/test-shell-control-plane-contract.ps1`

Ele protege:

- grafo MSVC unificado;
- backend real;
- Quick Settings V4;
- tray first-party;
- toast no-activate;
- health service;
- appearance persistence;
- Workspace Studio preservado;
- Continuity preservado;
- proibição de reparent/injeção cross-process.

O contrato é executado pelo `build-cloudos-native.cmd` antes do MSVC.

## 10. O que deliberadamente ainda não é prometido

- captura genérica dos ícones `Shell_NotifyIcon` de apps de terceiros;
- pareamento Bluetooth inteiramente custom sem UI do Windows;
- metadata/capa de mídia via GSMTC/SMTC;
- troca pública do endpoint default de áudio quando exigiria API não documentada;
- tema light/dark global em todo HWND legado;
- Shell Launcher/WESL em Windows Pro.

Esses itens exigem blocos próprios e não são simulados no Control Plane V4.
