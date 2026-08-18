# HUMAN_SIMULATION_REPORT.md

## CloudOS Workflow — Human User Simulation v2

**Branch:** `stabilization/cloudos-workflow-batch-4`  
**Commit executado:** `b1ac3e9de910edf7d252f8e4d964926aec9f2b2a`  
**Resultado:** 4 missão(ões) FALHOU

> Execução Playwright real contra frontend compilado + backend temporário CloudOS. Operações funcionais são UI/teclado; CDP/page.evaluate são usados somente para telemetria.

| Missão | Status | Duração |
|---|---|---:|
| 1. MISSÃO 1 | **FALHOU** | 0.0 s |
| 2. MISSÃO 2 | **FALHOU** | 0.0 s |
| 3. MISSÃO 3 | **FALHOU** | 0.0 s |
| 4. MISSÃO 4 | **FALHOU** | 0.0 s |
| 5. LONG SESSION | **PASSOU** | 230.6 s |
| 6. STRESS — 100 Workspaces / 500 / 1000 Notes | **ALERTA** | 581.6 s |

## Missão 1 — MISSÃO 1

**FALHOU**


```text
A missão terminou sem produzir resultado (timeout/crash/aborto do runner).
```

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

## Missão 5 — LONG SESSION

**PASSOU**

- Horizontes 1h/2h/4h/8h simulados por 150/300/600/1200 operações determinísticas com snapshots de heap/listeners/timers/observers/localStorage.

Screenshot: `test-results/human-simulation/screenshots/mission-5-pass.png`

## Missão 6 — STRESS — 100 Workspaces / 500 / 1000 Notes

**ALERTA**

- 100 Workspaces criados pela UI e todos preservados no catálogo visual.
- 500 e 1000 Notes alcançadas pela UI; busca de conteúdo, troca, edição e export ZIP executados.
- **ALERTA:** Heap após stress >8x baseline: 4.9 MiB → 61.4 MiB.

Screenshot: `test-results/human-simulation/screenshots/mission-6-pass.png`

## Telemetria

| Missão/Ponto | Heap | DOM nodes | JS listeners | localStorage | timers | intervals | ResizeObserver | MutationObserver | janelas |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 5/baseline | 4.8 MiB | 714 | 218 | 108.6 KiB | 3 | 5 | 1 | 2 | 3 |
| 5/1h | 5.7 MiB | 714 | 218 | 108.6 KiB | 0 | 5 | 1 | 2 | 3 |
| 5/2h | 5.9 MiB | 714 | 218 | 108.6 KiB | 0 | 5 | 1 | 2 | 3 |
| 5/4h | 6.3 MiB | 714 | 218 | 108.6 KiB | 0 | 5 | 1 | 2 | 3 |
| 5/8h | 6.5 MiB | 714 | 218 | 108.6 KiB | 0 | 5 | 1 | 2 | 3 |
| 6/start | 4.9 MiB | 714 | 218 | 108.6 KiB | 3 | 5 | 1 | 2 | 3 |
| 6/100-workspaces | 6.8 MiB | 1803 | 317 | 150.1 KiB | 0 | 5 | 1 | 2 | 3 |
| 6/500-notes | 33.6 MiB | 6280 | 1441 | 187.1 KiB | 0 | 5 | 1 | 2 | 3 |
| 6/1000-notes | 61.7 MiB | 10786 | 2442 | 187.1 KiB | 0 | 5 | 1 | 2 | 3 |
| 6/after-export | 61.4 MiB | 10804 | 1322 | 187.1 KiB | 0 | 5 | 1 | 2 | 3 |