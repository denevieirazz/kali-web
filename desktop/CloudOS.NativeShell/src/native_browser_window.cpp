#include "native_browser_window.h"

#include "native_theme.h"

#include <ShlObj.h>

#include <algorithm>
#include <array>
#include <filesystem>
#include <new>
#include <system_error>
#include <utility>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kBrowserClass[] = L"CloudOS.NativeShell.Browser.v1";
constexpr int kBackId = 7101;
constexpr int kForwardId = 7102;
constexpr int kReloadId = 7103;
constexpr int kHomeId = 7104;
constexpr int kAddressId = 7105;
constexpr int kGoId = 7106;
constexpr int kToolbarHeight = 52;
constexpr wchar_t kHomeUrl[] = L"https://www.google.com/";

bool IsHttpUrl(const std::wstring& value)
{
    return _wcsnicmp(value.c_str(), L"https://", 8) == 0 ||
        _wcsnicmp(value.c_str(), L"http://", 7) == 0;
}

std::wstring Trim(std::wstring value)
{
    const auto is_space = [](wchar_t ch)
    {
        return ch == L' ' || ch == L'\t' || ch == L'\r' || ch == L'\n';
    };
    while (!value.empty() && is_space(value.front())) value.erase(value.begin());
    while (!value.empty() && is_space(value.back())) value.pop_back();
    return value;
}
}

CloudOSNativeBrowserWindow::CloudOSNativeBrowserWindow(
    HINSTANCE instance,
    std::wstring initial_url)
    : instance_(instance),
      initial_url_(NormalizeUrl(std::move(initial_url)))
{
}

CloudOSNativeBrowserWindow::~CloudOSNativeBrowserWindow()
{
    if (alive_)
    {
        alive_->store(false);
    }

    if (webview_ != nullptr)
    {
        if (navigation_completed_registered_)
        {
            (void)webview_->remove_NavigationCompleted(navigation_completed_token_);
        }
        if (history_changed_registered_)
        {
            (void)webview_->remove_HistoryChanged(history_changed_token_);
        }
    }

    if (controller_ != nullptr)
    {
        (void)controller_->Close();
    }
    webview_.Reset();
    controller_.Reset();
    environment_.Reset();

    if (ui_font_ != nullptr)
    {
        DeleteObject(ui_font_);
        ui_font_ = nullptr;
    }
    if (toolbar_brush_ != nullptr)
    {
        DeleteObject(toolbar_brush_);
        toolbar_brush_ = nullptr;
    }
}

void CloudOSNativeBrowserWindow::Open(
    HINSTANCE instance,
    const std::wstring& initial_url)
{
    auto* browser = new (std::nothrow) CloudOSNativeBrowserWindow(instance, initial_url);
    if (browser == nullptr || !browser->Create())
    {
        delete browser;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir o Navegador do CloudOS.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeBrowserWindow::Create()
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeBrowserWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kBrowserClass;

    if (RegisterClassExW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kBrowserClass,
        L"Navegador - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1180,
        760,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    toolbar_brush_ = CreateSolidBrush(RGB(28, 32, 40));
    ui_font_ = CreateFontW(
        -15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

    back_button_ = CreateWindowW(L"BUTTON", L"<", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kBackId), instance_, nullptr);
    forward_button_ = CreateWindowW(L"BUTTON", L">", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kForwardId), instance_, nullptr);
    reload_button_ = CreateWindowW(L"BUTTON", L"Recarregar", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kReloadId), instance_, nullptr);
    home_button_ = CreateWindowW(L"BUTTON", L"Inicio", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kHomeId), instance_, nullptr);
    address_edit_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", initial_url_.c_str(),
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kAddressId), instance_, nullptr);
    go_button_ = CreateWindowW(L"BUTTON", L"Ir", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kGoId), instance_, nullptr);
    status_label_ = CreateWindowW(L"STATIC", L"Inicializando WebView2...",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0, window_, nullptr, instance_, nullptr);

    if (back_button_ == nullptr || forward_button_ == nullptr || reload_button_ == nullptr ||
        home_button_ == nullptr || address_edit_ == nullptr || go_button_ == nullptr ||
        status_label_ == nullptr)
    {
        DestroyWindow(window_);
        window_ = nullptr;
        return false;
    }

    if (ui_font_ != nullptr)
    {
        for (HWND child : {back_button_, forward_button_, reload_button_, home_button_, address_edit_, go_button_, status_label_})
        {
            SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(ui_font_), TRUE);
        }
    }

    DarkWindow(window_);
    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    InitializeWebView();
    return true;
}

void CloudOSNativeBrowserWindow::InitializeWebView()
{
    const std::wstring user_data = UserDataDirectory();
    if (user_data.empty())
    {
        ShowWebViewFailure(L"Nao foi possivel preparar o perfil do navegador.");
        return;
    }

    LPWSTR version = nullptr;
    const HRESULT version_result = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (FAILED(version_result) || version == nullptr)
    {
        if (version != nullptr) CoTaskMemFree(version);
        ShowWebViewFailure(L"WebView2 Runtime nao esta instalado ou nao foi encontrado.");
        return;
    }
    CoTaskMemFree(version);

    const auto lifetime = alive_;
    const HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
        nullptr,
        user_data.c_str(),
        nullptr,
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [this, lifetime](HRESULT hr, ICoreWebView2Environment* environment) -> HRESULT
            {
                if (!lifetime->load()) return S_OK;
                if (FAILED(hr) || environment == nullptr)
                {
                    ShowWebViewFailure(L"Falha ao criar o ambiente WebView2.");
                    return S_OK;
                }

                environment_ = environment;
                const HRESULT controller_hr = environment->CreateCoreWebView2Controller(
                    window_,
                    Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [this, lifetime](HRESULT create_hr, ICoreWebView2Controller* controller) -> HRESULT
                        {
                            if (!lifetime->load()) return S_OK;
                            if (FAILED(create_hr) || controller == nullptr)
                            {
                                ShowWebViewFailure(L"Falha ao criar a superficie WebView2.");
                                return S_OK;
                            }
                            ConfigureController(controller);
                            return S_OK;
                        }).Get());
                if (FAILED(controller_hr))
                {
                    ShowWebViewFailure(L"WebView2 recusou a criacao do controlador.");
                }
                return S_OK;
            }).Get());

    if (FAILED(result))
    {
        ShowWebViewFailure(L"Nao foi possivel inicializar o WebView2.");
    }
}

void CloudOSNativeBrowserWindow::ConfigureController(ICoreWebView2Controller* controller)
{
    controller_ = controller;
    if (FAILED(controller_->get_CoreWebView2(&webview_)) || webview_ == nullptr)
    {
        ShowWebViewFailure(L"WebView2 nao retornou o motor de navegacao.");
        return;
    }

    Microsoft::WRL::ComPtr<ICoreWebView2Settings> settings;
    if (SUCCEEDED(webview_->get_Settings(&settings)) && settings != nullptr)
    {
        (void)settings->put_IsScriptEnabled(TRUE);
        (void)settings->put_AreDefaultScriptDialogsEnabled(TRUE);
        (void)settings->put_AreDefaultContextMenusEnabled(TRUE);
        (void)settings->put_AreDevToolsEnabled(TRUE);
        (void)settings->put_IsStatusBarEnabled(FALSE);
        (void)settings->put_IsZoomControlEnabled(TRUE);
    }

    const auto lifetime = alive_;
    if (SUCCEEDED(webview_->add_NavigationCompleted(
            Microsoft::WRL::Callback<ICoreWebView2NavigationCompletedEventHandler>(
                [this, lifetime](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT
                {
                    if (!lifetime->load()) return S_OK;
                    BOOL success = FALSE;
                    if (args != nullptr) (void)args->get_IsSuccess(&success);
                    SetWindowTextW(status_label_, success ? L"Pronto" : L"Falha ao carregar a pagina");
                    UpdateNavigationState();
                    return S_OK;
                }).Get(),
            &navigation_completed_token_)))
    {
        navigation_completed_registered_ = true;
    }

    if (SUCCEEDED(webview_->add_HistoryChanged(
            Microsoft::WRL::Callback<ICoreWebView2HistoryChangedEventHandler>(
                [this, lifetime](ICoreWebView2*, IUnknown*) -> HRESULT
                {
                    if (!lifetime->load()) return S_OK;
                    UpdateNavigationState();
                    return S_OK;
                }).Get(),
            &history_changed_token_)))
    {
        history_changed_registered_ = true;
    }

    Layout();
    (void)controller_->put_IsVisible(TRUE);
    Navigate(initial_url_);
}

void CloudOSNativeBrowserWindow::Layout()
{
    if (window_ == nullptr) return;

    RECT client{};
    GetClientRect(window_, &client);
    const int width = std::max(1L, client.right - client.left);
    const int height = std::max(1L, client.bottom - client.top);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(8, dpi);
    const int row = Scale(kToolbarHeight, dpi);
    const int button_h = Scale(32, dpi);
    const int small_w = Scale(42, dpi);
    const int medium_w = Scale(88, dpi);
    const int go_w = Scale(48, dpi);
    const int gap = Scale(6, dpi);
    int x = margin;
    const int y = margin;

    MoveWindow(back_button_, x, y, small_w, button_h, TRUE); x += small_w + gap;
    MoveWindow(forward_button_, x, y, small_w, button_h, TRUE); x += small_w + gap;
    MoveWindow(reload_button_, x, y, medium_w, button_h, TRUE); x += medium_w + gap;
    MoveWindow(home_button_, x, y, Scale(64, dpi), button_h, TRUE); x += Scale(64, dpi) + gap;

    const int address_w = std::max(120, width - x - go_w - margin - gap);
    MoveWindow(address_edit_, x, y, address_w, button_h, TRUE);
    x += address_w + gap;
    MoveWindow(go_button_, x, y, go_w, button_h, TRUE);

    MoveWindow(status_label_, margin, Scale(42, dpi), width - margin * 2, Scale(18, dpi), TRUE);

    if (controller_ != nullptr)
    {
        RECT bounds{};
        bounds.left = 0;
        bounds.top = row + Scale(12, dpi);
        bounds.right = width;
        bounds.bottom = height;
        (void)controller_->put_Bounds(bounds);
    }
}

void CloudOSNativeBrowserWindow::NavigateFromAddress()
{
    const int length = GetWindowTextLengthW(address_edit_);
    if (length <= 0) return;
    std::wstring value(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(address_edit_, value.data(), length + 1);
    value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    Navigate(value);
}

void CloudOSNativeBrowserWindow::Navigate(const std::wstring& raw_url)
{
    if (webview_ == nullptr)
    {
        SetWindowTextW(status_label_, L"Motor de navegacao ainda nao esta pronto");
        return;
    }

    const std::wstring url = NormalizeUrl(raw_url);
    SetWindowTextW(address_edit_, url.c_str());
    SetWindowTextW(status_label_, L"Carregando...");
    const HRESULT result = webview_->Navigate(url.c_str());
    if (FAILED(result))
    {
        SetWindowTextW(status_label_, L"Endereco invalido ou navegacao recusada");
    }
}

void CloudOSNativeBrowserWindow::UpdateNavigationState()
{
    if (webview_ == nullptr) return;

    BOOL can_back = FALSE;
    BOOL can_forward = FALSE;
    (void)webview_->get_CanGoBack(&can_back);
    (void)webview_->get_CanGoForward(&can_forward);
    EnableWindow(back_button_, can_back);
    EnableWindow(forward_button_, can_forward);

    LPWSTR source = nullptr;
    if (SUCCEEDED(webview_->get_Source(&source)) && source != nullptr)
    {
        SetWindowTextW(address_edit_, source);
        CoTaskMemFree(source);
    }

    LPWSTR title = nullptr;
    if (SUCCEEDED(webview_->get_DocumentTitle(&title)) && title != nullptr)
    {
        std::wstring caption = title[0] != L'\0' ? title : L"Navegador";
        caption += L" - CloudOS";
        SetWindowTextW(window_, caption.c_str());
        CoTaskMemFree(title);
    }
}

void CloudOSNativeBrowserWindow::ShowWebViewFailure(const std::wstring& detail)
{
    SetWindowTextW(status_label_, detail.c_str());
    MessageBoxW(window_, detail.c_str(), L"Navegador - CloudOS", MB_OK | MB_ICONERROR);
}

std::wstring CloudOSNativeBrowserWindow::NormalizeUrl(std::wstring value)
{
    value = Trim(std::move(value));
    if (value.empty()) return kHomeUrl;
    if (IsHttpUrl(value)) return value;

    if (value.find(L' ') == std::wstring::npos && value.find(L'.') != std::wstring::npos)
    {
        return L"https://" + value;
    }

    std::wstring encoded;
    encoded.reserve(value.size() + 32u);
    for (const wchar_t ch : value)
    {
        encoded += ch == L' ' ? L'+' : ch;
    }
    return L"https://www.google.com/search?q=" + encoded;
}

std::wstring CloudOSNativeBrowserWindow::UserDataDirectory()
{
    PWSTR local_app_data = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &local_app_data)) ||
        local_app_data == nullptr)
    {
        return {};
    }

    const std::filesystem::path path =
        std::filesystem::path(local_app_data) / L"CloudOS" / L"BrowserProfile";
    CoTaskMemFree(local_app_data);

    std::error_code error;
    std::filesystem::create_directories(path, error);
    return error ? std::wstring{} : path.wstring();
}

LRESULT CloudOSNativeBrowserWindow::HandleMessage(
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    switch (message)
    {
    case WM_SIZE:
        Layout();
        return 0;

    case WM_COMMAND:
        if (HIWORD(w_param) == BN_CLICKED)
        {
            switch (LOWORD(w_param))
            {
            case kBackId:
                if (webview_ != nullptr) (void)webview_->GoBack();
                return 0;
            case kForwardId:
                if (webview_ != nullptr) (void)webview_->GoForward();
                return 0;
            case kReloadId:
                if (webview_ != nullptr) (void)webview_->Reload();
                return 0;
            case kHomeId:
                Navigate(kHomeUrl);
                return 0;
            case kGoId:
                NavigateFromAddress();
                return 0;
            default:
                break;
            }
        }
        if (LOWORD(w_param) == kAddressId && HIWORD(w_param) == EN_MAXTEXT)
        {
            return 0;
        }
        break;

    case WM_KEYDOWN:
        if (w_param == VK_RETURN && GetFocus() == address_edit_)
        {
            NavigateFromAddress();
            return 0;
        }
        break;

    case WM_CTLCOLORSTATIC:
        if (toolbar_brush_ != nullptr)
        {
            HDC dc = reinterpret_cast<HDC>(w_param);
            SetBkColor(dc, RGB(28, 32, 40));
            SetTextColor(dc, RGB(220, 224, 232));
            return reinterpret_cast<LRESULT>(toolbar_brush_);
        }
        break;

    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;

    case WM_NCDESTROY:
        window_ = nullptr;
        delete this;
        return 0;

    default:
        break;
    }

    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeBrowserWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeBrowserWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeBrowserWindow*>(create->lpCreateParams);
        if (self == nullptr) return FALSE;
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeBrowserWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
