#pragma once
#include <windows.h>
#include <array>
namespace CloudOS::DesignV12
{
inline constexpr COLORREF Background = RGB(24,24,24), Canvas = RGB(20,20,20), Surface = RGB(32,32,32), Raised = RGB(42,42,42), Hover = RGB(50,50,50), Active = RGB(58,58,58);
inline constexpr COLORREF Accent = RGB(76,142,219), AccentHover = RGB(115,166,227), AccentPressed = RGB(54,109,178), AccentSubtle = RGB(35,48,64);
inline constexpr COLORREF Text = RGB(245,245,245), Secondary = RGB(184,184,184), Caption = RGB(150,150,150), Disabled = RGB(110,110,110);
inline constexpr COLORREF Border = RGB(55,55,55), BorderStrong = RGB(70,70,70), Danger = RGB(217,101,108);
inline constexpr std::array<int,7> Spacing{4,8,12,16,20,24,32};
inline constexpr int RadiusSmall=8, RadiusMedium=12, RadiusLarge=16;
inline constexpr int Title=22, Subtitle=16, Body=14, Small=12;
inline constexpr int TaskbarHeight=52, StartWidth=640, StartHeight=680, QuickWidth=420;
inline constexpr UINT AnimationInterval=16;
}
