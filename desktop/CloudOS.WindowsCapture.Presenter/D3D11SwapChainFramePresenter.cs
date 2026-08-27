using System.Runtime.InteropServices;
using TerraFX.Interop.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace CloudOS.WindowsCapture.Presenter;

internal sealed unsafe class D3D11SwapChainFramePresenter : IDisposable
{
    private static readonly Guid Texture2DGuid = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");
    private static readonly Guid DxgiDeviceGuid = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
    private static readonly Guid DxgiFactory2Guid = new("50C83A1C-E072-4C48-87B0-3630FA36A6D0");
    private readonly object _sync = new();
    private readonly IntPtr _windowHandle;
    private IDXGISwapChain1* _swapChain;
    private ID3D11Device* _device;
    private ID3D11DeviceContext* _context;
    private int _bufferWidth;
    private int _bufferHeight;
    private bool _disposed;

    [ComImport]
    [Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface([In] ref Guid iid);
    }

    public D3D11SwapChainFramePresenter(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero) throw new ArgumentException("Presentation HWND is required.", nameof(windowHandle));
        _windowHandle = windowHandle;
    }

    public void Present(IDirect3DSurface surface, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(surface);
        if (width is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(width));
        if (height is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(height));

        lock (_sync)
        {
            ThrowIfDisposed();
            var access = surface.As<IDirect3DDxgiInterfaceAccess>();
            var iid = Texture2DGuid;
            var sourcePointer = access.GetInterface(ref iid);
            if (sourcePointer == IntPtr.Zero) throw new InvalidOperationException("Captured surface returned no ID3D11Texture2D.");

            var sourceTexture = (ID3D11Texture2D*)sourcePointer;
            try
            {
                EnsureSwapChain(sourceTexture, width, height);

                ID3D11Texture2D* backBuffer = null;
                var textureGuid = Texture2DGuid;
                var hr = _swapChain->GetBuffer(0, &textureGuid, (void**)&backBuffer);
                ThrowIfFailed(hr, "IDXGISwapChain1.GetBuffer");
                if (backBuffer is null) throw new InvalidOperationException("Swap chain returned no back buffer.");

                try
                {
                    _context->CopyResource((ID3D11Resource*)backBuffer, (ID3D11Resource*)sourceTexture);
                    hr = _swapChain->Present(1, 0);
                    ThrowIfFailed(hr, "IDXGISwapChain1.Present");
                }
                finally
                {
                    backBuffer->Release();
                }
            }
            finally
            {
                Marshal.Release(sourcePointer);
            }
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            ReleaseDeviceResources();
        }
    }

    private void EnsureSwapChain(ID3D11Texture2D* sourceTexture, int width, int height)
    {
        ID3D11Device* sourceDevice = null;
        sourceTexture->GetDevice(&sourceDevice);
        if (sourceDevice is null) throw new InvalidOperationException("Captured texture returned no D3D11 device.");

        try
        {
            if (_device != sourceDevice)
            {
                ReleaseDeviceResources();
                _device = sourceDevice;
                _device->AddRef();
                _device->GetImmediateContext(&_context);
                if (_context is null) throw new InvalidOperationException("D3D11 device returned no immediate context.");
                CreateSwapChain(width, height);
                return;
            }

            if (_swapChain is null)
            {
                CreateSwapChain(width, height);
                return;
            }

            if (_bufferWidth != width || _bufferHeight != height)
            {
                var hr = _swapChain->ResizeBuffers(
                    2,
                    checked((uint)width),
                    checked((uint)height),
                    DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM,
                    0);
                ThrowIfFailed(hr, "IDXGISwapChain1.ResizeBuffers");
                _bufferWidth = width;
                _bufferHeight = height;
            }
        }
        finally
        {
            sourceDevice->Release();
        }
    }

    private void CreateSwapChain(int width, int height)
    {
        if (_device is null) throw new InvalidOperationException("Cannot create swap chain without D3D11 device.");

        IDXGIDevice* dxgiDevice = null;
        IDXGIAdapter* adapter = null;
        IDXGIFactory2* factory = null;
        try
        {
            var dxgiDeviceGuid = DxgiDeviceGuid;
            var hr = _device->QueryInterface(&dxgiDeviceGuid, (void**)&dxgiDevice);
            ThrowIfFailed(hr, "ID3D11Device.QueryInterface(IDXGIDevice)");
            if (dxgiDevice is null) throw new InvalidOperationException("D3D11 device did not expose IDXGIDevice.");

            hr = dxgiDevice->GetAdapter(&adapter);
            ThrowIfFailed(hr, "IDXGIDevice.GetAdapter");
            if (adapter is null) throw new InvalidOperationException("IDXGIDevice returned no adapter.");

            var factoryGuid = DxgiFactory2Guid;
            hr = adapter->GetParent(&factoryGuid, (void**)&factory);
            ThrowIfFailed(hr, "IDXGIAdapter.GetParent(IDXGIFactory2)");
            if (factory is null) throw new InvalidOperationException("DXGI adapter returned no IDXGIFactory2.");

            DXGI_SWAP_CHAIN_DESC1 description = default;
            description.Width = checked((uint)width);
            description.Height = checked((uint)height);
            description.Format = DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM;
            description.Stereo = 0;
            description.SampleDesc.Count = 1;
            description.SampleDesc.Quality = 0;
            description.BufferUsage = DXGI_USAGE.DXGI_USAGE_RENDER_TARGET_OUTPUT;
            description.BufferCount = 2;
            description.Scaling = DXGI_SCALING.DXGI_SCALING_STRETCH;
            description.SwapEffect = DXGI_SWAP_EFFECT.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
            description.AlphaMode = DXGI_ALPHA_MODE.DXGI_ALPHA_MODE_IGNORE;
            description.Flags = 0;

            hr = factory->CreateSwapChainForHwnd(
                (IUnknown*)_device,
                _windowHandle,
                &description,
                null,
                null,
                &_swapChain);
            ThrowIfFailed(hr, "IDXGIFactory2.CreateSwapChainForHwnd");
            if (_swapChain is null) throw new InvalidOperationException("CreateSwapChainForHwnd returned no swap chain.");
            _bufferWidth = width;
            _bufferHeight = height;
        }
        finally
        {
            if (factory is not null) factory->Release();
            if (adapter is not null) adapter->Release();
            if (dxgiDevice is not null) dxgiDevice->Release();
        }
    }

    private void ReleaseDeviceResources()
    {
        if (_swapChain is not null)
        {
            _swapChain->Release();
            _swapChain = null;
        }
        if (_context is not null)
        {
            _context->Release();
            _context = null;
        }
        if (_device is not null)
        {
            _device->Release();
            _device = null;
        }
        _bufferWidth = 0;
        _bufferHeight = 0;
    }

    private static void ThrowIfFailed(int hr, string operation)
    {
        if (hr >= 0) return;
        throw new COMException($"{operation} failed with HRESULT 0x{hr:X8}.", hr);
    }

    private void ThrowIfDisposed()
    {
        if (_disposed) throw new ObjectDisposedException(nameof(D3D11SwapChainFramePresenter));
    }
}
