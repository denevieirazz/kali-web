using System.Runtime.InteropServices;
using TerraFX.Interop.DirectX;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace CloudOS.WindowsCapture;

internal static unsafe partial class WindowsCaptureInterop
{
    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid DxgiDeviceGuid = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");

    [ComImport]
    [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInterop
    {
        // CsWinRT's COM interop guidance keeps HRESULT translation in the CLR stub:
        // native HRESULT methods are represented as void and ABI values stay explicit.
        // This avoids mixing PreserveSig/manual HRESULT handling with the RCW produced by As<T>().
        void CreateForWindow([In] IntPtr window, in Guid iid, out IntPtr result);
        void CreateForMonitor([In] IntPtr monitor, in Guid iid, out IntPtr result);
    }

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

    public static GraphicsCaptureItem CreateItemForWindow(IntPtr windowHandle) =>
        CreateItem(static (interop, handle, iid, out IntPtr result) => interop.CreateForWindow(handle, iid, out result), windowHandle, "window");

    public static GraphicsCaptureItem CreateItemForMonitor(IntPtr monitorHandle) =>
        CreateItem(static (interop, handle, iid, out IntPtr result) => interop.CreateForMonitor(handle, iid, out result), monitorHandle, "monitor");

    private delegate void CreateItemCall(IGraphicsCaptureItemInterop interop, IntPtr handle, in Guid iid, out IntPtr result);

    private static GraphicsCaptureItem CreateItem(CreateItemCall create, IntPtr handle, string targetKind)
    {
        if (handle == IntPtr.Zero)
            throw new ArgumentException($"A non-zero {targetKind} handle is required.", nameof(handle));

        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        create(interop, handle, GraphicsCaptureItemGuid, out var itemPointer);
        if (itemPointer == IntPtr.Zero)
            throw new InvalidOperationException($"Windows.Graphics.Capture returned a null GraphicsCaptureItem for {targetKind}.");

        try
        {
            return GraphicsCaptureItem.FromAbi(itemPointer);
        }
        finally
        {
            Marshal.Release(itemPointer);
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
