# CloudOS Native — matriz de validação

Este documento define **o que cada teste prova** e, igualmente importante, o que ele **não** prova.

## Regra geral

Um contrato de texto/código prova que uma propriedade estrutural está presente. Um smoke de runtime prova comportamento no ambiente executado. Nenhum deles deve ser descrito como teste físico que não ocorreu.

Para qualquer alteração nativa relevante:

```powershell
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1
scripts\native\build-cloudos-native.cmd Release
```

Depois, observe a `CloudOS Native Full-System CI` no Windows runner.

---

## Suite de contratos

Entrypoint:

```text
scripts/native/test-native-contract-suite.ps1
```

A suite chama os contratos individuais em ordem determinística e falha no primeiro erro. O build oficial usa esse entrypoint em vez de manter uma lista duplicada de chamadas.

Os contratos protegem, entre outros:

- shell nativo compilado e ausência do antigo desktop web no grafo;
- lifecycle/single-instance;
- Visual V7 / Shell Experience V8;
- Health/Readiness V9;
- Lifecycle V10;
- Supervisor V11;
- Performance/Visual V12;
- Deployment V13;
- Shell Activation V14;
- organização/source-of-truth V15;
- Unified Integration V16;
- Unified Start/Search V17.

Contrato não substitui runtime smoke.

---

## V9 — Stability / Readiness

### Automatizado

- health mapping V9 com ABI fixa;
- readiness e heartbeat da UI thread;
- processo respondendo;
- amostras de working set/private bytes/handles/GDI/USER/threads;
- smoke curto no Full-System CI;
- harness de soak configurável.

### O que a CI atual prova

A Full-System CI executa um smoke curto de V9 e exige verdict `pass`.

### O que NÃO foi provado automaticamente

O harness suporta execução longa, mas **24 horas de soak não são afirmadas como executadas** nesta linha de validação. Sem evidência explícita de uma execução física de 24h, não escreva “24h PASS”.

---

## V10 — Lifecycle

### Automatizado

- single-instance;
- checkpoints/revalidação por mensagens/probes determinísticos;
- suspend/resume lógico;
- display/settings lifecycle;
- WTS/session disconnect/reconnect lógico;
- heartbeat atravessando as transições;
- checkpoint persistido.

### Limite

Hosted CI **não suspende fisicamente a máquina**, não transporta uma sessão RDP real e não faz hotplug físico de monitor. Esses casos pertencem à matriz de VM/hardware.

---

## V11 — Shell Supervisor

### Automatizado

- `CloudOS.Supervisor.exe --self-test`;
- shell real alcançando Ready sob Supervisor;
- heartbeat avançando;
- graceful exit;
- release do health mapping após shutdown;
- failure loop determinístico;
- orçamento/backoff de restart;
- ausência de processos CloudOS órfãos.

### Fallback Explorer no CI

O probe de failure loop valida a **decisão** de fallback, mas usa supressão de Explorer no hosted CI. Não descreva o smoke como “Explorer realmente foi lançado durante fallback” quando ele foi deliberadamente suprimido.

---

## V12 — Performance / Visual

### Automatizado

- native surface regression tests;
- backbuffer reuse;
- Desktop watcher create/rename/delete;
- geometria multi-monitor/DPI determinística;
- idle soak de aproximadamente 120 segundos;
- CPU média normalizada;
- crescimento de handles/GDI/USER;
- contadores de scans, icon load em paint e backbuffer allocations.

### Critério arquitetural

Idle deve ser orientado por eventos. Filesystem/Shell APIs caras não podem reaparecer dentro de paint.

### Limite

120 segundos verdes não equivalem a semanas de uso piloto nem a todos os drivers/GPU/hardware.

---

## V13 — Transactional Deployment

Smoke:

```text
scripts/native/run-native-deployment-smoke-v13.ps1
```

Executado contra diretórios temporários no Windows CI.

### Evidências esperadas

- clean install;
- reinstall idempotente;
- upgrade verificado;
- pacote corrompido rejeitado;
- versão ativa preservada após rejeição;
- transação interrompida reparada;
- rollback para versão anterior;
- uninstall apenas de raiz gerenciada;
- nenhuma modificação de registry/Winlogon.

### Limite

Não é instalação comercial/MSIX nem prova de falha de energia física no exato instante de I/O.

---

## V14 — Shell Activation

Smoke:

```text
scripts/native/run-native-shell-activation-smoke-v14.ps1
```

### Hosted CI

O smoke cria uma subchave exclusiva em:

```text
HKCU\Software\CloudOS\Tests\ShellActivationV14\<guid>
```

Ele **não escreve** a chave Winlogon real do runner.

### Evidências esperadas

- deployment V13 válido antes de ativar;
- prior value ausente restaurado como ausente;
- `explorer.exe` anterior restaurado exatamente;
- `REG_EXPAND_SZ` anterior restaurado com tipo/dado preservados;
- ativação idempotente;
- shell-entry estável resolve V13 e alcança Ready com Supervisor real;
- interrupção após escrita reparada pelo journal;
- payload ativo inválido rejeitado;
- uninstall V13 bloqueado enquanto V14 está ativo;
- uninstall permitido depois do rollback;
- snapshot da chave de produção Winlogon idêntico antes/depois.

### Limite

Hosted CI não faz logoff/login real, reboot, boot recovery, troca física de usuário ou cenário de credencial/logon. Esses gates exigem VM/piloto.

---

## V16 — Unified Integration

Contrato:

```text
scripts/native/test-unified-integration-v16-contract.ps1
```

Smoke:

```text
scripts/native/run-native-integration-smoke-v16.ps1
```

### Automatizado

- Browser WebView2 `DownloadStarting` conectado ao picker first-party;
- boundary única de inventário/package management Windows+Linux;
- inventário uninstall Windows permanece read-only;
- known folders e `\\wsl.localhost` preservados;
- adaptação compartilhada de launcher Linux pode ser consumida sem mover responsabilidade para surfaces;
- snapshot do HKCU Winlogon de produção idêntico antes/depois;
- nenhuma operação de install/upgrade/remove executada pelo smoke.

### Limite

A CI hospedada não instala software de terceiros e não prova WSLg GUI real quando não existe distro WSL configurada. `wsl.exe` presente com zero distros continua sendo um resultado válido do smoke, não prova de launch Linux.

---

## V17 — Unified Start/Search

Contrato:

```text
scripts/native/test-unified-start-search-v17-contract.ps1
```

Smoke:

```text
scripts/native/run-native-unified-start-search-smoke-v17.ps1
```

### Automatizado

- `NativeStartIndexKind::LinuxApp` existe;
- Start consome `NativeIntegrationV16::EnumerateLinuxGuiApps()` em vez de duplicar `.desktop`/WSL parsing;
- Desktop e Start usam o mesmo `EnsureLinuxLauncherShortcut()`;
- mudanças em application directories de distros observadas acionam refresh do Desktop e do Start via change notification;
- Start index não monta `wsl.exe`/`gtk-launch` diretamente;
- Supervisor V11 `--self-test` continua retornando 0;
- HKCU Winlogon de produção permanece idêntico;
- nenhuma operação mutável de package management é executada.

### O que NÃO prova

Se o hosted runner reportar `wsl_distribution_count = 0`, o smoke **não prova**:

- que um `.desktop` Linux real apareceu no Start;
- que WSLg abriu uma janela GUI real;
- que pin de app Linux sobreviveu a uma sessão física;
- que instalação/removal apt disparou o watcher numa distro real.

Esses casos exigem VM/host com WSLg configurado. Uma distro criada depois de o worker do Desktop iniciar também pode precisar de reindex/restart inicial para que seu novo diretório passe a ser observado; V17 não usa polling global para mascarar isso.

---

## Release / Proveniência

Scripts:

- `write-native-build-manifest.ps1`
- `verify-native-build-manifest.ps1`
- `get-native-build-fingerprint.ps1`
- `package-cloudos-native.ps1`

O release deve incluir e verificar:

- `CloudOS.exe`;
- `CloudOS.NativeRuntime.dll`;
- `CloudOS.Supervisor.exe`;
- manifesto com tamanho/SHA256;
- fingerprint de fontes;
- build head.

Em PR, `github.sha`/manifesto pode apontar para o merge commit sintético do PR, enquanto metadados do workflow mostram o **branch head real**. Relatórios devem distinguir os dois.

SHA256 garante integridade em relação ao manifesto. Sem assinatura Authenticode de produção, não confunda isso com identidade criptográfica do editor.

---

## V20 — Flutter Presentation & Native Bridge

### Automatizado
- Análise estática do Dart (`flutter analyze`) com 0 warnings/erros;
- Testes unitários e de contrato do `MethodChannel` (`cloudos/native/v19`);
- Compilação C++ do host Flutter Windows Release x64 com o adapter nativo linkado;
- Verificação de fallback gracioso para preview em testes headless.

---

## V21 — CloudOS System Broker & Event Bus

### Automatizado
- Contrato arquitetural `test-system-broker-v21-contract.ps1`;
- Compilação MSBuild Release x64 de `CloudOS.SystemBroker.exe` e `CloudOS.BrokerProbe.exe` com `/W4 /WX`;
- Auto-teste in-process com `--self-test` (serialização, DACL, EventBus, JobManager, AppService, SystemService, WSL);
- Smoke de IPC `run-system-broker-smoke-v21.ps1` via Named Pipe com probe de comandos e geração de `system-broker-v21-smoke.json`;
- Teste de estabilidade e ausência de vazamento de memória `test-system-broker-v21-soak.ps1` (120 segundos).

---

## Baseline CI

A `CloudOS CI Baseline` preserva o restante do repositório: lint/build/testes do frontend/backend/Host/Bootstrap/Browser e caracterizações aplicáveis.

V15 não transforma essas áreas em autoridade do desktop; elas continuam sendo código suportado/compatibilidade e precisam permanecer verdes enquanto existirem no repositório.


---

## Matriz física ainda necessária antes de chamar substituição do Explorer de produção

Em VM descartável e, depois, hardware piloto:

1. login com V14 ativado;
2. logout/login repetido;
3. crash antes de Ready;
4. crash-loop até fallback;
5. rollback independente para Explorer;
6. update V13 com V14 ativo;
7. rollback de versão V13 com V14 ativo;
8. reboot normal;
9. shutdown forçado/recuperação após transação interrompida;
10. duas contas e duas sessões;
11. RDP real;
12. suspend/resume físico;
13. monitor hotplug/DPI físico;
14. WSLg real: instalar/remover GUI app e validar Desktop/Start/Search/launch;
15. 24h soak por configuração;
16. piloto de dias/semanas antes de uso como shell diário.

Registre data, Windows build, hardware/VM, commit exato, artifact digest e resultado. Sem essa evidência, mantenha a descrição como “pendente”.
