# CloudOS PR #16 — Physical Windows Runtime Matrix State

PRODUCT_TESTED_SHA=ad9639f1ce8d808d2d532404fd9ca6673244052e
PR=16
PR_BRANCH=fix/cloudos-runtime-launch-rebind
EVIDENCE_BRANCH=evidence/pr16-physical-ad9639f
CURRENT_PHASE=PHYSICAL_MATRIX_EVALUATED
LAST_COMPLETED_CASE=WIN32_AND_CHROMIUM_PHYSICAL_CASES
NEXT_CASE=FINAL_EVIDENCE_RECORDING
TOTAL_RUNS=4
PASS=1
FAIL=1
EXPECTED_FAIL_CLOSED=2
EXTERNAL_WINDOW_LEAK=YES
ORPHAN_PROCESS=NO
CROSS_JOB_ADOPTION=NO
PHYSICAL_RUNTIME_GATE=FAIL
LAST_EVIDENCE_COMMIT=PENDING_CHECKPOINT
LAST_PUSH_STATUS=IN_PROGRESS
LAST_PUSH_TIME=2026-08-28T12:35:44Z

## Physical Execution Findings on SHA ad9639f1ce8d808d2d532404fd9ca6673244052e

1. **Brave (Chromium / Browser)**:
   - Verdict: PASS
   - Comportamento: Abriu perfeitamente contido dentro da janela do CloudOS.
   - External window leak: NO
   - Alt+Tab leak: NO

2. **Windows Start Menu Brokered Apps (Mapa de Caracteres, Limpeza de Disco, Clima)**:
   - Verdict: PASS_EXPECTED_FAIL_CLOSED
   - Comportamento: O catálogo detectou que o aplicativo usa broker do Windows/UWP e impediu a abertura desgovernada com modal de segurança ("Aplicativo protegido pela contenção").
   - External window leak: NO
   - Alt+Tab leak: NO

3. **Telegram (Win32 Standalone / Qt)**:
   - Verdict: FAIL
   - Comportamento: Processo (PID 14448) abriu solto no desktop do Windows (InJob: false, OwnedByHost: false) e apareceu na lista de Alt+Tab do Windows.
   - External window leak: YES
   - Alt+Tab leak: YES

4. **Instalação de Pacotes**:
   - Observação do usuário: Instalação de novos aplicativos externos no CloudOS não está habilitada/funcional no runtime atual.

## Physical Runtime Gate Verdict

PHYSICAL_RUNTIME_GATE=FAIL (Devido ao vazamento externo de top-level window/Alt+Tab em aplicativos Win32 standalone como Telegram; o candidate fail-closed de apps brokerizados e Chromium contido funcionaram conforme o esperado).
