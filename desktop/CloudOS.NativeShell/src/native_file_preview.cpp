#include "native_file_preview.h"

#include "native_theme.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cwctype>
#include <string_view>
#include <vector>

#pragma comment(lib, "windowscodecs.lib")

namespace CloudOS
{
namespace
{
using Microsoft::WRL::ComPtr;

constexpr wchar_t kPreviewClass[] = L"CloudOS.NativeShell.FilePreview.v5";
constexpr DWORD kMaximumTextBytes = 64u * 1024u;
constexpr std::size_t kMaximumTextCharacters = 12000;
constexpr UINT kMaximumImageDimension = 1200;

std::wstring Lower(std::wstring value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t value_character)
    {
        return static_cast<wchar_t>(std::towlower(value_character));
    });
    return value;
}

bool HasExtension(const std::wstring& path, std::initializer_list<std::wstring_view> extensions)
{
    const std::wstring lowered = Lower(NativeFilePreviewPane::Extension(path));
    return std::any_of(extensions.begin(), extensions.end(), [&lowered](std::wstring_view extension)
    {
        return lowered == extension;
    });
}

void SelectFont(HDC dc, HFONT font, HGDIOBJ* old_font)
{
    if (old_font != nullptr) *old_font = nullptr;
    if (dc != nullptr && font != nullptr && old_font != nullptr)
        *old_font = SelectObject(dc, font);
}
}

NativeFilePreviewPane::~NativeFilePreviewPane()
{
    Destroy();
}

bool NativeFilePreviewPane::Create(HINSTANCE instance, HWND parent)
{
    if (window_ != nullptr) return true;
    instance_ = instance;
    parent_ = parent;

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = &NativeFilePreviewPane::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kPreviewClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    window_ = CreateWindowExW(
        0, kPreviewClass, L"", WS_CHILD | WS_CLIPSIBLINGS,
        0, 0, 0, 0, parent_, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    const UINT dpi = GetDpiForWindow(parent_);
    title_font_ = CreateFontW(
        -Scale(17, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    text_font_ = CreateFontW(
        -Scale(13, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN, L"Cascadia Mono");
    background_ = CreateSolidBrush(WebSkin::BgSecondary);
    return true;
}

void NativeFilePreviewPane::Destroy() noexcept
{
    ReleaseImage();
    if (window_ != nullptr && IsWindow(window_)) DestroyWindow(window_);
    window_ = nullptr;
    parent_ = nullptr;
    if (title_font_ != nullptr) DeleteObject(title_font_);
    if (text_font_ != nullptr) DeleteObject(text_font_);
    if (background_ != nullptr) DeleteObject(background_);
    title_font_ = nullptr;
    text_font_ = nullptr;
    background_ = nullptr;
    instance_ = nullptr;
}

void NativeFilePreviewPane::Resize(const RECT& bounds) noexcept
{
    if (window_ == nullptr) return;
    MoveWindow(
        window_, bounds.left, bounds.top,
        std::max<LONG>(1, bounds.right - bounds.left),
        std::max<LONG>(1, bounds.bottom - bounds.top), TRUE);
}

void NativeFilePreviewPane::Show(bool visible) noexcept
{
    if (window_ != nullptr) ShowWindow(window_, visible ? SW_SHOW : SW_HIDE);
}

void NativeFilePreviewPane::Clear()
{
    ReleaseImage();
    path_.clear();
    title_.clear();
    metadata_.clear();
    text_.clear();
    kind_ = PreviewKind::Empty;
    if (window_ != nullptr) InvalidateRect(window_, nullptr, TRUE);
}

void NativeFilePreviewPane::SetPath(const std::wstring& path)
{
    if (!path_.empty() && _wcsicmp(path_.c_str(), path.c_str()) == 0) return;
    Clear();
    if (path.empty()) return;

    path_ = path;
    LoadMetadata(path_);

    const DWORD attributes = GetFileAttributesW(path_.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        kind_ = PreviewKind::Unavailable;
    }
    else if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        kind_ = PreviewKind::Directory;
    }
    else if (LooksLikeImage(path_) && LoadImage(path_))
    {
        kind_ = PreviewKind::Image;
    }
    else if (LooksLikeText(path_) && LoadText(path_))
    {
        kind_ = PreviewKind::Text;
    }
    else
    {
        kind_ = PreviewKind::Generic;
    }
    if (window_ != nullptr) InvalidateRect(window_, nullptr, TRUE);
}

bool NativeFilePreviewPane::LoadImage(const std::wstring& path)
{
    ComPtr<IWICImagingFactory> factory;
    HRESULT result = CoCreateInstance(
        CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
    if (FAILED(result)) return false;

    ComPtr<IWICBitmapDecoder> decoder;
    result = factory->CreateDecoderFromFilename(
        path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder);
    if (FAILED(result)) return false;

    ComPtr<IWICBitmapFrameDecode> frame;
    result = decoder->GetFrame(0, &frame);
    if (FAILED(result)) return false;

    UINT source_width = 0;
    UINT source_height = 0;
    result = frame->GetSize(&source_width, &source_height);
    if (FAILED(result) || source_width == 0 || source_height == 0) return false;

    UINT target_width = source_width;
    UINT target_height = source_height;
    const UINT longest = std::max(source_width, source_height);
    ComPtr<IWICBitmapSource> source = frame;
    ComPtr<IWICBitmapScaler> scaler;
    if (longest > kMaximumImageDimension)
    {
        const double ratio = static_cast<double>(kMaximumImageDimension) / static_cast<double>(longest);
        target_width = std::max<UINT>(1, static_cast<UINT>(static_cast<double>(source_width) * ratio));
        target_height = std::max<UINT>(1, static_cast<UINT>(static_cast<double>(source_height) * ratio));
        result = factory->CreateBitmapScaler(&scaler);
        if (FAILED(result)) return false;
        result = scaler->Initialize(frame.Get(), target_width, target_height, WICBitmapInterpolationModeFant);
        if (FAILED(result)) return false;
        source = scaler;
    }

    ComPtr<IWICFormatConverter> converter;
    result = factory->CreateFormatConverter(&converter);
    if (FAILED(result)) return false;
    result = converter->Initialize(
        source.Get(), GUID_WICPixelFormat32bppBGRA,
        WICBitmapDitherTypeNone, nullptr, 0.0, WICBitmapPaletteTypeCustom);
    if (FAILED(result)) return false;

    if (target_width > static_cast<UINT>(std::numeric_limits<int>::max()) ||
        target_height > static_cast<UINT>(std::numeric_limits<int>::max()))
        return false;
    const std::uint64_t stride64 = static_cast<std::uint64_t>(target_width) * 4ull;
    const std::uint64_t bytes64 = stride64 * static_cast<std::uint64_t>(target_height);
    if (stride64 > std::numeric_limits<UINT>::max() || bytes64 > std::numeric_limits<UINT>::max())
        return false;

    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = static_cast<LONG>(target_width);
    info.bmiHeader.biHeight = -static_cast<LONG>(target_height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;

    void* pixels = nullptr;
    HDC screen = GetDC(nullptr);
    HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
    if (screen != nullptr) ReleaseDC(nullptr, screen);
    if (bitmap == nullptr || pixels == nullptr)
    {
        if (bitmap != nullptr) DeleteObject(bitmap);
        return false;
    }

    result = converter->CopyPixels(
        nullptr,
        static_cast<UINT>(stride64),
        static_cast<UINT>(bytes64),
        static_cast<BYTE*>(pixels));
    if (FAILED(result))
    {
        DeleteObject(bitmap);
        return false;
    }

    ReleaseImage();
    bitmap_ = bitmap;
    bitmap_size_.cx = static_cast<LONG>(target_width);
    bitmap_size_.cy = static_cast<LONG>(target_height);
    return true;
}

bool NativeFilePreviewPane::LoadText(const std::wstring& path)
{
    HANDLE file = CreateFileW(
        path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER file_size{};
    if (!GetFileSizeEx(file, &file_size) || file_size.QuadPart < 0)
    {
        CloseHandle(file);
        return false;
    }
    const DWORD requested = static_cast<DWORD>(
        std::min<LONGLONG>(file_size.QuadPart, static_cast<LONGLONG>(kMaximumTextBytes)));
    std::vector<BYTE> bytes(requested);
    DWORD read = 0;
    const bool read_ok = requested == 0 || ReadFile(file, bytes.data(), requested, &read, nullptr) != FALSE;
    CloseHandle(file);
    if (!read_ok) return false;
    bytes.resize(read);

    std::wstring decoded;
    if (bytes.size() >= 2 && bytes[0] == 0xFFu && bytes[1] == 0xFEu)
    {
        const std::size_t count = (bytes.size() - 2u) / sizeof(wchar_t);
        const auto* wide = reinterpret_cast<const wchar_t*>(bytes.data() + 2u);
        decoded.assign(wide, wide + count);
    }
    else
    {
        std::size_t offset = 0;
        if (bytes.size() >= 3 && bytes[0] == 0xEFu && bytes[1] == 0xBBu && bytes[2] == 0xBFu)
            offset = 3;
        if (std::find(bytes.begin() + static_cast<std::ptrdiff_t>(offset), bytes.end(), static_cast<BYTE>(0)) != bytes.end())
            return false;
        const int input_size = static_cast<int>(bytes.size() - offset);
        if (input_size > 0)
        {
            const char* input = reinterpret_cast<const char*>(bytes.data() + offset);
            int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input, input_size, nullptr, 0);
            UINT code_page = CP_UTF8;
            DWORD flags = MB_ERR_INVALID_CHARS;
            if (required <= 0)
            {
                code_page = CP_ACP;
                flags = 0;
                required = MultiByteToWideChar(code_page, flags, input, input_size, nullptr, 0);
            }
            if (required <= 0) return false;
            decoded.assign(static_cast<std::size_t>(required), L'\0');
            if (MultiByteToWideChar(code_page, flags, input, input_size, decoded.data(), required) <= 0)
                return false;
        }
    }
    if (decoded.size() > kMaximumTextCharacters)
    {
        decoded.resize(kMaximumTextCharacters);
        decoded += L"\r\n\r\n… visualização limitada pelo CloudOS";
    }
    text_ = std::move(decoded);
    return true;
}

void NativeFilePreviewPane::LoadMetadata(const std::wstring& path)
{
    title_ = FileName(path);
    if (title_.empty()) title_ = path;

    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data))
    {
        metadata_ = L"Item indisponível";
        return;
    }

    const bool directory = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    metadata_ = directory ? L"Pasta" : L"Arquivo";
    if (!directory)
    {
        const ULONGLONG size =
            (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32u) | data.nFileSizeLow;
        metadata_ += L"  •  " + FormatBytes(size);
        const std::wstring extension = Extension(path);
        if (!extension.empty()) metadata_ += L"  •  " + extension;
    }
    const std::wstring modified = FormatModified(data.ftLastWriteTime);
    if (!modified.empty()) metadata_ += L"\r\nModificado: " + modified;
    metadata_ += L"\r\n" + path;
}

void NativeFilePreviewPane::ReleaseImage() noexcept
{
    if (bitmap_ != nullptr) DeleteObject(bitmap_);
    bitmap_ = nullptr;
    bitmap_size_ = SIZE{};
}

bool NativeFilePreviewPane::LooksLikeImage(const std::wstring& path)
{
    return HasExtension(path, {L".png", L".jpg", L".jpeg", L".bmp", L".gif", L".tif", L".tiff", L".webp", L".ico"});
}

bool NativeFilePreviewPane::LooksLikeText(const std::wstring& path)
{
    return HasExtension(path, {
        L".txt", L".md", L".log", L".json", L".xml", L".yaml", L".yml", L".toml", L".ini", L".cfg",
        L".c", L".cc", L".cpp", L".cxx", L".h", L".hpp", L".cs", L".js", L".jsx", L".ts", L".tsx",
        L".html", L".htm", L".css", L".scss", L".py", L".ps1", L".cmd", L".bat", L".sh", L".sql"});
}

std::wstring NativeFilePreviewPane::FileName(const std::wstring& path)
{
    const std::size_t separator = path.find_last_of(L"\\/");
    if (separator == std::wstring::npos) return path;
    if (separator + 1 >= path.size()) return path;
    return path.substr(separator + 1);
}

std::wstring NativeFilePreviewPane::Extension(const std::wstring& path)
{
    const std::wstring name = FileName(path);
    const std::size_t dot = name.find_last_of(L'.');
    if (dot == std::wstring::npos || dot == 0) return {};
    return name.substr(dot);
}

std::wstring NativeFilePreviewPane::FormatBytes(ULONGLONG bytes)
{
    constexpr std::array<const wchar_t*, 5> units{{L"B", L"KB", L"MB", L"GB", L"TB"}};
    double value = static_cast<double>(bytes);
    std::size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < units.size())
    {
        value /= 1024.0;
        ++unit;
    }
    wchar_t buffer[64]{};
    if (unit == 0)
        swprintf_s(buffer, L"%llu %s", bytes, units[unit]);
    else
        swprintf_s(buffer, L"%.1f %s", value, units[unit]);
    return buffer;
}

std::wstring NativeFilePreviewPane::FormatModified(const FILETIME& value)
{
    FILETIME local{};
    SYSTEMTIME time{};
    if (!FileTimeToLocalFileTime(&value, &local) || !FileTimeToSystemTime(&local, &time)) return {};
    wchar_t date[64]{};
    wchar_t clock[64]{};
    if (GetDateFormatEx(LOCALE_NAME_USER_DEFAULT, DATE_SHORTDATE, &time, nullptr, date, static_cast<int>(std::size(date)), nullptr) == 0)
        return {};
    if (GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &time, nullptr, clock, static_cast<int>(std::size(clock))) == 0)
        return date;
    std::wstring result = date;
    result += L" ";
    result += clock;
    return result;
}

void NativeFilePreviewPane::Paint(HDC dc)
{
    if (dc == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, background_);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(16, dpi);

    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, WebSkin::TextPrimary);
    HGDIOBJ old_font = nullptr;
    SelectFont(dc, title_font_, &old_font);
    RECT title_rect{margin, margin, client.right - margin, margin + Scale(48, dpi)};
    DrawTextW(dc, title_.empty() ? L"Visualização" : title_.c_str(), -1, &title_rect,
        DT_LEFT | DT_TOP | DT_END_ELLIPSIS | DT_SINGLELINE);
    if (old_font != nullptr) SelectObject(dc, old_font);

    SetTextColor(dc, WebSkin::TextSecondary);
    SelectFont(dc, text_font_, &old_font);
    RECT metadata_rect{margin, margin + Scale(42, dpi), client.right - margin, margin + Scale(118, dpi)};
    DrawTextW(dc, metadata_.c_str(), -1, &metadata_rect, DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS);
    if (old_font != nullptr) SelectObject(dc, old_font);

    const int body_top = margin + Scale(126, dpi);
    RECT body{margin, body_top, client.right - margin, client.bottom - margin};
    if (kind_ == PreviewKind::Image && bitmap_ != nullptr && bitmap_size_.cx > 0 && bitmap_size_.cy > 0)
    {
        const int available_width = std::max(1, body.right - body.left);
        const int available_height = std::max(1, body.bottom - body.top);
        const double scale = std::min(
            static_cast<double>(available_width) / static_cast<double>(bitmap_size_.cx),
            static_cast<double>(available_height) / static_cast<double>(bitmap_size_.cy));
        const int width = std::max(1, static_cast<int>(static_cast<double>(bitmap_size_.cx) * std::min(1.0, scale)));
        const int height = std::max(1, static_cast<int>(static_cast<double>(bitmap_size_.cy) * std::min(1.0, scale)));
        const int x = body.left + (available_width - width) / 2;
        const int y = body.top + (available_height - height) / 2;

        HDC memory = CreateCompatibleDC(dc);
        if (memory != nullptr)
        {
            HGDIOBJ previous = SelectObject(memory, bitmap_);
            SetStretchBltMode(dc, HALFTONE);
            StretchBlt(dc, x, y, width, height, memory, 0, 0, bitmap_size_.cx, bitmap_size_.cy, SRCCOPY);
            if (previous != nullptr) SelectObject(memory, previous);
            DeleteDC(memory);
        }
    }
    else if (kind_ == PreviewKind::Text)
    {
        SetTextColor(dc, WebSkin::TextPrimary);
        SelectFont(dc, text_font_, &old_font);
        DrawTextW(dc, text_.c_str(), -1, &body, DT_LEFT | DT_TOP | DT_WORDBREAK | DT_NOPREFIX);
        if (old_font != nullptr) SelectObject(dc, old_font);
    }
    else
    {
        std::wstring message;
        if (kind_ == PreviewKind::Directory) message = L"Pasta selecionada";
        else if (kind_ == PreviewKind::Unavailable) message = L"O item não está mais disponível.";
        else if (kind_ == PreviewKind::Generic) message = L"Sem visualização de conteúdo para este tipo de arquivo.";
        else message = L"Selecione um arquivo para visualizar.";
        SetTextColor(dc, WebSkin::TextTertiary);
        SelectFont(dc, text_font_, &old_font);
        DrawTextW(dc, message.c_str(), -1, &body, DT_LEFT | DT_TOP | DT_WORDBREAK);
        if (old_font != nullptr) SelectObject(dc, old_font);
    }
}

LRESULT CALLBACK NativeFilePreviewPane::WindowProcedure(
    HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<NativeFilePreviewPane*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<NativeFilePreviewPane*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->window_ = window;
    }
    if (self == nullptr) return DefWindowProcW(window, message, w_param, l_param);

    switch (message)
    {
    case WM_PAINT:
    {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        self->Paint(dc);
        EndPaint(window, &paint);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_NCDESTROY:
        if (self->window_ == window) self->window_ = nullptr;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        break;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
