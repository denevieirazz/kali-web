# Windows Captured Surface — Evidence Report

## Scope

Branch: `poc/cloudos-windows-captured-surface`

Base: `poc/cloudos-windows-contained-runtime` at `d4b497fd232ad1341e642d03711ae2ec3f7b36fe`.

PR: #15, kept **DRAFT / DO NOT MERGE** until physical and UX gates are complete.

Goal: replace the previous Windows `anchored-overlay` presentation with a generic captured-surface runtime for compatible Windows applications. No app-specific Brave/Chrome/Electron adapter is allowed as the architectural solution.

## Product contract

For an authorized Windows app launch:

```text
CloudOS catalog/session
  -> contained/correlated Windows process
  -> authorized same-session HWND
  -> Windows.Graphics.Capture + D3D11
  -> CloudOS-owned presentation surface
  -> input/focus/DPI/lifecycle mediation
```

The runtime is fail-closed:

- capture/presentation supported -> present inside CloudOS;
- unsupported/protected/broker/singleton/capture failure -> reject with diagnosis;
- never silently spill to an unmanaged Windows desktop window.

The POC does not use cross-process `SetParent` as a universal solution and does not use `--disable-gpu` as a Chromium/Brave fix.

## Physically proven lower-layer boundary

A conventional visible animated WinForms fixture was tested on the physical Windows development machine.

### HWND target

Both raw activation-factory and projected-factory paths reached a real same-PID HWND with valid native bounds, but produced:

```text
GraphicsCaptureItem.Size = 0x0
native bootstrap buffer = 642x452
CreateCaptureSession(item) = 0x8007139F / ERROR_NOT_CORRECT_STATE
frames = 0
```

### HMONITOR lower-layer control

Using the same machine and the same D3D/frame-pool stack:

```text
verdict = PASS
frames = 10
size = 2560x1440
GraphicsCaptureItem.Size = 2560x1440
empty frames = 0
```

Therefore the evidence currently supports:

```text
D3D11 hardware device                  HEALTHY
IDXGIDevice -> WinRT IDirect3DDevice   HEALTHY
Direct3D11CaptureFramePool             HEALTHY
GraphicsCaptureSession on monitor      HEALTHY
WGC compositor/frame delivery          HEALTHY
HWND GraphicsCaptureItem/session path  BLOCKED / NOT YET QUALIFIED
```

This does **not** prove the reason for the HWND failure.

## Current C# item isolation

The capture runtime treats three previously implicit choices as explicit diagnostic dimensions.

### Activation factory

- raw WinRT activation factory / ABI;
- projected factory control.

### Projection

- `GraphicsCaptureItem.FromAbi`;
- `MarshalInterface<GraphicsCaptureItem>.FromAbi`.

### ABI lifetime

- release original ABI reference after projection;
- hold the original ABI reference until capture-session disposal.

Current product candidate:

```text
raw activation factory
+ MarshalInterface<GraphicsCaptureItem>.FromAbi
+ hold original ABI reference until session disposal
```

The ABI pointer uses single-owner semantics so failure paths cannot double-release the same reference.

## Physical fixture matrix — schema v3

`scripts/test-windows-capture-probe.ps1` now runs one fixture and deliberately isolates five C# lanes:

1. `window / raw / marshal-interface / hold` — **PRODUCT CANDIDATE**;
2. `window / raw / marshal-interface / release` — lifetime control;
3. `window / raw / projected-type / hold` — projection control;
4. `window / projected-factory / marshal-interface / hold` — factory control;
5. `monitor / raw / marshal-interface / hold` — lower-layer control.

All lanes execute even if the product candidate fails. Only lane 1 may approve the product gate.

The summary records:

- `lifetimeSuspect`;
- `projectionSuspect`;
- `factorySuspect`;
- `lowerLayerHealthy`;
- `allWindowLanesFailed`;
- `csharpProductItemHealthy`.

## HWND state diagnostics

Before WGC setup, the C# probe records the exact target state:

- HWND, title, class and rectangle;
- visible/iconic/hung state;
- DWM cloak state;
- style/exstyle;
- owner/root-owner;
- nearest HMONITOR;
- thread/PID;
- DPI;
- display affinity when queryable.

This prevents a future `0x8007139F` from being interpreted without knowing whether the target was minimized, cloaked, protected, owned, or otherwise unusual.

## Independent native C++/WinRT reference

`desktop/CloudOS.WindowsCapture.NativeReference` intentionally shares no CsWinRT C# projection, C# COM marshaling, TerraFX D3D binding, or product frame-pool code.

It mirrors the desktop C++/WinRT pattern:

```text
get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()
  -> CreateForWindow(HWND, IID_IGraphicsCaptureItem, put_abi(item))
  -> GraphicsCaptureItem.Size / DisplayName
```

The executable now emits machine-readable JSON both on success and diagnostic failure:

```text
schemaVersion
verdict
stage
hwnd
itemWidth
itemHeight
displayName
hresult
message
```

The physical fixture matrix uses the exact HWND chosen by the C# probe and, when the local MSBuild/C++ toolchain is available, runs the native reference against that same HWND.

If the C++ toolchain is absent, the matrix records `NOT_AVAILABLE`; this never becomes a product PASS or product fallback.

The schema-v3 interpretation additionally records:

- `nativeReferenceAvailable`;
- `nativeReferenceProducedReport`;
- `nativeItemHealthy`;
- `nativeDisagreesWithCsharpItemMetadata`;
- `nativeAndCsharpBothReportUnusableWindowItem`;
- `nativeHealthyWhileCsharpWindowFails`.

Interpretation remains evidence-driven:

- native item valid while C# item metadata is invalid -> strong C#/projection/lifetime suspect;
- native item also unusable -> Windows/session/target eligibility becomes a stronger suspect;
- native `CreateForWindow` HRESULT failure -> failure exists below the C# product projection.

The native reference does not by itself prove full frame delivery; it is an independent item-creation/metadata control.

## Native CI contract

`Windows Captured Surface CI` validates on `windows-2022`:

- .NET capture runtime/probe build;
- C# CLI factory/projection/lifetime selectors;
- missing-argument exit contract;
- complete physical matrix PowerShell parse/contract;
- conventional WinForms fixture build;
- x64 C++/WinRT reference build;
- native reference CLI contract;
- native JSON failure contract by intentionally passing invalid HWND `0x1` and requiring:
  - exit code `3`;
  - JSON report present;
  - `verdict=ERROR`;
  - `stage=target-validation`;
  - zero item dimensions.

CI compilation and invalid-target contract tests are not physical proof that HWND WGC capture works.

## Generic installed-app qualification harness

`scripts/test-windows-capture-app.ps1` prepares the next physical gate without app-specific code.

It accepts an arbitrary executable path/command plus arguments and:

1. validates exact branch and expected HEAD;
2. resolves the executable without shell evaluation;
3. starts it with `ProcessStartInfo` + `ArgumentList` and `UseShellExecute=false`;
4. requires a visible top-level readiness window from the launched PID;
5. rejects launcher handoff/singleton/broker behavior when the launched PID exits before publishing its own window;
6. runs the same product candidate `window/raw/marshal-interface/hold`;
7. runs the native C++/WinRT reference on the exact C#-selected HWND when the C++ toolchain is available;
8. writes a single qualification summary and log;
9. terminates only the process launched for qualification unless explicitly asked to leave it running.

Current capture-only classifications:

```text
CAPTURE_SUPPORTED
CAPTURE_BLOCKED
RENDER_FAILED
BROKER_OR_SINGLETON_UNSAFE
```

`CAPTURE_SUPPORTED` means the capture-only product candidate delivered the required frames. It does not yet mean input, CloudOS presentation, Alt+Tab isolation, or complete product compatibility is proven.

The dedicated CI statically validates the generic harness security contract:

- `ArgumentList` is required;
- `UseShellExecute=false` is required;
- `cmd.exe` is forbidden;
- shell fallback is forbidden;
- same-PID qualification and fail-closed classifications must remain present.

## Current CI evidence before the next documentation-only head

The code/harness state at `e88f393cf2b740adf79d1fde8f43ef1e7ba8e89b` passed `Windows Captured Surface CI` run `33059026098` (#49), including the generic harness contract and native JSON contract.

The complete CloudOS baseline for that code state is tracked separately by its exact SHA/run and must be `success` before that SHA is called fully green.

## External API constraints confirmed

`IGraphicsCaptureItemInterop::CreateForWindow` remains the supported desktop interop API for a top-level HWND target on Windows 10 1903+.

The independent native implementation follows the Microsoft C++/WinRT activation-factory pattern. No public issue was found that safely explains the exact physical `Size=0x0` plus `CreateCaptureSession=0x8007139F` symptom, so the project does not label it an OS regression without physical native-reference evidence.

`GraphicsCaptureItem.TryCreateFromWindowId` is not used as an unpackaged fallback because its programmatic access path carries different capability/consent requirements and would not be a clean comparison for this POC.

## Gates intentionally deferred until physical access returns

1. Run the schema-v3 five-lane C# matrix plus native C++ reference on the fixture in one command.
2. If HWND candidate passes, qualify a normal real Win32 app through the generic app harness.
3. Qualify Chromium/Brave with GPU enabled, without per-app adapter and without `--disable-gpu`.
4. Add bounded GPU frame-health sampling to detect gray/static output.
5. Implement/prove a CloudOS-owned presentation surface.
6. Prove input, focus, DPI, resize, minimize/maximize and multi-window behavior.
7. Prove source-HWND quarantine with no unwanted Windows desktop/Alt+Tab exposure.
8. Integrate the proven captured surface into `native.session.*` lifecycle.
9. Prove generic installed-app discovery/live refresh.
10. Produce the final compatibility matrix with explicit fail-closed statuses.

## Current verdict

**POC STATUS: GITHUB/CI TOOLING ADVANCED; PHYSICAL HWND WGC QUALIFICATION STILL REQUIRED.**

The lower WGC/D3D path is physically proven through monitor capture. The remaining physical blocker is window-target item/session qualification. GitHub-only work has converted the next physical session from iterative debugging into one evidence-producing fixture matrix followed by one generic real-app harness.
