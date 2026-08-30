# Native reliability and recovery research — 2026-08-30

Problem: V7's textual contract blocked compilation; the first runtime then became
unresponsive while its floating-dock region was reapplied by a WinEvent callback.
The current native path also needs recovery that does not load CloudOS.exe, its
runtime DLL, WebView2, or the legacy React Bootstrap.

Sources consulted:

- [SetWindowRgn](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowrgn): changes send window-position messages; USER owns a successfully assigned region. Compare GetWindowRgn/EqualRgn before mutating.
- [WTS registration](https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtsregistersessionnotification): registration may fail before Terminal Services is ready; retry without waiting on the UI thread, and balance successful registrations with unregister.
- [Automatic resume](https://learn.microsoft.com/en-us/windows/win32/power/pbt-apmresumeautomatic): refresh after resume without assuming user interaction or forcing foreground focus.
- [Process image identity](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew): query the opened process handle, not just a filename or PID.
- [TaskDialogIndirect](https://learn.microsoft.com/en-us/windows/win32/api/commctrl/nf-commctrl-taskdialogindirect): native command links, cancel handling and accessibility through common controls.
- [Application Recovery](https://learn.microsoft.com/en-us/windows/win32/recovery/registering-for-application-recovery): periodic state checkpoints; do not introduce a second automatic restarter beside the existing watchdog.
- [Windows classic samples](https://github.com/microsoft/Windows-classic-samples), [MIT license](https://github.com/microsoft/Windows-classic-samples/blob/main/LICENSE): reference for native API structure only; no sample source copied.

Decision: reuse the Windows APIs above, retain the current C++/Win32 architecture,
add a small independently linked recovery executable with explicit user actions,
and collect only allowlisted diagnostic metadata. No new third-party source or
license obligation. No window embedding, web desktop or kernel work.

Recovery must match installation path, token user and session on an opened handle;
it must never terminate an arbitrary process named CloudOS. Force termination needs
a visible confirmation and uses an ordinary exit code to suppress watchdog restart.
Explorer is launched only by explicit action and by its Windows-directory path.
There is no registry write or automatic Shell Launcher activation. A missing or
unusable recovery binary must leave the existing watchdog error dialog available.

Crash dumps and unattended fallback/updates remain separate work: dumps may include
sensitive memory, and reliable post-crash dump capture needs a separate collector.
No crash handler should perform complex allocation, COM work or UI recovery inside
a corrupted process.
