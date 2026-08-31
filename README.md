# CloudOS Native Shell

CloudOS é um shell desktop nativo C++/Win32 sobre Windows. O Windows continua responsável por kernel, drivers, DWM, segurança, Win32 e serviços do sistema; o CloudOS fornece a experiência Desktop/Taskbar/Start, Window Manager, workspaces, Files, controles e aplicativos first-party.

> Para agentes de IA: comece por [`AGENTS.md`](AGENTS.md), depois [`docs/native/ARCHITECTURE.md`](docs/native/ARCHITECTURE.md) e [`docs/native/CODEMAP.md`](docs/native/CODEMAP.md).

## Arquitetura atual

```text
CloudOS.Supervisor.exe              V11: recovery externo/readiness/restart
        │
        └── CloudOS.exe --supervised
                │
                ├── Desktop / Taskbar / Start
                ├── Window Manager / Workspaces
                ├── Quick Settings / Notification Center
                ├── Files / apps first-party
                └── CloudOS.NativeRuntime.dll
```

O desktop atual **não é React/WPF/WebView2**. Essas áreas continuam no repositório por compatibilidade, testes, referência histórica/visual e componentes específicos. WebView2 permanece permitido no Navegador CloudOS, mas não é o renderer do Desktop principal.

## Estado dos marcos nativos

| Marco | Estado | Resultado principal |
|---|---|---|
| V9 Stability/Readiness | ✅ | health ABI, Ready e heartbeat da UI thread |
| V10 Lifecycle | ✅ | single-instance e revalidação de lifecycle |
| V11 Shell Supervisor | ✅ | supervisor externo, restart limitado e fallback Explorer |
| V12 Performance/Visual | ✅ | shell event-driven, paint cacheado, telemetria de idle |
| V13 Transactional Deployment | ✅ | versões imutáveis, staging, LKG, repair e rollback |
| V14 Shell Activation | ✅ hosted CI | ativação opt-in por usuário + restauração exata do Shell |
| V15 Repository Clarity | em validação | source-of-truth e navegação do código para humanos/IAs |

A CI hospedada não substitui a matriz física. Login real com V14, reboot, RDP físico, suspend físico, hotplug e soak de 24h continuam gates separados; veja [`docs/native/VALIDATION.md`](docs/native/VALIDATION.md).

## Onde está o código atual

```text
desktop/
├── CloudOS.NativeShell/       # CloudOS.exe — shell/UI atual
├── CloudOS.NativeRuntime/     # CloudOS.NativeRuntime.dll
├── CloudOS.NativeRecovery/    # CloudOS.Supervisor.exe
└── CloudOS.NativeCommon/      # protocolos/ABI compartilhados

scripts/native/                # build, contratos, smokes, V13 e V14
docs/native/                   # documentação autoritativa do shell nativo
```

O entrypoint compilado do shell é:

```text
desktop/CloudOS.NativeShell/src/main_shell_v2.cpp
```

Para localizar um subsistema, use [`docs/native/CODEMAP.md`](docs/native/CODEMAP.md) em vez de inferir responsabilidade só pelo nome do arquivo.

## Build nativo

Pré-requisitos principais no Windows:

- Visual Studio/Build Tools com Desktop development with C++;
- Windows SDK;
- PowerShell 7 (`pwsh`);
- WebView2 SDK restaurado pelo build somente para o Navegador CloudOS.

Build oficial:

```powershell
scripts\native\build-cloudos-native.cmd Release
```

Rodar apenas os contratos:

```powershell
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1
```

O build produz e verifica:

- `CloudOS.exe`;
- `CloudOS.NativeRuntime.dll`;
- `CloudOS.Supervisor.exe`;
- `cloudos-native-manifest.json`;
- fingerprint e SHA256 do release.

## Executar sem substituir Explorer

Depois de um build verificado, use os launchers do projeto/pacote que passam pelo `CloudOS.Supervisor.exe`. O Supervisor inicia `CloudOS.exe --supervised`; o watchdog interno não deve competir nesse modo.

## Instalar / atualizar — V13

V13 instala por usuário, por padrão em:

```text
%LOCALAPPDATA%\CloudOS\NativeShell
```

Entrypoints principais:

```powershell
scripts/native/install-cloudos-native-v13.ps1
scripts/native/update-cloudos-native-v13.ps1
scripts/native/get-cloudos-deployment-status-v13.ps1
scripts/native/rollback-cloudos-native-v13.ps1
scripts/native/repair-cloudos-native-v13.ps1
scripts/native/uninstall-cloudos-native-v13.ps1
```

Instalação/update **não ativa o CloudOS como shell de logon**.

## Ativação opt-in — V14

V14 é uma operação separada e explícita. A fonte de verdade é:

```text
scripts/native/CloudOS.ShellActivation.V14.psm1
```

O alvo de produção atual é o valor `Shell` do Winlogon do usuário atual em HKCU. Antes da alteração, V14 salva presença, tipo e dado anterior; rollback restaura exatamente o snapshot, inclusive o caso “valor ausente”. Há journal/repair para interrupção e detecção de drift externo.

Entrypoints:

```powershell
scripts/native/activate-cloudos-shell-v14.ps1
scripts/native/get-cloudos-shell-status-v14.ps1
scripts/native/rollback-cloudos-shell-v14.ps1
scripts/native/repair-cloudos-shell-v14.ps1
```

**Não use isso como shell diário em uma máquina importante antes da matriz de login/boot/rollback em VM e piloto.** Hosted CI testa a lógica V14 em uma subchave HKCU sandbox e confirma que a chave Winlogon real do runner não mudou.

## Documentação fonte de verdade

- [`AGENTS.md`](AGENTS.md) — regras e leitura rápida para agentes de IA.
- [`docs/native/README.md`](docs/native/README.md) — índice do nativo.
- [`docs/native/ARCHITECTURE.md`](docs/native/ARCHITECTURE.md) — processos, responsabilidades e fronteiras.
- [`docs/native/CODEMAP.md`](docs/native/CODEMAP.md) — mapa arquivo→subsistema.
- [`docs/native/VALIDATION.md`](docs/native/VALIDATION.md) — o que cada teste prova/não prova.
- [`docs/native/DESKTOP_SYSTEM_ROADMAP.md`](docs/native/DESKTOP_SYSTEM_ROADMAP.md) — gates de entrega.
- [`scripts/native/README.md`](scripts/native/README.md) — organização dos scripts.

## Código de compatibilidade / histórico

Ainda existem áreas como:

- `frontend/`;
- `backend/`;
- `desktop/CloudOS.Host/`;
- `desktop/CloudOS.Bootstrap/`;
- provas/experimentos históricos.

Elas não foram apagadas na V15 porque “limpar” não deve significar destruir compatibilidade ou histórico sem prova de que o código está morto. Quando um componente for aposentado, a remoção deve ocorrer em um marco próprio, com busca de referências e CI verde.

## Segurança e validação

- não há elevação silenciosa no fluxo V13/V14;
- V14 não usa HKLM, `Userinit`, `Run`, `RunOnce`, serviço ou tarefa agendada como atalho;
- recovery precisa continuar independente da UI do shell;
- release é validado por manifesto/fingerprint/SHA256;
- SHA256 não substitui assinatura Authenticode de produção;
- `main` não é usada como branch de experimento durante as validações dos marcos.

Consulte também [`SECURITY.md`](SECURITY.md) e a matriz nativa em [`docs/native/VALIDATION.md`](docs/native/VALIDATION.md).
