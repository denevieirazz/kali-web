# Relatorio de Validacao Fisica - CloudOS Windows Captured Surface

## Identificacao da Execucao
- Data: 27 de Agosto de 2026
- Branch: poc/cloudos-windows-captured-surface
- HEAD SHA: a790461d4246516e508133781ac7709f519b7718
- Ambiente: Windows 10.0.28000 (win-x64), PowerShell 7.6.5, .NET SDK 8.0.424 (.NET 8.0.30)
- Status Geral da Fundacao Fisica: NOT_READY (WGC Window Candidate bloqueado; Monitor Control 100% PASS)

---

## 1. Sumario Executivo das Fronteiras

| Fronteira / Gate | Alvo / Metodo | Verdict | Exit Code | Frames | HRESULT / Detalhes |
|---|---|---|---|---|---|
| **WGC Window Product Candidate** | HWND / RawActivationFactory / MarshalInterface / Hold | **ERROR** | 1 | 0 | 0x8007139F (ERROR_NOT_CORRECT_STATE) em CreateCaptureSession |
| **WGC Window Lifetime Control** | HWND / RawActivationFactory / MarshalInterface / Release | **ERROR** | 1 | 0 | 0x8007139F em CreateCaptureSession |
| **WGC Window Projection Control** | HWND / RawActivationFactory / ProjectedType / Hold | **ERROR** | 1 | 0 | 0x8007139F em CreateCaptureSession |
| **WGC Window Factory Control** | HWND / ProjectedFactory / MarshalInterface / Hold | **ERROR** | 1 | 0 | 0x8007139F em CreateCaptureSession |
| **WGC Monitor Lower-Layer Control** | HMONITOR (0x207A9) / RawActivationFactory | **PASS** | 0 | 10 (2560x1440) | S_OK (Direct3D11 FramePool e WGC saudaveis a 60fps) |
| **Host-Owned Presenter** | HWND / D3D11 presentation | **ERROR** | 1 | 0 | Falhou em CreateCaptureSession para o HWND (0x8007139F) |
| **Targeted Input Injection** | Win32 Non-Global Injection | **FAIL** | 2 | N/A | Rejeitou cliques/teclas; Replay e Stale Generation foram rejeitados |
| **Source Isolation** | Hidden / Cloaked / Minimized | **SKIPPED** | N/A | N/A | Ignorado porque o candidato de janela visivel nao passou |

---

## 2. Diagnostico Tecnico

1. Lower-Layer (GPU / D3D11 / WGC Engine): SAUDAVEL
   - O teste de controle com monitor (HMONITOR 0x207A9) obteve um GraphicsCaptureItem valido de 2560x1440 e capturou os 10 frames solicitados com sucesso via Direct3D11CaptureFramePool.
   - Isso prova que Direct3D11, DXGI, driver de video e o servico WGC do sistema operacional estao ativos e operantes.

2. Window Capture Candidate (HWND): BLOQUEADO EM CreateCaptureSession
   - Em todas as combinacoes avaliadas (Raw Activation Factory, Projected Factory, MarshalInterface, Projected Type, Hold e Release), o GraphicsCaptureItem criado a partir do HWND convencional (WinForms animado / PID 6748 / HWND 0x140986) gerou COMException 0x8007139F (ERROR_NOT_CORRECT_STATE) ao chamar CreateCaptureSession.

---

## 3. Arquivos de Evidencia Fisicos Anexados

- poc1-physical-evidence/windows-captured-surface/physical-finalization-summary.json
- poc1-physical-evidence/windows-captured-surface/fixture-wgc-matrix-summary.json
- poc1-physical-evidence/windows-captured-surface/fixture-window-product-candidate.json
- poc1-physical-evidence/windows-captured-surface/fixture-window-release-control.json
- poc1-physical-evidence/windows-captured-surface/fixture-window-projected-type-control.json
- poc1-physical-evidence/windows-captured-surface/fixture-window-projected-factory-control.json
- poc1-physical-evidence/windows-captured-surface/fixture-monitor-lower-layer-control.json
- poc1-physical-evidence/windows-captured-surface/fixture-presenter-smoke.json
- poc1-physical-evidence/windows-captured-surface/input/fixture-targeted-input.json
- poc1-physical-evidence/windows-captured-surface/fixture-wgc-smoke.log
