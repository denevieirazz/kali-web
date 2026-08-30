#pragma once

#include <Windows.h>

#include <string>

namespace CloudOS
{
class NativeFilePreviewPane final
{
public:
    NativeFilePreviewPane() = default;
    ~NativeFilePreviewPane();

    NativeFilePreviewPane(const NativeFilePreviewPane&) = delete;
    NativeFilePreviewPane& operator=(const NativeFilePreviewPane&) = delete;

    bool Create(HINSTANCE instance, HWND parent);
    void Destroy() noexcept;
    void Resize(const RECT& bounds) noexcept;
    void Show(bool visible) noexcept;
    void SetPath(const std::wstring& path);
    void Clear();

    [[nodiscard]] HWND Window() const noexcept { return window_; }
    [[nodiscard]] const std::wstring& Path() const noexcept { return path_; }

private:
    enum class PreviewKind
    {
        Empty,
        Directory,
        Image,
        Text,
        Generic,
        Unavailable,
    };

    bool LoadImage(const std::wstring& path);
    bool LoadText(const std::wstring& path);
    void LoadMetadata(const std::wstring& path);
    void Paint(HDC dc);
    void ReleaseImage() noexcept;

    static bool LooksLikeImage(const std::wstring& path);
    static bool LooksLikeText(const std::wstring& path);
    static std::wstring FileName(const std::wstring& path);
    static std::wstring Extension(const std::wstring& path);
    static std::wstring FormatBytes(ULONGLONG bytes);
    static std::wstring FormatModified(const FILETIME& value);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND parent_{};
    HWND window_{};
    HBITMAP bitmap_{};
    SIZE bitmap_size_{};
    HFONT title_font_{};
    HFONT text_font_{};
    HBRUSH background_{};
    PreviewKind kind_{PreviewKind::Empty};
    std::wstring path_;
    std::wstring title_;
    std::wstring metadata_;
    std::wstring text_;
};
} // namespace CloudOS
