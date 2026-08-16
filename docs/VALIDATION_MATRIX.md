# Matriz de validação — CloudOS Stabilization Batch 1

Estados permitidos: `pendente`, `automatizado`, `físico pendente`, `aprovado pelo proprietário`.

| Área | Teste automatizado | Windows físico | WSL2 físico | Visual | Banco real | Zero órfãos |
|---|---|---|---|---|---|---|
| Governança/manifest | schema, branch/SHA, caminhos e modos | n/a | n/a | revisão docs | não toca | n/a |
| Launcher | pré-requisitos, processo que morre antes do readiness, logs, stop idempotente | obrigatório | quando modo usa WSL | mensagens/modos | temp somente em validação | obrigatório |
| Terminal | lifecycle, fit, teardown, múltiplos panes/tabs, nenhuma exceção global `dimensions` | obrigatório | input/output/resize/Ctrl+C | obrigatório | temp | obrigatório |
| Browser capability UX | WebOnly bloqueia corretamente; Full exige Host | Full obrigatório | n/a | obrigatório | não toca | obrigatório |
| Browser WPF físico | fora do escopo de promoção do Batch 1; candidata separada | usar somente gate dedicado | n/a | gate dedicado | UDF temp em testes | obrigatório |
| Files OPFS | CRUD, preview, ícones, grade/lista, miniaturas | obrigatório | n/a | obrigatório | não toca | n/a |
| Files Windows grant | grant explícito, CRUD, cancel/rollback, lixeira | obrigatório | n/a | obrigatório | não toca | operações encerradas |
| Files Linux Home | traversal, symlink escape, POSIX, streaming, cancel/rollback, lixeira | launcher Windows + WSL | obrigatório | obrigatório | temp | core/ops encerrados |
| Onboarding | Tab/geometria, 100/125/150%, 1366x768, 500x700 | obrigatório | n/a | obrigatório | temp | n/a |
| Recovery | one-time, hash-only, rate-limit, save/print/copy e arquivo escolhido | obrigatório | n/a | obrigatório | temp | n/a |
| System Center | regressão da linha oficial | não revalidado neste lote | não revalidado neste lote | não | não toca | n/a |

## Gate físico

Nenhuma linha marcada como `físico pendente` pode ser convertida em `aprovado` por CI. O resultado físico deve registrar SHA, ambiente, comandos, logs, screenshots, DB antes/depois e processos antes/depois em `test-results/<area>/<sha>/<execution-id>/`.
