#pragma once

#include <Windows.h>
#include <WebView2.h>
#include <wrl.h>

#include <atomic>
#include <memory>
#include <string>

namespace CloudOS
{
class CloudOSNativeBrowserWindow final
{
public:
    static void Open(HINSTANCE instance, const std::wstring& initial_url = L"https://www.google.com/");

private:
    CloudOSNativeBrowserWindow(HINSTANCE instance, std::wstring initial_url);
    ~CloudOSNativeBrowserWindow();

    CloudOSNativeBrowserWindow(const CloudOSNativeBrowserWindow&) = delete;
    CloudOSNativeBrowserWindow& operator=(const CloudOSNativeBrowserWindow&) = delete;

    bool Create();
    void InitializeWebView();
    void ConfigureController(ICoreWebView2Controller* controller);
    void Layout();
    void NavigateFromAddress();
    void Navigate(const std::wstring& raw_url);
    void UpdateNavigationState();
    void ShowWebViewFailure(const std::wstring& detail);
    static std::wstring NormalizeUrl(std::wstring value);
    static std::wstring UserDataDirectory();

    LRESULT HandleMessage(UINT message, WPARAM w_param, LPARAM l_param);
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND back_button_{};
    HWND forward_button_{};
    HWND reload_button_{};
    HWND home_button_{};
    HWND address_edit_{};
    HWND go_button_{};
    HWND status_label_{};
    HFONT ui_font_{};
    HBRUSH toolbar_brush_{};
    std::wstring initial_url_;

    Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
    Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
    // DownloadStarting was introduced on ICoreWebView2_4. Keep the base
    // interface for common navigation and hold the versioned capability
    // separately so older/runtime capability failures degrade cleanly.
    Microsoft::WRL::ComPtr<ICoreWebView2_4> webview_v4_;
    EventRegistrationToken navigation_completed_token_{};
    EventRegistrationToken history_changed_token_{};
    EventRegistrationToken download_starting_token_{};
    bool navigation_completed_registered_{};
    bool history_changed_registered_{};
    bool download_starting_registered_{};

    std::shared_ptr<std::atomic_bool> alive_{std::make_shared<std::atomic_bool>(true)};
};
} // namespace CloudOS
