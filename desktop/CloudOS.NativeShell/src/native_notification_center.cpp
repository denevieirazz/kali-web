#include "native_notification_center.h"

#include "native_theme.h"

#include <commctrl.h>

#include <algorithm>
#include <mutex>
#include <new>
#include <vector>

namespace CloudOS
{
namespace
{
constexpr wchar_t kNotificationClass[] = L"CloudOS.NativeShell.NotificationCenter.v2";
constexpr int kListId = 8701;
constexpr int kClearId = 8702;

struct NotificationEntry final
{
    SYSTEMTIME time{};
    std::wstring title;
    std::wstring message;
    int severity{};
    bool read{};
};

std::mutex g_notification_mutex;
std::vector<NotificationEntry> g_notifications;

std::wstring TimeText(const SYSTEMTIME& time)
{
    wchar_t buffer[64]{};
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            TIME_NOSECONDS,
            &time,
            nullptr,
            buffer,
            static_cast<int>(std::size(buffer))) == 0)
    {
        return L"--:--";
    }
    return buffer;
}

void SetFont(HWND window, HFONT font)
{
    if (window != nullptr && font != nullptr)
    {
        SendMessageW(window, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
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
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kNotificationClass;
    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
        kNotificationClass,
        L"Notificacoes - CloudOS",
        WS_POPUP | WS_BORDER | WS_CLIPCHILDREN,
        0,
        0,
        460,
        560,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    background_ = CreateSolidBrush(RGB(24, 26, 31));
    font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
        instance_,
        nullptr);
    clear_button_ = CreateWindowW(
        L"BUTTON",
        L"Limpar historico",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kClearId)),
        instance_,
        nullptr);
    status_label_ = CreateWindowW(
        L"STATIC",
        L"",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0,
        window_,
        nullptr,
        instance_,
        nullptr);

    if (list_ == nullptr || clear_button_ == nullptr || status_label_ == nullptr)
    {
        Destroy();
        return false;
    }

    SetFont(list_, font_);
    SetFont(clear_button_, font_);
    SetFont(status_label_, font_);

    ListView_SetExtendedListViewStyle(
        list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    LVCOLUMNW time_column{};
    time_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    time_column.pszText = const_cast<LPWSTR>(L"Hora");
    time_column.cx = 72;
    ListView_InsertColumn(list_, 0, &time_column);

    LVCOLUMNW title_column{};
    title_column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
    title_column.pszText = const_cast<LPWSTR>(L"Notificacao");
    title_column.cx = 340;
    title_column.iSubItem = 1;
    ListView_InsertColumn(list_, 1, &title_column);

    DarkWindow(window_);
    Layout();
    RebuildList();
    return true;
}

void CloudOSNativeNotificationCenter::Destroy()
{
    if (window_ != nullptr && IsWindow(window_))
    {
        DestroyWindow(window_);
    }
    window_ = nullptr;
    list_ = nullptr;
    clear_button_ = nullptr;
    status_label_ = nullptr;

    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (background_ != nullptr)
    {
        DeleteObject(background_);
        background_ = nullptr;
    }
}

void CloudOSNativeNotificationCenter::Post(
    const std::wstring& title,
    const std::wstring& message,
    int severity)
{
    NotificationEntry entry{};
    GetLocalTime(&entry.time);
    entry.title = title.empty() ? L"CloudOS" : title;
    entry.message = message;
    entry.severity = severity;
    entry.read = false;

    std::scoped_lock lock(g_notification_mutex);
    g_notifications.insert(g_notifications.begin(), std::move(entry));
    if (g_notifications.size() > 100)
    {
        g_notifications.resize(100);
    }
}

std::size_t CloudOSNativeNotificationCenter::UnreadCount()
{
    std::scoped_lock lock(g_notification_mutex);
    return static_cast<std::size_t>(std::count_if(
        g_notifications.cbegin(),
        g_notifications.cend(),
        [](const NotificationEntry& entry)
        {
            return !entry.read;
        }));
}

void CloudOSNativeNotificationCenter::MarkAllRead()
{
    std::scoped_lock lock(g_notification_mutex);
    for (auto& entry : g_notifications)
    {
        entry.read = true;
    }
}

void CloudOSNativeNotificationCenter::Refresh()
{
    if (window_ != nullptr)
    {
        RebuildList();
    }
}

void CloudOSNativeNotificationCenter::RebuildList()
{
    if (list_ == nullptr)
    {
        return;
    }

    std::vector<NotificationEntry> snapshot;
    {
        std::scoped_lock lock(g_notification_mutex);
        snapshot = g_notifications;
    }

    ListView_DeleteAllItems(list_);
    for (std::size_t index = 0; index < snapshot.size(); ++index)
    {
        const NotificationEntry& entry = snapshot[index];
        const std::wstring time = TimeText(entry.time);
        std::wstring text = entry.title;
        if (!entry.message.empty())
        {
            text += L" — ";
            text += entry.message;
        }

        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = const_cast<LPWSTR>(time.c_str());
        ListView_InsertItem(list_, &item);
        ListView_SetItemText(
            list_,
            static_cast<int>(index),
            1,
            const_cast<LPWSTR>(text.c_str()));
    }

    std::wstring status = std::to_wstring(snapshot.size());
    status += snapshot.size() == 1 ? L" notificacao" : L" notificacoes";
    SetWindowTextW(status_label_, status.c_str());
}

void CloudOSNativeNotificationCenter::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }

    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(14, dpi);
    const int footer = Scale(44, dpi);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);

    MoveWindow(
        list_,
        margin,
        margin,
        std::max(1, width - margin * 2),
        std::max(1, height - margin * 3 - footer),
        TRUE);
    MoveWindow(
        status_label_,
        margin,
        height - margin - Scale(28, dpi),
        Scale(190, dpi),
        Scale(28, dpi),
        TRUE);
    MoveWindow(
        clear_button_,
        width - margin - Scale(140, dpi),
        height - margin - Scale(32, dpi),
        Scale(140, dpi),
        Scale(32, dpi),
        TRUE);
}

void CloudOSNativeNotificationCenter::ShowNear(const RECT& anchor)
{
    if (window_ == nullptr)
    {
        return;
    }

    MarkAllRead();
    RebuildList();

    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);

    const UINT dpi = GetDpiForWindow(window_);
    const int width = Scale(460, dpi);
    const int height = Scale(560, dpi);
    int x = anchor.right - width;
    int y = anchor.top - height - Scale(8, dpi);
    x = std::clamp<int>(x, static_cast<int>(info.rcWork.left), std::max<int>(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right - width)));
    y = std::clamp<int>(y, static_cast<int>(info.rcWork.top), std::max<int>(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom - height)));

    SetWindowPos(
        window_,
        HWND_TOPMOST,
        x,
        y,
        width,
        height,
        SWP_SHOWWINDOW);
    ShowWindow(window_, SW_SHOWNORMAL);
    SetForegroundWindow(window_);
}

void CloudOSNativeNotificationCenter::ToggleNear(const RECT& anchor)
{
    if (window_ == nullptr)
    {
        return;
    }
    if (IsWindowVisible(window_))
    {
        Hide();
    }
    else
    {
        ShowNear(anchor);
    }
}

void CloudOSNativeNotificationCenter::Hide()
{
    if (window_ != nullptr)
    {
        ShowWindow(window_, SW_HIDE);
    }
}

LRESULT CloudOSNativeNotificationCenter::HandleMessage(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;
    case WM_ACTIVATE:
        if (LOWORD(w_param) == WA_INACTIVE)
        {
            Hide();
        }
        return 0;
    case WM_COMMAND:
        if (LOWORD(w_param) == kClearId)
        {
            {
                std::scoped_lock lock(g_notification_mutex);
                g_notifications.clear();
            }
            RebuildList();
            return 0;
        }
        break;
    case WM_KEYDOWN:
        if (w_param == VK_ESCAPE)
        {
            Hide();
            return 0;
        }
        break;
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, RGB(235, 238, 244));
        SetBkColor(dc, RGB(24, 26, 31));
        return reinterpret_cast<LRESULT>(background_);
    }
    case WM_ERASEBKGND:
    {
        RECT client{};
        GetClientRect(window_, &client);
        FillRect(reinterpret_cast<HDC>(w_param), &client, background_);
        return 1;
    }
    case WM_DESTROY:
        window_ = nullptr;
        list_ = nullptr;
        clear_button_ = nullptr;
        status_label_ = nullptr;
        return 0;
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeNotificationCenter::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    auto* self = reinterpret_cast<CloudOSNativeNotificationCenter*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeNotificationCenter*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self != nullptr)
        {
            self->window_ = window;
        }
    }
    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
