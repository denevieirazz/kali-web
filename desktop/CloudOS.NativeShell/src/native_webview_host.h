#pragma once

#include <Windows.h>
#include <WebView2.h>
#include <wrl.h>

#include <atomic>
#include <functional>
#include <memory>
#include <string>

namespace CloudOS
{
class NativeWebViewHost final
{
public:
    using MessageCallback = std::function<void(const std::wstring&)>;
    using ReadyCallback = std::function<void(bool, const std::wstring&)>;

    NativeWebViewHost() = default;
    ~NativeWebViewHost();

    NativeWebViewHost(const NativeWebViewHost&) = delete;
    NativeWebViewHost& operator=(const NativeWebViewHost&) = delete;

    bool Create(
        HWND parent,
        const std::wstring& content_directory,
        MessageCallback message_callback,
        ReadyCallback ready_callback = {});
    void Destroy() noexcept;
    void Resize() noexcept;

    [[nodiscard]] bool Ready() const noexcept;
    void PostJson(const std::wstring& json) const noexcept;
    void PostString(const std::wstring& text) const noexcept;

    [[nodiscard]] static std::wstring DefaultContentDirectory();
    [[nodiscard]] static bool RuntimeAvailable(std::wstring* version = nullptr);

private:
    void NotifyReady(bool success, const std::wstring& detail);
    void ConfigureController(ICoreWebView2Controller* controller);
    [[nodiscard]] bool IsTrustedSource(const wchar_t* source) const noexcept;
    [[nodiscard]] static std::wstring UserDataDirectory();

    HWND parent_{};
    std::wstring content_directory_;
    std::wstring trusted_origin_{L"https://cloudos.local"};
    MessageCallback message_callback_;
    ReadyCallback ready_callback_;

    Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
    Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
    EventRegistrationToken web_message_token_{};
    EventRegistrationToken navigation_token_{};
    bool web_message_registered_{};
    bool navigation_registered_{};
    bool ready_{};

    std::shared_ptr<std::atomic_bool> alive_{
        std::make_shared<std::atomic_bool>(true)};
};
} // namespace CloudOS
