# Documentação CloudOS

A documentação desta pasta deve distinguir claramente estado de código, CI e validação física.

## Índice de estabilização

- `PROJECT_STATE.md` — fonte humana de verdade da linha oficial/candidatas.
- `BRANCH_INVENTORY.md` — ancestralidade, SHA, ahead/behind e finalidade.
- `ARCHITECTURE.md` — arquitetura técnica ativa.
- `VALIDATION_MATRIX.md` — gates automatizados/físicos.
- `KNOWN_ISSUES.md` — problemas confirmados e limites deliberados.
- `ROADMAP.md` — sequência de evolução após estabilização.
- `CLOUDOS_VIRTUAL_DISK_DESIGN.md` — opções futuras para VHDX real; não implementa disco.

`cloudos-project-state.json`, na raiz, é a contraparte consumível por scripts.

## Regra de evidência

Não converter `CI verde` em `validado fisicamente`. Qualquer documento que afirme validação Windows/WSL/visual deve apontar para um resultado versionado em `test-results/<area>/<sha>/<execution-id>/`.
