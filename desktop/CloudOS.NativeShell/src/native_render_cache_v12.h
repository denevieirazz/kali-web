#pragma once
#include <windows.h>
#include <commctrl.h>
#include "native_performance_v12.h"

namespace CloudOS
{
// UI-thread-only, per HWND. The subclass owns lifetime, including failure paths.
class NativeBackbufferV12 final
{
    HDC dc_{}; HBITMAP bitmap_{}; HGDIOBJ old_{}; int width_{}, height_{}; UINT dpi_{};
    static constexpr UINT_PTR Id = 0xB12;
    static LRESULT CALLBACK Cleanup(HWND window, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data)
    {
        if (msg == WM_NCDESTROY) { RemovePropW(window, L"CloudOS.Backbuffer.V12"); RemoveWindowSubclass(window, Cleanup, id); delete reinterpret_cast<NativeBackbufferV12*>(data); }
        return DefSubclassProc(window, msg, wp, lp);
    }
    void Reset()
    {
        if (dc_) { SelectObject(dc_, old_); DeleteObject(bitmap_); DeleteDC(dc_); }
        dc_ = nullptr; bitmap_ = nullptr; old_ = nullptr;
    }
public:
    ~NativeBackbufferV12() { Reset(); }
    static HDC Acquire(HWND window, HDC target, int width, int height)
    {
        auto* self = reinterpret_cast<NativeBackbufferV12*>(GetPropW(window, L"CloudOS.Backbuffer.V12"));
        if (!self)
        {
            self = new NativeBackbufferV12;
            if (!SetPropW(window, L"CloudOS.Backbuffer.V12", self) || !SetWindowSubclass(window, Cleanup, Id, reinterpret_cast<DWORD_PTR>(self)))
            { RemovePropW(window, L"CloudOS.Backbuffer.V12"); delete self; return nullptr; }
        }
        const UINT dpi = GetDpiForWindow(window);
        if (self->width_ != width || self->height_ != height || self->dpi_ != dpi || !self->dc_)
        {
            self->Reset(); self->dc_ = CreateCompatibleDC(target);
            self->bitmap_ = CreateCompatibleBitmap(target, width, height);
            if (!self->dc_ || !self->bitmap_) { if (self->bitmap_) DeleteObject(self->bitmap_); if (self->dc_) DeleteDC(self->dc_); self->dc_ = nullptr; self->bitmap_ = nullptr; return nullptr; }
            self->old_ = SelectObject(self->dc_, self->bitmap_);
            self->width_ = width; self->height_ = height; self->dpi_ = dpi;
            PerformanceV12::Add(PerformanceV12::BackbufferAllocation);
        }
        return self->dc_;
    }
};
}
