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

internal static unsafe partial class WindowsCaptureInterop
{
    private const string GraphicsCaptureItemRuntimeClass = "Windows.Graphics.Capture.GraphicsCaptureItem";
    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid GraphicsCaptureItemInteropGuid = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private static readonly Guid DxgiDeviceGuid = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");

    [ComImport]
    [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInteropProjected
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
    private static partial int RoGetActivationFactory(IntPtr activatableClassId, in Guid iid, out IntPtr factory);

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

    public static GraphicsCaptureItem CreateItemForWindow(
        IntPtr windowHandle,
        WindowsCaptureItemFactoryKind factoryKind = WindowsCaptureItemFactoryKind.RawActivationFactory)
    {
        if (windowHandle == IntPtr.Zero)
            throw new ArgumentException("A non-zero HWND is required.", nameof(windowHandle));

        return factoryKind switch
        {
            WindowsCaptureItemFactoryKind.RawActivationFactory => CreateItemRaw(windowHandle, isWindow: true),
            WindowsCaptureItemFactoryKind.ProjectedFactory => CreateItemProjected(windowHandle, isWindow: true),
            _ => throw new ArgumentOutOfRangeException(nameof(factoryKind))
        };
    }

    public static GraphicsCaptureItem CreateItemForMonitor(
        IntPtr monitorHandle,
        WindowsCaptureItemFactoryKind factoryKind = WindowsCaptureItemFactoryKind.RawActivationFactory)
    {
        if (monitorHandle == IntPtr.Zero)
            throw new ArgumentException("A non-zero HMONITOR is required.", nameof(monitorHandle));

        return factoryKind switch
        {
            WindowsCaptureItemFactoryKind.RawActivationFactory => CreateItemRaw(monitorHandle, isWindow: false),
            WindowsCaptureItemFactoryKind.ProjectedFactory => CreateItemProjected(monitorHandle, isWindow: false),
            _ => throw new ArgumentOutOfRangeException(nameof(factoryKind))
        };
    }

    private static GraphicsCaptureItem CreateItemRaw(IntPtr targetHandle, bool isWindow)
    {
        // Match the native C++/WinRT contract exactly:
        // RoGetActivationFactory(GraphicsCaptureItem, IGraphicsCaptureItemInterop) followed by
        // vtable CreateForWindow/CreateForMonitor. This removes RCW/projection ambiguity from
        // the factory boundary while keeping CsWinRT only for the returned runtime object.
        IntPtr className = IntPtr.Zero;
        IntPtr factory = IntPtr.Zero;
        IntPtr itemPointer = IntPtr.Zero;
        try
        {
            var result = WindowsCreateString(
                GraphicsCaptureItemRuntimeClass,
                checked((uint)GraphicsCaptureItemRuntimeClass.Length),
                out className);
            ThrowIfFailed(result, "WindowsCreateString(GraphicsCaptureItem)");

            result = RoGetActivationFactory(className, GraphicsCaptureItemInteropGuid, out factory);
            ThrowIfFailed(result, "RoGetActivationFactory(IGraphicsCaptureItemInterop)");
            if (factory == IntPtr.Zero)
                throw new InvalidOperationException("RoGetActivationFactory returned a null IGraphicsCaptureItemInterop pointer.");

            // IUnknown occupies slots 0..2. IGraphicsCaptureItemInterop then exposes:
            // slot 3 = CreateForWindow, slot 4 = CreateForMonitor.
            var method = GetVTableMethod<CreateCaptureItemAbi>(factory, isWindow ? 3 : 4);
            var itemIid = GraphicsCaptureItemGuid;
            result = method(factory, targetHandle, ref itemIid, out itemPointer);
            ThrowIfFailed(result, isWindow ? "IGraphicsCaptureItemInterop::CreateForWindow" : "IGraphicsCaptureItemInterop::CreateForMonitor");

            return ProjectCaptureItem(itemPointer, isWindow ? "window/raw-activation-factory" : "monitor/raw-activation-factory");
        }
        finally
        {
            if (itemPointer != IntPtr.Zero) Marshal.Release(itemPointer);
            if (factory != IntPtr.Zero) Marshal.Release(factory);
            if (className != IntPtr.Zero) _ = WindowsDeleteString(className);
        }
    }

    private static GraphicsCaptureItem CreateItemProjected(IntPtr targetHandle, bool isWindow)
    {
        // Retained strictly as a diagnostic control for the pre-fix CsWinRT/RCW path.
        // Product code defaults to RawActivationFactory and never silently falls back here.
        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInteropProjected>();
        if (isWindow)
            interop.CreateForWindow(targetHandle, GraphicsCaptureItemGuid, out var itemPointer);
        else
            interop.CreateForMonitor(targetHandle, GraphicsCaptureItemGuid, out itemPointer);

        try
        {
            return ProjectCaptureItem(itemPointer, isWindow ? "window/projected-factory" : "monitor/projected-factory");
        }
        finally
        {
            if (itemPointer != IntPtr.Zero) Marshal.Release(itemPointer);
        }
    }

    private static GraphicsCaptureItem ProjectCaptureItem(IntPtr itemPointer, string targetKind)
    {
        if (itemPointer == IntPtr.Zero)
            throw new InvalidOperationException($"Windows.Graphics.Capture returned a null GraphicsCaptureItem for {targetKind}.");

        return GraphicsCaptureItem.FromAbi(itemPointer);
    }

    private static TDelegate GetVTableMethod<TDelegate>(IntPtr instance, int slot)
        where TDelegate : Delegate
    {
        var vtable = Marshal.ReadIntPtr(instance);
        if (vtable == IntPtr.Zero)
            throw new InvalidOperationException("COM object exposed a null vtable.");
        var method = Marshal.ReadIntPtr(vtable, checked(slot * IntPtr.Size));
        if (method == IntPtr.Zero)
            throw new InvalidOperationException($"COM vtable slot {slot} was null.");
        return Marshal.GetDelegateForFunctionPointer<TDelegate>(method);
    }

    private static void ThrowIfFailed(int hresult, string operation)
    {
        if (hresult >= 0) return;
        try
        {
            Marshal.ThrowExceptionForHR(hresult);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            throw new InvalidOperationException($"{operation} failed with HRESULT 0x{hresult:X8}: {error.Message}", error);
        }
    }

    public static IDirect3DDevice CreateDirect3DDevice()
    {
        ID3D11Device* nativeDevice = null;
        ID3D11DeviceContext* immediateContext = null;
        ReadOnlySpan<D3D_FEATURE_LEVEL> featureLevels =
        [
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_11_1,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_11_0,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_10_1,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_10_0,
            D3D_FEATURE_LEVEL.D3D_FEATURE_LEVEL_9_3
        ];

        int result;
        fixed (D3D_FEATURE_LEVEL* featureLevelPointer = featureLevels)
        {
            D3D_FEATURE_LEVEL selectedFeatureLevel = default;
            result = D3D11CreateDevice(
                null,
                D3D_DRIVER_TYPE.D3D_DRIVER_TYPE_HARDWARE,
                0,
                (uint)D3D11_CREATE_DEVICE_FLAG.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                featureLevelPointer,
                (uint)featureLevels.Length,
                7,
                &nativeDevice,
                &selectedFeatureLevel,
                &immediateContext);
        }

        if (result < 0 || nativeDevice is null)
        {
            if (immediateContext is not null) immediateContext->Release();
            if (nativeDevice is not null) nativeDevice->Release();
            if (result < 0) Marshal.ThrowExceptionForHR(result);
            throw new InvalidOperationException("D3D11CreateDevice returned no device.");
        }

        if (immediateContext is not null) immediateContext->Release();

        IntPtr dxgiDevice = IntPtr.Zero;
        IntPtr graphicsDevice = IntPtr.Zero;
        try
        {
            var iid = DxgiDeviceGuid;
            result = Marshal.QueryInterface((IntPtr)nativeDevice, ref iid, out dxgiDevice);
            if (result < 0 || dxgiDevice == IntPtr.Zero)
            {
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                throw new InvalidOperationException("ID3D11Device did not expose IDXGIDevice.");
            }

            result = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out graphicsDevice);
            if (result < 0 || graphicsDevice == IntPtr.Zero)
            {
                if (result < 0) Marshal.ThrowExceptionForHR(result);
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
