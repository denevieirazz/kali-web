# Resultados de validação — CloudOS Stabilization Batch 1

A estrutura canônica do lote é:

```text
test-results/stabilization-batch-1/<sha>/<execution-id>/
  manifest.json
  summary.json
  git.json
  environment.json
  commands.json
  commands/
    <step>.stdout.log
    <step>.stderr.log
  safety/
    processes-before.json
    processes-after.json
    wsl-before.txt
    wsl-after.txt
  evidence/
    launcher-sessions.json
    manual-checkpoint.txt
  isolated-data/
  playwright-native-browser/
  playwright-native-browser-lifecycle/
```

No CI, o mesmo contrato é usado sob:

```text
test-results/stabilization-batch-1/<sha>/<github-run-id>-<os>/
```

`test-results/index.json` é o índice central versionado do Batch 1. Resultados de execução permanecem artefatos locais/CI e não devem ser commitados.

## Regras de segurança

- `Validar CloudOS.cmd` é a entrada física única para Gemini Low.
- A validação exige a branch `stabilization/cloudos-foundation-batch-1` e comprova o merge-base `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`.
- Todo backend iniciado pelo validador usa `CLOUDOS_DATA_DIR`, `CLOUDOS_TEST_ROOT` e `DATABASE_PATH` apontando para `isolated-data/`.
- O validador não executa comandos WSL mutantes. Ele somente registra snapshots read-only (`--list --verbose` e `--status`) antes/depois.
- Teardown do launcher atua apenas em PIDs registrados pela sessão e valida identidade por `StartTime`.
- stdout e stderr de cada comando físico ficam separados em `commands/`.
- Logs de launcher/Host/backend/frontend continuam preservados em `logs/session-*/`.
- A pausa de checkpoint manual não converte ENTER em aprovação visual. Aprovação física/visual pertence a Gemini Low, usuário e Copilot principal.
- Falhas preservam evidência e a causa do comando que falhou.
