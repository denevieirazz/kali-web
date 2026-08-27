using System.Runtime.InteropServices;
using TerraFX.Interop.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace CloudOS.WindowsCapture;

public sealed record WindowsFrameHealthOptions(
    int SampleEveryNFrames = 5,
    int MaximumSamples = 8,
    int MaximumRegionSize = 256,
    int GridSize = 32)
{
    public WindowsFrameHealthOptions Validate()
    {
        if (SampleEveryNFrames is < 1 or > 120) throw new ArgumentOutOfRangeException(nameof(SampleEveryNFrames));
        if (MaximumSamples is < 1 or > 64) throw new ArgumentOutOfRangeException(nameof(MaximumSamples));
        if (MaximumRegionSize is < 32 or > 1024) throw new ArgumentOutOfRangeException(nameof(MaximumRegionSize));
        if (GridSize is < 8 or > 128) throw new ArgumentOutOfRangeException(nameof(GridSize));
        return this;
    }
}

public sealed record WindowsFrameHealthSnapshot(
    bool Enabled,
    int AttemptedSamples,
    int SuccessfulSamples,
    int FailedSamples,
    int DistinctFrameHashes,
    int ChangedSamples,
    int FlatNeutralSamples,
    double MeanLuma,
    double MeanLumaVariance,
    double MeanChannelSpread,
    bool StaticSequenceSuspect,
    bool FlatNeutralSequenceSuspect,
    string? LastFrameHash,
    string? LastFailure);

internal sealed unsafe class WindowsFrameHealthSampler
{
    private static readonly Guid Texture2DGuid = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");
    private readonly object _sync = new();
    private readonly WindowsFrameHealthOptions _options;
    private readonly HashSet<ulong> _distinctHashes = [];
    private int _attemptedSamples;
    private int _successfulSamples;
    private int _failedSamples;
    private int _changedSamples;
    private int _flatNeutralSamples;
    private double _lumaTotal;
    private double _varianceTotal;
    private double _channelSpreadTotal;
    private ulong? _previousHash;
    private ulong? _lastHash;
    private string? _lastFailure;

    [ComImport]
    [Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface([In] ref Guid iid);
    }

    public WindowsFrameHealthSampler(WindowsFrameHealthOptions options)
    {
        _options = options.Validate();
    }

    public bool ShouldSample(long frameCount)
    {
        lock (_sync)
        {
            if (_attemptedSamples >= _options.MaximumSamples) return false;
            return frameCount == 1 || frameCount % _options.SampleEveryNFrames == 0;
        }
    }

    public void TrySample(IDirect3DSurface surface)
    {
        ArgumentNullException.ThrowIfNull(surface);
        lock (_sync) _attemptedSamples++;

        try
        {
            var sample = SampleSurface(surface);
            lock (_sync)
            {
                _successfulSamples++;
                _lumaTotal += sample.MeanLuma;
                _varianceTotal += sample.LumaVariance;
                _channelSpreadTotal += sample.MeanChannelSpread;
                _distinctHashes.Add(sample.Hash);
                if (_previousHash.HasValue && _previousHash.Value != sample.Hash) _changedSamples++;
                if (sample.FlatNeutral) _flatNeutralSamples++;
                _previousHash = sample.Hash;
                _lastHash = sample.Hash;
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            lock (_sync)
            {
                _failedSamples++;
                _lastFailure = $"{error.GetType().Name}: {error.Message}";
            }
        }
    }

    public WindowsFrameHealthSnapshot GetSnapshot()
    {
        lock (_sync)
        {
            var denominator = Math.Max(1, _successfulSamples);
            var staticSuspect = _successfulSamples >= 3 && _distinctHashes.Count <= 1;
            var flatNeutralSuspect = _successfulSamples >= 3 && _flatNeutralSamples == _successfulSamples;
            return new WindowsFrameHealthSnapshot(
                true,
                _attemptedSamples,
                _successfulSamples,
                _failedSamples,
                _distinctHashes.Count,
                _changedSamples,
                _flatNeutralSamples,
                _lumaTotal / denominator,
                _varianceTotal / denominator,
                _channelSpreadTotal / denominator,
                staticSuspect,
                flatNeutralSuspect,
                _lastHash.HasValue ? $"{_lastHash.Value:X16}" : null,
                _lastFailure);
        }
    }

    private FrameHealthSample SampleSurface(IDirect3DSurface surface)
    {
        var access = surface.As<IDirect3DDxgiInterfaceAccess>();
        var iid = Texture2DGuid;
        var texturePointer = access.GetInterface(ref iid);
        if (texturePointer == IntPtr.Zero) throw new InvalidOperationException("IDirect3DSurface returned no ID3D11Texture2D.");

        var texture = (ID3D11Texture2D*)texturePointer;
        ID3D11Device* device = null;
        ID3D11DeviceContext* context = null;
        ID3D11Texture2D* staging = null;
        var mapped = false;

        try
        {
            D3D11_TEXTURE2D_DESC sourceDescription = default;
            texture->GetDesc(&sourceDescription);
            if (sourceDescription.Width == 0 || sourceDescription.Height == 0)
                throw new InvalidOperationException("Captured texture has zero dimensions.");
            if (sourceDescription.SampleDesc.Count != 1)
                throw new NotSupportedException($"Frame-health sampler does not support multisampled capture textures ({sourceDescription.SampleDesc.Count} samples).");

            texture->GetDevice(&device);
            if (device is null) throw new InvalidOperationException("Captured texture returned no D3D11 device.");
            device->GetImmediateContext(&context);
            if (context is null) throw new InvalidOperationException("D3D11 device returned no immediate context.");

            var regionWidth = Math.Min((uint)_options.MaximumRegionSize, sourceDescription.Width);
            var regionHeight = Math.Min((uint)_options.MaximumRegionSize, sourceDescription.Height);
            var left = (sourceDescription.Width - regionWidth) / 2;
            var top = (sourceDescription.Height - regionHeight) / 2;

            var stagingDescription = sourceDescription;
            stagingDescription.Width = regionWidth;
            stagingDescription.Height = regionHeight;
            stagingDescription.MipLevels = 1;
            stagingDescription.ArraySize = 1;
            stagingDescription.SampleDesc.Count = 1;
            stagingDescription.SampleDesc.Quality = 0;
            stagingDescription.Usage = D3D11_USAGE.D3D11_USAGE_STAGING;
            stagingDescription.BindFlags = 0;
            stagingDescription.CPUAccessFlags = (uint)D3D11_CPU_ACCESS_FLAG.D3D11_CPU_ACCESS_READ;
            stagingDescription.MiscFlags = 0;

            var hr = device->CreateTexture2D(&stagingDescription, null, &staging);
            ThrowIfFailed(hr, "CreateTexture2D(frame-health staging)");
            if (staging is null) throw new InvalidOperationException("CreateTexture2D returned no staging texture.");

            D3D11_BOX sourceRegion = default;
            sourceRegion.left = left;
            sourceRegion.top = top;
            sourceRegion.front = 0;
            sourceRegion.right = left + regionWidth;
            sourceRegion.bottom = top + regionHeight;
            sourceRegion.back = 1;

            context->CopySubresourceRegion(
                (ID3D11Resource*)staging,
                0,
                0,
                0,
                0,
                (ID3D11Resource*)texture,
                0,
                &sourceRegion);

            D3D11_MAPPED_SUBRESOURCE mappedResource = default;
            hr = context->Map(
                (ID3D11Resource*)staging,
                0,
                D3D11_MAP.D3D11_MAP_READ,
                0,
                &mappedResource);
            ThrowIfFailed(hr, "Map(frame-health staging)");
            mapped = true;
            if (mappedResource.pData is null) throw new InvalidOperationException("Mapped staging texture returned null data.");

            return AnalyzeMappedBgra(
                (byte*)mappedResource.pData,
                mappedResource.RowPitch,
                regionWidth,
                regionHeight,
                _options.GridSize);
        }
        finally
        {
            if (mapped && context is not null && staging is not null)
                context->Unmap((ID3D11Resource*)staging, 0);
            if (staging is not null) staging->Release();
            if (context is not null) context->Release();
            if (device is not null) device->Release();
            Marshal.Release(texturePointer);
        }
    }

    private static FrameHealthSample AnalyzeMappedBgra(
        byte* data,
        uint rowPitch,
        uint width,
        uint height,
        int gridSize)
    {
        var columns = Math.Min(gridSize, checked((int)width));
        var rows = Math.Min(gridSize, checked((int)height));
        if (columns <= 0 || rows <= 0) throw new InvalidOperationException("Frame-health sample grid is empty.");

        double lumaSum = 0;
        double lumaSquaredSum = 0;
        double spreadSum = 0;
        ulong hash = 14695981039346656037UL;
        var sampleCount = 0;

        for (var gy = 0; gy < rows; gy++)
        {
            var y = rows == 1 ? 0u : (uint)((long)gy * (height - 1) / (rows - 1));
            var row = data + (nuint)(y * rowPitch);
            for (var gx = 0; gx < columns; gx++)
            {
                var x = columns == 1 ? 0u : (uint)((long)gx * (width - 1) / (columns - 1));
                var pixel = row + (nuint)(x * 4);
                var blue = pixel[0];
                var green = pixel[1];
                var red = pixel[2];

                var luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
                lumaSum += luma;
                lumaSquaredSum += luma * luma;
                var maximum = Math.Max(red, Math.Max(green, blue));
                var minimum = Math.Min(red, Math.Min(green, blue));
                spreadSum += maximum - minimum;

                hash = HashByte(hash, blue);
                hash = HashByte(hash, green);
                hash = HashByte(hash, red);
                sampleCount++;
            }
        }

        var meanLuma = lumaSum / sampleCount;
        var variance = Math.Max(0, lumaSquaredSum / sampleCount - meanLuma * meanLuma);
        var meanSpread = spreadSum / sampleCount;

        // This is deliberately diagnostic, not a product verdict. A legitimate UI can
        // contain flat neutral regions, so the signal is only meaningful across a sequence.
        var flatNeutral = variance <= 64.0 && meanSpread <= 8.0 && meanLuma is >= 12.0 and <= 243.0;
        return new FrameHealthSample(hash, meanLuma, variance, meanSpread, flatNeutral);
    }

    private static ulong HashByte(ulong hash, byte value)
    {
        hash ^= value;
        return hash * 1099511628211UL;
    }

    private static void ThrowIfFailed(int hr, string operation)
    {
        if (hr >= 0) return;
        Marshal.ThrowExceptionForHR(hr);
        throw new InvalidOperationException($"{operation} failed with HRESULT 0x{hr:X8}.");
    }

    private readonly record struct FrameHealthSample(
        ulong Hash,
        double MeanLuma,
        double LumaVariance,
        double MeanChannelSpread,
        bool FlatNeutral);
}
