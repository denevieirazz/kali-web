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
        // Preserve the native HRESULT and explicit output pointer. Treating this COM method as
        // an IntPtr-returning method changes the ABI shape and can manufacture an unusable item.
        [PreserveSig]
        int CreateForWindow([In] IntPtr window, in Guid iid, out IntPtr result);

        [PreserveSig]
        int CreateForMonitor([In] IntPtr monitor, in Guid iid, out IntPtr result);
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

    public static GraphicsCaptureItem CreateItemForWindow(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero)
            throw new ArgumentException("A non-zero HWND is required.", nameof(windowHandle));

        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var result = interop.CreateForWindow(windowHandle, GraphicsCaptureItemGuid, out var itemPointer);
        if (result < 0)
            Marshal.ThrowExceptionForHR(result);
        if (itemPointer == IntPtr.Zero)
            throw new InvalidOperationException("Windows.Graphics.Capture returned a null GraphicsCaptureItem.");

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
            // CreateDirect3D11DeviceFromDXGIDevice requires IDXGIDevice*, not ID3D11Device*.
            // Query the D3D device for the correct interface before crossing the WinRT bridge.
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

            // The returned pointer is an IInspectable for a WinRT IDirect3DDevice. Project it
            // with the CsWinRT inspectable marshaler; MarshalInterface is for classic COM ABI.
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
