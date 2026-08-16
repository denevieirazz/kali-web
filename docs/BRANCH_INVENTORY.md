# Inventário de branches — CloudOS

Base de comparação: `integration/cloudos-validated-features@2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`.

| Branch | SHA | Base / merge-base | Ahead | Behind | Arquivos alterados | Estado | Finalidade | Evidência | Destino previsto |
|---|---|---|---:|---:|---:|---|---|---|---|
| `integration/cloudos-validated-features` | `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc` | oficial | 0 | 0 | 0 | oficial validada | linha de features aprovadas | CI e validações promovidas anteriores | permanece imutável durante Batch 1 |
| `stabilization/cloudos-foundation-batch-1` | criada de `2d3380ba...` | `2d3380ba...` | em evolução | 0 | em evolução | candidata de estabilização | consolidar governança, launcher, Terminal, capability UX, Files e onboarding | CI + gate físico a produzir | revisão do proprietário; sem promoção automática |
| `feature/cloudos-files-real-transactional` | `d213dd10b5137e882f323eb60853d54cc9d4568a` | `2d3380ba...` | 36 | 0 | 23 | candidata isolada | OPFS + Windows grant + Linux Home, transações e confinement | CI da branch; físico pendente | transportar somente foundation auditada |
| `feature/cloudos-onboarding-files-ux` | `e034e4be768c240ecb830a6442ece18039f24fc2` | `2d3380ba...` | 35 | 0 | 23 | candidata isolada | onboarding/recovery + UX visual do Files oficial | CI e Playwright; revisão humana pendente | transportar somente UX/auth necessária |
| `fix/native-browser-physical-ui` | `710a5da64e0645d2b874e2cc9eea35561b280798` | merge-base `56f0ca8bc0a59987a43295da1ded277afc40e6e9` | 34 | 32 | 30 | divergente / candidata física | correções físicas do browser WPF | testes/probes próprios | manter isolada; não promover no Batch 1 |
| `feature/cloudos-linux-system-center-cgroups` | `14e125d77af9af0e4f84b039ea54f073c9ac38c2` | `2d3380ba...` | 22 | 0 | 26 | experimental isolada | processos Linux/cgroups/System Center | CI; gate físico ainda não aprovado | retomar após estabilização base |
| `main` | `45abf3347725a77b1456e7e0a94e2f0d45b175f2` | fora da linha de integração | n/a | n/a | n/a | proibida para este trabalho | histórico independente | não usar | nenhum |

## Regras de interpretação

- `ahead/behind` é sempre relativo à linha oficial declarada acima.
- Branch divergente não é classificada como obsoleta; requer análise de conteúdo/ancestralidade antes de qualquer decisão.
- Branch candidata não é considerada fisicamente aprovada apenas porque a CI está verde.
- O Batch 1 não apaga branches, worktrees ou resultados antigos.
