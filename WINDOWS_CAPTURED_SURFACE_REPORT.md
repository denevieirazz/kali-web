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
  -> authorized HWND
  -> captured pixels
  -> CloudOS-owned presentation surface
  -> input/focus/DPI mapping
```

The runtime is fail-closed:

- capture/presentation supported -> present inside CloudOS;
- unsupported/protected/broker-unsafe -> reject with diagnosis;
- never silently spill to an unmanaged Windows desktop window.

The POC does not use cross-process `SetParent` as a universal solution and does not use `--disable-gpu` as a Chromium/Brave fix.

## Historical green baseline

Before the captured-surface branch, the Windows containment branch had a validated green state including Host, WebView2, Playwright, Bootstrap, backend, frontend, E2E, Browser lifecycle, and native Host Browser lifecycle.

The captured-surface branch subsequently added a dedicated `Windows Captured Surface CI` workflow. The pre-lifetime-isolation frozen physical-test head `76c245ff5d78bb2ea1de6586d17a08eb08f5d0c5` passed:

- Windows Captured Surface CI run `33026869987` — SUCCESS;
- CloudOS CI Baseline run `33026870018` — SUCCESS.

## Physical evidence already collected

### Early fixture sizing failures

Earlier WGC attempts exposed `GraphicsCaptureItem.Size = 0x0` for HWND targets. Native DWM/GetWindowRect fallback was added so frame-pool bootstrap no longer depended solely on item metadata.

### D3D/WinRT ABI corrections

The POC corrected two structural boundaries:

1. D3D path now uses `ID3D11Device -> QueryInterface(IDXGIDevice) -> CreateDirect3D11DeviceFromDXGIDevice`.
2. The raw capture item path uses the WinRT activation factory and `IGraphicsCaptureItemInterop` ABI rather than treating `cmd`-style COM signatures as ordinary projected methods.

### Conventional WinForms fixture

The physical fixture was replaced with a conventional visible WinForms overlapped window with animated content, so the test no longer depends on the old `STATIC / WS_POPUP` containment fixture.

### Decisive A/B result at `7f1f561302e6fb24406de6c2e50814391b83e93d`

Same machine, same fixture process, same D3D device path, same WGC frame-pool code:

#### Window target

```text
capture kind: window
verdict: ERROR
stage: capture-session
HRESULT: 0x8007139F / ERROR_NOT_CORRECT_STATE
GraphicsCaptureItem.Size: 0x0
native bootstrap buffer: 642x452
buffer source: pre-wgc-dwm-extended-frame-bounds
frames: 0
```

#### Monitor control

```text
capture kind: monitor
verdict: PASS
frames: 10
size: 2560x1440
empty frames: 0
GraphicsCaptureItem.Size: 2560x1440
initial buffer source: graphics-capture-item
```

This evidence supports the following boundary:

```text
D3D11 hardware device                  HEALTHY
IDXGIDevice -> WinRT IDirect3DDevice   HEALTHY
Direct3D11CaptureFramePool             HEALTHY
GraphicsCaptureSession on monitor      HEALTHY
WGC compositor/frame delivery          HEALTHY
HWND GraphicsCaptureItem/session path  BLOCKED
```

It does **not** prove the reason for the HWND failure.

### Full three-lane matrix at `76c245ff5d78bb2ea1de6586d17a08eb08f5d0c5`

Physical fixture PID: `15864`.

Product gate result:

```text
WINDOW / RAW ACTIVATION FACTORY
ERROR
stage=capture-session
HRESULT=0x8007139F
item=0x0
buffer=642x452
frames=0
```

Legacy projected-factory control:

```text
WINDOW / PROJECTED FACTORY
ERROR
stage=capture-session
HRESULT=0x8007139F
item=0x0
buffer=642x452
frames=0
```

Lower-layer control:

```text
MONITOR / RAW ACTIVATION FACTORY
PASS
frames=10
size=2560x1440
item=2560x1440
```

Therefore changing only raw-vs-projected activation factory did not solve the HWND state.

## Current GitHub-only investigation

Physical PC access is currently unavailable. Work continues only through GitHub and CI.

### Capture item projection and ABI lifetime isolation

The runtime now treats two previously implicit behaviors as explicit variables:

#### Projection

- `GraphicsCaptureItem.FromAbi` (`projected-type-from-abi`)
- `MarshalInterface<GraphicsCaptureItem>.FromAbi` (`marshal-interface-from-abi`)

#### ABI ownership lifetime

- `release-after-projection`
- `hold-until-session-dispose`

The product candidate is deliberately conservative:

```text
raw activation factory
+ MarshalInterface<GraphicsCaptureItem>.FromAbi
+ hold original ABI reference until GraphicsCaptureSession disposal
```

Holding the ABI reference is a COM lifetime guarantee, not an HRESULT fallback. The legacy immediate-release behavior remains an explicit control lane.

### Five-lane future physical matrix

A single future physical run executes all lanes even if the product candidate fails:

1. `window / raw / marshal-interface / hold` — PRODUCT CANDIDATE;
2. `window / raw / marshal-interface / release` — lifetime control;
3. `window / raw / projected-type / hold` — projection control;
4. `window / projected-factory / marshal-interface / hold` — factory control;
5. `monitor / raw / marshal-interface / hold` — lower-layer control.

The summary automatically classifies:

- lifetime suspect;
- projection suspect;
- factory suspect;
- lower-layer health;
- all-window-lanes-failed.

### HWND diagnostics

Every C# probe report now records, before WGC setup:

- exact HWND;
- title and class name;
- window rectangle;
- visible/iconic/hung state;
- DWM cloak state;
- style and extended style;
- owner and root-owner HWND;
- nearest HMONITOR;
- thread/process IDs;
- DPI;
- display-affinity state when queryable.

This prevents a future `0x8007139F` from being interpreted without knowing whether the HWND was minimized, cloaked, protected, owned, or otherwise unusual.

## Native C++/WinRT reference probe

`desktop/CloudOS.WindowsCapture.NativeReference` is an intentionally independent reference implementation.

It mirrors the Microsoft C++/WinRT pattern:

```text
get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()
  -> CreateForWindow(HWND, IID_IGraphicsCaptureItem, put_abi(item))
  -> GraphicsCaptureItem.Size / DisplayName
```

It shares no CsWinRT projection, C# COM marshaling, TerraFX binding, or D3D frame-pool code with the product probe.

Future interpretation:

- native C++ item valid, C# item invalid -> C#/projection/lifetime boundary;
- native C++ item also `0x0` -> Windows/session/target configuration becomes the primary suspect;
- native C++ `CreateForWindow` fails directly -> OS/API/policy/target eligibility issue before the C# layer.

The native probe is compile/CLI validated in GitHub Actions; its physical HWND result remains pending.

## CI contract

`Windows Captured Surface CI` validates on `windows-2022`:

- .NET capture runtime/probe build;
- C# CLI contract including factory/projection/lifetime selectors;
- missing-argument exit contract;
- complete PowerShell five-lane matrix parse/contract;
- conventional WinForms fixture build;
- native C++/WinRT reference build;
- native reference CLI contract.

CI compilation is not considered proof that physical WGC HWND capture works.

## External API constraints confirmed

`IGraphicsCaptureItemInterop::CreateForWindow` remains the correct desktop interop API for HWND capture and is supported from Windows 10 1903.

`GraphicsCaptureItem.TryCreateFromWindowId` is not being used as an unpackaged fallback because Microsoft documents that its programmatic path requires `GraphicsCaptureAccess.RequestAccessAsync(Programmatic)` and the `graphicsCaptureProgrammatic` package capability.

## Gates intentionally deferred until physical access returns

1. Run the five-lane HWND item lifetime/projection matrix.
2. Run the native C++/WinRT HWND metadata reference on the exact same HWND.
3. Prove capture on a normal installed Win32 app.
4. Prove capture on Chromium/Brave with GPU enabled.
5. Add GPU frame-health sampling to detect gray/static output.
6. Implement/prove CloudOS-owned native presentation surface.
7. Prove input, focus, DPI, resize, minimize/maximize, and multi-window behavior.
8. Prove source HWND quarantine with no unwanted Windows desktop/Alt+Tab exposure.
9. Integrate the proven surface into `native.session.*` lifecycle.
10. Prove generic installed-app discovery/live refresh.
11. Produce a compatibility matrix with explicit fail-closed statuses.

## Current verdict

**POC STATUS: BLOCKED ON PHYSICAL HWND WGC QUALIFICATION, NOT BLOCKED ON CI.**

The lower WGC/D3D path is physically proven through monitor capture. The remaining physical blocker is specific to window-target capture item/session state. GitHub-only work is focused on making the next physical run decisive rather than iterative.
