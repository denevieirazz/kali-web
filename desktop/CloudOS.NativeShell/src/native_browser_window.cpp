#include "native_browser_window.h"

#include "native_folder_picker_v16.h"
#include "native_integration_v16.h"
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
constexpr UINT kWebViewRecoverMessage = WM_APP + 0x713;
constexpr ULONGLONG kRecoveryWindowMs = 30000ull;
constexpr unsigned kMaximumRecoveryAttempts = 3u;

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

std::wstring UniqueDownloadPath(const std::wstring& directory, const std::wstring& requested_name)
{
    if (directory.empty()) return {};
    std::filesystem::path file_name(requested_name);
    std::wstring leaf = file_name.filename().wstring();
    if (leaf.empty()) leaf = L"download.bin";

    std::filesystem::path candidate = std::filesystem::path(directory) / leaf;
    if (GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES) return candidate.wstring();

    const std::filesystem::path stem = candidate.stem();
    const std::filesystem::path extension = candidate.extension();
    for (unsigned int index = 1; index <= 9999u; ++index)
    {
        const std::wstring numbered = stem.wstring() + L" (" + std::to_wstring(index) + L")" + extension.wstring();
        candidate = std::filesystem::path(directory) / numbered;
        if (GetFileAttributesW(candidate.c_str()) == INVALID_FILE_ATTRIBUTES) return candidate.wstring();
    }
    return {};
}
} // namespace

CloudOSNativeBrowserWindow::CloudOSNativeBrowserWindow(
    HINSTANCE instance,
    std::wstring initial_url)
    : instance_(instance),
      initial_url_(NormalizeUrl(std::move(initial_url)))
{
}

CloudOSNativeBrowserWindow::~CloudOSNativeBrowserWindow()
{
    if (alive_) alive_->store(false);
    ResetWebView();

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
    window_class.hbrBackground = WebSkin::SharedBackgroundBrush();
    window_class.lpszClassName = kBrowserClass;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return false;

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
    if (window_ == nullptr) return false;

    toolbar_brush_ = CreateSolidBrush(WebSkin::BgPrimary);

    back_button_ = CreateWindowW(
        L"BUTTON", L"<", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kBackId), instance_, nullptr);
    forward_button_ = CreateWindowW(
        L"BUTTON", L">", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kForwardId), instance_, nullptr);
    reload_button_ = CreateWindowW(
        L"BUTTON", L"Recarregar", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kReloadId), instance_, nullptr);
    home_button_ = CreateWindowW(
        L"BUTTON", L"Inicio", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kHomeId), instance_, nullptr);
    address_edit_ = CreateWindowExW(
        0, L"EDIT", initial_url_.c_str(),
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kAddressId), instance_, nullptr);
    go_button_ = CreateWindowW(
        L"BUTTON", L"Ir", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(kGoId), instance_, nullptr);
    status_label_ = CreateWindowW(
        L"STATIC", L"Inicializando WebView2...",
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

    RefreshDpiResources();
    ApplyWebWindowMaterial(window_);
    WebSkin::PrepareEdit(address_edit_);
    for (HWND button : {back_button_, forward_button_, reload_button_, home_button_, go_button_})
        WebSkin::PrepareButton(button);

    Layout();
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    InitializeWebView();
    return true;
}

void CloudOSNativeBrowserWindow::InitializeWebView()
{
    if (webview_initializing_ || webview_ != nullptr || window_ == nullptr || !IsWindow(window_))
        return;

    webview_initializing_ = true;
    const std::wstring user_data = UserDataDirectory();
    if (user_data.empty())
    {
        webview_initializing_ = false;
        ShowWebViewFailure(L"Nao foi possivel preparar o perfil do navegador.");
        return;
    }

    LPWSTR version = nullptr;
    const HRESULT version_result = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (FAILED(version_result) || version == nullptr)
    {
        if (version != nullptr) CoTaskMemFree(version);
        webview_initializing_ = false;
        ShowWebViewFailure(L"WebView2 Runtime nao esta instalado ou nao foi encontrado.");
        return;
    }
    CoTaskMemFree(version);

    SetWindowTextW(status_label_, L"Inicializando WebView2...");
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
                    webview_initializing_ = false;
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
                            webview_initializing_ = false;
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
                    webview_initializing_ = false;
                    ShowWebViewFailure(L"WebView2 recusou a criacao do controlador.");
                }
                return S_OK;
            }).Get());

    if (FAILED(result))
    {
        webview_initializing_ = false;
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

    (void)webview_.As(&webview_v4_);

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
        navigation_completed_registered_ = true;

    if (SUCCEEDED(webview_->add_HistoryChanged(
            Microsoft::WRL::Callback<ICoreWebView2HistoryChangedEventHandler>(
                [this, lifetime](ICoreWebView2*, IUnknown*) -> HRESULT
                {
                    if (!lifetime->load()) return S_OK;
                    UpdateNavigationState();
                    return S_OK;
                }).Get(),
            &history_changed_token_)))
        history_changed_registered_ = true;

    if (SUCCEEDED(webview_->add_ProcessFailed(
            Microsoft::WRL::Callback<ICoreWebView2ProcessFailedEventHandler>(
                [this, lifetime](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT
                {
                    return lifetime->load() ? HandleProcessFailed(args) : S_OK;
                }).Get(),
            &process_failed_token_)))
        process_failed_registered_ = true;

    if (SUCCEEDED(webview_->add_PermissionRequested(
            Microsoft::WRL::Callback<ICoreWebView2PermissionRequestedEventHandler>(
                [this, lifetime](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT
                {
                    return lifetime->load() ? HandlePermissionRequested(args) : S_OK;
                }).Get(),
            &permission_requested_token_)))
        permission_requested_registered_ = true;

    if (SUCCEEDED(webview_->add_NewWindowRequested(
            Microsoft::WRL::Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                [this, lifetime](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT
                {
                    return lifetime->load() ? HandleNewWindowRequested(args) : S_OK;
                }).Get(),
            &new_window_requested_token_)))
        new_window_requested_registered_ = true;

    if (webview_v4_ != nullptr && SUCCEEDED(webview_v4_->add_DownloadStarting(
            Microsoft::WRL::Callback<ICoreWebView2DownloadStartingEventHandler>(
                [this, lifetime](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) -> HRESULT
                {
                    if (!lifetime->load() || args == nullptr) return S_OK;

                    LPWSTR default_path_raw = nullptr;
                    std::wstring default_path;
                    if (SUCCEEDED(args->get_ResultFilePath(&default_path_raw)) && default_path_raw != nullptr)
                    {
                        default_path = default_path_raw;
                        CoTaskMemFree(default_path_raw);
                    }

                    const std::filesystem::path suggested(default_path);
                    std::wstring initial_directory = suggested.parent_path().wstring();
                    if (initial_directory.empty()) initial_directory = NativeIntegrationV16::DownloadsFolder();
                    std::wstring file_name = suggested.filename().wstring();
                    if (file_name.empty()) file_name = L"download.bin";

                    std::wstring selected_directory;
                    if (!CloudOSNativeFolderPickerV16::Pick(window_, initial_directory, &selected_directory))
                    {
                        (void)args->put_Cancel(TRUE);
                        (void)args->put_Handled(TRUE);
                        SetWindowTextW(status_label_, L"Download cancelado");
                        return S_OK;
                    }

                    const std::wstring result_path = UniqueDownloadPath(selected_directory, file_name);
                    if (result_path.empty())
                    {
                        (void)args->put_Cancel(TRUE);
                        (void)args->put_Handled(TRUE);
                        SetWindowTextW(status_label_, L"Nao foi possivel preparar o destino do download");
                        return S_OK;
                    }

                    if (FAILED(args->put_ResultFilePath(result_path.c_str())))
                    {
                        (void)args->put_Cancel(TRUE);
                        (void)args->put_Handled(TRUE);
                        SetWindowTextW(status_label_, L"WebView2 recusou o destino do download");
                        return S_OK;
                    }
                    (void)args->put_Handled(TRUE);
                    std::wstring status = L"Baixando para CloudOS Files: ";
                    status += result_path;
                    SetWindowTextW(status_label_, status.c_str());
                    return S_OK;
                }).Get(),
            &download_starting_token_)))
        download_starting_registered_ = true;

    recovery_pending_ = false;
    Layout();
    (void)controller_->put_IsVisible(TRUE);
    Navigate(initial_url_);
}

void CloudOSNativeBrowserWindow::ResetWebView() noexcept
{
    if (webview_ != nullptr)
    {
        if (navigation_completed_registered_)
            (void)webview_->remove_NavigationCompleted(navigation_completed_token_);
        if (history_changed_registered_)
            (void)webview_->remove_HistoryChanged(history_changed_token_);
        if (process_failed_registered_)
            (void)webview_->remove_ProcessFailed(process_failed_token_);
        if (permission_requested_registered_)
            (void)webview_->remove_PermissionRequested(permission_requested_token_);
        if (new_window_requested_registered_)
            (void)webview_->remove_NewWindowRequested(new_window_requested_token_);
    }
    if (webview_v4_ != nullptr && download_starting_registered_)
        (void)webview_v4_->remove_DownloadStarting(download_starting_token_);

    navigation_completed_registered_ = false;
    history_changed_registered_ = false;
    process_failed_registered_ = false;
    permission_requested_registered_ = false;
    new_window_requested_registered_ = false;
    download_starting_registered_ = false;

    if (controller_ != nullptr) (void)controller_->Close();
    webview_v4_.Reset();
    webview_.Reset();
    controller_.Reset();
    environment_.Reset();
    webview_initializing_ = false;
}

void CloudOSNativeBrowserWindow::ScheduleWebViewRecovery(COREWEBVIEW2_PROCESS_FAILED_KIND kind)
{
    if (window_ == nullptr || !IsWindow(window_) || recovery_pending_) return;

    const ULONGLONG now = GetTickCount64();
    if (recovery_window_start_ == 0 || now - recovery_window_start_ > kRecoveryWindowMs)
    {
        recovery_window_start_ = now;
        recovery_attempts_ = 0;
    }
    ++recovery_attempts_;
    if (recovery_attempts_ > kMaximumRecoveryAttempts)
    {
        SetWindowTextW(status_label_, L"WebView2 entrou em falha repetida; recuperacao automatica pausada");
        return;
    }

    recovery_pending_ = true;
    (void)PostMessageW(
        window_,
        kWebViewRecoverMessage,
        static_cast<WPARAM>(kind),
        0);
}

void CloudOSNativeBrowserWindow::RecoverWebView()
{
    recovery_pending_ = false;
    if (window_ == nullptr || !IsWindow(window_)) return;

    const std::wstring source = CurrentUrl();
    if (!source.empty()) initial_url_ = source;
    SetWindowTextW(status_label_, L"Recuperando mecanismo WebView2...");
    ResetWebView();
    InitializeWebView();
}

HRESULT CloudOSNativeBrowserWindow::HandleProcessFailed(ICoreWebView2ProcessFailedEventArgs* args)
{
    if (args == nullptr) return S_OK;

    COREWEBVIEW2_PROCESS_FAILED_KIND kind = COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED;
    if (FAILED(args->get_ProcessFailedKind(&kind))) return S_OK;

    switch (kind)
    {
    case COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED:
        SetWindowTextW(status_label_, L"Processo principal WebView2 encerrou; recuperando...");
        ScheduleWebViewRecovery(kind);
        break;
    case COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE:
        SetWindowTextW(status_label_, L"Renderizador WebView2 nao respondeu; recriando superficie...");
        ScheduleWebViewRecovery(kind);
        break;
    case COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED:
    case COREWEBVIEW2_PROCESS_FAILED_KIND_FRAME_RENDER_PROCESS_EXITED:
        SetWindowTextW(status_label_, L"Renderizador WebView2 reiniciou; recarregando pagina...");
        if (webview_ != nullptr) (void)webview_->Reload();
        break;
    default:
        SetWindowTextW(status_label_, L"Um processo auxiliar WebView2 falhou; o navegador continua monitorado");
        break;
    }
    return S_OK;
}

const wchar_t* CloudOSNativeBrowserWindow::PermissionKindLabel(
    COREWEBVIEW2_PERMISSION_KIND kind) noexcept
{
    switch (kind)
    {
    case COREWEBVIEW2_PERMISSION_KIND_MICROPHONE: return L"microfone";
    case COREWEBVIEW2_PERMISSION_KIND_CAMERA: return L"camera";
    case COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION: return L"localizacao";
    case COREWEBVIEW2_PERMISSION_KIND_NOTIFICATIONS: return L"notificacoes";
    case COREWEBVIEW2_PERMISSION_KIND_OTHER_SENSORS: return L"sensores";
    case COREWEBVIEW2_PERMISSION_KIND_CLIPBOARD_READ: return L"leitura da area de transferencia";
    default: return L"recurso protegido";
    }
}

HRESULT CloudOSNativeBrowserWindow::HandlePermissionRequested(
    ICoreWebView2PermissionRequestedEventArgs* args)
{
    if (args == nullptr) return S_OK;

    COREWEBVIEW2_PERMISSION_KIND kind = COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION;
    BOOL user_initiated = FALSE;
    (void)args->get_PermissionKind(&kind);
    (void)args->get_IsUserInitiated(&user_initiated);

    // Background requests never receive sensitive capability access. A user
    // gesture is required before CloudOS even presents an allow/deny decision.
    if (!user_initiated || kind == COREWEBVIEW2_PERMISSION_KIND_UNKNOWN_PERMISSION)
    {
        (void)args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
        SetWindowTextW(status_label_, L"Permissao web bloqueada por politica do CloudOS");
        return S_OK;
    }

    LPWSTR uri_raw = nullptr;
    std::wstring uri;
    if (SUCCEEDED(args->get_Uri(&uri_raw)) && uri_raw != nullptr)
    {
        uri = uri_raw;
        CoTaskMemFree(uri_raw);
    }

    std::wstring prompt = L"O site solicita acesso a ";
    prompt += PermissionKindLabel(kind);
    prompt += L".\n\n";
    if (!uri.empty())
    {
        prompt += uri;
        prompt += L"\n\n";
    }
    prompt += L"Permitir somente para esta solicitacao?";

    const int decision = MessageBoxW(
        window_,
        prompt.c_str(),
        L"Permissao do Navegador - CloudOS",
        MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2);
    (void)args->put_State(
        decision == IDYES
            ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
            : COREWEBVIEW2_PERMISSION_STATE_DENY);
    SetWindowTextW(
        status_label_,
        decision == IDYES ? L"Permissao concedida para esta solicitacao" : L"Permissao negada");
    return S_OK;
}

HRESULT CloudOSNativeBrowserWindow::HandleNewWindowRequested(
    ICoreWebView2NewWindowRequestedEventArgs* args)
{
    if (args == nullptr) return S_OK;

    LPWSTR uri_raw = nullptr;
    std::wstring uri;
    if (SUCCEEDED(args->get_Uri(&uri_raw)) && uri_raw != nullptr)
    {
        uri = uri_raw;
        CoTaskMemFree(uri_raw);
    }

    // Keep ordinary web popups inside the CloudOS browser authority. Non-web
    // schemes are not forwarded blindly to the Windows shell.
    if (IsHttpUrl(uri))
    {
        (void)args->put_Handled(TRUE);
        CloudOSNativeBrowserWindow::Open(instance_, uri);
        SetWindowTextW(status_label_, L"Nova pagina aberta em uma janela CloudOS");
    }
    else
    {
        (void)args->put_Handled(TRUE);
        SetWindowTextW(status_label_, L"Popup com protocolo externo bloqueado");
    }
    return S_OK;
}

void CloudOSNativeBrowserWindow::RefreshDpiResources()
{
    if (ui_font_ != nullptr)
    {
        DeleteObject(ui_font_);
        ui_font_ = nullptr;
    }

    const UINT dpi = window_ != nullptr ? GetDpiForWindow(window_) : 96u;
    ui_font_ = CreateFontW(
        -MulDiv(15, static_cast<int>(dpi), 96),
        0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI Variable Text");
    if (ui_font_ == nullptr) return;

    for (HWND child : {back_button_, forward_button_, reload_button_, home_button_,
             address_edit_, go_button_, status_label_})
    {
        if (child != nullptr) SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(ui_font_), TRUE);
    }
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
    MoveWindow(address_edit_, x, y, address_w, button_h, TRUE); x += address_w + gap;
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
    initial_url_ = url;
    SetWindowTextW(address_edit_, url.c_str());
    SetWindowTextW(status_label_, L"Carregando...");
    if (FAILED(webview_->Navigate(url.c_str())))
        SetWindowTextW(status_label_, L"Endereco invalido ou navegacao recusada");
}

std::wstring CloudOSNativeBrowserWindow::CurrentUrl() const
{
    if (webview_ == nullptr) return initial_url_;
    LPWSTR source = nullptr;
    if (FAILED(webview_->get_Source(&source)) || source == nullptr) return initial_url_;
    std::wstring result(source);
    CoTaskMemFree(source);
    return result;
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
        initial_url_ = source;
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
    if (status_label_ != nullptr) SetWindowTextW(status_label_, detail.c_str());
    if (window_ != nullptr && IsWindow(window_))
    {
        MessageBoxW(window_, detail.c_str(), L"Navegador - CloudOS", MB_OK | MB_ICONERROR);
    }
}

std::wstring CloudOSNativeBrowserWindow::NormalizeUrl(std::wstring value)
{
    value = Trim(std::move(value));
    if (value.empty()) return kHomeUrl;
    if (IsHttpUrl(value)) return value;
    if (value.find(L' ') == std::wstring::npos && value.find(L'.') != std::wstring::npos)
        return L"https://" + value;

    std::wstring encoded;
    encoded.reserve(value.size() + 32u);
    for (const wchar_t ch : value) encoded += ch == L' ' ? L'+' : ch;
    return L"https://www.google.com/search?q=" + encoded;
}

std::wstring CloudOSNativeBrowserWindow::UserDataDirectory()
{
    PWSTR local_app_data = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_CREATE,
            nullptr,
            &local_app_data)) ||
        local_app_data == nullptr)
        return {};

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
        if (controller_ != nullptr)
            (void)controller_->put_IsVisible(w_param == SIZE_MINIMIZED ? FALSE : TRUE);
        Layout();
        return 0;
    case WM_DPICHANGED:
    {
        const auto* suggested = reinterpret_cast<const RECT*>(l_param);
        if (suggested != nullptr)
        {
            (void)SetWindowPos(
                window_, nullptr,
                suggested->left, suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOZORDER | SWP_NOACTIVATE);
        }
        RefreshDpiResources();
        Layout();
        return 0;
    }
    case WM_SETFOCUS:
        if (controller_ != nullptr)
            (void)controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
        break;
    case kWebViewRecoverMessage:
        RecoverWebView();
        return 0;
    case WM_COMMAND:
        if (HIWORD(w_param) == BN_CLICKED)
        {
            switch (LOWORD(w_param))
            {
            case kBackId: if (webview_ != nullptr) (void)webview_->GoBack(); return 0;
            case kForwardId: if (webview_ != nullptr) (void)webview_->GoForward(); return 0;
            case kReloadId:
                if (webview_ != nullptr) (void)webview_->Reload();
                else InitializeWebView();
                return 0;
            case kHomeId: Navigate(kHomeUrl); return 0;
            case kGoId: NavigateFromAddress(); return 0;
            default: break;
            }
        }
        break;
    case WM_KEYDOWN:
        if (w_param == VK_RETURN && GetFocus() == address_edit_)
        {
            NavigateFromAddress();
            return 0;
        }
        break;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr && draw->CtlType == ODT_BUTTON &&
            WebSkin::PaintOwnerDrawButton(draw, ButtonTone::Neutral)) return TRUE;
        break;
    }
    case WM_CTLCOLORSTATIC:
        if (toolbar_brush_ != nullptr)
        {
            HDC dc = reinterpret_cast<HDC>(w_param);
            SetBkColor(dc, WebSkin::BgPrimary);
            SetTextColor(dc, WebSkin::TextSecondary);
            return reinterpret_cast<LRESULT>(toolbar_brush_);
        }
        break;
    case WM_CLOSE:
        DestroyWindow(window_);
        return 0;
    case WM_NCDESTROY:
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
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
        self = reinterpret_cast<CloudOSNativeBrowserWindow*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
    }
    return self != nullptr
        ? self->HandleMessage(message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
