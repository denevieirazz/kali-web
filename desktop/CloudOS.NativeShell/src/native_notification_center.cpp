#include "native_flyout_layout.h"
#include "native_performance_v12.h"
#include "native_notification_center.h"

#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <mutex>
#include <atomic>
#include "native_window_manager.h"
#include <new>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr wchar_t kNotificationClass[] = L"CloudOS.NativeShell.NotificationCenter.v2";
constexpr int kListId = 8701;
constexpr int kClearId = 8702;

using NotificationEntry = NativeNotificationItemV12;
std::uint64_t g_revision_v12{};
std::atomic<HWND> g_notification_target_v12{};
constexpr UINT kNotificationChangedV12=WM_APP+0x61A;

std::mutex g_notification_mutex;
std::vector<NotificationEntry> g_notifications;

std::wstring TimeText(const SYSTEMTIME& time)
{
    wchar_t buffer[64]{};
    if (GetTimeFormatEx(LOCALE_NAME_USER_DEFAULT, TIME_NOSECONDS, &time, nullptr,
            buffer, static_cast<int>(std::size(buffer))) == 0)
    {
        return L"--:--";
    }
    return buffer;
}

void SetFont(HWND window, HFONT font)
{
    if (window != nullptr && font != nullptr)
        SendMessageW(window, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}
}

CloudOSNativeNotificationCenter::~CloudOSNativeNotificationCenter()
{
    Destroy();
}

bool CloudOSNativeNotificationCenter::Create(HINSTANCE instance)
{
    instance_ = instance;
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeNotificationCenter::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kNotificationClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kNotificationClass,
        L"Notificacoes - CloudOS",
        WS_POPUP | WS_CLIPCHILDREN,
        0, 0, 480, 580,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;

    background_ = WebSkin::CreateBackgroundBrush();
    font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");

    list_ = CreateWindowExW(
        0, WC_LISTVIEWW, L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_NOCOLUMNHEADER | LVS_SHAREIMAGELISTS | WS_TABSTOP,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)), instance_, nullptr);
    clear_button_ = CreateWindowW(
        L"BUTTON", L"Limpar historico",
        WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kClearId)), instance_, nullptr);
    status_label_ = CreateWindowW(
        L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    if (list_ == nullptr || clear_button_ == nullptr || status_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    SetFont(list_, font_);
    SetFont(clear_button_, font_);
    SetFont(status_label_, font_);
    WebSkin::PrepareListView(list_);
    WebSkin::PrepareButton(clear_button_);

    ListView_SetExtendedListViewStyle(list_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    LVCOLUMNW column{}; column.mask=LVCF_TEXT|LVCF_WIDTH; column.pszText=const_cast<LPWSTR>(L"Notificacoes"); column.cx=420; ListView_InsertColumn(list_,0,&column);
    heading_v12_=CreateWindowW(L"STATIC",L"Notificacoes",WS_CHILD|WS_VISIBLE,0,0,0,0,window_,nullptr,instance_,nullptr);
    WebSkin::ApplyUxTheme(window_);
    ApplyWebFlyoutMaterial(window_);
    Layout();
    RebuildList();
    g_notification_target_v12=window_;
    return true;
}

void CloudOSNativeNotificationCenter::Destroy()
{
    g_notification_target_v12=nullptr;
    if (list_) ListView_SetImageList(list_,nullptr,LVSIL_SMALL);
    if (row_image_v12_) { ImageList_Destroy(row_image_v12_); row_image_v12_=nullptr; }
    if (heading_font_v12_) { DeleteObject(heading_font_v12_); heading_font_v12_=nullptr; }
    if (window_ != nullptr && IsWindow(window_)) DestroyWindow(window_);
    window_ = nullptr; list_ = nullptr; clear_button_ = nullptr; status_label_ = nullptr;
    if (font_ != nullptr) { DeleteObject(font_); font_ = nullptr; }
    if (background_ != nullptr) { DeleteObject(background_); background_ = nullptr; }
}

void CloudOSNativeNotificationCenter::Post(const std::wstring& title, const std::wstring& message, int severity)
{
    NotificationEntry entry{};
    GetLocalTime(&entry.time);
    entry.title = title.empty() ? L"CloudOS" : title;
    entry.message = message;
    entry.severity = severity;
    entry.read = false;
    std::scoped_lock lock(g_notification_mutex);
    entry.id=++g_revision_v12;
    if(auto target=g_notification_target_v12.load()) PostMessageW(target,kNotificationChangedV12,0,0);
    g_notifications.insert(g_notifications.begin(), std::move(entry));
    if (g_notifications.size() > 100) g_notifications.resize(100);
}

std::size_t CloudOSNativeNotificationCenter::UnreadCount()
{
    std::scoped_lock lock(g_notification_mutex);
    return static_cast<std::size_t>(std::count_if(g_notifications.cbegin(), g_notifications.cend(),
        [](const NotificationEntry& entry) { return !entry.read; }));
}

void CloudOSNativeNotificationCenter::MarkAllRead()
{
    std::scoped_lock lock(g_notification_mutex);
    for (auto& entry : g_notifications) entry.read = true;
    ++g_revision_v12;
    if(auto target=g_notification_target_v12.load()) PostMessageW(target,kNotificationChangedV12,0,0);
}

void CloudOSNativeNotificationCenter::Refresh()
{
    if (window_ != nullptr && IsWindowVisible(window_)) RebuildList();
}

void CloudOSNativeNotificationCenter::RebuildList()
{
    if (list_ == nullptr) return;
    std::vector<NotificationEntry> snapshot;
    {
        std::scoped_lock lock(g_notification_mutex);
        if (revision_v12_ == g_revision_v12) return;
        revision_v12_=g_revision_v12;
        snapshot = g_notifications;
    }
    const int selected=ListView_GetNextItem(list_,-1,LVNI_SELECTED);
    const auto selected_id=selected>=0 && selected<static_cast<int>(snapshot_v12_.size()) ? snapshot_v12_[selected].id : 0;
    snapshot_v12_=snapshot;
    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < snapshot.size(); ++index)
    {
        const NotificationEntry& entry = snapshot[index];

        std::wstring text = entry.title;
        if (!entry.message.empty()) { text += L"  ·  "; text += entry.message; }
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = const_cast<LPWSTR>(text.c_str());
        ListView_InsertItem(list_, &item);

    }
    for(std::size_t index=0;index<snapshot.size();++index) if(snapshot[index].id==selected_id) ListView_SetItemState(list_,static_cast<int>(index),LVIS_SELECTED|LVIS_FOCUSED,LVIS_SELECTED|LVIS_FOCUSED);
    std::wstring status = std::to_wstring(snapshot.size());
    status += snapshot.size() == 1 ? L" notificacao" : L" notificacoes";
    SetWindowTextW(status_label_, status.c_str());
    InvalidateRect(list_, nullptr, FALSE);
}

void CloudOSNativeNotificationCenter::Layout()
{
    if (window_ == nullptr) return;
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    if (dpi_v12_ != dpi && list_)
    {
        dpi_v12_=dpi;
        if(font_) DeleteObject(font_);
        if(heading_font_v12_) DeleteObject(heading_font_v12_);
        font_=CreateFontW(-Scale(14,dpi),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI Variable Text");
        heading_font_v12_=CreateFontW(-Scale(22,dpi),0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI Variable Display");
        for(HWND control:{list_,status_label_,clear_button_}) SetFont(control,font_);
        SetFont(heading_v12_,heading_font_v12_);
        ListView_SetImageList(list_,nullptr,LVSIL_SMALL);
        if(row_image_v12_) ImageList_Destroy(row_image_v12_);
        row_image_v12_=ImageList_Create(1,Scale(112,dpi),ILC_COLOR32,1,1);
        ListView_SetImageList(list_,row_image_v12_,LVSIL_SMALL);
    }
    const int margin = Scale(20, dpi);
    const int footer = Scale(48, dpi);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    MoveWindow(heading_v12_,margin,margin,width-margin*2,Scale(32,dpi),TRUE);
    MoveWindow(list_, margin, Scale(68,dpi), std::max(1, width - margin * 2),
        std::max(1, height - Scale(68,dpi) - margin*2 - footer), TRUE);
    ListView_SetColumnWidth(list_,0,std::max(1,width-margin*2-Scale(18,dpi)));
    MoveWindow(status_label_, margin, height - margin - Scale(30, dpi), std::max(1,width-margin*2-Scale(162,dpi)), Scale(30, dpi), TRUE);
    MoveWindow(clear_button_, width - margin - Scale(150, dpi), height - margin - Scale(36, dpi),
        Scale(150, dpi), Scale(36, dpi), TRUE);
}

void CloudOSNativeNotificationCenter::ShowNear(const RECT& anchor)
{
    if (window_ == nullptr) return;
    MarkAllRead();
    RebuildList();
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{}; info.cbSize = sizeof(info); GetMonitorInfoW(monitor, &info);
    const UINT dpi = GetDpiForWindow(window_);
    const RECT fitted=FitFlyout(anchor,info.rcWork,Scale(440,dpi),Scale(580,dpi),Scale(12,dpi));
    SetWindowPos(window_,HWND_TOPMOST,fitted.left,fitted.top,fitted.right-fitted.left,fitted.bottom-fitted.top,SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
    SetFocus(list_);
}

void CloudOSNativeNotificationCenter::ToggleNear(const RECT& anchor)
{
    if (window_ == nullptr) return;
    IsWindowVisible(window_) ? Hide() : ShowNear(anchor);
}

void CloudOSNativeNotificationCenter::Hide()
{
    if (window_ != nullptr) ShowWindow(window_, SW_HIDE);
}

void CloudOSNativeNotificationCenter::OpenSelection()
{
    const int index=ListView_GetNextItem(list_,-1,LVNI_SELECTED);
    if(index>=0 && index<static_cast<int>(snapshot_v12_.size()))
    { const auto entry=snapshot_v12_[index]; MessageBoxW(window_,entry.message.c_str(),entry.title.c_str(),MB_OK); }
}

LRESULT CloudOSNativeNotificationCenter::DrawCard(NMLVCUSTOMDRAW* draw)
{
    if(draw->nmcd.dwDrawStage==CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
    if(draw->nmcd.dwDrawStage!=CDDS_ITEMPREPAINT) return CDRF_DODEFAULT;
    const auto index=static_cast<std::size_t>(draw->nmcd.dwItemSpec);
    if(index>=snapshot_v12_.size()) return CDRF_DODEFAULT;
    PerformanceV12::PaintScope perf(PerformanceV12::NotificationPaint);
    RECT r{}; ListView_GetItemRect(list_,static_cast<int>(index),&r,LVIR_BOUNDS);
    FillRect(draw->nmcd.hdc,&r,WebSkin::SharedSurfaceBrush());
    const UINT dpi=GetDpiForWindow(window_); InflateRect(&r,-Scale(2,dpi),-Scale(4,dpi));
    const auto& entry=snapshot_v12_[index];
    const bool selected=(ListView_GetItemState(list_,static_cast<int>(index),LVIS_SELECTED)&LVIS_SELECTED)!=0;
    { Gdiplus::Graphics g(draw->nmcd.hdc); g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
      WebSkin::DrawRoundedPanel(g,Gdiplus::RectF(static_cast<float>(r.left),static_cast<float>(r.top),static_cast<float>(r.right-r.left),static_cast<float>(r.bottom-r.top)),8,WebSkin::GdiColor(selected?WebSkin::BgActive:WebSkin::BgTertiary),WebSkin::GdiColor(WebSkin::BorderSubtle)); }
    const auto old=SelectObject(draw->nmcd.hdc,font_); SetBkMode(draw->nmcd.hdc,TRANSPARENT);
    r.left+=Scale(12,dpi);r.right-=Scale(12,dpi);r.top+=Scale(10,dpi);
    RECT title=r;title.right-=Scale(50,dpi);title.bottom=title.top+Scale(22,dpi);
    SetTextColor(draw->nmcd.hdc,entry.severity>0?WebSkin::Danger:WebSkin::TextPrimary);
    DrawTextW(draw->nmcd.hdc,entry.title.c_str(),-1,&title,DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX);
    RECT time=r;time.left=time.right-Scale(48,dpi);time.bottom=time.top+Scale(20,dpi);
    SetTextColor(draw->nmcd.hdc,WebSkin::TextTertiary);const auto text=TimeText(entry.time);DrawTextW(draw->nmcd.hdc,text.c_str(),-1,&time,DT_RIGHT|DT_SINGLELINE);
    r.top+=Scale(28,dpi);r.bottom-=Scale(8,dpi);SetTextColor(draw->nmcd.hdc,WebSkin::TextSecondary);
    DrawTextW(draw->nmcd.hdc,entry.message.c_str(),-1,&r,DT_WORDBREAK|DT_END_ELLIPSIS|DT_NOPREFIX);
    SelectObject(draw->nmcd.hdc,old);return CDRF_SKIPDEFAULT;
}

LRESULT CloudOSNativeNotificationCenter::HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case kNotificationChangedV12:
        Refresh();
        EnumThreadWindows(GetCurrentThreadId(),[](HWND target,LPARAM)->BOOL { wchar_t name[128]{}; GetClassNameW(target,name,128); if(wcscmp(name,L"CloudOS.NativeShell.Desktop.v2")==0) PostMessageW(target,CLOUDOS_WM_MODEL_CHANGED_V12,0,0); return TRUE; },0);
        return 0;
    case WM_SIZE: Layout(); return 0;
    case WM_DPICHANGED: { const RECT fitted=FitSuggestedFlyout(*reinterpret_cast<RECT*>(l_param)); SetWindowPos(window_,nullptr,fitted.left,fitted.top,fitted.right-fitted.left,fitted.bottom-fitted.top,SWP_NOZORDER|SWP_NOACTIVATE); Layout(); return 0; }
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE) Hide();
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kClearId)
        {
            { std::scoped_lock lock(g_notification_mutex); g_notifications.clear(); ++g_revision_v12; }
            RebuildList();
            PostMessageW(window_, kNotificationChangedV12, 0, 0);
            return 0;
        }
        break;
    case WM_NOTIFY:
    {
        const auto* header = reinterpret_cast<const NMHDR*>(l_param);
        if (header && header->hwndFrom == list_ && (header->code == NM_DBLCLK || (header->code == LVN_KEYDOWN && reinterpret_cast<NMLVKEYDOWN*>(l_param)->wVKey == VK_RETURN))) { OpenSelection(); return 0; }
        if (header != nullptr && header->hwndFrom == list_ && header->code == NM_CUSTOMDRAW)
            return DrawCard(reinterpret_cast<LPNMLVCUSTOMDRAW>(l_param));
        break;
    }
    case WM_DRAWITEM:
        if (WebSkin::PaintOwnerDrawButton(reinterpret_cast<const DRAWITEMSTRUCT*>(l_param), ButtonTone::Danger)) return TRUE;
        break;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE) { Hide(); return 0; }
        break;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND:
    {
        RECT client{}; GetClientRect(window_, &client);
        WebSkin::PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_DESTROY:
        window_ = nullptr; list_ = nullptr; clear_button_ = nullptr; status_label_ = nullptr;
        return 0;
    default: break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeNotificationCenter::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeNotificationCenter*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeNotificationCenter*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr) self->window_ = window;
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
