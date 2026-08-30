# CloudOS Native System Center V1

## Objetivo

A Central do Sistema é a superfície operacional de hardware e sistema do CloudOS. Ela existe para reduzir a dependência de vários painéis separados do Windows sem reimplementar subsistemas que o próprio Windows já expõe por APIs públicas.

A implementação é C++/Win32 nativa. Não usa React, HTML ou WebView2 e não reparenta janelas de outros processos.

## Autoridade

Arquivos principais:

- `native_system_control_backend.h/.cpp`: integração com APIs do Windows;
- `native_system_control_window.h/.cpp`: superfície Win32 e interação;
- `native_app_launcher_v4.cpp`: descoberta e abertura pelo shell;
- `native_theme.h`: catálogo `systemcenter` e WebSkin;
- `native_search_engine.cpp`: aliases de busca;
- `scripts/native/test-system-center-contract.ps1`: contrato de regressão.

## Páginas

### Visão Geral

Mostra:

- carga de memória;
- RAM livre;
- contagem de processos;
- contagem de monitores;
- adaptadores de rede;
- volumes montados;
- estado de serviços essenciais como WLAN AutoConfig, Windows Audio, Bluetooth Support, DNS, DHCP, Event Log, WMI e Windows Update.

Também oferece atalhos para Gerenciador de Tarefas, Configurações, Gerenciador de Dispositivos e Painel de Controle.

### Wi-Fi

Usa Native Wi-Fi (`wlanapi`):

- `WlanOpenHandle`;
- `WlanEnumInterfaces`;
- `WlanQueryInterface`;
- `WlanGetAvailableNetworkList`;
- `WlanConnect`;
- `WlanDisconnect`.

A lista mostra SSID, qualidade do sinal, segurança, estado, perfil salvo e interface.

#### Regra de credenciais

A Central do Sistema conecta diretamente somente redes que já possuem perfil salvo no Windows. V1 não recebe nem armazena senha Wi-Fi.

Quando uma rede protegida não possui perfil salvo, o CloudOS abre `ms-settings:network-wifi` para que o Windows faça o fluxo de credencial. Depois que o perfil existe, a rede pode ser reconectada pela Central usando `WlanConnect`.

### Tela

A pilha de brilho é deliberadamente em duas camadas:

1. **DDC/CI** para monitores que expõem controle físico ao Windows:
   - `GetNumberOfPhysicalMonitorsFromHMONITOR`;
   - `GetPhysicalMonitorsFromHMONITOR`;
   - `GetMonitorBrightness`;
   - `SetMonitorBrightness`;
   - `DestroyPhysicalMonitors`.
2. **WMI** para painéis integrados compatíveis:
   - namespace `ROOT\WMI`;
   - `WmiMonitorBrightness`;
   - `WmiMonitorBrightnessMethods.WmiSetBrightness`.

Se o monitor não expõe DDC/CI e o equipamento não expõe WMI de brilho, o slider não finge suporte. A UI informa que o controle direto não está disponível e oferece as configurações oficiais de Tela.

### Áudio

Usa Core Audio:

- `IMMDeviceEnumerator`;
- endpoint padrão `eRender/eMultimedia`;
- `IAudioEndpointVolume`;
- `GetMasterVolumeLevelScalar`;
- `SetMasterVolumeLevelScalar`;
- `GetMute` / `SetMute`;
- nome amigável pelo Property Store.

O slider altera o volume master real do endpoint padrão.

### Energia

Usa:

- `GetSystemPowerStatus` para AC/bateria e estimativa;
- `PowerGetActiveScheme` para plano ativo;
- `PowerSetActiveScheme` para alternar entre:
  - Equilibrado;
  - Economia de energia;
  - Alto desempenho.

O Windows pode não disponibilizar todos os planos em todos os dispositivos. Nesse caso a falha é exibida; a Central não cria planos artificiais.

### Rede

Usa `GetAdaptersAddresses` e `InetNtopW` para apresentar:

- nome e descrição do adaptador;
- estado operacional;
- IPv4;
- IPv6;
- endereço MAC;
- velocidade de link anunciada.

Há atalhos para Conexões de Rede, Configurações de Rede e `ipconfig /all`.

### Armazenamento

Usa:

- `GetLogicalDriveStringsW`;
- `GetDriveTypeW`;
- `GetVolumeInformationW`;
- `GetDiskFreeSpaceExW`.

A página mostra volume, rótulo, tipo, sistema de arquivos, espaço livre e capacidade. Um volume selecionado pode ser aberto no Explorer oficial do Windows.

### Processos

Usa Toolhelp + PSAPI:

- `CreateToolhelp32Snapshot`;
- `Process32FirstW` / `Process32NextW`;
- `OpenProcess`;
- `GetProcessMemoryInfo`.

A lista é ordenada por working set e mostra até 60 processos.

O comando de término:

- exige seleção explícita;
- impede a própria Central de finalizar o processo `CloudOS.exe`;
- apresenta confirmação com aviso de perda de dados;
- só então usa `TerminateProcess`.

Para controle completo e privilégios elevados, o Gerenciador de Tarefas continua disponível.

## Design e UX

A janela segue o WebSkin nativo:

- `#0a0a0f` / `#111118` / `#1a1a24`;
- índigo `#6366f1`;
- botões owner-draw;
- ListView em dark mode;
- material DWM de janela principal;
- barra lateral com oito seções;
- atualização periódica a cada dois segundos.

Atalhos internos:

- `Ctrl+1..8`: alternar página;
- `F5`: atualização imediata.

## Descoberta no shell

ID canônico: `systemcenter`.

Aliases do launcher incluem:

- `system-center`;
- `hardware`;
- `hardware-center`;
- `systemcontrol`;
- `controle-sistema`.

A Central também aparece no catálogo do Start e no Quick Hub.

## Segurança e limites intencionais

V1 não tenta:

- armazenar senhas Wi-Fi;
- burlar permissões de processo/serviço;
- implementar pairing Bluetooth por APIs privadas;
- controlar mídia global por SMTC;
- inventar brilho em hardware sem DDC/CI/WMI;
- substituir Device Manager, Disk Management ou Task Manager para operações administrativas avançadas.

Esses limites mantêm a integração dentro de APIs públicas e evitam regressões destrutivas.

## Bibliotecas Windows

O projeto vincula explicitamente, além das dependências já existentes:

- `dxva2.lib`;
- `iphlpapi.lib`;
- `powrprof.lib`;
- `psapi.lib`;
- `propsys.lib`;
- `wlanapi.lib`;
- `wbemuuid.lib`;
- `ws2_32.lib`.

## Regressões protegidas

`test-system-center-contract.ps1` falha se desaparecerem:

- APIs WLAN reais;
- Core Audio;
- DDC/CI + fallback WMI;
- power plans;
- telemetria de adaptadores, discos, processos e serviços;
- as oito páginas;
- integração no Launcher V4;
- catálogo/pesquisa;
- bibliotecas do grafo MSVC.

Também falha se WebView2, React, HTML ou `SetParent` entrarem nessa superfície.
