#pragma once
#include "native_theme.h"
#include <oleacc.h>
#include <memory>
#include <vector>

namespace CloudOS
{
// Only use with menus owned by CloudOS, never with Shell extension IContextMenu.
class NativePopupMenu final
{
    struct Item
    {
        MSAAMENUINFO accessible{};
        HMENU menu{};
        UINT position{};
        UINT original_type{};
        ULONG_PTR original_data{};
        std::wstring text;
        bool separator{};
        bool submenu{};
    };
    std::vector<std::unique_ptr<Item>> items_;
    HFONT font_{};
    UINT dpi_{96};
    static constexpr UINT_PTR kSubclass = 0x504D454E;
    void Prepare(HMENU menu)
    {
        MENUINFO style{sizeof(style)};
        style.fMask = MIM_BACKGROUND; style.hbrBack = WebSkin::SharedSurfaceBrush();
        SetMenuInfo(menu, &style);
        const int count = GetMenuItemCount(menu);
        for (int index = 0; index < count; ++index)
        {
            wchar_t caption[1024]{};
            MENUITEMINFOW info{sizeof(info)};
            info.fMask = MIIM_FTYPE | MIIM_DATA | MIIM_STRING | MIIM_SUBMENU;
            info.dwTypeData = caption; info.cch = static_cast<UINT>(std::size(caption));
            if (!GetMenuItemInfoW(menu, index, TRUE, &info) || (info.fType & MFT_OWNERDRAW)) continue;
            auto item = std::make_unique<Item>();
            item->menu = menu; item->position = index; item->original_type = info.fType;
            item->original_data = info.dwItemData; item->text = caption;
            item->accessible = {MSAA_MENU_SIG, static_cast<DWORD>(item->text.size()), item->text.data()};
            item->separator = (info.fType & MFT_SEPARATOR) != 0; item->submenu = info.hSubMenu != nullptr;
            const HMENU child = info.hSubMenu;
            info.fMask = MIIM_FTYPE | MIIM_DATA;
            info.fType |= MFT_OWNERDRAW; info.dwItemData = reinterpret_cast<ULONG_PTR>(item.get());
            SetMenuItemInfoW(menu, index, TRUE, &info);
            items_.push_back(std::move(item));
            if (child) Prepare(child);
        }
    }
    Item* Find(ULONG_PTR data)
    {
        for (auto& item : items_) if (reinterpret_cast<ULONG_PTR>(item.get()) == data) return item.get();
        return nullptr;
    }
    static LRESULT CALLBACK Subclass(HWND window, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR data)
    {
        auto& self = *reinterpret_cast<NativePopupMenu*>(data);
        if (msg == WM_MEASUREITEM)
        {
            auto* measure = reinterpret_cast<MEASUREITEMSTRUCT*>(lp);
            auto* item = measure && measure->CtlType == ODT_MENU ? self.Find(measure->itemData) : nullptr;
            if (item)
            {
                HDC dc = GetDC(window); auto old = SelectObject(dc, self.font_);
                SIZE size{}; GetTextExtentPoint32W(dc, item->text.c_str(), static_cast<int>(item->text.size()), &size);
                SelectObject(dc, old); ReleaseDC(window, dc);
                measure->itemWidth = std::clamp<int>(size.cx + Scale(64, self.dpi_), Scale(220, self.dpi_), Scale(460, self.dpi_));
                measure->itemHeight = Scale(item->separator ? 10 : 36, self.dpi_);
                return TRUE;
            }
        }
        if (msg == WM_DRAWITEM)
        {
            const auto* draw = reinterpret_cast<DRAWITEMSTRUCT*>(lp);
            auto* item = draw && draw->CtlType == ODT_MENU ? self.Find(draw->itemData) : nullptr;
            if (item)
            {
                RECT r = draw->rcItem;
                FillRect(draw->hDC, &r, WebSkin::SharedSurfaceBrush());
                if (item->separator)
                {
                    r.left += Scale(12, self.dpi_); r.right -= Scale(12, self.dpi_);
                    r.top = (r.top + r.bottom) / 2; r.bottom = r.top + 1;
                    FillRect(draw->hDC, &r, WebSkin::SharedEditBrush()); return TRUE;
                }
                if (draw->itemState & ODS_SELECTED) FillRect(draw->hDC, &r, WebSkin::SharedEditBrush());
                const bool disabled = (draw->itemState & (ODS_DISABLED | ODS_GRAYED)) != 0;
                auto old = SelectObject(draw->hDC, self.font_);
                SetBkMode(draw->hDC, TRANSPARENT);
                SetTextColor(draw->hDC, disabled ? WebSkin::TextDisabled : WebSkin::TextPrimary);
                RECT label = r; label.left += Scale(28, self.dpi_); label.right -= Scale(30, self.dpi_);
                DrawTextW(draw->hDC, item->text.c_str(), -1, &label, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
                if (item->submenu)
                {
                    r.left = r.right - Scale(24, self.dpi_);
                    DrawTextW(draw->hDC, L"›", -1, &r, DT_SINGLELINE | DT_VCENTER);
                }
                if (draw->itemState & ODS_CHECKED)
                {
                    r = draw->rcItem; r.left += Scale(8, self.dpi_);
                    DrawTextW(draw->hDC, L"✓", -1, &r, DT_SINGLELINE | DT_VCENTER);
                }
                SelectObject(draw->hDC, old); return TRUE;
            }
        }
        return DefSubclassProc(window, msg, wp, lp);
    }
public:
    static BOOL Track(HMENU menu, UINT flags, int x, int y, int reserved, HWND owner, const RECT* exclude)
    {
        NativePopupMenu skin;
        skin.dpi_ = GetDpiForWindow(owner);
        skin.font_ = CreateFontW(-Scale(14, skin.dpi_), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
        if (!SetWindowSubclass(owner, Subclass, kSubclass, reinterpret_cast<DWORD_PTR>(&skin)))
        { DeleteObject(skin.font_); return TrackPopupMenu(menu, flags, x, y, reserved, owner, exclude); }
        skin.Prepare(menu);
        const BOOL result = TrackPopupMenu(menu, flags, x, y, reserved, owner, exclude);
        RemoveWindowSubclass(owner, Subclass, kSubclass);
        for (const auto& item : skin.items_)
        {
            MENUITEMINFOW info{sizeof(info)}; info.fMask = MIIM_FTYPE | MIIM_DATA;
            info.fType = item->original_type; info.dwItemData = item->original_data;
            SetMenuItemInfoW(item->menu, item->position, TRUE, &info);
        }
        DeleteObject(skin.font_);
        return result;
    }
};
}
