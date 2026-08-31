# Arquitetura atual — CloudOS Native Shell

## 1. Visão geral

O CloudOS atual é um shell desktop nativo sobre Windows. Ele não substitui kernel, drivers, Win32, DWM ou os serviços do Windows. A camada CloudOS fornece Desktop, Taskbar, Start, flyouts, Window Manager, workspaces, Files e apps first-party, enquanto integra capacidades do sistema operacional por APIs Windows.

A autoridade do desktop é C++/Win32:

```text
CloudOS.NativeShell (C++/Win32)
    └─ CloudOS.exe
         ├─ Desktop / Taskbar / Start
         ├─ Window Manager / Workspaces
         ├─ Quick Settings / Notification Center / System Center
         ├─ Files e apps first-party
         ├─ Health V9 + Lifecycle V10
         └─ CloudOS.NativeRuntime.dll
```

WebView2 existe apenas onde é apropriado, principalmente no Navegador CloudOS. O antigo desktop React não participa do build nativo.

## 2. Grafo de processos e autoridade

### Execução normal portátil/de desenvolvimento

```text
launcher
  └─ CloudOS.Supervisor.exe          [V11 — autoridade externa de recovery]
       └─ CloudOS.exe --supervised   [shell/UI]
            └─ CloudOS.NativeRuntime.dll
```

Quando `CloudOS.exe` recebe `--supervised`, o watchdog embutido não cria um segundo loop de recovery concorrente. O Supervisor observa readiness/heartbeat V9, reinicia com orçamento limitado e mantém Explorer como fallback seguro.

### Instalação V13

```text
%LOCALAPPDATA%\CloudOS\NativeShell\
  ├─ state\deployment-v13.json
  ├─ state\deployment-v13.journal.json
  ├─ versions\<versão verificada>\
  │    ├─ CloudOS.exe
  │    ├─ CloudOS.NativeRuntime.dll
  │    ├─ CloudOS.Supervisor.exe
  │    └─ cloudos-native-manifest.json
  └─ tools\...
```

V13 separa o estado `active_version` da versão física. Uma versão só é publicada depois de manifesto, tamanho, SHA256 e `CloudOS.Supervisor.exe --self-test`. A versão anterior pode permanecer como last-known-good.

### Ativação opt-in V14

```text
HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell
  └─ comando estável V14
       └─ <install-root>\shell-v14\CloudOS.ShellEntry.V14.cmd
            └─ resolve deployment-v13.json
                 └─ versions\<active>\CloudOS.Supervisor.exe
                      └─ CloudOS.exe --supervised
```

A ativação V14 é explícita. Instalar ou atualizar não altera automaticamente o shell de logon.

Antes da escrita, V14 salva presença, tipo e dado não expandido do valor `Shell`. Rollback restaura exatamente esse snapshot — inclusive o caso em que o valor não existia. Um journal permite desfazer uma escrita interrompida. Drift externo é detectado e não é sobrescrito silenciosamente.

Hosted CI testa V14 somente em `HKCU\Software\CloudOS\Tests\ShellActivationV14\...`; a chave Winlogon real é comparada antes/depois e deve permanecer intacta.

## 3. Componentes de processo

### `desktop/CloudOS.NativeShell`

Responsável pela experiência desktop e pela coordenação dos subsistemas nativos. O entrypoint compilado é `src/main_shell_v2.cpp`.

Principais grupos:

- Desktop: wallpaper, ícones, drop target e menu de contexto.
- Shell chrome: Taskbar, Start, Quick Settings, Notification Center, toast.
- Window management: enumeração, eventos, workspaces, Snap e previews DWM.
- Control plane: System Center, tray first-party, system controls.
- Files: navegação, busca, preview e operações nativas.
- Session: continuity, recovery e lifecycle.
- Apps: Browser, Terminal, Notepad, Calculator, Projects, Run etc.

Veja a correspondência arquivo→responsabilidade em `CODEMAP.md`.

### `desktop/CloudOS.NativeRuntime`

DLL de runtime nativo usada pelo shell. Contém integrações que devem permanecer separadas da apresentação, incluindo runtime base, terminal, eventos de janela e WSL.

### `desktop/CloudOS.NativeRecovery`

Produz `CloudOS.Supervisor.exe`. Apesar do nome histórico da pasta, a saída atual é o Supervisor V11 e ele é a autoridade externa de readiness/restart/fallback.

### `desktop/CloudOS.NativeCommon`

Contratos compartilhados entre processos. Alterações aqui exigem atenção especial a ABI, tamanho de estruturas, nomes de mapping/event/message e compatibilidade entre binários.

## 4. Health V9

Health V9 é a fonte compartilhada de readiness/heartbeat entre shell e Supervisor.

Invariantes importantes:

- snapshot fixo e pointer-free de 96 bytes;
- mapping `Local\CloudOS.NativeShell.Health.v9`;
- ready event `Local\CloudOS.NativeShell.Ready.v9`;
- heartbeat produzido pela UI thread;
- Desktop autoritativo `CloudOS.NativeShell.Desktop.v2`.

O objetivo é distinguir processo existente de shell realmente pronto/respondendo.

## 5. Lifecycle V10

Lifecycle trata mudanças de sessão/sistema sem criar outra instância do shell:

- suspend/resume checkpoint e revalidação;
- display/AppBar/workarea revalidation;
- WTS/RDP checkpoint/refresh;
- retry de registro WTS quando necessário;
- single-instance.

A CI usa mensagens/probes determinísticos. Ela não deve ser descrita como prova de suspend físico, transporte RDP ou hotplug real.

## 6. Supervisor V11

Responsabilidades:

1. iniciar `CloudOS.exe --supervised`;
2. aguardar Ready com timeout;
3. observar freshness do heartbeat;
4. distinguir saída normal de falha/hang;
5. reiniciar com backoff/orçamento limitado;
6. solicitar graceful exit antes de `TerminateProcess`;
7. recorrer a Explorer apenas quando necessário.

Não deve existir um segundo supervisor/recovery loop competindo com ele.

## 7. Performance/Visual V12

Princípios que devem continuar verdadeiros:

- atualização event-driven para superfícies do shell;
- `WM_PAINT` desenha estado preparado/cacheado;
- filesystem/Shell APIs caras não entram no caminho de pintura;
- backbuffers são reutilizados;
- invalidação usa regiões quando possível;
- workers fazem I/O/trabalho lento e retornam resultado à UI thread;
- painéis escondidos não continuam fazendo refresh caro;
- telemetria mede repaints/scans/recursos sem coletar conteúdo pessoal.

## 8. Deployment V13

`CloudOS.Deployment.V13.psm1` é a fonte de verdade da instalação por usuário.

Operações:

- install/update transacional;
- verificação antes de publish;
- estado ativo separado;
- last-known-good;
- repair de journal/staging interrompido;
- rollback;
- uninstall guardado por estado gerenciado.

V13 não é um ativador de Winlogon.

## 9. Shell Activation V14

`CloudOS.ShellActivation.V14.psm1` é a fonte de verdade do mecanismo moderno de ativação opt-in.

Ele não deve ser confundido com `configure-cloudos-shell-launcher.ps1`, que é um utilitário legado/administrativo para o recurso Windows Shell Launcher (`WESL_UserSetting`).

V14 mantém escopo current-user e não usa HKLM, Userinit, Run/RunOnce, serviço ou tarefa agendada como atalho.

## 10. Estado e persistência

O estado deve ter dono claro:

- deployment/update: V13 state + journal;
- shell activation: V14 state + journal;
- shell runtime/preferences: módulos nativos correspondentes;
- continuity/workspaces: serviços de session/workspace;
- release integrity: manifesto + fingerprint + hashes.

Não crie um segundo arquivo de estado para a mesma verdade sem definir migração e autoridade.

## 11. Fronteira legado/compatibilidade

Ainda existem `frontend/`, `backend/`, `desktop/CloudOS.Host`, Bootstrap e testes do Browser/WPF. Eles podem continuar úteis para compatibilidade, caracterização e componentes específicos.

Para o **desktop atual**, porém:

```text
não usar React como autoridade do Desktop
não usar WPF Host como autoridade do shell
não construir frontend para gerar CloudOS.exe
não adicionar WebView2 ao Desktop principal
```

O `CloudOS.NativeShell.vcxproj`, o manifesto release e a Full-System CI são as provas executáveis dessa fronteira.

## 12. Regra de dependência

Prefira dependências na direção:

```text
UI surface
  ↓
service/model explícito
  ↓
platform/runtime boundary
  ↓
Windows API
```

Evite:

- surface chamando filesystem/WMI/rede durante paint;
- módulos alterando estado global de outro subsistema sem API clara;
- scripts de instalação escrevendo configuração de shell como efeito colateral;
- recovery dependendo da UI do próprio shell quebrado.

## 13. Leitura recomendada antes de editar

- mapa de arquivos: `docs/native/CODEMAP.md`;
- validação: `docs/native/VALIDATION.md`;
- regras para agentes: `AGENTS.md`;
- scripts: `scripts/native/README.md`;
- código do shell: `desktop/CloudOS.NativeShell/src/README.md`.
