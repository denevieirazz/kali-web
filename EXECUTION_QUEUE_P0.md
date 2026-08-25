# EXECUTION_QUEUE_P0.md — Fila de Prioridade P0 (Integridade Crítica de CI e Gates)

## EF2-P0-001 — Garantir que workflows de PR testem o SHA/ref correto

- **Status:** **CONCLUÍDA**
- **Objetivo:**
  1. Mapear todos os workflows disparados por `pull_request` ou `push`.
  2. Identificar qual revisão cada workflow deveria testar e qual testa atualmente.
  3. Corrigir primeiro `workflow-drone-ci.yml` e `workflow-batch4-stabilization-ci.yml`.
  4. Registrar `testedSha`, `headSha`, `baseSha`, `mergeSha`, `ref` e `event_name` nos relatórios e nos artefatos.
  5. Criar gate determinístico que detecte e falhe em caso de mismatch entre o SHA esperado do commit e o SHA executado pelo checkout.
  6. Preservar o conteúdo funcional do Drone e da Human Simulation.
- **Validação Mínima:**
  - `git diff --check`
  - Inspeção e validação de schema dos YAML
  - Comparação explícita entre `git rev-parse HEAD` e os SHAs do evento de CI
- **Critério de Parada:** Parar imediatamente após concluir e validar a EF2-P0-001. Não avançar para EF2-P0-002.

---

## EF2-P0-002 — Eliminar mutação do spec da Human Simulation no CI

- **Status:** **CONCLUÍDA**
- **Dependência:** EF2-P0-001

---

## EF2-P0-003 — Gate de fail-closed para mismatch de SHA em PRs

- **Status:** **CONCLUÍDA**
- **Dependência:** EF2-P0-001, EF2-P0-002

---

## EF2-P0-004 — Auditoria de retenção e nomeação determinística de artifacts

- **Status:** **CONCLUÍDA**
- **Dependência:** EF2-P0-003
