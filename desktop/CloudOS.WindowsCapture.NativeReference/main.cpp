#include <windows.h>
#include <windows.graphics.capture.h>
#include <windows.graphics.capture.interop.h>
#include <winrt/base.h>
#include <winrt/Windows.Graphics.Capture.h>

#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

namespace capture = winrt::Windows::Graphics::Capture;

namespace
{
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
            << L"  --hwnd <decimal|0xHEX>\n"
            << L"\n"
            << L"This probe only validates native CreateForWindow + GraphicsCaptureItem metadata.\n";
    }
}

int wmain(int argc, wchar_t** argv)
{
    if (argc == 2 && std::wstring_view(argv[1]) == L"--help")
    {
        PrintHelp();
        return 0;
    }

    if (argc != 3 || std::wstring_view(argv[1]) != L"--hwnd")
    {
        PrintHelp();
        return 64;
    }

    try
    {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        const auto hwnd = ParseWindowHandle(argv[2]);
        if (!IsWindow(hwnd))
        {
            std::wcerr << L"NATIVE_REFERENCE_ERROR=INVALID_HWND\n";
            return 3;
        }

        const auto item = CreateItemForWindow(hwnd);
        const auto size = item.Size();
        const auto name = item.DisplayName();

        std::wcout << L"NATIVE_REFERENCE_RESULT=SUCCESS\n";
        std::wcout << L"HWND=0x" << std::hex << std::uppercase
                   << reinterpret_cast<std::uintptr_t>(hwnd) << std::dec << L"\n";
        std::wcout << L"ITEM_WIDTH=" << size.Width << L"\n";
        std::wcout << L"ITEM_HEIGHT=" << size.Height << L"\n";
        std::wcout << L"DISPLAY_NAME=" << name.c_str() << L"\n";

        // A zero-sized item is the exact state observed in the C# HWND path and is
        // therefore a diagnostic failure even though CreateForWindow returned S_OK.
        return size.Width > 0 && size.Height > 0 ? 0 : 2;
    }
    catch (const winrt::hresult_error& error)
    {
        std::wcerr << L"NATIVE_REFERENCE_ERROR=HRESULT\n";
        std::wcerr << L"HRESULT=0x" << std::hex << std::uppercase
                   << static_cast<std::uint32_t>(error.code().value) << std::dec << L"\n";
        std::wcerr << L"MESSAGE=" << error.message().c_str() << L"\n";
        return 1;
    }
    catch (const std::exception& error)
    {
        std::cerr << "NATIVE_REFERENCE_ERROR=EXCEPTION\n";
        std::cerr << "MESSAGE=" << error.what() << "\n";
        return 1;
    }
}
