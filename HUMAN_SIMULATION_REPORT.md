# HUMAN_SIMULATION_REPORT.md

## CloudOS Workflow — Human User Simulation v2

**Branch:** `stabilization/cloudos-workflow-batch-4`  
**Commit executado:** `b13297411f2ef333438ae618a90b8e3b9a31bdcf`  
**Resultado:** 6 missão(ões) FALHOU

> Execução Playwright real contra frontend compilado + backend temporário CloudOS. Operações funcionais são UI/teclado; CDP/page.evaluate são usados somente para telemetria.

| Missão | Status | Duração |
|---|---|---:|
| 1. CLIENTE NOVO | **FALHOU** | 14.2 s |
| 2. MISSÃO 2 | **FALHOU** | 0.0 s |
| 3. MISSÃO 3 | **FALHOU** | 0.0 s |
| 4. MISSÃO 4 | **FALHOU** | 0.0 s |
| 5. MISSÃO 5 | **FALHOU** | 0.0 s |
| 6. MISSÃO 6 | **FALHOU** | 0.0 s |

## Missão 1 — CLIENTE NOVO

**FALHOU**

- Workspace criado pela UI.
- Note criada, salva e editada.
- Evidence criada.
- Export ZIP real: Cliente Humano 001.cloudos-workspace.zip.

```text
locator.click: Timeout 12000ms exceeded.
Call log:
[2m  - waiting for locator('.window:has(.workflow-workspace)').last().locator('button.window-btn.close')[22m
[2m    - locator resolved to <button title="Fechar" class="window-btn close">…</button>[22m
[2m  - attempting click action[22m
[2m    2 × waiting for element to be visible, enabled and stable[22m
[2m      - element is visible, enabled and stable[22m
[2m      - scrolling into view if needed[22m
[2m      - done scrolling[22m
[2m      - <div class="wb4-context-grid">…</div> from <aside class="wb4-context" aria-label="Contexto do projeto ativo">…</aside> subtree intercepts pointer events[22m
[2m    - retrying click action[22m
[2m    - waiting 20ms[22m
[2m    2 × waiting for element to be visible, enabled and stable[22m
[2m      - element is visible, enabled and stable[22m
[2m      - scrolling into view if needed[22m
[2m      - done scrolling[22m
[2m      - <div class="wb4-context-grid">…</div> from <aside class="wb4-context" aria-label="Contexto do projeto ativo">…</aside> subtree intercepts pointer events[22m
[2m    - retrying click action[22m
[2m      - waiting 100ms[22m
[2m    23 × waiting for element to be visible, enabled and stable[22m
[2m       - element is visible, enabled and stable[22m
[2m       - scrolling into view if needed[22m
[2m       - done scrolling[22m
[2m       - <div class="wb4-context-grid">…</div> from <aside class="wb4-context" aria-label="Contexto do projeto ativo">…</aside> subtree intercepts pointer events[22m
[2m     - retrying click action[22m
[2m       - waiting 500ms[22m

    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation-v2.spec.ts:305:104
    at runMission (/home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation-v2.spec.ts:225:5)
    at /home/runner/work/kali-web/kali-web/tests/playwright/workflow-human-simulation-v2.spec.ts:283:5
```

Screenshot: `test-results/human-simulation/screenshots/mission-1-failure.png`

## Missão 2 — MISSÃO 2

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

## Missão 3 — MISSÃO 3

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

## Missão 4 — MISSÃO 4

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

## Missão 5 — MISSÃO 5

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

## Missão 6 — MISSÃO 6

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

## Telemetria

| Missão/Ponto | Heap | DOM nodes | JS listeners | localStorage | timers | intervals | ResizeObserver | MutationObserver | janelas |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|