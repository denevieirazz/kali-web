using System.Runtime.InteropServices;
using TerraFX.Interop.DirectX;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace CloudOS.WindowsCapture;

internal static unsafe partial class WindowsCaptureInterop
{
    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");

    [ComImport]
    [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [ComVisible(true)]
    private interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow([In] IntPtr window, in Guid iid);
        IntPtr CreateForMonitor([In] IntPtr monitor, in Guid iid);
    }

    [LibraryImport("d3d11.dll", EntryPoint = "CreateDirect3D11DeviceFromDXGIDevice")]
    private static partial uint CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [LibraryImport("d3d11.dll")]
    private static partial uint D3D11CreateDevice(
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
        if (windowHandle == IntPtr.Zero) throw new ArgumentException("A non-zero HWND is required.", nameof(windowHandle));

        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var itemPointer = interop.CreateForWindow(windowHandle, GraphicsCaptureItemGuid);
        if (itemPointer == IntPtr.Zero) throw new InvalidOperationException("Windows.Graphics.Capture returned a null GraphicsCaptureItem.");

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

        uint result;
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

        if (result != 0 || nativeDevice is null)
        {
            if (immediateContext is not null) immediateContext->Release();
            if (nativeDevice is not null) nativeDevice->Release();
            Marshal.ThrowExceptionForHR(unchecked((int)result));
            throw new InvalidOperationException("D3D11CreateDevice failed without an HRESULT exception.");
        }

        if (immediateContext is not null) immediateContext->Release();

        IntPtr graphicsDevice = IntPtr.Zero;
        try
        {
            result = CreateDirect3D11DeviceFromDXGIDevice((IntPtr)nativeDevice, out graphicsDevice);
            if (result != 0 || graphicsDevice == IntPtr.Zero)
            {
                Marshal.ThrowExceptionForHR(unchecked((int)result));
                throw new InvalidOperationException("CreateDirect3D11DeviceFromDXGIDevice returned no device.");
            }

            return MarshalInterface<IDirect3DDevice>.FromAbi(graphicsDevice);
        }
        finally
        {
            if (graphicsDevice != IntPtr.Zero) Marshal.Release(graphicsDevice);
            nativeDevice->Release();
        }
    }
}
