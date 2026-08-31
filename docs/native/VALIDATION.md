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
- Package Maintenance V17.

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

### Limite

O harness suporta execução longa, mas **24 horas de soak não são afirmadas como executadas** sem evidência física específica.

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

Hosted CI **não suspende fisicamente a máquina**, não transporta uma sessão RDP real e não faz hotplug físico de monitor.

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

O probe valida a **decisão** de fallback, mas suprime o lançamento real do Explorer no hosted CI.

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

Smoke: `scripts/native/run-native-deployment-smoke-v13.ps1`.

Executado contra diretórios temporários no Windows CI. Prova clean install, reinstall idempotente, upgrade verificado, rejeição de pacote corrompido, repair, rollback e uninstall da raiz gerenciada sem modificar registry/Winlogon.

Não é instalação comercial/MSIX nem prova de falha de energia física no exato instante de I/O.

---

## V14 — Shell Activation

Smoke: `scripts/native/run-native-shell-activation-smoke-v14.ps1`.

Hosted CI usa uma subchave exclusiva `HKCU\Software\CloudOS\Tests\ShellActivationV14\<guid>` e **não escreve** a chave Winlogon real do runner.

Prova restauração exata de ausência/Explorer/`REG_EXPAND_SZ`, idempotência, shell-entry Ready, repair de journal, rejeição de payload inválido, interlock de uninstall e snapshot Winlogon de produção idêntico antes/depois.

Hosted CI não faz logoff/login real, reboot, boot recovery ou troca física de usuário.

---

## V16 — Unified Integration

Contrato: `scripts/native/test-unified-integration-v16-contract.ps1`.

Smoke: `scripts/native/run-native-integration-smoke-v16.ps1`.

### O que a CI prova

- grafo compilado da integração Windows + Linux;
- Browser com destino de download first-party;
- boundary de inventário/package management presente;
- known folders resolvidos;
- capability snapshot de WinGet/WSL;
- Winlogon real idêntico antes/depois;
- nenhuma mutação de pacote executada pelo smoke.

### Limite

Hosted CI não instala/remove software de terceiros e não afirma WSLg GUI real quando não existe distro/WSLg adequada.

---

## V17 — Package Maintenance

Contrato:

```text
scripts/native/test-package-maintenance-v17-contract.ps1
```

Smoke:

```text
scripts/native/run-native-package-maintenance-smoke-v17.ps1
```

### O que a CI prova

- binário nativo Release presente;
- builder de upgrade Windows via WinGet com seleção exata;
- builders Linux para apt `--only-upgrade`, Snap `refresh` e Flatpak `update`;
- resolução de ownership apt via `dpkg-query -S` em vez de adivinhar pelo nome visual;
- allowlist/token validation da identidade Linux;
- ação **Atualizar app** ligada ao Apps com confirmação e Terminal visível;
- Winlogon de produção idêntico antes/depois;
- `mutating_package_operation_executed = false`.

### O que NÃO prova

Hosted CI **não executa upgrade real** de WinGet/apt/Snap/Flatpak, não aprova UAC/sudo, não prova comportamento de instaladores de terceiros e não prova upgrade Linux num runner sem distro apropriada. Esses casos pertencem à matriz manual/VM.

---

## Release / Proveniência

Scripts:

- `write-native-build-manifest.ps1`
- `verify-native-build-manifest.ps1`
- `get-native-build-fingerprint.ps1`
- `package-cloudos-native.ps1`

O release deve incluir e verificar `CloudOS.exe`, `CloudOS.NativeRuntime.dll`, `CloudOS.Supervisor.exe`, manifesto com tamanho/SHA256, fingerprint de fontes e build head.

Em PR, `github.sha`/manifesto pode apontar para o merge commit sintético do PR, enquanto metadados do workflow mostram o **branch head real**. Relatórios devem distinguir os dois.

SHA256 garante integridade em relação ao manifesto. Sem assinatura Authenticode de produção, não confunda isso com identidade criptográfica do editor.

---

## Baseline CI

A `CloudOS CI Baseline` preserva o restante do repositório: lint/build/testes do frontend/backend/Host/Bootstrap/Browser e caracterizações aplicáveis. Essas áreas não substituem a autoridade do desktop nativo.

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
14. 24h soak por configuração;
15. WinGet install/update/remove real com UAC quando aplicável;
16. apt/Snap/Flatpak install/update/remove real com sudo e falhas controladas;
17. piloto de dias/semanas antes de uso como shell diário.

Registre data, Windows build, hardware/VM, commit exato, artifact digest e resultado. Sem essa evidência, mantenha a descrição como “pendente”.
