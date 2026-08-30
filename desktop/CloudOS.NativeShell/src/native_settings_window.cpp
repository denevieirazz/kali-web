#include "native_settings_window.h"

#include "native_theme.h"

#include <shellapi.h>

#include <algorithm>
#include <array>
#include <string>

#pragma comment(lib, "shell32.lib")

namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.NativeShell.Settings.v2";
constexpr wchar_t kRegistryPath[] = L"Software\\CloudOS\\Native";
constexpr wchar_t kDesktopClass[] = L"CloudOS.NativeShell.CloudOSDesktop.v19";
constexpr int kDistroId = 3002;
constexpr int kSaveId = 3003;
constexpr int kWindowsSettingsId = 3004;
constexpr int kInstallWslId = 3005;

HBRUSH BackgroundBrush()
{
    static HBRUSH brush = CloudOS::WebSkin::CreateBackgroundBrush();
    return brush;
}

HBRUSH EditBrush()
{
    static HBRUSH brush = CloudOS::WebSkin::CreateEditBrush();
    return brush;
}

bool EnsureClass(HINSTANCE instance)
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeSettingsWindow::WindowProcedure;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    window_class.hbrBackground = nullptr;
    window_class.lpszClassName = kClassName;
    window_class.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
    if (RegisterClassExW(&window_class) != 0) return true;
    return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

std::wstring ReadControlText(HWND control)
{
    const int length = GetWindowTextLengthW(control);
    if (length <= 0) return {};
    std::wstring text(static_cast<std::size_t>(length) + 1u, L'\0');
    const int copied = GetWindowTextW(control, text.data(), length + 1);
    text.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0u);
    return text;
}

std::wstring Trim(std::wstring text)
{
    const auto is_space = [](wchar_t value)
    {
        return value == L' ' || value == L'\t' || value == L'\r' || value == L'\n';
    };
    while (!text.empty() && is_space(text.front())) text.erase(text.begin());
    while (!text.empty() && is_space(text.back())) text.pop_back();
    return text;
}
} // namespace

CloudOSNativeSettingsWindow::CloudOSNativeSettingsWindow(HINSTANCE instance) : instance_(instance) {}

void CloudOSNativeSettingsWindow::Open(HINSTANCE instance)
{
    auto* self = new CloudOSNativeSettingsWindow(instance);
    if (!self->Create()) delete self;
}

CloudOSNativeSettings CloudOSNativeSettingsWindow::Load()
{
    CloudOSNativeSettings settings;
    HKEY key{};
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS)
        return settings;

    std::array<wchar_t, 256> distro{};
    DWORD type = 0;
    DWORD size = static_cast<DWORD>(distro.size() * sizeof(wchar_t));
    if (RegQueryValueExW(key, L"DefaultWslDistribution", nullptr, &type,
            reinterpret_cast<BYTE*>(distro.data()), &size) == ERROR_SUCCESS &&
        (type == REG_SZ || type == REG_EXPAND_SZ) && distro[0] != L'\0')
    {
        settings.default_wsl_distribution = distro.data();
    }
    RegCloseKey(key);
    return settings;
}

bool CloudOSNativeSettingsWindow::Save(const CloudOSNativeSettings& settings)
{
    HKEY key{};
    DWORD disposition = 0;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, REG_OPTION_NON_VOLATILE,
            KEY_SET_VALUE, nullptr, &key, &disposition) != ERROR_SUCCESS)
        return false;

    const DWORD bytes = static_cast<DWORD>((settings.default_wsl_distribution.size() + 1u) * sizeof(wchar_t));
    const LONG result = RegSetValueExW(key, L"DefaultWslDistribution", 0, REG_SZ,
        reinterpret_cast<const BYTE*>(settings.default_wsl_distribution.c_str()), bytes);
    (void)RegDeleteValueW(key, L"TilingOnStart");
    RegCloseKey(key);
    return result == ERROR_SUCCESS;
}

bool CloudOSNativeSettingsWindow::Create()
{
    if (!EnsureClass(instance_)) return false;
    window_ = CreateWindowExW(
        WS_EX_APPWINDOW, kClassName, L"Configuracoes - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT, CW_USEDEFAULT, 720, 430,
        nullptr, nullptr, instance_, this);
    if (window_ == nullptr) return false;
    CloudOS::ApplyWebWindowMaterial(window_);
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeSettingsWindow::Layout()
{
    RECT client{}; GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = CloudOS::Scale(28, dpi);
    const int title_height = CloudOS::Scale(40, dpi);
    const int row_height = CloudOS::Scale(42, dpi);
    const int note_height = CloudOS::Scale(58, dpi);
    const int gap = CloudOS::Scale(14, dpi);
    const int full_width = std::max(1, static_cast<int>(client.right) - margin * 2);

    int top = margin;
    SetWindowPos(title_, nullptr, margin, top, full_width, title_height, SWP_NOZORDER | SWP_NOACTIVATE);
    top += title_height + gap;
    SetWindowPos(tiling_note_, nullptr, margin, top, full_width, note_height, SWP_NOZORDER | SWP_NOACTIVATE);
    top += note_height + gap;

    const int label_width = CloudOS::Scale(205, dpi);
    SetWindowPos(distro_label_, nullptr, margin, top, label_width, row_height, SWP_NOZORDER | SWP_NOACTIVATE);
    SetWindowPos(distro_edit_, nullptr, margin + label_width, top,
        std::max(1, full_width - label_width), row_height, SWP_NOZORDER | SWP_NOACTIVATE);
    top += row_height + gap * 2;

    const int button_width = CloudOS::Scale(190, dpi);
    SetWindowPos(save_button_, nullptr, margin, top, button_width, row_height, SWP_NOZORDER | SWP_NOACTIVATE);
    SetWindowPos(windows_settings_button_, nullptr, margin + button_width + gap, top,
        button_width, row_height, SWP_NOZORDER | SWP_NOACTIVATE);
    SetWindowPos(install_wsl_button_, nullptr, margin + (button_width + gap) * 2, top,
        std::max(1, full_width - (button_width + gap) * 2), row_height, SWP_NOZORDER | SWP_NOACTIVATE);
}

void CloudOSNativeSettingsWindow::LoadIntoControls()
{
    const CloudOSNativeSettings settings = Load();
    SetWindowTextW(distro_edit_, settings.default_wsl_distribution.c_str());
}

void CloudOSNativeSettingsWindow::SaveFromControls()
{
    CloudOSNativeSettings settings;
    settings.default_wsl_distribution = Trim(ReadControlText(distro_edit_));
    if (settings.default_wsl_distribution.empty()) settings.default_wsl_distribution = L"kali-linux";
    if (!Save(settings))
    {
        MessageBoxW(window_, L"Nao foi possivel salvar as configuracoes no perfil do Windows.",
            L"CloudOS", MB_OK | MB_ICONERROR);
        return;
    }
    HWND desktop = FindWindowW(kDesktopClass, nullptr);
    if (desktop != nullptr) PostMessageW(desktop, CLOUDOS_WM_NATIVE_SETTINGS_CHANGED, 0, 0);
    MessageBoxW(window_, L"Configuracoes salvas.", L"CloudOS", MB_OK | MB_ICONINFORMATION);
}

void CloudOSNativeSettingsWindow::OpenWindowsSettings()
{
    const HINSTANCE result = ShellExecuteW(window_, L"open", L"ms-settings:", nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32)
        MessageBoxW(window_, L"Nao foi possivel abrir as Configuracoes do Windows.", L"CloudOS", MB_OK | MB_ICONERROR);
}

void CloudOSNativeSettingsWindow::InstallWsl()
{
    if (MessageBoxW(window_,
            L"O Windows pode solicitar privilegios de administrador e reinicializacao. Deseja iniciar a instalacao/atualizacao do WSL agora?",
            L"CloudOS", MB_YESNO | MB_ICONQUESTION) != IDYES)
        return;

    const CloudOSNativeSettings settings = Load();
    std::wstring parameters = L"--install -d \"";
    parameters += settings.default_wsl_distribution;
    parameters += L"\"";
    const HINSTANCE result = ShellExecuteW(window_, L"runas", L"wsl.exe", parameters.c_str(), nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32)
        MessageBoxW(window_, L"Nao foi possivel iniciar o instalador do WSL.", L"CloudOS", MB_OK | MB_ICONERROR);
}

LRESULT CloudOSNativeSettingsWindow::HandleMessage(UINT message, WPARAM w_param, LPARAM l_param)
{
    switch (message)
    {
    case WM_CREATE:
    {
        title_ = CreateWindowExW(0, L"STATIC", L"CloudOS · Sistema e WSL",
            WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
        tiling_note_ = CreateWindowExW(0, L"STATIC",
            L"Layout automatico permanece desligado ao iniciar. O Tiling so e ativado manualmente com Ctrl+Alt+T.",
            WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
        distro_label_ = CreateWindowExW(0, L"STATIC", L"Distribuicao WSL padrao:",
            WS_CHILD | WS_VISIBLE | SS_CENTERIMAGE, 0, 0, 0, 0, window_, nullptr, instance_, nullptr);
        distro_edit_ = CreateWindowExW(0, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 0, 0, 0, 0, window_,
            reinterpret_cast<HMENU>(kDistroId), instance_, nullptr);
        save_button_ = CreateWindowExW(0, L"BUTTON", L"Salvar",
            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window_,
            reinterpret_cast<HMENU>(kSaveId), instance_, nullptr);
        windows_settings_button_ = CreateWindowExW(0, L"BUTTON", L"Configuracoes do Windows",
            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window_,
            reinterpret_cast<HMENU>(kWindowsSettingsId), instance_, nullptr);
        install_wsl_button_ = CreateWindowExW(0, L"BUTTON", L"Instalar / atualizar WSL",
            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW, 0, 0, 0, 0, window_,
            reinterpret_cast<HMENU>(kInstallWslId), instance_, nullptr);

        const UINT dpi = GetDpiForWindow(window_);
        HFONT body_font = CreateFontW(-CloudOS::Scale(14, dpi), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
        HFONT title_font = CreateFontW(-CloudOS::Scale(22, dpi), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
        SendMessageW(title_, WM_SETFONT, reinterpret_cast<WPARAM>(title_font), TRUE);
        for (HWND child : {tiling_note_, distro_label_, distro_edit_, save_button_, windows_settings_button_, install_wsl_button_})
            if (child != nullptr) SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(body_font), TRUE);

        CloudOS::WebSkin::PrepareEdit(distro_edit_);
        for (HWND button : {save_button_, windows_settings_button_, install_wsl_button_})
            CloudOS::WebSkin::PrepareButton(button);
        LoadIntoControls();
        Layout();
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
    case WM_COMMAND:
        if (HIWORD(w_param) == BN_CLICKED)
        {
            switch (LOWORD(w_param))
            {
            case kSaveId: SaveFromControls(); return 0;
            case kWindowsSettingsId: OpenWindowsSettings(); return 0;
            case kInstallWslId: InstallWsl(); return 0;
            default: break;
            }
        }
        break;
    case WM_DRAWITEM:
    {
        const auto* draw = reinterpret_cast<const DRAWITEMSTRUCT*>(l_param);
        if (draw != nullptr)
        {
            const auto tone = draw->CtlID == kSaveId ? CloudOS::ButtonTone::Accent : CloudOS::ButtonTone::Neutral;
            if (CloudOS::WebSkin::PaintOwnerDrawButton(draw, tone)) return TRUE;
        }
        break;
    }
    case WM_CTLCOLORSTATIC:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, reinterpret_cast<HWND>(l_param) == title_ ? CloudOS::WebSkin::TextPrimary : CloudOS::WebSkin::TextSecondary);
        return reinterpret_cast<LRESULT>(BackgroundBrush());
    }
    case WM_CTLCOLOREDIT:
    {
        HDC dc = reinterpret_cast<HDC>(w_param);
        SetTextColor(dc, CloudOS::WebSkin::TextPrimary);
        SetBkColor(dc, CloudOS::WebSkin::BgTertiary);
        return reinterpret_cast<LRESULT>(EditBrush());
    }
    case WM_ERASEBKGND:
    {
        RECT client{}; GetClientRect(window_, &client);
        CloudOS::WebSkin::PaintWindowBackground(reinterpret_cast<HDC>(w_param), client);
        return 1;
    }
    case WM_DESTROY:
        window_ = nullptr;
        delete this;
        return 0;
    default: break;
    }
    return DefWindowProcW(window_, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeSettingsWindow::WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param)
{
    CloudOSNativeSettingsWindow* self = reinterpret_cast<CloudOSNativeSettingsWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeSettingsWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    return self != nullptr ? self->HandleMessage(message, w_param, l_param)
                           : DefWindowProcW(window, message, w_param, l_param);
}
