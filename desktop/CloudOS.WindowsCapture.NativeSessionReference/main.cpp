#include <windows.h>
#include <windows.graphics.capture.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <d3d11.h>
#include <dxgi.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace capture = winrt::Windows::Graphics::Capture;
namespace directx = winrt::Windows::Graphics::DirectX;
namespace direct3d11 = winrt::Windows::Graphics::DirectX::Direct3D11;
namespace graphics = winrt::Windows::Graphics;

namespace
{
    struct ProbeOptions
    {
        HWND hwnd{};
        int seconds{ 5 };
        int minimumFrames{ 10 };
        std::optional<std::wstring> outputPath;
    };

    struct CaptureResult
    {
        int itemWidth{};
        int itemHeight{};
        int bufferWidth{};
        int bufferHeight{};
        std::string bufferSource;
        long long frameCount{};
        int lastWidth{};
        int lastHeight{};
        std::string stage;
        std::string verdict;
        std::optional<std::string> hresult;
        std::optional<std::string> message;
    };

    std::string Utf8(std::wstring_view value)
    {
        if (value.empty()) return {};
        const auto required = WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0,
            nullptr,
            nullptr);
        if (required <= 0) throw std::runtime_error("WideCharToMultiByte sizing failed");

        std::string result(static_cast<std::size_t>(required), '\0');
        const auto written = WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            required,
            nullptr,
            nullptr);
        if (written != required) throw std::runtime_error("WideCharToMultiByte conversion failed");
        return result;
    }

    std::string JsonEscape(std::string_view value)
    {
        std::ostringstream stream;
        for (const unsigned char character : value)
        {
            switch (character)
            {
            case '\\': stream << "\\\\"; break;
            case '"': stream << "\\\""; break;
            case '\b': stream << "\\b"; break;
            case '\f': stream << "\\f"; break;
            case '\n': stream << "\\n"; break;
            case '\r': stream << "\\r"; break;
            case '\t': stream << "\\t"; break;
            default:
                if (character < 0x20)
                {
                    stream << "\\u"
                           << std::hex << std::uppercase << std::setw(4) << std::setfill('0')
                           << static_cast<unsigned int>(character)
                           << std::dec << std::nouppercase << std::setfill(' ');
                }
                else
                {
                    stream << static_cast<char>(character);
                }
            }
        }
        return stream.str();
    }

    std::string JsonString(std::string_view value)
    {
        return "\"" + JsonEscape(value) + "\"";
    }

    std::string HexHandle(HWND hwnd)
    {
        std::ostringstream stream;
        stream << "0x" << std::hex << std::uppercase
               << reinterpret_cast<std::uintptr_t>(hwnd);
        return stream.str();
    }

    std::string HexHResult(HRESULT value)
    {
        std::ostringstream stream;
        stream << "0x" << std::hex << std::uppercase << std::setw(8) << std::setfill('0')
               << static_cast<std::uint32_t>(value);
        return stream.str();
    }

    HWND ParseWindowHandle(const std::wstring& text)
    {
        std::size_t parsed = 0;
        const int base = text.rfind(L"0x", 0) == 0 || text.rfind(L"0X", 0) == 0 ? 16 : 10;
        const auto payload = base == 16 ? text.substr(2) : text;
        const auto value = std::stoull(payload, &parsed, base);
        if (parsed != payload.size() || value == 0)
            throw std::invalid_argument("invalid HWND");
        return reinterpret_cast<HWND>(static_cast<std::uintptr_t>(value));
    }

    int ParseInt(const std::wstring& text, int minimum, int maximum, std::string_view name)
    {
        std::size_t parsed = 0;
        const auto value = std::stoll(text, &parsed, 10);
        if (parsed != text.size() || value < minimum || value > maximum)
            throw std::invalid_argument(std::string(name) + " is out of range");
        return static_cast<int>(value);
    }

    ProbeOptions ParseOptions(int argc, wchar_t** argv)
    {
        ProbeOptions options;
        bool hwndSeen = false;

        for (int index = 1; index < argc; ++index)
        {
            const std::wstring_view argument(argv[index]);
            auto next = [&](std::wstring_view option) -> std::wstring
            {
                if (++index >= argc) throw std::invalid_argument("missing value for " + Utf8(option));
                return argv[index];
            };

            if (argument == L"--hwnd")
            {
                if (hwndSeen) throw std::invalid_argument("--hwnd may only be specified once");
                options.hwnd = ParseWindowHandle(next(argument));
                hwndSeen = true;
            }
            else if (argument == L"--seconds")
            {
                options.seconds = ParseInt(next(argument), 1, 30, "--seconds");
            }
            else if (argument == L"--min-frames")
            {
                options.minimumFrames = ParseInt(next(argument), 1, 1000, "--min-frames");
            }
            else if (argument == L"--output")
            {
                options.outputPath = next(argument);
                if (options.outputPath->empty()) throw std::invalid_argument("--output must not be empty");
            }
            else
            {
                throw std::invalid_argument("unknown option: " + Utf8(argument));
            }
        }

        if (!hwndSeen) throw std::invalid_argument("--hwnd is required");
        return options;
    }

    capture::GraphicsCaptureItem CreateItemForWindow(HWND hwnd)
    {
        auto interopFactory = winrt::get_activation_factory<
            capture::GraphicsCaptureItem,
            IGraphicsCaptureItemInterop>();

        capture::GraphicsCaptureItem item{ nullptr };
        winrt::check_hresult(interopFactory->CreateForWindow(
            hwnd,
            winrt::guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
            reinterpret_cast<void**>(winrt::put_abi(item))));
        return item;
    }

    direct3d11::IDirect3DDevice CreateDirect3DDevice()
    {
        winrt::com_ptr<ID3D11Device> nativeDevice;
        D3D_FEATURE_LEVEL featureLevel{};
        winrt::check_hresult(D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            nullptr,
            0,
            D3D11_SDK_VERSION,
            nativeDevice.put(),
            &featureLevel,
            nullptr));

        auto dxgiDevice = nativeDevice.as<IDXGIDevice>();
        winrt::com_ptr<IInspectable> inspectable;
        winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(
            dxgiDevice.get(),
            inspectable.put()));
        return inspectable.as<direct3d11::IDirect3DDevice>();
    }

    graphics::SizeInt32 ResolveBufferSize(HWND hwnd, graphics::SizeInt32 itemSize, std::string& source)
    {
        if (itemSize.Width > 0 && itemSize.Height > 0)
        {
            source = "graphics-capture-item";
            return itemSize;
        }

        RECT rect{};
        if (!GetWindowRect(hwnd, &rect))
            winrt::throw_last_error();
        const auto width = static_cast<long long>(rect.right) - rect.left;
        const auto height = static_cast<long long>(rect.bottom) - rect.top;
        if (width <= 0 || height <= 0 || width > INT_MAX || height > INT_MAX)
            throw std::runtime_error("GetWindowRect did not produce a usable capture size");

        source = "get-window-rect-bootstrap";
        return graphics::SizeInt32{ static_cast<int>(width), static_cast<int>(height) };
    }

    CaptureResult RunCapture(const ProbeOptions& options)
    {
        CaptureResult result{};
        std::string stage = "support-check";

        try
        {
            if (!capture::GraphicsCaptureSession::IsSupported())
                throw std::runtime_error("Windows.Graphics.Capture is not supported in this session");

            stage = "create-item";
            const auto item = CreateItemForWindow(options.hwnd);

            stage = "item-metadata";
            const auto itemSize = item.Size();
            result.itemWidth = itemSize.Width;
            result.itemHeight = itemSize.Height;

            stage = "resolve-buffer-size";
            auto bufferSize = ResolveBufferSize(options.hwnd, itemSize, result.bufferSource);
            result.bufferWidth = bufferSize.Width;
            result.bufferHeight = bufferSize.Height;

            stage = "d3d-device";
            const auto device = CreateDirect3DDevice();

            stage = "frame-pool";
            auto framePool = capture::Direct3D11CaptureFramePool::CreateFreeThreaded(
                device,
                directx::DirectXPixelFormat::B8G8R8A8UIntNormalized,
                3,
                bufferSize);

            stage = "capture-session";
            auto session = framePool.CreateCaptureSession(item);

            std::mutex mutex;
            std::condition_variable condition;
            long long frameCount = 0;
            int lastWidth = 0;
            int lastHeight = 0;
            std::optional<std::string> asynchronousFailure;

            const auto token = framePool.FrameArrived(
                [&](capture::Direct3D11CaptureFramePool const& sender, winrt::Windows::Foundation::IInspectable const&)
                {
                    try
                    {
                        auto frame = sender.TryGetNextFrame();
                        if (!frame) return;
                        const auto size = frame.ContentSize();
                        if (size.Width <= 0 || size.Height <= 0) return;

                        {
                            std::lock_guard guard(mutex);
                            ++frameCount;
                            lastWidth = size.Width;
                            lastHeight = size.Height;
                        }
                        condition.notify_all();
                    }
                    catch (const winrt::hresult_error& error)
                    {
                        {
                            std::lock_guard guard(mutex);
                            asynchronousFailure = HexHResult(error.code().value) + " " + Utf8(error.message().c_str());
                        }
                        condition.notify_all();
                    }
                    catch (const std::exception& error)
                    {
                        {
                            std::lock_guard guard(mutex);
                            asynchronousFailure = error.what();
                        }
                        condition.notify_all();
                    }
                });

            stage = "start-capture";
            session.StartCapture();

            stage = "frame-wait";
            {
                std::unique_lock lock(mutex);
                condition.wait_for(
                    lock,
                    std::chrono::seconds(options.seconds),
                    [&]
                    {
                        return frameCount >= options.minimumFrames || asynchronousFailure.has_value();
                    });
                result.frameCount = frameCount;
                result.lastWidth = lastWidth;
                result.lastHeight = lastHeight;
                if (asynchronousFailure)
                {
                    result.verdict = "ERROR";
                    result.stage = "frame-arrived";
                    result.message = *asynchronousFailure;
                }
            }

            framePool.FrameArrived(token);
            session.Close();
            framePool.Close();

            if (result.verdict.empty())
            {
                result.verdict = result.frameCount >= options.minimumFrames ? "PASS" : "FAIL";
                result.stage = result.verdict == "PASS" ? "complete" : "frame-wait";
                if (result.verdict != "PASS")
                    result.message = "minimum frame count was not reached before timeout";
            }
            return result;
        }
        catch (const winrt::hresult_error& error)
        {
            result.verdict = "ERROR";
            result.stage = stage;
            result.hresult = HexHResult(error.code().value);
            result.message = Utf8(error.message().c_str());
            return result;
        }
        catch (const std::exception& error)
        {
            result.verdict = "ERROR";
            result.stage = stage;
            result.message = error.what();
            return result;
        }
    }

    std::string BuildReport(HWND hwnd, const ProbeOptions& options, const CaptureResult& result)
    {
        std::ostringstream json;
        json << "{\n"
             << "  \"schemaVersion\": 1,\n"
             << "  \"probe\": \"CloudOS.WindowsCapture.NativeSessionReference\",\n"
             << "  \"verdict\": " << JsonString(result.verdict) << ",\n"
             << "  \"stage\": " << JsonString(result.stage) << ",\n"
             << "  \"hwnd\": " << JsonString(HexHandle(hwnd)) << ",\n"
             << "  \"requestedSeconds\": " << options.seconds << ",\n"
             << "  \"minimumFrames\": " << options.minimumFrames << ",\n"
             << "  \"itemWidth\": " << result.itemWidth << ",\n"
             << "  \"itemHeight\": " << result.itemHeight << ",\n"
             << "  \"bufferWidth\": " << result.bufferWidth << ",\n"
             << "  \"bufferHeight\": " << result.bufferHeight << ",\n"
             << "  \"bufferSource\": " << JsonString(result.bufferSource) << ",\n"
             << "  \"frameCount\": " << result.frameCount << ",\n"
             << "  \"lastWidth\": " << result.lastWidth << ",\n"
             << "  \"lastHeight\": " << result.lastHeight << ",\n"
             << "  \"hresult\": " << (result.hresult ? JsonString(*result.hresult) : "null") << ",\n"
             << "  \"message\": " << (result.message ? JsonString(*result.message) : "null") << "\n"
             << "}";
        return json.str();
    }

    void EmitReport(const std::string& json, const std::optional<std::wstring>& outputPath)
    {
        std::cout << json << '\n';
        if (!outputPath) return;

        const auto utf8Path = Utf8(*outputPath);
        std::ofstream output(utf8Path, std::ios::binary | std::ios::trunc);
        if (!output) throw std::runtime_error("could not open --output path");
        output << json << '\n';
        if (!output) throw std::runtime_error("could not write --output report");
    }

    void PrintHelp()
    {
        std::wcout
            << L"CloudOS native C++/WinRT Windows capture session reference\n"
            << L"  --hwnd <decimal|0xHEX> [--seconds <1-30>] [--min-frames <1-1000>] [--output <path>]\n"
            << L"\n"
            << L"Independent native A/B: CreateForWindow -> D3D11 -> frame pool -> CreateCaptureSession -> StartCapture -> frames.\n";
    }
}

int wmain(int argc, wchar_t** argv)
{
    if (argc == 2 && std::wstring_view(argv[1]) == L"--help")
    {
        PrintHelp();
        return 0;
    }

    ProbeOptions options;
    try
    {
        options = ParseOptions(argc, argv);
    }
    catch (const std::exception& error)
    {
        PrintHelp();
        std::cerr << "NATIVE_SESSION_REFERENCE_ARGUMENT_ERROR=" << error.what() << "\n";
        return 64;
    }

    try
    {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);

        if (!IsWindow(options.hwnd))
        {
            CaptureResult invalid{};
            invalid.verdict = "ERROR";
            invalid.stage = "target-validation";
            invalid.message = "IsWindow returned false";
            EmitReport(BuildReport(options.hwnd, options, invalid), options.outputPath);
            return 3;
        }

        const auto result = RunCapture(options);
        EmitReport(BuildReport(options.hwnd, options, result), options.outputPath);
        if (result.verdict == "PASS") return 0;
        if (result.verdict == "FAIL") return 2;
        return 1;
    }
    catch (const winrt::hresult_error& error)
    {
        std::wcerr << L"NATIVE_SESSION_REFERENCE_FATAL=0x" << std::hex << std::uppercase
                   << static_cast<std::uint32_t>(error.code().value) << std::dec
                   << L" " << error.message().c_str() << L"\n";
        return 1;
    }
    catch (const std::exception& error)
    {
        std::cerr << "NATIVE_SESSION_REFERENCE_FATAL=" << error.what() << "\n";
        return 1;
    }
}
