#include "native_shell_view_host.h"
#include "native_theme.h"

#include <Ole2.h>
#include <ShlObj.h>

#include <new>
#include <utility>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")

namespace CloudOS
{
// Hosting remains Microsoft ExplorerBrowser COM, not HTML/WebView. The only
// integration added by Files V5 is a safe selection bridge from IFolderView2
// back into first-party CloudOS chrome.

NativeShellViewHost::EventSink::EventSink(NativeShellViewHost* owner) noexcept : owner_(owner) {}

HRESULT STDMETHODCALLTYPE NativeShellViewHost::EventSink::QueryInterface(REFIID iid, void** object)
{
    if (object == nullptr) return E_POINTER;
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_IExplorerBrowserEvents)
    {
        *object = static_cast<IExplorerBrowserEvents*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE NativeShellViewHost::EventSink::AddRef()
{
    return static_cast<ULONG>(InterlockedIncrement(&references_));
}

ULONG STDMETHODCALLTYPE NativeShellViewHost::EventSink::Release()
{
    const LONG references = InterlockedDecrement(&references_);
    if (references == 0) { delete this; return 0; }
    return static_cast<ULONG>(references);
}

HRESULT STDMETHODCALLTYPE NativeShellViewHost::EventSink::OnNavigationPending(PCIDLIST_ABSOLUTE)
{
    return S_OK;
}

HRESULT STDMETHODCALLTYPE NativeShellViewHost::EventSink::OnViewCreated(IShellView* shell_view)
{
    if (shell_view != nullptr)
    {
        IFolderView2* folder_view = nullptr;
        if (SUCCEEDED(shell_view->QueryInterface(IID_PPV_ARGS(&folder_view))) && folder_view != nullptr)
        {
            (void)folder_view->SetViewModeAndIconSize(FVM_DETAILS, 20);
            folder_view->Release();
        }

        HWND shell_window = nullptr;
        if (SUCCEEDED(shell_view->GetWindow(&shell_window)) && shell_window != nullptr)
        {
            WebSkin::ApplyUxTheme(shell_window);
            WebSkin::PrepareWindowTree(shell_window);
            InvalidateRect(shell_window, nullptr, TRUE);
        }
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE NativeShellViewHost::EventSink::OnNavigationComplete(PCIDLIST_ABSOLUTE folder)
{
    if (owner_ != nullptr) owner_->OnNavigationComplete(folder);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE NativeShellViewHost::EventSink::OnNavigationFailed(PCIDLIST_ABSOLUTE)
{
    return S_OK;
}

NativeShellViewHost::~NativeShellViewHost() { Destroy(); }

bool NativeShellViewHost::Create(HWND parent, const RECT& bounds, NavigationCallback navigation_callback)
{
    Destroy();
    if (parent == nullptr) return false;

    const HRESULT ole_result = OleInitialize(nullptr);
    if (FAILED(ole_result)) return false;
    ole_initialized_ = true;

    IExplorerBrowser* browser = nullptr;
    HRESULT result = CoCreateInstance(CLSID_ExplorerBrowser, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&browser));
    if (FAILED(result) || browser == nullptr)
    {
        OleUninitialize();
        ole_initialized_ = false;
        return false;
    }

    FOLDERSETTINGS settings{};
    settings.ViewMode = FVM_DETAILS;
    settings.fFlags = static_cast<FOLDERFLAGS>(
        FWF_AUTOARRANGE | FWF_NOWEBVIEW | FWF_FULLROWSELECT | FWF_NOCLIENTEDGE);

    result = browser->Initialize(parent, &bounds, &settings);
    if (FAILED(result))
    {
        browser->Release();
        OleUninitialize();
        ole_initialized_ = false;
        return false;
    }

    const EXPLORER_BROWSER_OPTIONS options = static_cast<EXPLORER_BROWSER_OPTIONS>(
        EBO_ALWAYSNAVIGATE | EBO_NOBORDER);
    (void)browser->SetOptions(options);
    (void)browser->SetPropertyBag(L"CloudOS.NativeFiles.ShellView.v5.WebSkin");
    (void)browser->SetEmptyText(L"Esta pasta esta vazia.");

    auto* sink = new (std::nothrow) EventSink(this);
    DWORD cookie = 0;
    if (sink != nullptr)
    {
        if (FAILED(browser->Advise(sink, &cookie))) cookie = 0;
        sink->Release();
    }

    parent_ = parent;
    browser_ = browser;
    advise_cookie_ = cookie;
    navigation_callback_ = std::move(navigation_callback);
    current_path_.clear();
    return true;
}

void NativeShellViewHost::Destroy() noexcept
{
    if (browser_ != nullptr)
    {
        if (advise_cookie_ != 0)
        {
            (void)browser_->Unadvise(advise_cookie_);
            advise_cookie_ = 0;
        }
        (void)browser_->Destroy();
        browser_->Release();
        browser_ = nullptr;
    }
    parent_ = nullptr;
    current_path_.clear();
    navigation_callback_ = {};
    if (ole_initialized_)
    {
        OleUninitialize();
        ole_initialized_ = false;
    }
}

void NativeShellViewHost::Resize(const RECT& bounds) noexcept
{
    if (browser_ != nullptr) (void)browser_->SetRect(nullptr, bounds);
}

bool NativeShellViewHost::IsReady() const noexcept { return browser_ != nullptr; }
const std::wstring& NativeShellViewHost::CurrentPath() const noexcept { return current_path_; }

std::vector<std::wstring> NativeShellViewHost::SelectedPaths() const
{
    std::vector<std::wstring> result;
    IFolderView2* view = nullptr;
    if (!GetCurrentView(&view) || view == nullptr) return result;

    IShellItemArray* selection = nullptr;
    const HRESULT selection_result = view->GetSelection(TRUE, &selection);
    view->Release();
    if (FAILED(selection_result) || selection == nullptr) return result;

    DWORD count = 0;
    if (FAILED(selection->GetCount(&count)))
    {
        selection->Release();
        return result;
    }

    constexpr DWORD kMaximumSelection = 256;
    const DWORD bounded = (std::min)(count, kMaximumSelection);
    result.reserve(bounded);
    for (DWORD index = 0; index < bounded; ++index)
    {
        IShellItem* item = nullptr;
        if (FAILED(selection->GetItemAt(index, &item)) || item == nullptr) continue;
        std::wstring path = DisplayPathFromShellItem(item);
        item->Release();
        if (!path.empty()) result.push_back(std::move(path));
    }
    selection->Release();
    return result;
}

bool NativeShellViewHost::Navigate(const std::wstring& path)
{
    if (browser_ == nullptr || path.empty()) return false;
    PIDLIST_ABSOLUTE item_id_list = nullptr;
    const HRESULT parse_result = SHParseDisplayName(path.c_str(), nullptr, &item_id_list, 0, nullptr);
    if (FAILED(parse_result) || item_id_list == nullptr) return false;
    const HRESULT browse_result = browser_->BrowseToIDList(item_id_list, SBSP_ABSOLUTE);
    CoTaskMemFree(item_id_list);
    return SUCCEEDED(browse_result);
}

bool NativeShellViewHost::NavigateBack()
{
    return browser_ != nullptr && SUCCEEDED(browser_->BrowseToIDList(nullptr, SBSP_NAVIGATEBACK));
}

bool NativeShellViewHost::NavigateForward()
{
    return browser_ != nullptr && SUCCEEDED(browser_->BrowseToIDList(nullptr, SBSP_NAVIGATEFORWARD));
}

bool NativeShellViewHost::NavigateParent()
{
    return browser_ != nullptr && SUCCEEDED(browser_->BrowseToIDList(nullptr, SBSP_PARENT));
}

bool NativeShellViewHost::Refresh()
{
    IShellView* view = nullptr;
    if (!GetCurrentView(&view) || view == nullptr) return false;
    const HRESULT result = view->Refresh();
    view->Release();
    return SUCCEEDED(result);
}

bool NativeShellViewHost::BeginRenameSelection()
{
    IFolderView2* view = nullptr;
    if (!GetCurrentView(&view) || view == nullptr) return false;
    const HRESULT result = view->DoRename();
    view->Release();
    return SUCCEEDED(result);
}

bool NativeShellViewHost::DeleteSelection()
{
    IFolderView2* view = nullptr;
    if (!GetCurrentView(&view) || view == nullptr) return false;
    const HRESULT result = view->InvokeVerbOnSelection("delete");
    view->Release();
    return SUCCEEDED(result);
}

std::wstring NativeShellViewHost::DisplayPathFromPidl(PCIDLIST_ABSOLUTE folder)
{
    if (folder == nullptr) return {};
    PWSTR value = nullptr;
    if (SUCCEEDED(SHGetNameFromIDList(folder, SIGDN_FILESYSPATH, &value)) && value != nullptr)
    {
        std::wstring path(value); CoTaskMemFree(value); return path;
    }
    if (value != nullptr) { CoTaskMemFree(value); value = nullptr; }
    if (SUCCEEDED(SHGetNameFromIDList(folder, SIGDN_DESKTOPABSOLUTEPARSING, &value)) && value != nullptr)
    {
        std::wstring path(value); CoTaskMemFree(value); return path;
    }
    if (value != nullptr) CoTaskMemFree(value);
    return {};
}

std::wstring NativeShellViewHost::DisplayPathFromShellItem(IShellItem* item)
{
    if (item == nullptr) return {};
    PWSTR value = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &value)) && value != nullptr)
    {
        std::wstring path(value);
        CoTaskMemFree(value);
        return path;
    }
    if (value != nullptr) { CoTaskMemFree(value); value = nullptr; }
    if (SUCCEEDED(item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &value)) && value != nullptr)
    {
        std::wstring path(value);
        CoTaskMemFree(value);
        return path;
    }
    if (value != nullptr) CoTaskMemFree(value);
    return {};
}

void NativeShellViewHost::OnNavigationComplete(PCIDLIST_ABSOLUTE folder)
{
    current_path_ = DisplayPathFromPidl(folder);
    if (navigation_callback_) navigation_callback_(current_path_);
}
} // namespace CloudOS
