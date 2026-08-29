#include "native_webview_host.h"

#include <ShlObj.h>

#include <filesystem>
#include <system_error>
#include <utility>

#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kTrustedUrl[] = L"https://cloudos.local/index.html";

bool DirectoryContainsIndex(const std::wstring& directory)
{
    if (directory.empty())
    {
        return false;
    }
    std::error_code error;
    const std::filesystem::path index =
        std::filesystem::path(directory) / L"index.html";
    return std::filesystem::is_regular_file(index, error) && !error;
}
}

NativeWebViewHost::~NativeWebViewHost()
{
    Destroy();
}

std::wstring NativeWebViewHost::DefaultContentDirectory()
{
    wchar_t executable[32768]{};
    const DWORD length = GetModuleFileNameW(
        nullptr,
        executable,
        static_cast<DWORD>(std::size(executable)));
    if (length == 0 || length >= std::size(executable))
    {
        return {};
    }
    return (std::filesystem::path(executable).parent_path() / L"ui").wstring();
}

std::wstring NativeWebViewHost::UserDataDirectory()
{
    PWSTR local_app_data = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_CREATE,
            nullptr,
            &local_app_data)) ||
        local_app_data == nullptr)
    {
        return {};
    }

    const std::filesystem::path path =
        std::filesystem::path(local_app_data) / L"CloudOS" / L"WebView2";
    CoTaskMemFree(local_app_data);

    std::error_code error;
    std::filesystem::create_directories(path, error);
    return error ? std::wstring{} : path.wstring();
}

bool NativeWebViewHost::RuntimeAvailable(std::wstring* version)
{
    if (version != nullptr)
    {
        version->clear();
    }

    LPWSTR raw_version = nullptr;
    const HRESULT result =
        GetAvailableCoreWebView2BrowserVersionString(nullptr, &raw_version);
    if (FAILED(result) || raw_version == nullptr)
    {
        if (raw_version != nullptr)
        {
            CoTaskMemFree(raw_version);
        }
        return false;
    }

    if (version != nullptr)
    {
        *version = raw_version;
    }
    CoTaskMemFree(raw_version);
    return true;
}

bool NativeWebViewHost::Create(
    HWND parent,
    const std::wstring& content_directory,
    MessageCallback message_callback,
    ReadyCallback ready_callback)
{
    Destroy();

    if (parent == nullptr ||
        !IsWindow(parent) ||
        !DirectoryContainsIndex(content_directory) ||
        !RuntimeAvailable())
    {
        return false;
    }

    const std::wstring user_data = UserDataDirectory();
    if (user_data.empty())
    {
        return false;
    }

    parent_ = parent;
    content_directory_ = content_directory;
    message_callback_ = std::move(message_callback);
    ready_callback_ = std::move(ready_callback);
    alive_ = std::make_shared<std::atomic_bool>(true);
    const auto lifetime = alive_;

    const HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
        nullptr,
        user_data.c_str(),
        nullptr,
        Microsoft::WRL::Callback<
            ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [this, lifetime](
                HRESULT environment_result,
                ICoreWebView2Environment* environment) -> HRESULT
            {
                if (!lifetime->load())
                {
                    return S_OK;
                }
                if (FAILED(environment_result) || environment == nullptr)
                {
                    wchar_t err_buf[256]{}; swprintf_s(err_buf, L"Falha ao criar o ambiente WebView2 (hr=0x%08X).", static_cast<unsigned int>(environment_result)); NotifyReady(false, err_buf);
                    return S_OK;
                }

                environment_ = environment;
                const HRESULT controller_result =
                    environment->CreateCoreWebView2Controller(
                        parent_,
                        Microsoft::WRL::Callback<
                            ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                            [this, lifetime](
                                HRESULT creation_result,
                                ICoreWebView2Controller* controller) -> HRESULT
                            {
                                if (!lifetime->load())
                                {
                                    return S_OK;
                                }
                                if (FAILED(creation_result) || controller == nullptr)
                                {
                                    wchar_t err_buf[256]{}; swprintf_s(err_buf, L"Falha ao criar o controlador WebView2 (hr=0x%08X).", static_cast<unsigned int>(creation_result)); NotifyReady(false, err_buf);
                                    return S_OK;
                                }
                                ConfigureController(controller);
                                return S_OK;
                            }).Get());
                if (FAILED(controller_result))
                {
                    wchar_t err_buf[256]{}; swprintf_s(err_buf, L"WebView2 recusou a criacao do controlador (hr=0x%08X).", static_cast<unsigned int>(controller_result)); NotifyReady(false, err_buf);
                }
                return S_OK;
            }).Get());

    if (FAILED(result))
    {
        Destroy();
        return false;
    }
    return true;
}

void NativeWebViewHost::ConfigureController(ICoreWebView2Controller* controller)
{
    controller_ = controller;
    if (FAILED(controller_->get_CoreWebView2(&webview_)) || webview_ == nullptr)
    {
        NotifyReady(false, L"WebView2 nao forneceu a superficie principal.");
        return;
    }

    Microsoft::WRL::ComPtr<ICoreWebView2Settings> settings;
    if (SUCCEEDED(webview_->get_Settings(&settings)) && settings != nullptr)
    {
        (void)settings->put_IsScriptEnabled(TRUE);
        (void)settings->put_IsWebMessageEnabled(TRUE);
        (void)settings->put_AreDefaultScriptDialogsEnabled(FALSE);
        (void)settings->put_AreDefaultContextMenusEnabled(FALSE);
#ifdef NDEBUG
        (void)settings->put_AreDevToolsEnabled(FALSE);
#else
        (void)settings->put_AreDevToolsEnabled(TRUE);
#endif
        (void)settings->put_IsZoomControlEnabled(FALSE);
        (void)settings->put_IsStatusBarEnabled(FALSE);
    }

    Microsoft::WRL::ComPtr<ICoreWebView2_3> webview3;
    if (FAILED(webview_.As(&webview3)) || webview3 == nullptr ||
        FAILED(webview3->SetVirtualHostNameToFolderMapping(
            L"cloudos.local",
            content_directory_.c_str(),
            COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS)))
    {
        NotifyReady(false, L"Nao foi possivel mapear os assets locais da interface.");
        return;
    }

    const auto lifetime = alive_;
    if (SUCCEEDED(webview_->add_WebMessageReceived(
            Microsoft::WRL::Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                [this, lifetime](
                    ICoreWebView2*,
                    ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT
                {
                    if (!lifetime->load() || args == nullptr)
                    {
                        return S_OK;
                    }

                    LPWSTR source = nullptr;
                    if (FAILED(args->get_Source(&source)) ||
                        !IsTrustedSource(source))
                    {
                        if (source != nullptr) CoTaskMemFree(source);
                        return S_OK;
                    }
                    CoTaskMemFree(source);

                    LPWSTR raw_message = nullptr;
                    if (SUCCEEDED(args->TryGetWebMessageAsString(&raw_message)) &&
                        raw_message != nullptr)
                    {
                        const std::wstring message(raw_message);
                        CoTaskMemFree(raw_message);
                        if (message_callback_)
                        {
                            message_callback_(message);
                        }
                    }
                    return S_OK;
                }).Get(),
            &web_message_token_)))
    {
        web_message_registered_ = true;
    }

    if (SUCCEEDED(webview_->add_NavigationStarting(
            Microsoft::WRL::Callback<ICoreWebView2NavigationStartingEventHandler>(
                [this, lifetime](
                    ICoreWebView2*,
                    ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT
                {
                    if (!lifetime->load() || args == nullptr)
                    {
                        return S_OK;
                    }
                    LPWSTR uri = nullptr;
                    if (SUCCEEDED(args->get_Uri(&uri)) && uri != nullptr)
                    {
                        if (!IsTrustedSource(uri))
                        {
                            (void)args->put_Cancel(TRUE);
                        }
                        CoTaskMemFree(uri);
                    }
                    return S_OK;
                }).Get(),
            &navigation_token_)))
    {
        navigation_registered_ = true;
    }

    if (!web_message_registered_ || !navigation_registered_)
    {
        NotifyReady(false, L"Nao foi possivel proteger o canal da interface WebView2.");
        return;
    }

    Resize();
    (void)controller_->put_IsVisible(TRUE);
    if (FAILED(webview_->Navigate(kTrustedUrl)))
    {
        NotifyReady(false, L"Nao foi possivel carregar a interface local do CloudOS.");
        return;
    }

    ready_ = true;
    NotifyReady(true, L"");
}

bool NativeWebViewHost::IsTrustedSource(const wchar_t* source) const noexcept
{
    if (source == nullptr)
    {
        return false;
    }
    const std::size_t origin_length = trusted_origin_.size();
    if (_wcsnicmp(source, trusted_origin_.c_str(), origin_length) != 0)
    {
        return false;
    }
    const wchar_t next = source[origin_length];
    return next == L'\0' || next == L'/' || next == L'?' || next == L'#';
}

void NativeWebViewHost::NotifyReady(bool success, const std::wstring& detail)
{
    if (!success)
    {
        ready_ = false;
    }
    if (ready_callback_)
    {
        ready_callback_(success, detail);
    }
}

void NativeWebViewHost::Resize() noexcept
{
    if (controller_ == nullptr || parent_ == nullptr || !IsWindow(parent_))
    {
        return;
    }
    RECT bounds{};
    if (GetClientRect(parent_, &bounds))
    {
        (void)controller_->put_Bounds(bounds);
    }
}

bool NativeWebViewHost::Ready() const noexcept
{
    return ready_ && webview_ != nullptr;
}

void NativeWebViewHost::PostJson(const std::wstring& json) const noexcept
{
    if (Ready() && !json.empty())
    {
        (void)webview_->PostWebMessageAsJson(json.c_str());
    }
}

void NativeWebViewHost::PostString(const std::wstring& text) const noexcept
{
    if (Ready())
    {
        (void)webview_->PostWebMessageAsString(text.c_str());
    }
}

void NativeWebViewHost::Destroy() noexcept
{
    if (alive_)
    {
        alive_->store(false);
    }
    ready_ = false;

    if (webview_ != nullptr)
    {
        if (web_message_registered_)
        {
            (void)webview_->remove_WebMessageReceived(web_message_token_);
        }
        if (navigation_registered_)
        {
            (void)webview_->remove_NavigationStarting(navigation_token_);
        }
    }
    web_message_registered_ = false;
    navigation_registered_ = false;
    web_message_token_ = {};
    navigation_token_ = {};

    if (controller_ != nullptr)
    {
        (void)controller_->Close();
    }
    webview_.Reset();
    controller_.Reset();
    environment_.Reset();

    parent_ = nullptr;
    content_directory_.clear();
    message_callback_ = {};
    ready_callback_ = {};
}
} // namespace CloudOS

