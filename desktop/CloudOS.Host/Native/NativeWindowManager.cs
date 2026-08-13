#nullable disable
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace CloudOS.Host.Native
{
    /// <summary>
    /// Tracks top-level windows that belong to processes explicitly registered by the host.
    /// This type deliberately does not launch processes, inject input, re-parent windows, or
    /// terminate processes. Keep process launch policy outside this class.
    /// </summary>
    public sealed class NativeWindowManager : IDisposable
    {
        private readonly object _sync = new object();
        private readonly Dictionary<int, TrackedProcess> _processes = new Dictionary<int, TrackedProcess>();
        private readonly Dictionary<IntPtr, NativeWindowSnapshot> _windows = new Dictionary<IntPtr, NativeWindowSnapshot>();
        private readonly NativeWindowManagerOptions _options;
        private readonly int _hostProcessId;
        private readonly int _hostSessionId;
        private readonly int _hostIntegrityLevel;
        private readonly ManualResetEvent _hookReady = new ManualResetEvent(false);
        private readonly Thread _hookThread;
        private readonly NativeMethods.WinEventDelegate _winEventCallback;

        private Exception _hookStartException;
        private uint _hookThreadId;
        private IntPtr _objectHook;
        private IntPtr _foregroundHook;
        private IntPtr _minimizeHook;
        private bool _disposed;

        public NativeWindowManager()
            : this(new NativeWindowManagerOptions())
        {
        }

        public NativeWindowManager(NativeWindowManagerOptions options)
        {
            if (options == null) throw new ArgumentNullException("options");
            options.Validate();

            _options = options.Clone();
            using (Process host = Process.GetCurrentProcess())
            {
                _hostProcessId = host.Id;
                _hostSessionId = host.SessionId;
            }
            _hostIntegrityLevel = NativeMethods.GetProcessIntegrityLevel(_hostProcessId);

            _winEventCallback = OnWinEvent;
            _hookThread = new Thread(HookThreadMain);
            _hookThread.IsBackground = true;
            _hookThread.Name = "CloudOS.NativeWindowManager.WinEvent";
            _hookThread.Start();

            if (!_hookReady.WaitOne(_options.HookStartupTimeoutMilliseconds))
            {
                Dispose();
                throw new TimeoutException("Timed out while starting the WinEvent hook thread.");
            }

            if (_hookStartException != null)
            {
                Exception error = _hookStartException;
                Dispose();
                throw new InvalidOperationException("Could not install native window event hooks.", error);
            }
        }

        /// <summary>
        /// Raised on the internal hook thread. UI consumers must marshal the callback to their
        /// dispatcher. Exceptions thrown by subscribers are contained at the native boundary.
        /// </summary>
        public event EventHandler<NativeWindowChangedEventArgs> WindowChanged;

        /// <summary>
        /// Registers a process as trusted for window management. Call this only with the Process
        /// returned by the host's own allowlisted launcher, never with an arbitrary renderer PID.
        /// Registration is restricted to a live non-host process in the current Windows session.
        /// </summary>
        public void TrackLaunchedProcess(Process process)
        {
            ThrowIfDisposed();
            if (process == null) throw new ArgumentNullException("process");

            TrackedProcess registration = CreateRegistration(process);
            List<NativeWindowChangedEventArgs> removed = new List<NativeWindowChangedEventArgs>();
            bool alreadyTracked = false;

            lock (_sync)
            {
                TrackedProcess current;
                if (_processes.TryGetValue(registration.ProcessId, out current))
                {
                    if (current.StartTimeUtcTicks == registration.StartTimeUtcTicks)
                    {
                        // Idempotent registration of the same process instance.
                        alreadyTracked = true;
                    }
                    else
                    {
                        RemoveWindowsForProcessLocked(registration.ProcessId, removed);
                    }
                }
                else if (_processes.Count >= _options.MaxTrackedProcesses)
                {
                    throw new InvalidOperationException("The tracked process limit has been reached.");
                }

                if (!alreadyTracked) _processes[registration.ProcessId] = registration;
            }

            RaiseChanges(removed);
            Refresh();
        }

        /// <summary>
        /// Removes the process capability and all of its cached HWNDs. It does not close windows
        /// or terminate the process.
        /// </summary>
        public bool UntrackProcess(int processId)
        {
            ThrowIfDisposed();
            List<NativeWindowChangedEventArgs> removed = new List<NativeWindowChangedEventArgs>();
            bool existed;

            lock (_sync)
            {
                existed = _processes.Remove(processId);
                if (existed) RemoveWindowsForProcessLocked(processId, removed);
            }

            RaiseChanges(removed);
            return existed;
        }

        /// <summary>
        /// Reconciles the cache with EnumWindows. This is also the polling fallback if a native
        /// event is missed during process startup or shell transitions.
        /// </summary>
        public void Refresh()
        {
            ThrowIfDisposed();

            // Reclaim capabilities held by processes that exited without producing a final
            // top-level-window event. Start-time validation also catches PID reuse.
            List<TrackedProcess> registrations;
            lock (_sync) registrations = new List<TrackedProcess>(_processes.Values);
            foreach (TrackedProcess registration in registrations)
            {
                if (!IsSameProcessInstance(registration)) UntrackInvalidProcess(registration.ProcessId);
            }

            Dictionary<IntPtr, NativeWindowSnapshot> discovered = new Dictionary<IntPtr, NativeWindowSnapshot>();
            Dictionary<int, int> discoveredPerProcess = new Dictionary<int, int>();
            NativeMethods.EnumWindows(delegate(IntPtr hwnd, IntPtr state)
            {
                try
                {
                    NativeWindowSnapshot snapshot;
                    if (TryCreateSnapshot(hwnd, out snapshot))
                    {
                        int processCount;
                        discoveredPerProcess.TryGetValue(snapshot.ProcessId, out processCount);
                        if (discovered.Count < _options.MaxTotalWindows
                            && processCount < _options.MaxWindowsPerProcess)
                        {
                            discovered[hwnd] = snapshot;
                            discoveredPerProcess[snapshot.ProcessId] = processCount + 1;
                        }
                    }
                }
                catch
                {
                    // Never let a bad foreign HWND unwind through an unmanaged callback.
                }
                return true;
            }, IntPtr.Zero);

            List<NativeWindowChangedEventArgs> changes = new List<NativeWindowChangedEventArgs>();
            lock (_sync)
            {
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in discovered)
                {
                    NativeWindowSnapshot previous;
                    NativeWindowChangeKind kind = _windows.TryGetValue(item.Key, out previous)
                        ? NativeWindowChangeKind.Updated
                        : NativeWindowChangeKind.Added;

                    _windows[item.Key] = item.Value;
                    changes.Add(new NativeWindowChangedEventArgs(kind, item.Value));
                }

                List<IntPtr> stale = new List<IntPtr>();
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in _windows)
                {
                    if (!discovered.ContainsKey(item.Key)) stale.Add(item.Key);
                }

                foreach (IntPtr hwnd in stale)
                {
                    NativeWindowSnapshot old = _windows[hwnd];
                    _windows.Remove(hwnd);
                    changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, old));
                }
            }

            RaiseChanges(changes);
        }

        public IList<NativeWindowSnapshot> GetWindows()
        {
            ThrowIfDisposed();
            lock (_sync)
            {
                return new List<NativeWindowSnapshot>(_windows.Values).AsReadOnly();
            }
        }

        public IList<NativeWindowSnapshot> GetWindows(int processId)
        {
            ThrowIfDisposed();
            List<NativeWindowSnapshot> result = new List<NativeWindowSnapshot>();
            lock (_sync)
            {
                foreach (NativeWindowSnapshot window in _windows.Values)
                {
                    if (window.ProcessId == processId) result.Add(window);
                }
            }
            return result.AsReadOnly();
        }

        public bool TryFocus(long windowHandle, out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;

            if (NativeMethods.IsIconic(hwnd)) NativeMethods.ShowWindowAsync(hwnd, NativeMethods.SW_RESTORE);
            if (!NativeMethods.SetForegroundWindow(hwnd))
            {
                error = "Windows denied foreground activation. User interaction may be required.";
                return false;
            }

            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            error = null;
            return true;
        }

        public bool TryMinimize(long windowHandle, out string error)
        {
            return TrySetShowState(windowHandle, NativeMethods.SW_MINIMIZE, out error);
        }

        public bool TryMaximize(long windowHandle, out string error)
        {
            return TrySetShowState(windowHandle, NativeMethods.SW_MAXIMIZE, out error);
        }

        public bool TryRestore(long windowHandle, out string error)
        {
            return TrySetShowState(windowHandle, NativeMethods.SW_RESTORE, out error);
        }

        /// <summary>
        /// Requests graceful close with WM_CLOSE. The method never calls TerminateProcess and
        /// aborts if the target window does not answer within the configured timeout.
        /// </summary>
        public bool TryClose(long windowHandle, out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;

            IntPtr messageResult;
            IntPtr sent = NativeMethods.SendMessageTimeout(
                hwnd,
                NativeMethods.WM_CLOSE,
                IntPtr.Zero,
                IntPtr.Zero,
                NativeMethods.SMTO_ABORTIFHUNG | NativeMethods.SMTO_BLOCK,
                (uint)_options.CloseTimeoutMilliseconds,
                out messageResult);

            if (sent == IntPtr.Zero)
            {
                int nativeError = Marshal.GetLastWin32Error();
                error = nativeError == NativeMethods.ERROR_TIMEOUT
                    ? "The window did not respond to the close request before the timeout."
                    : "WM_CLOSE could not be delivered (Win32 error " + nativeError + ").";
                return false;
            }

            error = null;
            return true;
        }

        public void Dispose()
        {
            bool shouldStop;
            lock (_sync)
            {
                shouldStop = !_disposed;
                _disposed = true;
                _processes.Clear();
                _windows.Clear();
            }

            if (!shouldStop) return;

            uint threadId = _hookThreadId;
            if (threadId != 0) NativeMethods.PostThreadMessage(threadId, NativeMethods.WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
            if (_hookThread != null && _hookThread.IsAlive && Thread.CurrentThread != _hookThread)
            {
                _hookThread.Join(_options.HookShutdownTimeoutMilliseconds);
            }
            _hookReady.Close();
        }

        private TrackedProcess CreateRegistration(Process process)
        {
            try
            {
                process.Refresh();
                if (process.HasExited) throw new InvalidOperationException("Cannot track an exited process.");
                if (process.Id <= 0 || process.Id == _hostProcessId)
                    throw new InvalidOperationException("The CloudOS host process cannot be registered as a managed app.");
                if (process.SessionId != _hostSessionId)
                    throw new InvalidOperationException("Only processes in the CloudOS host's Windows session can be tracked.");

                int integrityLevel = NativeMethods.GetProcessIntegrityLevel(process.Id);
                if (integrityLevel > _hostIntegrityLevel)
                    throw new InvalidOperationException("A process with higher integrity than the CloudOS host cannot be tracked.");

                return new TrackedProcess(process.Id, process.StartTime.ToUniversalTime().Ticks, process.SessionId, integrityLevel);
            }
            catch (InvalidOperationException)
            {
                throw;
            }
            catch (Exception error)
            {
                throw new InvalidOperationException("The process identity could not be verified.", error);
            }
        }

        private bool TrySetShowState(long windowHandle, int command, out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;

            // ShowWindowAsync's return value describes the previous visibility state, not success.
            NativeMethods.ShowWindowAsync(hwnd, command);
            if (!NativeMethods.IsWindow(hwnd))
            {
                error = "The window disappeared before the state change completed.";
                return false;
            }

            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            error = null;
            return true;
        }

        private bool TryAuthorizeOperation(long windowHandle, out IntPtr hwnd, out string error)
        {
            hwnd = IntPtr.Zero;
            error = null;

            lock (_sync)
            {
                if (_disposed)
                {
                    error = "NativeWindowManager is disposed.";
                    return false;
                }
            }

            try
            {
                hwnd = new IntPtr(windowHandle);
            }
            catch (OverflowException)
            {
                error = "The HWND value is invalid for this process architecture.";
                return false;
            }

            NativeWindowSnapshot tracked;
            TrackedProcess registration;
            lock (_sync)
            {
                if (!_windows.TryGetValue(hwnd, out tracked))
                {
                    error = "The HWND is not registered with CloudOS.";
                    return false;
                }
                if (!_processes.TryGetValue(tracked.ProcessId, out registration))
                {
                    error = "The owning process is no longer registered with CloudOS.";
                    return false;
                }
            }

            uint currentOwner;
            NativeMethods.GetWindowThreadProcessId(hwnd, out currentOwner);
            if (!NativeMethods.IsWindow(hwnd) || currentOwner != (uint)registration.ProcessId)
            {
                RemoveWindow(hwnd);
                error = "The HWND is stale or now belongs to another process.";
                return false;
            }

            if (!IsSameProcessInstance(registration))
            {
                UntrackInvalidProcess(registration.ProcessId);
                error = "The registered process exited or its PID was reused.";
                return false;
            }

            return true;
        }

        private bool IsSameProcessInstance(TrackedProcess registration)
        {
            try
            {
                using (Process process = Process.GetProcessById(registration.ProcessId))
                {
                    return !process.HasExited
                        && process.SessionId == registration.SessionId
                        && process.StartTime.ToUniversalTime().Ticks == registration.StartTimeUtcTicks
                        && NativeMethods.GetProcessIntegrityLevel(registration.ProcessId) == registration.IntegrityLevel;
                }
            }
            catch
            {
                return false;
            }
        }

        private bool TryCreateSnapshot(IntPtr hwnd, out NativeWindowSnapshot snapshot)
        {
            snapshot = null;
            if (hwnd == IntPtr.Zero || !NativeMethods.IsWindow(hwnd)) return false;
            if (NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT) != hwnd) return false;
            if (!NativeMethods.IsWindowVisible(hwnd)) return false;

            uint ownerPid;
            NativeMethods.GetWindowThreadProcessId(hwnd, out ownerPid);
            if (ownerPid == 0 || ownerPid == (uint)_hostProcessId) return false;

            TrackedProcess registration;
            int processId = unchecked((int)ownerPid);
            lock (_sync)
            {
                if (!_processes.TryGetValue(processId, out registration)) return false;
            }

            if (!IsSameProcessInstance(registration))
            {
                UntrackInvalidProcess(processId);
                return false;
            }

            long extendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
            bool isAppWindow = (extendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0;
            bool isToolWindow = (extendedStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0;
            if (isToolWindow && !isAppWindow) return false;
            if (NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero && !isAppWindow) return false;
            if (NativeMethods.IsWindowCloaked(hwnd)) return false;

            NativeMethods.RECT rect;
            if (!NativeMethods.GetWindowRect(hwnd, out rect)) return false;
            if (rect.Right <= rect.Left || rect.Bottom <= rect.Top) return false;

            snapshot = new NativeWindowSnapshot(
                hwnd.ToInt64(),
                processId,
                NativeMethods.GetWindowTitle(hwnd, _options.MaxTitleLength),
                NativeMethods.IsWindowVisible(hwnd),
                NativeMethods.IsIconic(hwnd),
                NativeMethods.IsZoomed(hwnd),
                new NativeWindowBounds(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top),
                DateTimeOffset.UtcNow);
            return true;
        }

        private void HookThreadMain()
        {
            try
            {
                _hookThreadId = NativeMethods.GetCurrentThreadId();

                // Force creation of this thread's message queue before Dispose can post WM_QUIT.
                NativeMethods.MSG message;
                NativeMethods.PeekMessage(out message, IntPtr.Zero, 0, 0, NativeMethods.PM_NOREMOVE);

                const uint flags = NativeMethods.WINEVENT_OUTOFCONTEXT | NativeMethods.WINEVENT_SKIPOWNPROCESS;
                _objectHook = NativeMethods.SetWinEventHook(
                    NativeMethods.EVENT_OBJECT_CREATE,
                    NativeMethods.EVENT_OBJECT_NAMECHANGE,
                    IntPtr.Zero,
                    _winEventCallback,
                    0,
                    0,
                    flags);
                _foregroundHook = NativeMethods.SetWinEventHook(
                    NativeMethods.EVENT_SYSTEM_FOREGROUND,
                    NativeMethods.EVENT_SYSTEM_FOREGROUND,
                    IntPtr.Zero,
                    _winEventCallback,
                    0,
                    0,
                    flags);
                _minimizeHook = NativeMethods.SetWinEventHook(
                    NativeMethods.EVENT_SYSTEM_MINIMIZESTART,
                    NativeMethods.EVENT_SYSTEM_MINIMIZEEND,
                    IntPtr.Zero,
                    _winEventCallback,
                    0,
                    0,
                    flags);

                if (_objectHook == IntPtr.Zero || _foregroundHook == IntPtr.Zero || _minimizeHook == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWinEventHook failed.");

                _hookReady.Set();
                while (NativeMethods.GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
                {
                    NativeMethods.TranslateMessage(ref message);
                    NativeMethods.DispatchMessage(ref message);
                }
            }
            catch (Exception error)
            {
                _hookStartException = error;
                _hookReady.Set();
            }
            finally
            {
                Unhook(ref _objectHook);
                Unhook(ref _foregroundHook);
                Unhook(ref _minimizeHook);
            }
        }

        private void OnWinEvent(
            IntPtr hook,
            uint eventType,
            IntPtr hwnd,
            int objectId,
            int childId,
            uint eventThread,
            uint eventTime)
        {
            try
            {
                if (hwnd == IntPtr.Zero) return;
                if (eventType >= NativeMethods.EVENT_OBJECT_CREATE
                    && eventType <= NativeMethods.EVENT_OBJECT_NAMECHANGE
                    && (objectId != NativeMethods.OBJID_WINDOW || childId != 0)) return;

                if (eventType == NativeMethods.EVENT_OBJECT_DESTROY)
                {
                    RemoveWindow(hwnd);
                    return;
                }

                RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            }
            catch
            {
                // Never allow managed exceptions to escape an unmanaged WinEvent callback.
            }
        }

        private void RefreshOne(IntPtr hwnd, NativeWindowChangeKind existingKind)
        {
            NativeWindowSnapshot snapshot;
            if (!TryCreateSnapshot(hwnd, out snapshot))
            {
                RemoveWindow(hwnd);
                return;
            }

            NativeWindowChangedEventArgs change;
            lock (_sync)
            {
                bool alreadyKnown = _windows.ContainsKey(hwnd);
                if (!alreadyKnown
                    && (_windows.Count >= _options.MaxTotalWindows
                        || CountWindowsForProcessLocked(snapshot.ProcessId) >= _options.MaxWindowsPerProcess))
                    return;

                NativeWindowChangeKind kind = alreadyKnown
                    ? existingKind
                    : NativeWindowChangeKind.Added;
                _windows[hwnd] = snapshot;
                change = new NativeWindowChangedEventArgs(kind, snapshot);
            }
            RaiseChange(change);
        }

        private void RemoveWindow(IntPtr hwnd)
        {
            NativeWindowChangedEventArgs change = null;
            lock (_sync)
            {
                NativeWindowSnapshot snapshot;
                if (_windows.TryGetValue(hwnd, out snapshot))
                {
                    _windows.Remove(hwnd);
                    change = new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, snapshot);
                }
            }
            if (change != null) RaiseChange(change);
        }

        private void UntrackInvalidProcess(int processId)
        {
            List<NativeWindowChangedEventArgs> changes = new List<NativeWindowChangedEventArgs>();
            lock (_sync)
            {
                _processes.Remove(processId);
                RemoveWindowsForProcessLocked(processId, changes);
            }
            RaiseChanges(changes);
        }

        private void RemoveWindowsForProcessLocked(int processId, IList<NativeWindowChangedEventArgs> changes)
        {
            List<IntPtr> handles = new List<IntPtr>();
            foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in _windows)
            {
                if (item.Value.ProcessId == processId) handles.Add(item.Key);
            }

            foreach (IntPtr hwnd in handles)
            {
                NativeWindowSnapshot snapshot = _windows[hwnd];
                _windows.Remove(hwnd);
                changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, snapshot));
            }
        }

        private int CountWindowsForProcessLocked(int processId)
        {
            int count = 0;
            foreach (NativeWindowSnapshot snapshot in _windows.Values)
            {
                if (snapshot.ProcessId == processId) count++;
            }
            return count;
        }

        private void RaiseChanges(IEnumerable<NativeWindowChangedEventArgs> changes)
        {
            foreach (NativeWindowChangedEventArgs change in changes) RaiseChange(change);
        }

        private void RaiseChange(NativeWindowChangedEventArgs change)
        {
            EventHandler<NativeWindowChangedEventArgs> handler = WindowChanged;
            if (handler == null) return;
            try { handler(this, change); }
            catch { /* The WinEvent hook must remain alive if a consumer fails. */ }
        }

        private static void Unhook(ref IntPtr hook)
        {
            IntPtr current = hook;
            hook = IntPtr.Zero;
            if (current != IntPtr.Zero) NativeMethods.UnhookWinEvent(current);
        }

        private void ThrowIfDisposed()
        {
            lock (_sync)
            {
                if (_disposed) throw new ObjectDisposedException("NativeWindowManager");
            }
        }

        private sealed class TrackedProcess
        {
            public TrackedProcess(int processId, long startTimeUtcTicks, int sessionId, int integrityLevel)
            {
                ProcessId = processId;
                StartTimeUtcTicks = startTimeUtcTicks;
                SessionId = sessionId;
                IntegrityLevel = integrityLevel;
            }

            public int ProcessId { get; private set; }
            public long StartTimeUtcTicks { get; private set; }
            public int SessionId { get; private set; }
            public int IntegrityLevel { get; private set; }
        }
    }

    public sealed class NativeWindowManagerOptions
    {
        public NativeWindowManagerOptions()
        {
            MaxTrackedProcesses = 32;
            MaxWindowsPerProcess = 32;
            MaxTotalWindows = 256;
            MaxTitleLength = 1024;
            CloseTimeoutMilliseconds = 1500;
            HookStartupTimeoutMilliseconds = 5000;
            HookShutdownTimeoutMilliseconds = 3000;
        }

        public int MaxTrackedProcesses { get; set; }
        public int MaxWindowsPerProcess { get; set; }
        public int MaxTotalWindows { get; set; }
        public int MaxTitleLength { get; set; }
        public int CloseTimeoutMilliseconds { get; set; }
        public int HookStartupTimeoutMilliseconds { get; set; }
        public int HookShutdownTimeoutMilliseconds { get; set; }

        internal NativeWindowManagerOptions Clone()
        {
            return (NativeWindowManagerOptions)MemberwiseClone();
        }

        internal void Validate()
        {
            if (MaxTrackedProcesses < 1 || MaxTrackedProcesses > 256) throw new ArgumentOutOfRangeException("MaxTrackedProcesses");
            if (MaxWindowsPerProcess < 1 || MaxWindowsPerProcess > 256) throw new ArgumentOutOfRangeException("MaxWindowsPerProcess");
            if (MaxTotalWindows < 1 || MaxTotalWindows > 2048) throw new ArgumentOutOfRangeException("MaxTotalWindows");
            if (MaxTitleLength < 32 || MaxTitleLength > 32768) throw new ArgumentOutOfRangeException("MaxTitleLength");
            if (CloseTimeoutMilliseconds < 100 || CloseTimeoutMilliseconds > 10000) throw new ArgumentOutOfRangeException("CloseTimeoutMilliseconds");
            if (HookStartupTimeoutMilliseconds < 100 || HookStartupTimeoutMilliseconds > 30000) throw new ArgumentOutOfRangeException("HookStartupTimeoutMilliseconds");
            if (HookShutdownTimeoutMilliseconds < 100 || HookShutdownTimeoutMilliseconds > 30000) throw new ArgumentOutOfRangeException("HookShutdownTimeoutMilliseconds");
        }
    }

    public sealed class NativeWindowSnapshot
    {
        internal NativeWindowSnapshot(
            long handle,
            int processId,
            string title,
            bool isVisible,
            bool isMinimized,
            bool isMaximized,
            NativeWindowBounds bounds,
            DateTimeOffset observedAtUtc)
        {
            Handle = handle;
            ProcessId = processId;
            Title = title ?? String.Empty;
            IsVisible = isVisible;
            IsMinimized = isMinimized;
            IsMaximized = isMaximized;
            Bounds = bounds;
            ObservedAtUtc = observedAtUtc;
        }

        public long Handle { get; private set; }
        public int ProcessId { get; private set; }
        public string Title { get; private set; }
        public bool IsVisible { get; private set; }
        public bool IsMinimized { get; private set; }
        public bool IsMaximized { get; private set; }
        public NativeWindowBounds Bounds { get; private set; }
        public DateTimeOffset ObservedAtUtc { get; private set; }
    }

    public struct NativeWindowBounds
    {
        public NativeWindowBounds(int x, int y, int width, int height)
        {
            this = new NativeWindowBounds();
            X = x;
            Y = y;
            Width = width;
            Height = height;
        }

        public int X { get; private set; }
        public int Y { get; private set; }
        public int Width { get; private set; }
        public int Height { get; private set; }
    }

    public enum NativeWindowChangeKind
    {
        Added,
        Updated,
        Removed
    }

    public sealed class NativeWindowChangedEventArgs : EventArgs
    {
        internal NativeWindowChangedEventArgs(NativeWindowChangeKind kind, NativeWindowSnapshot window)
        {
            Kind = kind;
            Window = window;
        }

        public NativeWindowChangeKind Kind { get; private set; }
        public NativeWindowSnapshot Window { get; private set; }
    }

    internal static class NativeMethods
    {
        internal const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
        internal const uint EVENT_SYSTEM_MINIMIZESTART = 0x0016;
        internal const uint EVENT_SYSTEM_MINIMIZEEND = 0x0017;
        internal const uint EVENT_OBJECT_CREATE = 0x8000;
        internal const uint EVENT_OBJECT_DESTROY = 0x8001;
        internal const uint EVENT_OBJECT_NAMECHANGE = 0x800C;
        internal const int OBJID_WINDOW = 0;
        internal const uint WINEVENT_OUTOFCONTEXT = 0;
        internal const uint WINEVENT_SKIPOWNPROCESS = 2;

        internal const uint GA_ROOT = 2;
        internal const uint GW_OWNER = 4;
        internal const int GWL_EXSTYLE = -20;
        internal const long WS_EX_TOOLWINDOW = 0x00000080L;
        internal const long WS_EX_APPWINDOW = 0x00040000L;
        internal const int SW_MINIMIZE = 6;
        internal const int SW_MAXIMIZE = 3;
        internal const int SW_RESTORE = 9;
        internal const uint WM_CLOSE = 0x0010;
        internal const uint WM_QUIT = 0x0012;
        internal const uint SMTO_BLOCK = 0x0001;
        internal const uint SMTO_ABORTIFHUNG = 0x0002;
        internal const int ERROR_TIMEOUT = 1460;
        internal const uint PM_NOREMOVE = 0;
        internal const int DWMWA_CLOAKED = 14;
        internal const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        internal const uint TOKEN_QUERY = 0x0008;
        internal const int TOKEN_INTEGRITY_LEVEL = 25;
        internal const int ERROR_INSUFFICIENT_BUFFER = 122;

        internal delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr state);
        internal delegate void WinEventDelegate(
            IntPtr hook,
            uint eventType,
            IntPtr hwnd,
            int objectId,
            int childId,
            uint eventThread,
            uint eventTime);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RECT
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct POINT
        {
            internal int X;
            internal int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct MSG
        {
            internal IntPtr Hwnd;
            internal uint Message;
            internal UIntPtr WParam;
            internal IntPtr LParam;
            internal uint Time;
            internal POINT Point;
            internal uint Private;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SID_AND_ATTRIBUTES
        {
            internal IntPtr Sid;
            internal uint Attributes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_MANDATORY_LABEL
        {
            internal SID_AND_ATTRIBUTES Label;
        }

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool EnumWindows(EnumWindowsProc callback, IntPtr state);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr SetWinEventHook(
            uint eventMin,
            uint eventMax,
            IntPtr eventHookModule,
            WinEventDelegate callback,
            uint processId,
            uint threadId,
            uint flags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnhookWinEvent(IntPtr hook);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsIconic(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsZoomed(IntPtr hwnd);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetWindow(IntPtr hwnd, uint command);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindowAsync(IntPtr hwnd, int command);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr SendMessageTimeout(
            IntPtr hwnd,
            uint message,
            IntPtr wParam,
            IntPtr lParam,
            uint flags,
            uint timeout,
            out IntPtr result);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
        private static extern int GetWindowLong32(IntPtr hwnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int valueSize);

        [DllImport("kernel32.dll")]
        internal static extern uint GetCurrentThreadId();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(
            IntPtr tokenHandle,
            int tokenInformationClass,
            IntPtr tokenInformation,
            int tokenInformationLength,
            out int returnLength);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

        [DllImport("advapi32.dll")]
        private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint subAuthorityIndex);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostThreadMessage(uint threadId, uint message, UIntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        internal static extern int GetMessage(out MSG message, IntPtr hwnd, uint min, uint max);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PeekMessage(out MSG message, IntPtr hwnd, uint min, uint max, uint remove);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TranslateMessage(ref MSG message);

        [DllImport("user32.dll")]
        internal static extern IntPtr DispatchMessage(ref MSG message);

        internal static long GetWindowExtendedStyle(IntPtr hwnd)
        {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hwnd, GWL_EXSTYLE).ToInt64()
                : GetWindowLong32(hwnd, GWL_EXSTYLE);
        }

        internal static string GetWindowTitle(IntPtr hwnd, int maxLength)
        {
            StringBuilder buffer = new StringBuilder(maxLength + 1);
            int copied = GetWindowText(hwnd, buffer, buffer.Capacity);
            return copied > 0 ? buffer.ToString(0, copied) : String.Empty;
        }

        internal static bool IsWindowCloaked(IntPtr hwnd)
        {
            try
            {
                int cloaked;
                int result = DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out cloaked, sizeof(int));
                return result == 0 && cloaked != 0;
            }
            catch (DllNotFoundException)
            {
                return false;
            }
            catch (EntryPointNotFoundException)
            {
                return false;
            }
        }

        internal static int GetProcessIntegrityLevel(int processId)
        {
            IntPtr processHandle = IntPtr.Zero;
            IntPtr tokenHandle = IntPtr.Zero;
            IntPtr tokenBuffer = IntPtr.Zero;
            try
            {
                processHandle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
                if (processHandle == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed while checking integrity.");

                if (!OpenProcessToken(processHandle, TOKEN_QUERY, out tokenHandle))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken failed while checking integrity.");

                int required;
                GetTokenInformation(tokenHandle, TOKEN_INTEGRITY_LEVEL, IntPtr.Zero, 0, out required);
                int firstError = Marshal.GetLastWin32Error();
                if (required <= 0 || firstError != ERROR_INSUFFICIENT_BUFFER)
                    throw new Win32Exception(firstError, "Could not size the token integrity buffer.");

                tokenBuffer = Marshal.AllocHGlobal(required);
                if (!GetTokenInformation(tokenHandle, TOKEN_INTEGRITY_LEVEL, tokenBuffer, required, out required))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not read token integrity information.");

                TOKEN_MANDATORY_LABEL label = (TOKEN_MANDATORY_LABEL)Marshal.PtrToStructure(
                    tokenBuffer,
                    typeof(TOKEN_MANDATORY_LABEL));
                if (label.Label.Sid == IntPtr.Zero) throw new InvalidOperationException("The token integrity SID is missing.");

                IntPtr countPointer = GetSidSubAuthorityCount(label.Label.Sid);
                if (countPointer == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Invalid token integrity SID.");
                byte count = Marshal.ReadByte(countPointer);
                if (count == 0) throw new InvalidOperationException("The token integrity SID has no sub-authority.");

                IntPtr ridPointer = GetSidSubAuthority(label.Label.Sid, (uint)(count - 1));
                if (ridPointer == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Invalid token integrity RID.");
                return Marshal.ReadInt32(ridPointer);
            }
            finally
            {
                if (tokenBuffer != IntPtr.Zero) Marshal.FreeHGlobal(tokenBuffer);
                if (tokenHandle != IntPtr.Zero) CloseHandle(tokenHandle);
                if (processHandle != IntPtr.Zero) CloseHandle(processHandle);
            }
        }
    }
}
