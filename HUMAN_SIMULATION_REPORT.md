# HUMAN_SIMULATION_REPORT.md

## CloudOS Workflow — Human User Simulation

**Branch:** `stabilization/cloudos-workflow-batch-4`  
**Commit executado:** `b2d152ce1c492930d86c820d1f4305eb381eeeb0`  
**Início:** 2026-08-18T14:46:13.094Z  
**Fim:** 2026-08-18T15:21:16.152Z  
**Resultado:** 6 missão(ões) FALHOU

> Esta suíte usa Playwright contra o frontend compilado servido pelo backend CloudOS temporário. As operações funcionais são executadas pela UI e por teclado real do browser automation. Apenas telemetria é coletada por CDP/page.evaluate.

## Resumo

| Missão | Status | Duração |
|---|---|---:|
| 1. CLIENTE NOVO | **FALHOU** | 0.8 s |
| 2. DIA DE TRABALHO | **FALHOU** | 2096.8 s |
| 3. FILES | **FALHOU** | 0.0 s |
| 4. TERMINAL | **FALHOU** | 0.0 s |
| 5. LONG SESSION | **FALHOU** | 0.0 s |
| 6. STRESS — 100 Workspaces / 500 / 1000 Notes | **FALHOU** | 0.0 s |

## Missão 1 — CLIENTE NOVO

**FALHOU**


```text
locator.fill: Error: strict mode violation: locator('.ww-modal').last().getByLabel('Cliente') resolved to 2 elements:
    1) <select>…</select> aka getByLabel('TipoClienteProjetoTicketLaboratórioPersonalizado')
    2) <input value=""/> aka getByRole('textbox', { name: 'Cliente' })

Call log:
[2m  - waiting for locator('.ww-modal').last().getByLabel('Cliente')[22m

    at createWorkspaceViaUI (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:188:37)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:333:7
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:331:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-1-failure.png`

## Missão 2 — DIA DE TRABALHO

**FALHOU**


```text
locator.click: Test timeout of 2100000ms exceeded.
Call log:
[2m  - waiting for locator('.workflow-workspace').last().locator('.ww-tabs').getByRole('button', { name: 'Evidence', exact: true })[22m

    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:404:131
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:384:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-2-failure.png`

## Missão 3 — FILES

**FALHOU**


```text
keyboard.press: Target page, context or browser has been closed
    at ensureWorkspace (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:154:23)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:420:7
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:419:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-3-failure.png`

## Missão 4 — TERMINAL

**FALHOU**


```text
keyboard.press: Target page, context or browser has been closed
    at ensureTerminal (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:177:23)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:469:24
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:468:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-4-failure.png`

## Missão 5 — LONG SESSION

**FALHOU**


```text
page.evaluate: Target page, context or browser has been closed
    at snapshotRuntime (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:231:30)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:498:22
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:497:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-5-failure.png`

## Missão 6 — STRESS — 100 Workspaces / 500 / 1000 Notes

**FALHOU**


```text
keyboard.press: Target page, context or browser has been closed
    at ensureWorkspace (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:154:23)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:539:25
    at mission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:319:9)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation.spec.ts:538:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-6-failure.png`

## Telemetria de sessão longa

| Ponto | Heap usada | Heap total | DOM nodes | JS listeners | localStorage | timers | intervals | ResizeObserver | MutationObserver | janelas |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|

## Critério

- **PASSOU:** fluxo concluído e invariantes funcionais preservadas.
- **ALERTA:** fluxo concluiu, mas foi observado comportamento de escala/stale/pressão que merece revisão.
- **FALHOU:** operação real não concluiu, perdeu persistência/integridade ou gerou exceção impeditiva.
