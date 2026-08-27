using System.Runtime.InteropServices;
using TerraFX.Interop.DirectX;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace CloudOS.WindowsCapture;

public enum WindowsCaptureItemFactoryKind
{
    RawActivationFactory,
    ProjectedFactory
}

public enum WindowsCaptureItemProjectionKind
{
    ProjectedTypeFromAbi,
    MarshalInterfaceFromAbi
}

public enum WindowsCaptureAbiLifetimeKind
{
    ReleaseAfterProjection,
    HoldUntilSessionDispose
}

internal sealed class WindowsCaptureItemLease : IDisposable
{
    private IntPtr _abiReference;
    private bool _disposed;

    public WindowsCaptureItemLease(
        GraphicsCaptureItem item,
        IntPtr abiReference,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind,
        string creationPath)
    {
        Item = item ?? throw new ArgumentNullException(nameof(item));
        _abiReference = abiReference;
        ProjectionKind = projectionKind;
        LifetimeKind = lifetimeKind;
        CreationPath = creationPath;
    }

    public GraphicsCaptureItem Item { get; }
    public WindowsCaptureItemProjectionKind ProjectionKind { get; }
    public WindowsCaptureAbiLifetimeKind LifetimeKind { get; }
    public string CreationPath { get; }
    public bool HoldsAbiReference => _abiReference != IntPtr.Zero;

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        var pointer = Interlocked.Exchange(ref _abiReference, IntPtr.Zero);
        if (pointer != IntPtr.Zero)
            Marshal.Release(pointer);
    }
}

internal static unsafe partial class WindowsCaptureInterop
{
    private const string CaptureItemRuntimeClass = "Windows.Graphics.Capture.GraphicsCaptureItem";
    private static readonly Guid CaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid CaptureInteropGuid = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid DxgiDeviceGuid = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");

    [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IProjectedCaptureInterop
    {
        void CreateForWindow([In] IntPtr window, in Guid iid, out IntPtr result);
        void CreateForMonitor([In] IntPtr monitor, in Guid iid, out IntPtr result);
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int CreateCaptureItemAbi(IntPtr self, IntPtr target, ref Guid iid, out IntPtr result);

    [LibraryImport("combase.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int WindowsCreateString(string sourceString, uint length, out IntPtr hstring);

    [LibraryImport("combase.dll")]
    private static partial int WindowsDeleteString(IntPtr hstring);

    [LibraryImport("combase.dll")]
    private static partial int RoGetActivationFactory(IntPtr classId, in Guid iid, out IntPtr factory);

    [LibraryImport("d3d11.dll", EntryPoint = "CreateDirect3D11DeviceFromDXGIDevice")]
    private static partial int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [LibraryImport("d3d11.dll")]
    private static partial int D3D11CreateDevice(
        IDXGIAdapter* adapter,
        D3D_DRIVER_TYPE driverType,
        nint software,
        uint flags,
        D3D_FEATURE_LEVEL* featureLevels,
        uint featureLevelCount,
        uint sdkVersion,
        ID3D11Device** device,
        D3D_FEATURE_LEVEL* selectedFeatureLevel,
        ID3D11DeviceContext** immediateContext);

    public static WindowsCaptureItemLease CreateItemForWindow(
        IntPtr hwnd,
        WindowsCaptureItemFactoryKind factoryKind,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind) =>
        factoryKind == WindowsCaptureItemFactoryKind.RawActivationFactory
            ? CreateItemRaw(hwnd, true, projectionKind, lifetimeKind)
            : CreateItemProjected(hwnd, true, projectionKind, lifetimeKind);

    public static WindowsCaptureItemLease CreateItemForMonitor(
        IntPtr hmon,
        WindowsCaptureItemFactoryKind factoryKind,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind) =>
        factoryKind == WindowsCaptureItemFactoryKind.RawActivationFactory
            ? CreateItemRaw(hmon, false, projectionKind, lifetimeKind)
            : CreateItemProjected(hmon, false, projectionKind, lifetimeKind);

    private static WindowsCaptureItemLease CreateItemRaw(
        IntPtr target,
        bool window,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind)
    {
        if (target == IntPtr.Zero) throw new ArgumentException("Capture handle must be non-zero.", nameof(target));

        IntPtr className = IntPtr.Zero;
        IntPtr factory = IntPtr.Zero;
        IntPtr itemPointer = IntPtr.Zero;
        try
        {
            var hr = WindowsCreateString(CaptureItemRuntimeClass, (uint)CaptureItemRuntimeClass.Length, out className);
            ThrowIfFailed(hr, "WindowsCreateString");
            hr = RoGetActivationFactory(className, CaptureInteropGuid, out factory);
            ThrowIfFailed(hr, "RoGetActivationFactory");
            if (factory == IntPtr.Zero) throw new InvalidOperationException("Activation factory pointer was null.");

            var callback = GetVTableMethod<CreateCaptureItemAbi>(factory, window ? 3 : 4);
            var iid = CaptureItemGuid;
            hr = callback(factory, target, ref iid, out itemPointer);
            ThrowIfFailed(hr, window ? "CreateForWindow" : "CreateForMonitor");

            // Transfer the ABI reference exactly once. From this point ProjectItem owns it,
            // so the outer finally must not release the same pointer on a projection error.
            var ownedPointer = itemPointer;
            itemPointer = IntPtr.Zero;
            return ProjectItem(
                ownedPointer,
                window ? "window/raw" : "monitor/raw",
                projectionKind,
                lifetimeKind);
        }
        finally
        {
            if (itemPointer != IntPtr.Zero) Marshal.Release(itemPointer);
            if (factory != IntPtr.Zero) Marshal.Release(factory);
            if (className != IntPtr.Zero) _ = WindowsDeleteString(className);
        }
    }

    private static WindowsCaptureItemLease CreateItemProjected(
        IntPtr target,
        bool window,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind)
    {
        if (target == IntPtr.Zero) throw new ArgumentException("Capture handle must be non-zero.", nameof(target));

        var interop = GraphicsCaptureItem.As<IProjectedCaptureInterop>();
        IntPtr itemPointer;
        if (window)
            interop.CreateForWindow(target, CaptureItemGuid, out itemPointer);
        else
            interop.CreateForMonitor(target, CaptureItemGuid, out itemPointer);

        try
        {
            var ownedPointer = itemPointer;
            itemPointer = IntPtr.Zero;
            return ProjectItem(
                ownedPointer,
                window ? "window/projected" : "monitor/projected",
                projectionKind,
                lifetimeKind);
        }
        finally
        {
            if (itemPointer != IntPtr.Zero) Marshal.Release(itemPointer);
        }
    }

    private static WindowsCaptureItemLease ProjectItem(
        IntPtr pointer,
        string path,
        WindowsCaptureItemProjectionKind projectionKind,
        WindowsCaptureAbiLifetimeKind lifetimeKind)
    {
        if (pointer == IntPtr.Zero) throw new InvalidOperationException($"Capture item pointer was null for {path}.");

        GraphicsCaptureItem item;
        try
        {
            item = projectionKind switch
            {
                WindowsCaptureItemProjectionKind.ProjectedTypeFromAbi => GraphicsCaptureItem.FromAbi(pointer),
                WindowsCaptureItemProjectionKind.MarshalInterfaceFromAbi => MarshalInterface<GraphicsCaptureItem>.FromAbi(pointer),
                _ => throw new ArgumentOutOfRangeException(nameof(projectionKind))
            };
        }
        catch
        {
            Marshal.Release(pointer);
            throw;
        }

        if (lifetimeKind == WindowsCaptureAbiLifetimeKind.ReleaseAfterProjection)
        {
            Marshal.Release(pointer);
            return new WindowsCaptureItemLease(item, IntPtr.Zero, projectionKind, lifetimeKind, path);
        }

        if (lifetimeKind != WindowsCaptureAbiLifetimeKind.HoldUntilSessionDispose)
        {
            Marshal.Release(pointer);
            throw new ArgumentOutOfRangeException(nameof(lifetimeKind));
        }

        return new WindowsCaptureItemLease(item, pointer, projectionKind, lifetimeKind, path);
    }

    private static T GetVTableMethod<T>(IntPtr instance, int slot) where T : Delegate
    {
        var vtable = Marshal.ReadIntPtr(instance);
        if (vtable == IntPtr.Zero) throw new InvalidOperationException("COM vtable was null.");
        var method = Marshal.ReadIntPtr(vtable, slot * IntPtr.Size);
        if (method == IntPtr.Zero) throw new InvalidOperationException($"COM vtable slot {slot} was null.");
        return Marshal.GetDelegateForFunctionPointer<T>(method);
    }

    private static void ThrowIfFailed(int hr, string operation)
    {
        if (hr >= 0) return;
        try { Marshal.ThrowExceptionForHR(hr); }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            throw new InvalidOperationException($"{operation} failed with HRESULT 0x{hr:X8}: {error.Message}", error);
        }
    }

    public static IDirect3DDevice CreateDirect3DDevice()
    {
        ID3D11Device* nativeDevice = null;
        ID3D11DeviceContext* context = null;
        ReadOnlySpan<D3D_FEATURE_LEVEL> levels =
        [
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_11_1,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_11_0,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_10_0,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_9_3
        ];

        int hr;
        fixed (D3D_FEATURE_LEVEL* levelPointer = levels)
        {
            D3D_FEATURE_LEVEL selected = default;
            hr = D3D11CreateDevice(
                null,
                D3D_DRIVER_TYPE.D3D_DRIVER_TYPE_HARDWARE,
                0,
                (uint)D3D11_CREATE_DEVICE_FLAG.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                levelPointer,
                (uint)levels.Length,
                7,
                &nativeDevice,
                &selected,
                &context);
        }

        if (context is not null) context->Release();
        if (hr < 0 || nativeDevice is null)
        {
            if (nativeDevice is not null) nativeDevice->Release();
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
            throw new InvalidOperationException("D3D11CreateDevice returned no device.");
        }

        IntPtr dxgiDevice = IntPtr.Zero;
        IntPtr graphicsDevice = IntPtr.Zero;
        try
        {
            var iid = DxgiDeviceGuid;
            hr = Marshal.QueryInterface((IntPtr)nativeDevice, ref iid, out dxgiDevice);
            if (hr < 0 || dxgiDevice == IntPtr.Zero)
            {
                if (hr < 0) Marshal.ThrowExceptionForHR(hr);
                throw new InvalidOperationException("ID3D11Device did not expose IDXGIDevice.");
            }

            hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out graphicsDevice);
            if (hr < 0 || graphicsDevice == IntPtr.Zero)
            {
                if (hr < 0) Marshal.ThrowExceptionForHR(hr);
                throw new InvalidOperationException("CreateDirect3D11DeviceFromDXGIDevice returned no device.");
            }

            return MarshalInspectable<IDirect3DDevice>.FromAbi(graphicsDevice);
        }
        finally
        {
            if (graphicsDevice != IntPtr.Zero) Marshal.Release(graphicsDevice);
            if (dxgiDevice != IntPtr.Zero) Marshal.Release(dxgiDevice);
            nativeDevice->Release();
        }
    }
}
