#pragma once

#include <Windows.h>
#include <ShObjIdl.h>

#include <functional>
#include <string>

namespace CloudOS
{

class NativeShellViewHost final
{
public:
    using NavigationCallback = std::function<void(const std::wstring&)>;

    NativeShellViewHost() = default;
    ~NativeShellViewHost();

    NativeShellViewHost(const NativeShellViewHost&) = delete;
    NativeShellViewHost& operator=(const NativeShellViewHost&) = delete;

    bool Create(
        HWND parent,
        const RECT& bounds,
        NavigationCallback navigation_callback = {});

    void Destroy() noexcept;
    void Resize(const RECT& bounds) noexcept;

    [[nodiscard]] bool IsReady() const noexcept;
    [[nodiscard]] const std::wstring& CurrentPath() const noexcept;

    bool Navigate(const std::wstring& path);
    bool NavigateBack();
    bool NavigateForward();
    bool NavigateParent();
    bool Refresh();

    bool BeginRenameSelection();
    bool DeleteSelection();

private:
    class EventSink final : public IExplorerBrowserEvents
    {
    public:
        explicit EventSink(NativeShellViewHost* owner) noexcept;

        HRESULT STDMETHODCALLTYPE QueryInterface(
            REFIID iid,
            void** object) override;
        ULONG STDMETHODCALLTYPE AddRef() override;
        ULONG STDMETHODCALLTYPE Release() override;

        HRESULT STDMETHODCALLTYPE OnNavigationPending(
            PCIDLIST_ABSOLUTE folder) override;
        HRESULT STDMETHODCALLTYPE OnViewCreated(
            IShellView* shell_view) override;
        HRESULT STDMETHODCALLTYPE OnNavigationComplete(
            PCIDLIST_ABSOLUTE folder) override;
        HRESULT STDMETHODCALLTYPE OnNavigationFailed(
            PCIDLIST_ABSOLUTE folder) override;

    private:
        ~EventSink() = default;

        LONG references_{1};
        NativeShellViewHost* owner_{};
    };

    void OnNavigationComplete(PCIDLIST_ABSOLUTE folder);
    static std::wstring DisplayPathFromPidl(PCIDLIST_ABSOLUTE folder);

    template <typename Interface>
    bool GetCurrentView(Interface** view) const
    {
        if (view == nullptr)
        {
            return false;
        }
        *view = nullptr;
        return browser_ != nullptr &&
            SUCCEEDED(browser_->GetCurrentView(
                __uuidof(Interface),
                reinterpret_cast<void**>(view)));
    }

    HWND parent_{};
    bool ole_initialized_{};
    IExplorerBrowser* browser_{};
    DWORD advise_cookie_{};
    NavigationCallback navigation_callback_;
    std::wstring current_path_;
};

} // namespace CloudOS
