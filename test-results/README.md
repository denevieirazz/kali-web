# Resultados de validação

A estrutura canônica é:

```text
test-results/<area>/<sha>/<execution-id>/
  validation.json
  commands.txt
  environment.json
  git.json
  database-before.json
  database-after.json
  processes-before.json
  processes-after.json
  logs/
  screenshots/
  artifacts.json
```

`test-results/index.json` indexa execuções produzidas pelos validadores do Batch 1.

## Regras

- nunca reutilizar a mesma pasta para SHA/execution-id diferentes;
- resultados físicos precisam registrar exatamente o HEAD testado;
- banco real deve ser comparado antes/depois e permanecer intacto;
- processos pertencentes à sessão devem ser registrados antes/depois;
- screenshots são evidência visual, não substituem assertions;
- falhas preservam logs e temporários necessários ao diagnóstico;
- sucesso pode limpar somente temporários inequivocamente pertencentes à sessão.
