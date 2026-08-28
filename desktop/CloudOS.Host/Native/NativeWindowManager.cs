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
    /// Newly observed top-level windows remain hidden until they are attached to a CloudOS
    /// owner surface. Losing containment terminates the tracked process; there is no external
    /// desktop fallback.
    /// </summary>
    public sealed class NativeWindowManager : IDisposable
    {
        private readonly object _sync = new object();
        private readonly Dictionary<int, TrackedProcess> _processes = new Dictionary<int, TrackedProcess>();
        private readonly Dictionary<IntPtr, NativeWindowSnapshot> _windows = new Dictionary<IntPtr, NativeWindowSnapshot>();
        private readonly Dictionary<IntPtr, AttachedWindowState> _attachments = new Dictionary<IntPtr, AttachedWindowState>();
        private readonly Dictionary<IntPtr, CapturedSourceState> _capturedSources = new Dictionary<IntPtr, CapturedSourceState>();
        private readonly HashSet<int> _containedProcesses = new HashSet<int>();
        private readonly Dictionary<IntPtr, int> _quarantinedWindows = new Dictionary<IntPtr, int>();
        private readonly Dictionary<int, string> _containmentFailures = new Dictionary<int, string>();
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
        /// Registers a process as trusted for fail-closed containment. Call this only after
        /// NativeLaunchContainmentPolicy admitted a Host-created suspended Job member.
        /// Every eligible top-level window from this process is hidden until TryAttach succeeds.
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
                _containedProcesses.Add(registration.ProcessId);
                _containmentFailures.Remove(registration.ProcessId);
            }

            RaiseChanges(removed);
            Refresh();
        }

        public bool UntrackProcess(int processId)
        {
            string error;
            return TryTerminateTrackedProcess(processId, out error);
        }

        public bool TryGetContainmentFailure(int processId, out string error)
        {
            ThrowIfDisposed();
            lock (_sync) return _containmentFailures.TryGetValue(processId, out error);
        }

        public bool IsTrackedProcess(int processId)
        {
            ThrowIfDisposed();
            lock (_sync) return _processes.ContainsKey(processId);
        }

        public bool TryQuarantineTrackedProcess(int processId, out string error)
        {
            ThrowIfDisposed();
            lock (_sync)
            {
                if (!_processes.ContainsKey(processId))
                {
                    error = "The process is not tracked by CloudOS.";
                    return false;
                }
            }
            ForceHideWindowsForProcess(processId);
            lock (_sync)
            {
                if (_containmentFailures.TryGetValue(processId, out error)) return false;
            }
            error = null;
            return true;
        }

        public bool TryGetProcessId(long windowHandle, out int processId)
        {
            processId = 0;
            IntPtr hwnd;
            try { hwnd = new IntPtr(windowHandle); }
            catch (OverflowException) { return false; }
            lock (_sync)
            {
                NativeWindowSnapshot snapshot;
                if (_disposed || !_windows.TryGetValue(hwnd, out snapshot)) return false;
                processId = snapshot.ProcessId;
                return true;
            }
        }

        public bool TryTerminateTrackedProcess(int processId, out string error)
        {
            ThrowIfDisposed();
            TrackedProcess registration;
            lock (_sync)
            {
                if (!_processes.TryGetValue(processId, out registration))
                {
                    error = null;
                    return true;
                }
            }

            ForceHideWindowsForProcess(processId);
            try
            {
                using (Process process = Process.GetProcessById(processId))
                {
                    process.Refresh();
                    if (!process.HasExited)
                    {
                        if (!IsSameProcessInstance(registration))
                        {
                            RemoveTrackedProcess(processId);
                            error = null;
                            return true;
                        }
                        if (NativeLaunchContainmentPolicy.IsSharedBroker(process.ProcessName))
                            throw new InvalidOperationException("A shared Windows broker cannot be terminated by CloudOS.");

                        process.Kill(true);
                        if (!process.WaitForExit(_options.TerminationTimeoutMilliseconds))
                            throw new TimeoutException("The contained process did not terminate before the deadline.");
                    }
                }
            }
            catch (ArgumentException)
            {
            }
            catch (Exception terminationError) when (terminationError is InvalidOperationException
                || terminationError is Win32Exception
                || terminationError is NotSupportedException
                || terminationError is TimeoutException)
            {
                lock (_sync) _containmentFailures[processId] = terminationError.Message;
                error = terminationError.Message;
                return false;
            }

            RemoveTrackedProcess(processId);
            error = null;
            return true;
        }

        public void Refresh()
        {
            ThrowIfDisposed();

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
                }
                return true;
            }, IntPtr.Zero);

            List<NativeWindowChangedEventArgs> changes = new List<NativeWindowChangedEventArgs>();
            lock (_sync)
            {
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in discovered)
                {
                    NativeWindowSnapshot previous;
                    if (_windows.TryGetValue(item.Key, out previous))
                    {
                        _windows[item.Key] = item.Value;
                        if (!HasSameObservableState(previous, item.Value))
                            changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Updated, item.Value));
                    }
                    else
                    {
                        _windows[item.Key] = item.Value;
                        changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Added, item.Value));
                    }
                }

                List<IntPtr> stale = new List<IntPtr>();
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> item in _windows)
                {
                    if (!discovered.ContainsKey(item.Key)) stale.Add(item.Key);
                }

                foreach (IntPtr hwnd in stale)
                {
                    if ((_attachments.ContainsKey(hwnd) || _capturedSources.ContainsKey(hwnd)) && NativeMethods.IsWindow(hwnd))
                        continue;
                    NativeWindowSnapshot old = _windows[hwnd];
                    _windows.Remove(hwnd);
                    _attachments.Remove(hwnd);
                    _quarantinedWindows.Remove(hwnd);
                    changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, old));
                }

                List<IntPtr> staleQuarantines = new List<IntPtr>();
                foreach (IntPtr hwnd in _quarantinedWindows.Keys)
                {
                    if (!NativeMethods.IsWindow(hwnd)) staleQuarantines.Add(hwnd);
                }
                foreach (IntPtr hwnd in staleQuarantines) _quarantinedWindows.Remove(hwnd);
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

            AttachedWindowState attachment;
            lock (_sync) _attachments.TryGetValue(hwnd, out attachment);
            if (attachment == null)
            {
                TryForceHideWindow(hwnd, out _);
                error = "The window is quarantined and cannot be focused before attachment.";
                return false;
            }

            lock (attachment.SyncRoot)
            {
                if (!attachment.RequestedVisible)
                {
                    error = "The CloudOS Hub surface is hidden. Open the Hub before focusing this application.";
                    return false;
                }
                if (!TryRestoreResponsive(hwnd, true, out error)) return false;
                if (!TryApplyAttachedLayout(hwnd, attachment, attachment.Bounds, true, false, false, out error))
                {
                    QuarantineAfterContainmentFailure(hwnd, attachment, error);
                    return false;
                }
            }
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

        public bool TryAttach(
            long windowHandle,
            long ownerWindowHandle,
            NativeWindowBounds bounds,
            bool visible,
            out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;

            IntPtr owner;
            try
            {
                owner = new IntPtr(ownerWindowHandle);
            }
            catch (OverflowException)
            {
                error = "The CloudOS owner HWND is invalid for this process architecture.";
                return false;
            }

            if (!TryValidateOwner(owner, out error) || !TryValidateAttachedBounds(bounds, out error)) return false;

            AttachedWindowState state;
            bool alreadyAttached;
            lock (_sync)
            {
                alreadyAttached = _attachments.TryGetValue(hwnd, out state);
                if (!alreadyAttached && !_quarantinedWindows.ContainsKey(hwnd))
                {
                    error = "The window was not observed inside the CloudOS launch quarantine.";
                    return false;
                }
            }

            if (alreadyAttached)
                return TryApplyAttachedLayout(hwnd, state, bounds, visible, false, true, out error);

            if (NativeMethods.GetAncestor(hwnd, NativeMethods.GA_ROOT) != hwnd)
            {
                error = "Only a top-level application window can be attached to CloudOS.";
                return false;
            }

            state = new AttachedWindowState(
                owner,
                NativeMethods.GetWindowStyle(hwnd),
                NativeMethods.GetWindowExtendedStyle(hwnd));

            try
            {
                lock (state.SyncRoot)
                {
                    if (!TryForceHideWindow(hwnd, out error)) throw new InvalidOperationException(error);

                    long attachedStyle = GetExpectedAttachedStyle(state);
                    long attachedExtendedStyle = GetExpectedAttachedExtendedStyle(state);

                    NativeMethods.SetWindowStyle(hwnd, attachedStyle);
                    NativeMethods.SetWindowExtendedStyle(hwnd, attachedExtendedStyle);
                    NativeMethods.SetWindowOwner(hwnd, owner);
                    IntPtr actualOwner = NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER);
                    long actualStyle = NativeMethods.GetWindowStyle(hwnd);
                    long actualExtendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
                    long forbiddenFrameStyles = NativeMethods.WS_CAPTION
                        | NativeMethods.WS_THICKFRAME
                        | NativeMethods.WS_MINIMIZEBOX
                        | NativeMethods.WS_MAXIMIZEBOX
                        | NativeMethods.WS_SYSMENU;
                    if (actualOwner != owner
                        || (actualStyle & forbiddenFrameStyles) != 0
                        || (actualExtendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0
                        || (actualExtendedStyle & NativeMethods.WS_EX_TOOLWINDOW) == 0)
                        throw new Win32Exception(
                            Marshal.GetLastWin32Error(),
                            "Windows refused the CloudOS docking styles or owner "
                                + "(owner=" + actualOwner.ToInt64() + "/" + owner.ToInt64()
                                + ", style=0x" + actualStyle.ToString("X") + "/0x" + attachedStyle.ToString("X")
                                + ", ex=0x" + actualExtendedStyle.ToString("X") + "/0x" + attachedExtendedStyle.ToString("X") + ").");

                    if (!TryRestoreResponsive(hwnd, true, out error))
                        throw new InvalidOperationException(error);

                    state.Bounds = bounds;
                    state.RequestedVisible = visible;
                    lock (_sync) _attachments[hwnd] = state;
                    if (!TryApplyAttachedLayout(hwnd, state, bounds, visible, true, false, out error))
                        throw new InvalidOperationException(error);
                }

                RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                error = null;
                return true;
            }
            catch (Exception attachError)
            {
                QuarantineAfterContainmentFailure(hwnd, state, attachError.Message);
                error = "The application does not support CloudOS containment: " + attachError.Message;
                return false;
            }
        }

        public bool TryPrepareCapturedSource(
            long windowHandle,
            long ownerWindowHandle,
            NativeWindowBounds bounds,
            bool visible,
            out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;

            IntPtr owner;
            try { owner = new IntPtr(ownerWindowHandle); }
            catch (OverflowException)
            {
                error = "The CloudOS owner HWND is invalid for this process architecture.";
                return false;
            }
            if (!TryValidateOwner(owner, out error) || !TryValidateAttachedBounds(bounds, out error)) return false;

            CapturedSourceState state;
            bool existing;
            lock (_sync)
            {
                if (_attachments.ContainsKey(hwnd))
                {
                    error = "An anchored window cannot also become a captured source.";
                    return false;
                }
                existing = _capturedSources.TryGetValue(hwnd, out state);
                if (!existing)
                {
                    if (!_quarantinedWindows.ContainsKey(hwnd))
                    {
                        error = "The capture source was not observed inside the CloudOS launch quarantine.";
                        return false;
                    }
                    state = new CapturedSourceState(
                        owner,
                        NativeMethods.GetWindowExtendedStyle(hwnd));
                    if (NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero)
                    {
                        error = "Only an unowned primary window can become a captured source.";
                        return false;
                    }
                    _capturedSources[hwnd] = state;
                }
            }

            if (existing)
            {
                lock (state.SyncRoot)
                {
                    if (!IsCurrentCapturedSource(hwnd, state))
                    {
                        error = "The captured source was replaced during preparation.";
                        return false;
                    }
                    state.RequestedVisible = visible;
                    return TryApplyCapturedSourceLayout(hwnd, state, bounds, out error);
                }
            }

            try
            {
                lock (state.SyncRoot)
                {
                    NativeMethods.SetWindowExtendedStyle(hwnd, state.CapturedExtendedStyle);
                    state.Bounds = bounds;
                    state.RequestedVisible = visible;
                    if (!TryApplyCapturedSourceLayout(hwnd, state, bounds, out error))
                        throw new InvalidOperationException(error);
                    state.Prepared = true;
                }
                RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                error = null;
                return true;
            }
            catch (Exception captureError) when (captureError is InvalidOperationException or Win32Exception)
            {
                lock (state.SyncRoot)
                {
                    lock (_sync)
                    {
                        if (_capturedSources.TryGetValue(hwnd, out CapturedSourceState current)
                            && Object.ReferenceEquals(current, state))
                            _capturedSources.Remove(hwnd);
                    }
                    TryForceHideWindow(hwnd, out _);
                }
                error = "The Windows source could not enter captured isolation: " + captureError.Message;
                return false;
            }
        }

        public bool TryActivateCapturedSource(
            long windowHandle,
            long presentationWindowHandle,
            NativeWindowBounds bounds,
            bool visible,
            out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;
            IntPtr presenter;
            try { presenter = new IntPtr(presentationWindowHandle); }
            catch (OverflowException)
            {
                error = "The captured presentation HWND is invalid for this process architecture.";
                return false;
            }
            if (!TryValidateOwner(presenter, out error) || !TryValidateAttachedBounds(bounds, out error)) return false;

            CapturedSourceState state;
            lock (_sync)
            {
                if (!_capturedSources.TryGetValue(hwnd, out state))
                {
                    error = "The source did not enter captured isolation.";
                    return false;
                }
            }

            lock (state.SyncRoot)
            {
                if (!IsCurrentCapturedSource(hwnd, state) || !state.Prepared)
                {
                    error = "The source did not enter captured isolation.";
                    return false;
                }
                state.Presenter = presenter;
                state.Active = true;
                state.RequestedVisible = visible;
                if (!TryApplyCapturedSourceLayout(hwnd, state, bounds, out error))
                {
                    RecordCapturedContainmentFailure(hwnd, state, error);
                    return false;
                }
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            return true;
        }

        public bool TryUpdateCapturedSourceLayout(
            long windowHandle,
            NativeWindowBounds bounds,
            bool visible,
            out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;
            if (!TryValidateAttachedBounds(bounds, out error)) return false;
            CapturedSourceState state;
            lock (_sync)
            {
                if (!_capturedSources.TryGetValue(hwnd, out state))
                {
                    error = "The captured source is not active.";
                    return false;
                }
            }

            lock (state.SyncRoot)
            {
                if (!IsCurrentCapturedSource(hwnd, state) || !state.Active)
                {
                    error = "The captured source is not active.";
                    return false;
                }
                state.RequestedVisible = visible;
                if (!TryApplyCapturedSourceLayout(hwnd, state, bounds, out error))
                {
                    RecordCapturedContainmentFailure(hwnd, state, error);
                    return false;
                }
            }
            return true;
        }

        public void CancelCapturedSource(long windowHandle)
        {
            IntPtr hwnd;
            try { hwnd = new IntPtr(windowHandle); }
            catch (OverflowException) { return; }

            CapturedSourceState state;
            lock (_sync) _capturedSources.TryGetValue(hwnd, out state);
            if (state != null)
            {
                lock (state.SyncRoot)
                {
                    lock (_sync)
                    {
                        if (_capturedSources.TryGetValue(hwnd, out CapturedSourceState current)
                            && Object.ReferenceEquals(current, state))
                            _capturedSources.Remove(hwnd);
                    }
                    TryForceHideWindow(hwnd, out _);
                }
            }
            else
            {
                TryForceHideWindow(hwnd, out _);
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
        }

        public bool TryUpdateAttachedLayout(
            long windowHandle,
            NativeWindowBounds bounds,
            bool visible,
            out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;
            if (!TryValidateAttachedBounds(bounds, out error)) return false;

            AttachedWindowState state;
            lock (_sync)
            {
                if (!_attachments.TryGetValue(hwnd, out state))
                {
                    error = "The window is not attached to a CloudOS surface.";
                    return false;
                }
            }

            if (!TryApplyAttachedLayout(hwnd, state, bounds, visible, false, true, out error))
            {
                QuarantineAfterContainmentFailure(hwnd, state, error);
                return false;
            }
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            return true;
        }

        public bool TryDetach(long windowHandle, out string error)
        {
            IntPtr hwnd;
            if (!TryAuthorizeOperation(windowHandle, out hwnd, out error)) return false;
            TryForceHideWindow(hwnd, out _);
            error = "External window detach is disabled by the CloudOS containment policy.";
            return false;
        }

        public bool IsAttached(long windowHandle)
        {
            IntPtr hwnd;
            try { hwnd = new IntPtr(windowHandle); }
            catch (OverflowException) { return false; }
            lock (_sync) return !_disposed && _attachments.ContainsKey(hwnd);
        }

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
            List<int> processIds;
            bool shouldStop;
            lock (_sync)
            {
                shouldStop = !_disposed;
                if (!shouldStop) return;
                processIds = new List<int>(_processes.Keys);
            }

            foreach (int processId in processIds)
            {
                string ignored;
                TryTerminateTrackedProcess(processId, out ignored);
            }

            lock (_sync)
            {
                _disposed = true;
                foreach (IntPtr hwnd in _windows.Keys) TryForceHideWindow(hwnd, out _);
                _attachments.Clear();
                _capturedSources.Clear();
                _processes.Clear();
                _windows.Clear();
                _containedProcesses.Clear();
                _quarantinedWindows.Clear();
                _containmentFailures.Clear();
            }

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

            AttachedWindowState attachment;
            lock (_sync) _attachments.TryGetValue(hwnd, out attachment);
            if (attachment == null)
            {
                TryForceHideWindow(hwnd, out _);
                error = "The window is quarantined and cannot change state before attachment.";
                return false;
            }

            lock (attachment.SyncRoot)
            {
                if (command != NativeMethods.SW_MINIMIZE)
                {
                    if (!attachment.RequestedVisible)
                    {
                        error = "The CloudOS Hub surface is hidden. Open the Hub before restoring this application.";
                        return false;
                    }
                    if (!TryRestoreResponsive(hwnd, true, out error)) return false;
                    if (!TryApplyAttachedLayout(hwnd, attachment, attachment.Bounds, true, false, false, out error))
                    {
                        QuarantineAfterContainmentFailure(hwnd, attachment, error);
                        return false;
                    }
                    RefreshOne(hwnd, NativeWindowChangeKind.Updated);
                    return true;
                }

                NativeMethods.ShowWindowAsync(hwnd, command);
                if (!NativeMethods.IsWindow(hwnd))
                {
                    error = "The window disappeared before the state change completed.";
                    return false;
                }
            }

            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            error = null;
            return true;
        }

        private bool TryValidateOwner(IntPtr owner, out string error)
        {
            error = null;
            if (owner == IntPtr.Zero || !NativeMethods.IsWindow(owner))
            {
                error = "The CloudOS owner window is unavailable.";
                return false;
            }

            uint ownerProcessId;
            NativeMethods.GetWindowThreadProcessId(owner, out ownerProcessId);
            if (ownerProcessId != (uint)_hostProcessId)
            {
                error = "The containment owner does not belong to the CloudOS host.";
                return false;
            }
            return true;
        }

        private static bool TryValidateAttachedBounds(NativeWindowBounds bounds, out string error)
        {
            if (bounds.Width < 32 || bounds.Height < 32
                || bounds.Width > 32768 || bounds.Height > 32768
                || bounds.X < -131072 || bounds.X > 131072
                || bounds.Y < -131072 || bounds.Y > 131072)
            {
                error = "The requested CloudOS window bounds are invalid.";
                return false;
            }
            error = null;
            return true;
        }

        private static long GetExpectedAttachedStyle(AttachedWindowState state)
        {
            return state.AttachedStyle;
        }

        private static long GetExpectedAttachedExtendedStyle(AttachedWindowState state)
        {
            return state.AttachedExtendedStyle;
        }

        private bool TryValidateAttachedContainment(
            IntPtr hwnd,
            AttachedWindowState state,
            out string error)
        {
            lock (state.SyncRoot)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    error = "The attached window no longer exists.";
                    return false;
                }
                if (!TryValidateOwner(state.Owner, out error)
                    || NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != state.Owner)
                {
                    error = error ?? "The application removed its CloudOS owner.";
                    return false;
                }
                if (NativeMethods.GetWindowStyle(hwnd) != GetExpectedAttachedStyle(state))
                {
                    error = "The application restored an external window frame during validation.";
                    return false;
                }
                if (NativeMethods.GetWindowExtendedStyle(hwnd) != GetExpectedAttachedExtendedStyle(state))
                {
                    error = "The application restored an external Alt+Tab window style.";
                    return false;
                }

                if (!NativeMethods.IsIconic(hwnd))
                {
                    NativeMethods.RECT actual;
                    NativeWindowBounds bounds = state.Bounds;
                    if (!NativeMethods.GetWindowRect(hwnd, out actual)
                        || actual.Left < bounds.X - 4
                        || actual.Top < bounds.Y - 4
                        || actual.Right > bounds.X + bounds.Width + 4
                        || actual.Bottom > bounds.Y + bounds.Height + 4)
                    {
                        error = "The application moved outside its CloudOS surface.";
                        return false;
                    }
                    if (NativeMethods.IsWindowVisible(hwnd) != state.RequestedVisible)
                    {
                        error = state.RequestedVisible
                            ? "The application disappeared from its CloudOS surface."
                            : "The application became externally visible while its CloudOS surface was hidden.";
                        return false;
                    }
                }

                error = null;
                return true;
            }
        }

        private bool TryApplyCapturedSourceLayout(
            IntPtr hwnd,
            CapturedSourceState state,
            NativeWindowBounds bounds,
            out string error)
        {
            lock (state.SyncRoot)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    error = "The captured source window no longer exists.";
                    return false;
                }
                if (!TryValidateOwner(state.Owner, out error)) return false;
                if (state.Active && !TryValidateOwner(state.Presenter, out error)) return false;

                NativeMethods.SetWindowExtendedStyle(hwnd, state.CapturedExtendedStyle);
                if (state.Active) NativeMethods.SetWindowOwner(hwnd, state.Owner);
                if (state.RequestedVisible && NativeMethods.IsIconic(hwnd))
                    NativeMethods.ShowWindowAsync(hwnd, NativeMethods.SW_RESTORE);

                IntPtr insertAfter = state.Active ? state.Presenter : state.Owner;
                if (!NativeMethods.SetWindowPos(
                    hwnd,
                    insertAfter,
                    bounds.X,
                    bounds.Y,
                    bounds.Width,
                    bounds.Height,
                    NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOOWNERZORDER
                        | (state.RequestedVisible ? NativeMethods.SWP_SHOWWINDOW : NativeMethods.SWP_HIDEWINDOW)))
                {
                    error = "Windows refused to place the captured source behind CloudOS (Win32 error "
                        + Marshal.GetLastWin32Error() + ").";
                    return false;
                }
                state.Bounds = bounds;
                return TryValidateCapturedSourceContainment(hwnd, state, out error);
            }
        }

        private bool TryValidateCapturedSourceContainment(
            IntPtr hwnd,
            CapturedSourceState state,
            out string error)
        {
            lock (state.SyncRoot)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    error = "The captured source window no longer exists.";
                    return false;
                }
                if (!TryValidateOwner(state.Owner, out error)) return false;
                IntPtr actualOwner = NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER);
                if ((state.Active && actualOwner != state.Owner)
                    || (!state.Active && actualOwner != IntPtr.Zero))
                {
                    error = state.Active
                        ? "The captured source removed its CloudOS owner."
                        : "The preparing capture source unexpectedly gained an external owner.";
                    return false;
                }
                long extendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
                if ((extendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0
                    || (extendedStyle & NativeMethods.WS_EX_TOOLWINDOW) == 0)
                {
                    error = "The captured source restored an external Alt+Tab/taskbar style.";
                    return false;
                }
                if (state.RequestedVisible && NativeMethods.IsIconic(hwnd))
                {
                    error = "The captured source became minimized and stopped rendering.";
                    return false;
                }

                bool ownerVisible = NativeMethods.IsWindowVisible(state.Owner)
                    && !NativeMethods.IsIconic(state.Owner);
                bool sourceVisible = NativeMethods.IsWindowVisible(hwnd);
                bool expectedVisible = ownerVisible && state.RequestedVisible;
                if (expectedVisible != sourceVisible)
                {
                    error = expectedVisible
                        ? "The captured source stopped rendering behind CloudOS."
                        : "The captured source remained visible while CloudOS was hidden.";
                    return false;
                }

                if (sourceVisible)
                {
                    NativeMethods.RECT actual;
                    NativeWindowBounds bounds = state.Bounds;
                    if (!NativeMethods.GetWindowRect(hwnd, out actual)
                        || actual.Left < bounds.X - 4
                        || actual.Top < bounds.Y - 4
                        || actual.Right > bounds.X + bounds.Width + 4
                        || actual.Bottom > bounds.Y + bounds.Height + 4)
                    {
                        error = "The captured source moved outside its CloudOS surface.";
                        return false;
                    }
                    if (state.Active)
                    {
                        NativeMethods.RECT presenterRect;
                        if (!NativeMethods.IsWindowVisible(state.Presenter)
                            || !NativeMethods.GetWindowRect(state.Presenter, out presenterRect)
                            || presenterRect.Left > actual.Left + 4
                            || presenterRect.Top > actual.Top + 4
                            || presenterRect.Right < actual.Right - 4
                            || presenterRect.Bottom < actual.Bottom - 4
                            || !NativeMethods.IsWindowAbove(hwnd, state.Presenter))
                        {
                            error = "The captured source is no longer fully covered by its CloudOS presenter.";
                            return false;
                        }
                    }
                }
                error = null;
                return true;
            }
        }

        private bool IsCurrentCapturedSource(IntPtr hwnd, CapturedSourceState state)
        {
            lock (_sync)
            {
                return _capturedSources.TryGetValue(hwnd, out CapturedSourceState current)
                    && Object.ReferenceEquals(current, state);
            }
        }

        private void RecordCapturedContainmentFailure(
            IntPtr hwnd,
            CapturedSourceState state,
            string reason)
        {
            lock (state.SyncRoot)
            {
                int processId = 0;
                lock (_sync)
                {
                    CapturedSourceState current;
                    if (_capturedSources.TryGetValue(hwnd, out current) && Object.ReferenceEquals(current, state))
                        _capturedSources.Remove(hwnd);
                    NativeWindowSnapshot snapshot;
                    if (_windows.TryGetValue(hwnd, out snapshot)) processId = snapshot.ProcessId;
                    if (processId == 0)
                    {
                        uint nativeProcessId;
                        NativeMethods.GetWindowThreadProcessId(hwnd, out nativeProcessId);
                        if (nativeProcessId <= Int32.MaxValue) processId = unchecked((int)nativeProcessId);
                    }
                    if (processId > 0) _quarantinedWindows[hwnd] = processId;
                    if (processId > 0) _containmentFailures[processId] = reason ?? "Captured source containment failed.";
                }
                TryForceHideWindow(hwnd, out _);
            }
        }

        private bool TryApplyAttachedLayout(
            IntPtr hwnd,
            AttachedWindowState state,
            NativeWindowBounds bounds,
            bool visible,
            bool frameChanged,
            bool preserveMinimized,
            out string error)
        {
            lock (state.SyncRoot)
            {
                if (!NativeMethods.IsWindow(hwnd))
                {
                    error = "The attached window no longer exists.";
                    return false;
                }
                if (!TryValidateOwner(state.Owner, out error)
                    || NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != state.Owner)
                {
                    error = error ?? "The application is no longer owned by the CloudOS window.";
                    return false;
                }

                if (preserveMinimized && NativeMethods.IsIconic(hwnd))
                {
                    state.Bounds = bounds;
                    state.RequestedVisible = visible;
                    error = null;
                    return true;
                }

                long currentStyle = NativeMethods.GetWindowStyle(hwnd);
                long currentExtendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
                long forbiddenFrameStyles = NativeMethods.WS_CAPTION
                    | NativeMethods.WS_THICKFRAME
                    | NativeMethods.WS_MINIMIZEBOX
                    | NativeMethods.WS_MAXIMIZEBOX
                    | NativeMethods.WS_SYSMENU;
                if (frameChanged
                    ? (currentStyle & forbiddenFrameStyles) != 0
                    : currentStyle != GetExpectedAttachedStyle(state))
                {
                    error = "The application restored an external window frame "
                        + "(initial=" + frameChanged + ", actual=0x" + currentStyle.ToString("X")
                        + ", expected=0x" + GetExpectedAttachedStyle(state).ToString("X") + ").";
                    return false;
                }
                if (frameChanged
                    ? (currentExtendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0
                        || (currentExtendedStyle & NativeMethods.WS_EX_TOOLWINDOW) == 0
                    : currentExtendedStyle != GetExpectedAttachedExtendedStyle(state))
                {
                    error = "The application restored an external Alt+Tab window style.";
                    return false;
                }

                uint flags = NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOOWNERZORDER
                    | (visible ? NativeMethods.SWP_SHOWWINDOW : NativeMethods.SWP_HIDEWINDOW);
                if (frameChanged) flags |= NativeMethods.SWP_FRAMECHANGED;
                if (!visible) flags |= NativeMethods.SWP_NOZORDER;
                if (!NativeMethods.SetWindowPos(
                    hwnd,
                    visible ? NativeMethods.HWND_TOP : IntPtr.Zero,
                    bounds.X,
                    bounds.Y,
                    bounds.Width,
                    bounds.Height,
                    flags))
                {
                    error = "Windows refused to position the application inside CloudOS (Win32 error "
                        + Marshal.GetLastWin32Error() + ").";
                    return false;
                }

                state.Bounds = bounds;
                state.RequestedVisible = visible;
                if (frameChanged)
                {
                    state.RecordAppliedStyles(
                        NativeMethods.GetWindowStyle(hwnd),
                        NativeMethods.GetWindowExtendedStyle(hwnd));
                }
                return TryValidateAttachedContainment(hwnd, state, out error);
            }
        }

        private bool TryRestoreResponsive(IntPtr hwnd, bool restoreMaximized, out string error)
        {
            if (!NativeMethods.IsIconic(hwnd) && (!restoreMaximized || !NativeMethods.IsZoomed(hwnd)))
            {
                error = null;
                return true;
            }

            IntPtr messageResult;
            IntPtr sent = NativeMethods.SendMessageTimeout(
                hwnd,
                NativeMethods.WM_SYSCOMMAND,
                new IntPtr(NativeMethods.SC_RESTORE),
                IntPtr.Zero,
                NativeMethods.SMTO_ABORTIFHUNG | NativeMethods.SMTO_BLOCK,
                (uint)_options.CloseTimeoutMilliseconds,
                out messageResult);
            if (sent == IntPtr.Zero || NativeMethods.IsIconic(hwnd)
                || (restoreMaximized && NativeMethods.IsZoomed(hwnd)))
            {
                error = "The application did not respond to the restore request.";
                return false;
            }
            error = null;
            return true;
        }

        private void QuarantineAfterContainmentFailure(IntPtr hwnd, AttachedWindowState state, string reason)
        {
            RecordAttachedContainmentFailure(hwnd, state, reason);
            RefreshOne(hwnd, NativeWindowChangeKind.Updated);
        }

        private void RecordAttachedContainmentFailure(IntPtr hwnd, AttachedWindowState state, string reason)
        {
            lock (state.SyncRoot)
            {
                int processId = 0;
                lock (_sync)
                {
                    AttachedWindowState current;
                    if (_attachments.TryGetValue(hwnd, out current) && Object.ReferenceEquals(current, state))
                        _attachments.Remove(hwnd);
                    NativeWindowSnapshot snapshot;
                    if (_windows.TryGetValue(hwnd, out snapshot)) processId = snapshot.ProcessId;
                    if (processId == 0)
                    {
                        uint nativeProcessId;
                        NativeMethods.GetWindowThreadProcessId(hwnd, out nativeProcessId);
                        if (nativeProcessId <= Int32.MaxValue) processId = unchecked((int)nativeProcessId);
                    }
                    if (processId > 0) _quarantinedWindows[hwnd] = processId;
                    if (processId > 0) _containmentFailures[processId] = reason ?? "Native window containment failed.";
                }
                TryForceHideWindow(hwnd, out _);
            }
        }

        private static bool TryForceHideWindow(IntPtr hwnd, out string error)
        {
            if (!NativeMethods.IsWindow(hwnd))
            {
                error = "The application window no longer exists.";
                return false;
            }

            NativeMethods.SetWindowPos(
                hwnd,
                IntPtr.Zero,
                0,
                0,
                0,
                0,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_NOZORDER
                    | NativeMethods.SWP_NOOWNERZORDER | NativeMethods.SWP_NOMOVE
                    | NativeMethods.SWP_NOSIZE | NativeMethods.SWP_HIDEWINDOW);
            NativeMethods.ShowWindowAsync(hwnd, NativeMethods.SW_HIDE);
            if (NativeMethods.IsWindowVisible(hwnd))
            {
                error = "Windows refused to quarantine the application HWND.";
                return false;
            }
            error = null;
            return true;
        }

        private void ForceHideWindowsForProcess(int processId)
        {
            HashSet<IntPtr> handles = new HashSet<IntPtr>();
            lock (_sync)
            {
                foreach (KeyValuePair<IntPtr, NativeWindowSnapshot> window in _windows)
                {
                    if (window.Value.ProcessId == processId) handles.Add(window.Key);
                }
                foreach (KeyValuePair<IntPtr, int> window in _quarantinedWindows)
                {
                    if (window.Value == processId) handles.Add(window.Key);
                }
                foreach (KeyValuePair<IntPtr, CapturedSourceState> window in _capturedSources)
                {
                    uint ownerPid;
                    NativeMethods.GetWindowThreadProcessId(window.Key, out ownerPid);
                    if (ownerPid == (uint)processId) handles.Add(window.Key);
                }
            }
            foreach (IntPtr hwnd in handles) TryForceHideWindow(hwnd, out _);
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
                RemoveWindow(hwnd, true);
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

            uint ownerPid;
            NativeMethods.GetWindowThreadProcessId(hwnd, out ownerPid);
            if (ownerPid == 0 || ownerPid == (uint)_hostProcessId) return false;

            TrackedProcess registration;
            AttachedWindowState attachment;
            CapturedSourceState capturedSource;
            bool isAttached;
            bool isCapturedSource;
            bool requiresContainment;
            int processId = unchecked((int)ownerPid);
            lock (_sync)
            {
                if (!_processes.TryGetValue(processId, out registration)) return false;
                isAttached = _attachments.TryGetValue(hwnd, out attachment);
                isCapturedSource = _capturedSources.TryGetValue(hwnd, out capturedSource);
                requiresContainment = _containedProcesses.Contains(processId);
            }

            if (!IsSameProcessInstance(registration))
            {
                UntrackInvalidProcess(processId);
                return false;
            }

            if (isAttached && !TryValidateAttachedContainment(hwnd, attachment, out string attachedError))
            {
                RecordAttachedContainmentFailure(hwnd, attachment, attachedError);
                return false;
            }
            if (isCapturedSource)
            {
                bool prepared;
                lock (capturedSource.SyncRoot) prepared = capturedSource.Prepared;
                if (prepared && !TryValidateCapturedSourceContainment(hwnd, capturedSource, out string capturedError))
                {
                    RecordCapturedContainmentFailure(hwnd, capturedSource, capturedError);
                    return false;
                }
            }

            if (!isAttached && !isCapturedSource && requiresContainment)
            {
                string quarantineError;
                if (!TryForceHideWindow(hwnd, out quarantineError))
                {
                    lock (_sync) _containmentFailures[processId] = quarantineError;
                    return false;
                }
                lock (_sync)
                {
                    if (!_quarantinedWindows.ContainsKey(hwnd)
                        && _quarantinedWindows.Count >= _options.MaxTotalWindows)
                    {
                        _containmentFailures[processId] = "The native quarantine window limit was exceeded.";
                        return false;
                    }
                    _quarantinedWindows[hwnd] = processId;
                }
            }
            else if (!isAttached && !isCapturedSource && !NativeMethods.IsWindowVisible(hwnd))
            {
                return false;
            }

            long extendedStyle = NativeMethods.GetWindowExtendedStyle(hwnd);
            bool isAppWindow = (extendedStyle & NativeMethods.WS_EX_APPWINDOW) != 0;
            bool isToolWindow = (extendedStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0;
            if (!isAttached && !isCapturedSource && isToolWindow && !isAppWindow) return false;
            if (!isAttached && !isCapturedSource && NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero && !isAppWindow) return false;
            if (!isAttached && !isCapturedSource && NativeMethods.IsWindowCloaked(hwnd)) return false;

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
                isAttached || isCapturedSource,
                new NativeWindowBounds(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top),
                DateTimeOffset.UtcNow);
            return true;
        }

        private void HookThreadMain()
        {
            try
            {
                _hookThreadId = NativeMethods.GetCurrentThreadId();

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
                    RemoveWindow(hwnd, true);
                    return;
                }

                RefreshOne(hwnd, NativeWindowChangeKind.Updated);
            }
            catch
            {
            }
        }

        private void RefreshOne(IntPtr hwnd, NativeWindowChangeKind existingKind)
        {
            NativeWindowSnapshot snapshot;
            if (!TryCreateSnapshot(hwnd, out snapshot))
            {
                RemoveWindow(hwnd, false);
                return;
            }

            NativeWindowChangedEventArgs change = null;
            lock (_sync)
            {
                NativeWindowSnapshot previous;
                bool alreadyKnown = _windows.TryGetValue(hwnd, out previous);
                if (!alreadyKnown
                    && (_windows.Count >= _options.MaxTotalWindows
                        || CountWindowsForProcessLocked(snapshot.ProcessId) >= _options.MaxWindowsPerProcess))
                    return;

                _windows[hwnd] = snapshot;
                if (!alreadyKnown)
                    change = new NativeWindowChangedEventArgs(NativeWindowChangeKind.Added, snapshot);
                else if (!HasSameObservableState(previous, snapshot))
                    change = new NativeWindowChangedEventArgs(existingKind, snapshot);
            }
            if (change != null) RaiseChange(change);
        }

        private void RemoveWindow(IntPtr hwnd, bool discardAttachment = false)
        {
            NativeWindowChangedEventArgs change = null;
            lock (_sync)
            {
                if (!discardAttachment
                    && (_attachments.ContainsKey(hwnd) || _capturedSources.ContainsKey(hwnd))
                    && NativeMethods.IsWindow(hwnd))
                    return;
                NativeWindowSnapshot snapshot;
                if (_windows.TryGetValue(hwnd, out snapshot))
                {
                    _windows.Remove(hwnd);
                    change = new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, snapshot);
                }
                if (discardAttachment || !NativeMethods.IsWindow(hwnd))
                {
                    _attachments.Remove(hwnd);
                    _capturedSources.Remove(hwnd);
                    _quarantinedWindows.Remove(hwnd);
                }
            }
            if (change != null) RaiseChange(change);
        }

        private void UntrackInvalidProcess(int processId)
        {
            RemoveTrackedProcess(processId);
        }

        private void RemoveTrackedProcess(int processId)
        {
            List<NativeWindowChangedEventArgs> changes = new List<NativeWindowChangedEventArgs>();
            lock (_sync)
            {
                _processes.Remove(processId);
                _containedProcesses.Remove(processId);
                _containmentFailures.Remove(processId);
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
                _attachments.Remove(hwnd);
                _capturedSources.Remove(hwnd);
                _quarantinedWindows.Remove(hwnd);
                changes.Add(new NativeWindowChangedEventArgs(NativeWindowChangeKind.Removed, snapshot));
            }

            List<IntPtr> quarantined = new List<IntPtr>();
            foreach (KeyValuePair<IntPtr, int> item in _quarantinedWindows)
            {
                if (item.Value == processId) quarantined.Add(item.Key);
            }
            foreach (IntPtr hwnd in quarantined) _quarantinedWindows.Remove(hwnd);

            List<IntPtr> captured = new List<IntPtr>();
            foreach (KeyValuePair<IntPtr, CapturedSourceState> item in _capturedSources)
            {
                uint ownerPid;
                NativeMethods.GetWindowThreadProcessId(item.Key, out ownerPid);
                if (ownerPid == (uint)processId) captured.Add(item.Key);
            }
            foreach (IntPtr hwnd in captured) _capturedSources.Remove(hwnd);
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

        internal static bool HasSameObservableState(NativeWindowSnapshot left, NativeWindowSnapshot right)
        {
            if (ReferenceEquals(left, right)) return true;
            if (left == null || right == null) return false;
            return left.Handle == right.Handle
                && left.ProcessId == right.ProcessId
                && String.Equals(left.Title, right.Title, StringComparison.Ordinal)
                && left.IsVisible == right.IsVisible
                && left.IsMinimized == right.IsMinimized
                && left.IsMaximized == right.IsMaximized
                && left.IsAttached == right.IsAttached
                && left.Bounds.X == right.Bounds.X
                && left.Bounds.Y == right.Bounds.Y
                && left.Bounds.Width == right.Bounds.Width
                && left.Bounds.Height == right.Bounds.Height;
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
            catch { }
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

        private sealed class AttachedWindowState
        {
            public AttachedWindowState(
                IntPtr owner,
                long originalStyle,
                long originalExtendedStyle)
            {
                Owner = owner;
                OriginalStyle = originalStyle;
                OriginalExtendedStyle = originalExtendedStyle;
                AttachedStyle = originalStyle
                    & ~NativeMethods.WS_CAPTION
                    & ~NativeMethods.WS_THICKFRAME
                    & ~NativeMethods.WS_MINIMIZEBOX
                    & ~NativeMethods.WS_MAXIMIZEBOX
                    & ~NativeMethods.WS_SYSMENU;
                AttachedExtendedStyle = (originalExtendedStyle & ~NativeMethods.WS_EX_APPWINDOW)
                    | NativeMethods.WS_EX_TOOLWINDOW;
            }

            public object SyncRoot { get; } = new object();
            public IntPtr Owner { get; private set; }
            public long OriginalStyle { get; private set; }
            public long OriginalExtendedStyle { get; private set; }
            public long AttachedStyle { get; private set; }
            public long AttachedExtendedStyle { get; private set; }
            public NativeWindowBounds Bounds { get; set; }
            public bool RequestedVisible { get; set; }

            public void RecordAppliedStyles(long style, long extendedStyle)
            {
                AttachedStyle = style;
                AttachedExtendedStyle = extendedStyle;
            }
        }

        private sealed class CapturedSourceState
        {
            public CapturedSourceState(IntPtr owner, long originalExtendedStyle)
            {
                Owner = owner;
                OriginalExtendedStyle = originalExtendedStyle;
                CapturedExtendedStyle = (originalExtendedStyle & ~NativeMethods.WS_EX_APPWINDOW)
                    | NativeMethods.WS_EX_TOOLWINDOW;
            }

            public object SyncRoot { get; } = new object();
            public IntPtr Owner { get; private set; }
            public IntPtr Presenter { get; set; }
            public long OriginalExtendedStyle { get; private set; }
            public long CapturedExtendedStyle { get; private set; }
            public NativeWindowBounds Bounds { get; set; }
            public bool Prepared { get; set; }
            public bool Active { get; set; }
            public bool RequestedVisible { get; set; }
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
            TerminationTimeoutMilliseconds = 3000;
            HookStartupTimeoutMilliseconds = 5000;
            HookShutdownTimeoutMilliseconds = 3000;
        }

        public int MaxTrackedProcesses { get; set; }
        public int MaxWindowsPerProcess { get; set; }
        public int MaxTotalWindows { get; set; }
        public int MaxTitleLength { get; set; }
        public int CloseTimeoutMilliseconds { get; set; }
        public int TerminationTimeoutMilliseconds { get; set; }
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
            if (TerminationTimeoutMilliseconds < 100 || TerminationTimeoutMilliseconds > 30000) throw new ArgumentOutOfRangeException("TerminationTimeoutMilliseconds");
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
            bool isAttached,
            NativeWindowBounds bounds,
            DateTimeOffset observedAtUtc)
        {
            Handle = handle;
            ProcessId = processId;
            Title = title ?? String.Empty;
            IsVisible = isVisible;
            IsMinimized = isMinimized;
            IsMaximized = isMaximized;
            IsAttached = isAttached;
            Bounds = bounds;
            ObservedAtUtc = observedAtUtc;
        }

        public long Handle { get; private set; }
        public int ProcessId { get; private set; }
        public string Title { get; private set; }
        public bool IsVisible { get; private set; }
        public bool IsMinimized { get; private set; }
        public bool IsMaximized { get; private set; }
        public bool IsAttached { get; private set; }
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
        internal const uint GW_HWNDPREV = 3;
        internal const int GWL_STYLE = -16;
        internal const int GWL_EXSTYLE = -20;
        internal const int GWLP_HWNDPARENT = -8;
        internal const long WS_CAPTION = 0x00C00000L;
        internal const long WS_THICKFRAME = 0x00040000L;
        internal const long WS_MINIMIZEBOX = 0x00020000L;
        internal const long WS_MAXIMIZEBOX = 0x00010000L;
        internal const long WS_SYSMENU = 0x00080000L;
        internal const long WS_EX_TOOLWINDOW = 0x00000080L;
        internal const long WS_EX_APPWINDOW = 0x00040000L;
        internal const int SW_HIDE = 0;
        internal const int SW_SHOWNOACTIVATE = 4;
        internal const int SW_SHOWMINIMIZED = 2;
        internal const int SW_SHOWMAXIMIZED = 3;
        internal const int SW_MINIMIZE = 6;
        internal const int SW_MAXIMIZE = 3;
        internal const int SW_RESTORE = 9;
        internal const uint WM_CLOSE = 0x0010;
        internal const uint WM_QUIT = 0x0012;
        internal const uint WM_SYSCOMMAND = 0x0112;
        internal const int SC_RESTORE = 0xF120;
        internal const uint SMTO_BLOCK = 0x0001;
        internal const uint SMTO_ABORTIFHUNG = 0x0002;
        internal const int ERROR_TIMEOUT = 1460;
        internal const uint PM_NOREMOVE = 0;
        internal const int DWMWA_CLOAKED = 14;
        internal const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        internal const uint TOKEN_QUERY = 0x0008;
        internal const int TOKEN_INTEGRITY_LEVEL = 25;
        internal const int ERROR_INSUFFICIENT_BUFFER = 122;
        internal const uint SWP_NOZORDER = 0x0004;
        internal const uint SWP_NOSIZE = 0x0001;
        internal const uint SWP_NOMOVE = 0x0002;
        internal const uint SWP_NOACTIVATE = 0x0010;
        internal const uint SWP_FRAMECHANGED = 0x0020;
        internal const uint SWP_SHOWWINDOW = 0x0040;
        internal const uint SWP_HIDEWINDOW = 0x0080;
        internal const uint SWP_NOOWNERZORDER = 0x0200;
        internal static readonly IntPtr HWND_TOP = IntPtr.Zero;

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
        internal struct WINDOWPLACEMENT
        {
            internal int Length;
            internal int Flags;
            internal int ShowCommand;
            internal POINT MinPosition;
            internal POINT MaxPosition;
            internal RECT NormalPosition;
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

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowPlacement(IntPtr hwnd, ref WINDOWPLACEMENT placement);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPlacement(IntPtr hwnd, [In] ref WINDOWPLACEMENT placement);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(
            IntPtr hwnd,
            IntPtr insertAfter,
            int x,
            int y,
            int width,
            int height,
            uint flags);

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

        [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
        private static extern int SetWindowLong32(IntPtr hwnd, int index, int value);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hwnd, int index, IntPtr value);

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

        internal static long GetWindowStyle(IntPtr hwnd)
        {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hwnd, GWL_STYLE).ToInt64()
                : GetWindowLong32(hwnd, GWL_STYLE);
        }

        internal static void SetWindowStyle(IntPtr hwnd, long style)
        {
            SetWindowLongValue(hwnd, GWL_STYLE, new IntPtr(style));
        }

        internal static void SetWindowExtendedStyle(IntPtr hwnd, long style)
        {
            SetWindowLongValue(hwnd, GWL_EXSTYLE, new IntPtr(style));
        }

        internal static void SetWindowOwner(IntPtr hwnd, IntPtr owner)
        {
            SetWindowLongValue(hwnd, GWLP_HWNDPARENT, owner);
        }

        internal static WINDOWPLACEMENT CreateWindowPlacement()
        {
            WINDOWPLACEMENT placement = new WINDOWPLACEMENT();
            placement.Length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
            return placement;
        }

        private static void SetWindowLongValue(IntPtr hwnd, int index, IntPtr value)
        {
            if (IntPtr.Size == 8)
                SetWindowLongPtr64(hwnd, index, value);
            else
                SetWindowLong32(hwnd, index, value.ToInt32());
        }

        internal static string GetWindowTitle(IntPtr hwnd, int maxLength)
        {
            StringBuilder buffer = new StringBuilder(maxLength + 1);
            int copied = GetWindowText(hwnd, buffer, buffer.Capacity);
            return copied > 0 ? buffer.ToString(0, copied) : String.Empty;
        }

        internal static bool IsWindowAbove(IntPtr lowerWindow, IntPtr expectedUpperWindow)
        {
            if (lowerWindow == IntPtr.Zero || expectedUpperWindow == IntPtr.Zero) return false;
            IntPtr current = lowerWindow;
            for (int index = 0; index < 512; index++)
            {
                current = GetWindow(current, GW_HWNDPREV);
                if (current == IntPtr.Zero) return false;
                if (current == expectedUpperWindow) return true;
            }
            return false;
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
