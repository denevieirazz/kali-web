# Performance and visual V12: audit and architecture

Base: `work/shell-supervisor-v11` at `8a961ecb592c8e7b84c80689f41f4a9ae1a59eb3`, confirmed with origin before edits.

The complete pre-edit call-site inventory is preserved in `outputs/cloudos-v12/audit-call-sites.txt` in the local validation output. The active build graph, not obsolete implementations, determines the changes.

| Owner | Before | V12 policy |
| --- | --- | --- |
| Main/Desktop reconcile | 1000 ms: enumeration, monitor signature, recovery and full refresh | Runtime window events update model; coalesced view notification; display messages rebuild monitors; 30 s dirty recovery fallback only |
| Desktop metrics | 1000 ms plus Query in Paint | Optional widgets off by default; worker sample only when enabled, invalidate widget region |
| Desktop files/icons/wallpaper | filesystem, Shell and registry/image decode in Paint | Directory notification worker + immutable snapshot; async shared icon cache; wallpaper prepared outside Paint |
| Taskbar | 1000 ms reload/rebuild/full invalidation, rebuild in Paint | Model update on real change; minute clock invalidation; separate cached rendering |
| Start index | 750 ms even while hidden | No polling timer; worker publication refreshes visible results |
| Quick Settings | 1800 ms synchronous audio/mixer/brightness/WLAN scans | Visible-only cached UI; worker refresh; slow radio cadence; advanced controls collapsed |
| Control plane | 5000 ms heavy synchronous queries | 30 s worker health refresh; request coalescing; alerts posted on UI thread |
| Tray attach | 1800 ms persistent attach/refresh | Explicit attachment on taskbar creation; invalidate only tray bounds on data changes |
| Workspace Studio / Continuity | 850 / 2000 ms enumeration from automation and checkpoint services | Studio receives coalesced model events; Continuity observes revisions and keeps only a 5 s pending-checkpoint deadline check |
| Health V9/Lifecycle V10/Supervisor V11 | Heartbeat and recovery contracts | Preserve; heartbeat is not a paint trigger |
| Hover/toast/overview/application timers | Interaction, transient visibility, optional application telemetry | Retain where needed; no 8 ms animation cadence; hidden shell surfaces do no work |

Sources researched before implementation:

- Microsoft Learn: [directory notifications](https://learn.microsoft.com/en-us/windows/win32/fileio/obtaining-directory-change-notifications), [asynchronous I/O lifetime](https://learn.microsoft.com/en-us/windows/win32/fileio/synchronous-and-asynchronous-i-o).
- Microsoft Learn: [SetWinEventHook](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook), [SHGetFileInfoW](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetfileinfow), [CreateCompatibleDC](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-createcompatibledc), [named shared memory](https://learn.microsoft.com/en-us/windows/win32/memory/creating-named-shared-memory).
- Microsoft Windows classic samples were consulted as the mature native reference. Repository license: MIT; no sample code or proprietary assets copied. Implementation uses documented APIs and original code.

Workers prepare data and post messages; only the UI thread owns HWND rendering. Cache entries own their HICON and retain shared ownership through a draw. Directory watches cancel overlapped I/O and drain completion before freeing buffers. Per-HWND backbuffers are destroyed on NCDESTROY and replaced on resize/DPI change. Telemetry stores numeric counts/timing only in a process-scoped local mapping; no paths, titles, SSIDs or file names.

Fallbacks: failed directory watch exposes an explicit refresh path, failed icon loading leaves a native placeholder, unavailable DWM materials use a solid neutral surface. Existing Windows top-level windows remain top-level; no reparenting or browser shell is introduced.

Additional SDK validation during integration:

- [SetWindowSubclass](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-setwindowsubclass): subclasses stay on the owning UI thread and are removed on NCDESTROY.
- [TBM_GETTHUMBRECT](https://learn.microsoft.com/en-us/windows/win32/controls/tbm-getthumbrect) and [CB_GETLBTEXT](https://learn.microsoft.com/en-us/windows/win32/controls/cb-getlbtext): preserve real common-control input/accessibility; get text length before allocating its buffer. No third-party control code copied.
- [Graphics::DrawImage](https://learn.microsoft.com/en-us/windows/win32/api/gdiplusgraphics/nf-gdiplusgraphics-graphics-drawimage(image_constrect__int_int_int_int_unit_constimageattributes_drawimageabort_void)): wallpaper decoding/scaling runs on an owned worker, publishes a prepared bitmap and paints matching pixel rectangles. Compressed artwork is decoded once per change, outside Paint.

The first instrumented soak intentionally failed: it found 202 background reconciliations in Studio/Continuity even after the main timer was removed. Those call paths are now covered explicitly by the V12 contract. The baseline V11 binary has no per-surface numeric counters; missing baseline paint/I/O timings are not estimated. V12 counters cover shell surfaces, not all first-party application windows. Cold first paint includes GDI/font warm-up; show-to-first-paint is not compositor presentation latency.
