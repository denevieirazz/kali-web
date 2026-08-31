# CloudOS Native — índice de documentação

Este diretório documenta a arquitetura **atual** do CloudOS Native Shell. Para o desktop nativo, estes documentos têm precedência sobre descrições antigas de React/WPF encontradas em outras áreas do repositório.

## Comece aqui

1. [`ARCHITECTURE.md`](ARCHITECTURE.md) — processos, responsabilidades e fronteiras.
2. [`CODEMAP.md`](CODEMAP.md) — qual arquivo editar para cada subsistema.
3. [`VALIDATION.md`](VALIDATION.md) — contratos, smokes e o que cada teste realmente prova.
4. [`DESKTOP_SYSTEM_ROADMAP.md`](DESKTOP_SYSTEM_ROADMAP.md) — marcos entregues e próximos gates.

## Marcos de segurança/entrega recentes

- [`SHELL_SUPERVISOR_V11.md`](SHELL_SUPERVISOR_V11.md) — autoridade externa de recovery, readiness e heartbeat.
- Performance/Visual V12 — arquitetura event-driven, paint cacheado e telemetria; veja contratos/scripts V12 e o roadmap.
- [`TRANSACTIONAL_DEPLOYMENT_V13.md`](TRANSACTIONAL_DEPLOYMENT_V13.md) — deploy versionado por usuário, LKG, repair e rollback.
- Documentação V14 de ativação do shell — veja `scripts/native/CloudOS.ShellActivation.V14.psm1`, o contrato V14 e o roadmap; hosted CI usa HKCU sandbox.
- Repository Clarity V15 — `AGENTS.md`, `CODEMAP.md`, `VALIDATION.md` e a suite central tornam a árvore legível por humanos/IAs sem criar uma segunda arquitetura.
- [`UNIFIED_INTEGRATION_V16.md`](UNIFIED_INTEGRATION_V16.md) — downloads Browser→Files, catálogo/instalação/remoção Windows+Linux, WSLg e Desktop integrado.
- [`UNIFIED_START_SEARCH_V17.md`](UNIFIED_START_SEARCH_V17.md) — Start/Search consumindo o mesmo catálogo Linux V16, launcher Shell compartilhado e refresh event-driven.

## Regra de autoridade

```text
CloudOS Native Shell C++/Win32 = desktop atual
CloudOS.Supervisor.exe         = recovery/supervisão externa
V13                            = instalação/update/rollback de versões
V14                            = ativação opt-in do shell e restauração exata
V16                            = boundary de integração Windows + Linux/WSL
V17                            = Start/Search unificado consumindo a boundary V16
React/WPF/Node legado          = compatibilidade, referência e testes; não autoridade do desktop nativo
```

Se um documento contradizer esse modelo, confirme no código compilado (`CloudOS.NativeShell.vcxproj`), no manifesto nativo e na CI Full-System antes de confiar nele.
