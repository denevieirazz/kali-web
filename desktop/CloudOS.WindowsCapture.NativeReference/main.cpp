#include <windows.h>
#include <windows.graphics.capture.h>
#include <windows.graphics.capture.interop.h>
#include <winrt/base.h>
#include <winrt/Windows.Graphics.Capture.h>

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace capture = winrt::Windows::Graphics::Capture;

namespace
{
    struct ProbeOptions
    {
        HWND hwnd{};
        std::optional<std::wstring> outputPath;
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
        {
            throw std::invalid_argument("invalid HWND");
        }

        return reinterpret_cast<HWND>(static_cast<std::uintptr_t>(value));
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
        // This deliberately mirrors the Microsoft Win32CaptureSample/C++/WinRT pattern.
        // It shares no CsWinRT projection or C# COM marshaling with the product probe.
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

    void PrintHelp()
    {
        std::wcout
            << L"CloudOS native C++/WinRT Windows capture item reference\n"
            << L"  --hwnd <decimal|0xHEX> [--output <path>]\n"
            << L"\n"
            << L"This probe only validates native CreateForWindow + GraphicsCaptureItem metadata.\n";
    }

    std::string BuildReport(
        HWND hwnd,
        std::string_view verdict,
        std::string_view stage,
        int itemWidth,
        int itemHeight,
        std::string_view displayName,
        std::optional<std::string_view> hresult,
        std::optional<std::string_view> message)
    {
        std::ostringstream json;
        json << "{\n"
             << "  \"schemaVersion\": 1,\n"
             << "  \"probe\": \"CloudOS.WindowsCapture.NativeReference\",\n"
             << "  \"verdict\": " << JsonString(verdict) << ",\n"
             << "  \"stage\": " << JsonString(stage) << ",\n"
             << "  \"hwnd\": " << JsonString(HexHandle(hwnd)) << ",\n"
             << "  \"itemWidth\": " << itemWidth << ",\n"
             << "  \"itemHeight\": " << itemHeight << ",\n"
             << "  \"displayName\": " << JsonString(displayName) << ",\n"
             << "  \"hresult\": " << (hresult ? JsonString(*hresult) : "null") << ",\n"
             << "  \"message\": " << (message ? JsonString(*message) : "null") << "\n"
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
        std::cerr << "NATIVE_REFERENCE_ARGUMENT_ERROR=" << error.what() << "\n";
        return 64;
    }

    try
    {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);

        if (!IsWindow(options.hwnd))
        {
            const auto report = BuildReport(
                options.hwnd,
                "ERROR",
                "target-validation",
                0,
                0,
                "",
                std::nullopt,
                "IsWindow returned false");
            EmitReport(report, options.outputPath);
            return 3;
        }

        const auto item = CreateItemForWindow(options.hwnd);
        const auto size = item.Size();
        const auto displayName = Utf8(item.DisplayName().c_str());
        const auto validSize = size.Width > 0 && size.Height > 0;
        const auto report = BuildReport(
            options.hwnd,
            validSize ? "PASS" : "FAIL",
            validSize ? "complete" : "item-metadata",
            size.Width,
            size.Height,
            displayName,
            std::nullopt,
            validSize ? std::nullopt : std::optional<std::string_view>("GraphicsCaptureItem.Size was empty"));
        EmitReport(report, options.outputPath);
        return validSize ? 0 : 2;
    }
    catch (const winrt::hresult_error& error)
    {
        try
        {
            const auto hresult = HexHResult(error.code().value);
            const auto message = Utf8(error.message().c_str());
            const auto report = BuildReport(
                options.hwnd,
                "ERROR",
                "create-item-or-metadata",
                0,
                0,
                "",
                hresult,
                message);
            EmitReport(report, options.outputPath);
        }
        catch (...) {}

        std::wcerr << L"NATIVE_REFERENCE_ERROR=HRESULT\n";
        std::wcerr << L"HRESULT=0x" << std::hex << std::uppercase
                   << static_cast<std::uint32_t>(error.code().value) << std::dec << L"\n";
        std::wcerr << L"MESSAGE=" << error.message().c_str() << L"\n";
        return 1;
    }
    catch (const std::exception& error)
    {
        try
        {
            const auto report = BuildReport(
                options.hwnd,
                "ERROR",
                "probe-runtime",
                0,
                0,
                "",
                std::nullopt,
                error.what());
            EmitReport(report, options.outputPath);
        }
        catch (...) {}

        std::cerr << "NATIVE_REFERENCE_ERROR=EXCEPTION\n";
        std::cerr << "MESSAGE=" << error.what() << "\n";
        return 1;
    }
}
