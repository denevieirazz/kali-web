#pragma once

#include <windows.h>

#include <array>

namespace CloudOS
{
struct NativeAppearanceState final
{
    COLORREF accent{RGB(76, 142, 219)};
    bool transparency{true};
    bool compact_status{};
};

class NativeAppearanceManager final
{
public:
    static NativeAppearanceState Current();
    static void SetAccent(COLORREF accent);
    static void SetTransparency(bool enabled);
    static void SetCompactStatus(bool enabled);
    static COLORREF Accent();
    static COLORREF AccentHover();
    static COLORREF AccentSubtle();
    static COLORREF NextPresetAccent(COLORREF current);
    static std::array<COLORREF, 6> Presets();

private:
    static NativeAppearanceState Load();
    static void Save(const NativeAppearanceState& state);
};
} // namespace CloudOS
