#include "native_theme.h"
#include "native_appearance_manager.h"

#include <algorithm>
#include <mutex>

namespace CloudOS
{
namespace
{
constexpr wchar_t kAppearanceKey[] = L"Software\\CloudOS\\AppearanceV4";
constexpr wchar_t kAccentValue[] = L"Accent";
constexpr wchar_t kTransparencyValue[] = L"Transparency";
constexpr wchar_t kCompactValue[] = L"CompactStatus";

std::mutex g_appearance_mutex;
bool g_loaded{};
NativeAppearanceState g_state{};

BYTE BlendChannel(BYTE value, BYTE target, unsigned amount)
{
    return static_cast<BYTE>((static_cast<unsigned>(value) * (100u - amount) +
        static_cast<unsigned>(target) * amount) / 100u);
}

COLORREF Blend(COLORREF color, COLORREF target, unsigned amount)
{
    amount = std::min(amount, 100u);
    return RGB(
        BlendChannel(GetRValue(color), GetRValue(target), amount),
        BlendChannel(GetGValue(color), GetGValue(target), amount),
        BlendChannel(GetBValue(color), GetBValue(target), amount));
}

bool ReadDword(HKEY key, const wchar_t* name, DWORD* value)
{
    if (value == nullptr) return false;
    DWORD type = 0;
    DWORD size = sizeof(*value);
    return RegQueryValueExW(key, name, nullptr, &type,
        reinterpret_cast<BYTE*>(value), &size) == ERROR_SUCCESS &&
        type == REG_DWORD && size == sizeof(*value);
}
}

std::array<COLORREF, 6> NativeAppearanceManager::Presets()
{
    return {
        RGB(99, 102, 241),
        RGB(56, 139, 253),
        RGB(20, 184, 166),
        RGB(244, 63, 94),
        RGB(245, 158, 11),
        RGB(168, 85, 247),
    };
}

NativeAppearanceState NativeAppearanceManager::Load()
{
    NativeAppearanceState result{};
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kAppearanceKey, 0, KEY_READ, &key) != ERROR_SUCCESS)
        return result;

    DWORD value = 0;
    if (ReadDword(key, kAccentValue, &value))
        result.accent = static_cast<COLORREF>(value & 0x00FFFFFFu);
    if (ReadDword(key, kTransparencyValue, &value))
        result.transparency = value != 0;
    if (ReadDword(key, kCompactValue, &value))
        result.compact_status = value != 0;
    RegCloseKey(key);
    return result;
}

void NativeAppearanceManager::Save(const NativeAppearanceState& state)
{
    HKEY key = nullptr;
    DWORD disposition = 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kAppearanceKey, 0, nullptr, 0,
            KEY_WRITE, nullptr, &key, &disposition) != ERROR_SUCCESS)
        return;
    const DWORD accent = static_cast<DWORD>(state.accent & 0x00FFFFFFu);
    const DWORD transparency = state.transparency ? 1u : 0u;
    const DWORD compact = state.compact_status ? 1u : 0u;
    (void)RegSetValueExW(key, kAccentValue, 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&accent), sizeof(accent));
    (void)RegSetValueExW(key, kTransparencyValue, 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&transparency), sizeof(transparency));
    (void)RegSetValueExW(key, kCompactValue, 0, REG_DWORD,
        reinterpret_cast<const BYTE*>(&compact), sizeof(compact));
    (void)RegFlushKey(key);
    RegCloseKey(key);
}

NativeAppearanceState NativeAppearanceManager::Current()
{
    std::scoped_lock lock(g_appearance_mutex);
    if (!g_loaded)
    {
        g_state = Load();
        g_loaded = true;
        WebSkin::Accent = g_state.accent;
        WebSkin::AccentCyan = g_state.accent;
        WebSkin::AccentHover = Blend(g_state.accent, RGB(255,255,255), 18);
        WebSkin::AccentActive = Blend(g_state.accent, RGB(0,0,0), 15);
        WebSkin::AccentSubtle = Blend(g_state.accent, WebSkin::BgPrimary, 80);
    }
    return g_state;
}

void NativeAppearanceManager::SetAccent(COLORREF accent)
{
    std::scoped_lock lock(g_appearance_mutex);
    if (!g_loaded) { g_state = Load(); g_loaded = true; }
    g_state.accent = accent & 0x00FFFFFFu;
    WebSkin::Accent = g_state.accent;
    WebSkin::AccentCyan = g_state.accent;
    WebSkin::AccentHover = Blend(g_state.accent, RGB(255,255,255), 18);
    WebSkin::AccentSubtle = Blend(g_state.accent, WebSkin::BgPrimary, 80);
    Save(g_state);
}

void NativeAppearanceManager::SetTransparency(bool enabled)
{
    std::scoped_lock lock(g_appearance_mutex);
    if (!g_loaded) { g_state = Load(); g_loaded = true; }
    g_state.transparency = enabled;
    WebSkin::Accent = g_state.accent;
    WebSkin::AccentCyan = g_state.accent;
    WebSkin::AccentHover = Blend(g_state.accent, RGB(255,255,255), 18);
    WebSkin::AccentSubtle = Blend(g_state.accent, WebSkin::BgPrimary, 80);
    Save(g_state);
}

void NativeAppearanceManager::SetCompactStatus(bool enabled)
{
    std::scoped_lock lock(g_appearance_mutex);
    if (!g_loaded) { g_state = Load(); g_loaded = true; }
    g_state.compact_status = enabled;
    WebSkin::Accent = g_state.accent;
    WebSkin::AccentCyan = g_state.accent;
    WebSkin::AccentHover = Blend(g_state.accent, RGB(255,255,255), 18);
    WebSkin::AccentSubtle = Blend(g_state.accent, WebSkin::BgPrimary, 80);
    Save(g_state);
}

COLORREF NativeAppearanceManager::Accent()
{
    return Current().accent;
}

COLORREF NativeAppearanceManager::AccentHover()
{
    return Blend(Accent(), RGB(255, 255, 255), 24u);
}

COLORREF NativeAppearanceManager::AccentSubtle()
{
    return Blend(Accent(), RGB(17, 17, 24), 72u);
}

COLORREF NativeAppearanceManager::NextPresetAccent(COLORREF current)
{
    const auto presets = Presets();
    for (std::size_t index = 0; index < presets.size(); ++index)
    {
        if (presets[index] == current)
            return presets[(index + 1u) % presets.size()];
    }
    return presets.front();
}
} // namespace CloudOS
