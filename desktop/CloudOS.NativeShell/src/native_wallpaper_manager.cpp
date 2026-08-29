#include "native_wallpaper_manager.h"

#include "native_notification_center.h"

#include <commdlg.h>

#include <algorithm>
#include <memory>

#pragma comment(lib, "comdlg32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kRegistryPath[] = L"Software\\CloudOS\\ShellV2";
constexpr wchar_t kWallpaperValue[] = L"WallpaperPath";

std::wstring g_cached_path;
std::unique_ptr<Gdiplus::Image> g_cached_image;

void InvalidateCache()
{
    g_cached_path.clear();
    g_cached_image.reset();
}

bool Exists(const std::wstring& path)
{
    if (path.empty())
    {
        return false;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

void EnsureCache()
{
    const std::wstring path = NativeWallpaperManager::CurrentPath();
    if (path == g_cached_path && g_cached_image != nullptr)
    {
        return;
    }

    g_cached_path = path;
    g_cached_image.reset();
    if (!Exists(path))
    {
        return;
    }

    auto image = std::make_unique<Gdiplus::Image>(path.c_str(), FALSE);
    if (image->GetLastStatus() == Gdiplus::Ok &&
        image->GetWidth() > 0 && image->GetHeight() > 0)
    {
        g_cached_image = std::move(image);
    }
}
}

std::wstring NativeWallpaperManager::CurrentPath()
{
    DWORD bytes = 0;
    const LSTATUS size_status = RegGetValueW(
        HKEY_CURRENT_USER,
        kRegistryPath,
        kWallpaperValue,
        RRF_RT_REG_SZ,
        nullptr,
        nullptr,
        &bytes);
    if (size_status != ERROR_SUCCESS || bytes < sizeof(wchar_t))
    {
        return {};
    }

    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    DWORD type = 0;
    if (RegGetValueW(
            HKEY_CURRENT_USER,
            kRegistryPath,
            kWallpaperValue,
            RRF_RT_REG_SZ,
            &type,
            value.data(),
            &bytes) != ERROR_SUCCESS)
    {
        return {};
    }

    while (!value.empty() && value.back() == L'\0')
    {
        value.pop_back();
    }
    return value;
}

bool NativeWallpaperManager::Apply(const std::wstring& path)
{
    if (!Exists(path))
    {
        return false;
    }

    HKEY key = nullptr;
    if (RegCreateKeyExW(
            HKEY_CURRENT_USER,
            kRegistryPath,
            0,
            nullptr,
            REG_OPTION_NON_VOLATILE,
            KEY_SET_VALUE,
            nullptr,
            &key,
            nullptr) != ERROR_SUCCESS)
    {
        return false;
    }

    const DWORD bytes = static_cast<DWORD>((path.size() + 1u) * sizeof(wchar_t));
    const LSTATUS status = RegSetValueExW(
        key,
        kWallpaperValue,
        0,
        REG_SZ,
        reinterpret_cast<const BYTE*>(path.c_str()),
        bytes);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS)
    {
        return false;
    }

    InvalidateCache();

    // Keep Windows and CloudOS visually aligned where Windows accepts the format.
    (void)SystemParametersInfoW(
        SPI_SETDESKWALLPAPER,
        0,
        const_cast<wchar_t*>(path.c_str()),
        SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);

    CloudOSNativeNotificationCenter::Post(
        L"Wallpaper alterado",
        L"A nova imagem foi salva na sessao do CloudOS.");
    return true;
}

bool NativeWallpaperManager::PickAndApply(HWND owner)
{
    wchar_t path[MAX_PATH * 4]{};
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = owner;
    dialog.lpstrFile = path;
    dialog.nMaxFile = static_cast<DWORD>(std::size(path));
    dialog.lpstrFilter =
        L"Imagens\0*.jpg;*.jpeg;*.png;*.bmp;*.gif\0"
        L"Todos os arquivos\0*.*\0\0";
    dialog.lpstrTitle = L"Escolher wallpaper do CloudOS";
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;

    if (!GetOpenFileNameW(&dialog))
    {
        return false;
    }
    return Apply(path);
}

void NativeWallpaperManager::Reset()
{
    HKEY key = nullptr;
    if (RegOpenKeyExW(
            HKEY_CURRENT_USER,
            kRegistryPath,
            0,
            KEY_SET_VALUE,
            &key) == ERROR_SUCCESS)
    {
        (void)RegDeleteValueW(key, kWallpaperValue);
        RegCloseKey(key);
    }
    InvalidateCache();
    CloudOSNativeNotificationCenter::Post(
        L"Wallpaper restaurado",
        L"O CloudOS voltou ao fundo padrao.");
}

bool NativeWallpaperManager::Draw(
    Gdiplus::Graphics& graphics,
    int width,
    int height)
{
    if (width <= 0 || height <= 0)
    {
        return false;
    }

    EnsureCache();
    if (g_cached_image == nullptr)
    {
        return false;
    }

    const double source_width = static_cast<double>(g_cached_image->GetWidth());
    const double source_height = static_cast<double>(g_cached_image->GetHeight());
    const double destination_ratio = static_cast<double>(width) / static_cast<double>(height);
    const double source_ratio = source_width / source_height;

    Gdiplus::Rect source{};
    if (source_ratio > destination_ratio)
    {
        const int crop_width = static_cast<int>(source_height * destination_ratio);
        source.X = static_cast<int>((source_width - crop_width) / 2.0);
        source.Y = 0;
        source.Width = std::max(1, crop_width);
        source.Height = static_cast<int>(source_height);
    }
    else
    {
        const int crop_height = static_cast<int>(source_width / destination_ratio);
        source.X = 0;
        source.Y = static_cast<int>((source_height - crop_height) / 2.0);
        source.Width = static_cast<int>(source_width);
        source.Height = std::max(1, crop_height);
    }

    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    graphics.DrawImage(
        g_cached_image.get(),
        Gdiplus::Rect(0, 0, width, height),
        source.X,
        source.Y,
        source.Width,
        source.Height,
        Gdiplus::UnitPixel);
    return true;
}
} // namespace CloudOS
