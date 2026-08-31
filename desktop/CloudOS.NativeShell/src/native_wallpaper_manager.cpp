#include "native_wallpaper_manager.h"

#include "native_notification_center.h"

#include <commdlg.h>

#include <algorithm>
#include <memory>
#include <mutex>
#include <condition_variable>
#include <thread>
#include "native_theme.h"

#pragma comment(lib, "comdlg32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kRegistryPath[] = L"Software\\CloudOS\\ShellV2";
constexpr wchar_t kWallpaperValue[] = L"WallpaperPath";

class WallpaperCacheV12 final
{
    std::mutex mutex_; std::condition_variable wake_; std::thread worker_;
    std::shared_ptr<Gdiplus::Bitmap> bitmap_;
    bool stopped_{},pending_{},force_{}; int width_{},height_{}; HWND target_{};
    void Work()
    {
        std::wstring previous_path; int previous_width{},previous_height{}; bool initialized{};
        for(;;)
        {
            int width{},height{}; HWND target{}; bool force{};
            {std::unique_lock lock(mutex_);wake_.wait(lock,[this]{return stopped_||pending_;});if(stopped_)break;
             pending_=false;width=width_;height=height_;target=target_;force=force_;force_=false;}
            const auto path=NativeWallpaperManager::CurrentPath();
            if(!force && initialized && path==previous_path && width==previous_width && height==previous_height) continue;
            previous_path=path;previous_width=width;previous_height=height;initialized=true;
            std::shared_ptr<Gdiplus::Bitmap> result;
            if(!path.empty())
            {
                Gdiplus::Image source(path.c_str(),FALSE);
                if(source.GetLastStatus()==Gdiplus::Ok && source.GetWidth() && source.GetHeight())
                {
                    result=std::make_shared<Gdiplus::Bitmap>(width,height,PixelFormat32bppPARGB);
                    Gdiplus::Graphics draw(result.get());
                    const double ratio=static_cast<double>(width)/height;
                    const double source_ratio=static_cast<double>(source.GetWidth())/source.GetHeight();
                    const double crop_width=source_ratio>ratio?source.GetHeight()*ratio:source.GetWidth();
                    const double crop_height=source_ratio>ratio?source.GetHeight():source.GetWidth()/ratio;
                    draw.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
                    draw.DrawImage(&source,Gdiplus::Rect(0,0,width,height),static_cast<INT>((source.GetWidth()-crop_width)/2),static_cast<INT>((source.GetHeight()-crop_height)/2),static_cast<INT>(crop_width),static_cast<INT>(crop_height),Gdiplus::UnitPixel);
                    draw.Flush(Gdiplus::FlushIntentionSync);
                }
            }
            {std::scoped_lock lock(mutex_);bitmap_=std::move(result);}
            if(target) PostMessageW(target,WM_APP+0x61D,0,0);
        }
    }
public:
    ~WallpaperCacheV12(){Stop();}
    void Request(HWND target,int width,int height,bool force)
    {
        {std::scoped_lock lock(mutex_);stopped_=false;
         if(target)target_=target;if(width>0)width_=width;if(height>0)height_=height;
         if(width_<=0 || height_<=0) return;
         pending_=true;force_=force_||force;
         if(!worker_.joinable())worker_=std::thread([this]{Work();});}
        wake_.notify_one();
    }
    std::shared_ptr<Gdiplus::Bitmap> Snapshot(){std::scoped_lock lock(mutex_);return bitmap_;}
    void Stop(){ {std::scoped_lock lock(mutex_);stopped_=true;} wake_.notify_all();if(worker_.joinable())worker_.join();bitmap_.reset();pending_=false;target_=nullptr;width_=height_=0; }
};
WallpaperCacheV12& WallpaperCache(){static WallpaperCacheV12 cache;return cache;}

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

}

void NativeWallpaperManager::Prepare(HWND target,int width,int height,bool force) { WallpaperCache().Request(target,width,height,force); }
void NativeWallpaperManager::Stop() {WallpaperCache().Stop();}

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

    Prepare(nullptr,0,0,true);

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
    Prepare(nullptr,0,0,true);
    CloudOSNativeNotificationCenter::Post(
        L"Wallpaper restaurado",
        L"O CloudOS voltou ao fundo padrao.");
}

bool NativeWallpaperManager::Draw(Gdiplus::Graphics& graphics,int width,int height)
{
    const auto bitmap=WallpaperCache().Snapshot();
    if(!bitmap || bitmap->GetWidth()!=static_cast<UINT>(width) || bitmap->GetHeight()!=static_cast<UINT>(height)) return false;
    const auto state=graphics.Save();
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeNearestNeighbor);
    const bool drawn=graphics.DrawImage(bitmap.get(),Gdiplus::Rect(0,0,width,height),0,0,width,height,Gdiplus::UnitPixel)==Gdiplus::Ok;
    graphics.Restore(state);return drawn;
}
} // namespace CloudOS
