#include "native_desktop_drop_target.h"

#include "native_notification_center.h"

#include <ole2.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <mutex>
#include <new>
#include <unordered_map>
#include <vector>

namespace CloudOS
{
namespace
{
using Microsoft::WRL::ComPtr;

std::mutex g_targets_mutex;
std::unordered_map<HWND, IDropTarget*> g_targets;

bool HasFileDrop(IDataObject* data_object)
{
    if (data_object == nullptr)
    {
        return false;
    }
    FORMATETC format{};
    format.cfFormat = CF_HDROP;
    format.dwAspect = DVASPECT_CONTENT;
    format.lindex = -1;
    format.tymed = TYMED_HGLOBAL;
    return SUCCEEDED(data_object->QueryGetData(&format));
}

std::vector<std::wstring> ExtractPaths(IDataObject* data_object)
{
    std::vector<std::wstring> paths;
    if (data_object == nullptr)
    {
        return paths;
    }

    FORMATETC format{};
    format.cfFormat = CF_HDROP;
    format.dwAspect = DVASPECT_CONTENT;
    format.lindex = -1;
    format.tymed = TYMED_HGLOBAL;

    STGMEDIUM medium{};
    if (FAILED(data_object->GetData(&format, &medium)))
    {
        return paths;
    }

    const HDROP drop = reinterpret_cast<HDROP>(medium.hGlobal);
    if (drop != nullptr)
    {
        const UINT count = DragQueryFileW(drop, 0xFFFFFFFFu, nullptr, 0);
        paths.reserve(count);
        for (UINT index = 0; index < count; ++index)
        {
            const UINT length = DragQueryFileW(drop, index, nullptr, 0);
            std::wstring path(static_cast<std::size_t>(length) + 1u, L'\0');
            if (DragQueryFileW(drop, index, path.data(), length + 1u) != 0)
            {
                path.resize(length);
                paths.push_back(std::move(path));
            }
        }
    }
    ReleaseStgMedium(&medium);
    return paths;
}

bool CopyToDesktop(const std::vector<std::wstring>& paths)
{
    if (paths.empty())
    {
        return false;
    }

    ComPtr<IShellItem> destination;
    if (FAILED(SHGetKnownFolderItem(
            FOLDERID_Desktop,
            KF_FLAG_DEFAULT,
            nullptr,
            IID_PPV_ARGS(&destination))))
    {
        return false;
    }

    ComPtr<IFileOperation> operation;
    if (FAILED(CoCreateInstance(
            CLSID_FileOperation,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&operation))))
    {
        return false;
    }

    (void)operation->SetOperationFlags(
        FOF_ALLOWUNDO |
        FOF_NOCONFIRMMKDIR |
        FOFX_ADDUNDORECORD);

    unsigned int scheduled = 0;
    for (const std::wstring& path : paths)
    {
        ComPtr<IShellItem> source;
        if (SUCCEEDED(SHCreateItemFromParsingName(
                path.c_str(),
                nullptr,
                IID_PPV_ARGS(&source))))
        {
            if (SUCCEEDED(operation->CopyItem(
                    source.Get(),
                    destination.Get(),
                    nullptr,
                    nullptr)))
            {
                ++scheduled;
            }
        }
    }

    if (scheduled == 0 || FAILED(operation->PerformOperations()))
    {
        return false;
    }

    BOOL aborted = FALSE;
    if (FAILED(operation->GetAnyOperationsAborted(&aborted)) || aborted)
    {
        return false;
    }
    return true;
}

class DesktopDropTarget final : public IDropTarget
{
public:
    explicit DesktopDropTarget(HWND target) : target_(target) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override
    {
        if (object == nullptr)
        {
            return E_POINTER;
        }
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IDropTarget)
        {
            *object = static_cast<IDropTarget*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override
    {
        return static_cast<ULONG>(InterlockedIncrement(&references_));
    }

    ULONG STDMETHODCALLTYPE Release() override
    {
        const LONG count = InterlockedDecrement(&references_);
        if (count == 0)
        {
            delete this;
        }
        return static_cast<ULONG>(count);
    }

    HRESULT STDMETHODCALLTYPE DragEnter(
        IDataObject* data_object,
        DWORD,
        POINTL,
        DWORD* effect) override
    {
        if (effect == nullptr)
        {
            return E_POINTER;
        }
        accepted_ = HasFileDrop(data_object);
        *effect = accepted_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DragOver(
        DWORD,
        POINTL,
        DWORD* effect) override
    {
        if (effect == nullptr)
        {
            return E_POINTER;
        }
        *effect = accepted_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DragLeave() override
    {
        accepted_ = false;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Drop(
        IDataObject* data_object,
        DWORD,
        POINTL,
        DWORD* effect) override
    {
        if (effect == nullptr)
        {
            return E_POINTER;
        }
        *effect = DROPEFFECT_NONE;
        const std::vector<std::wstring> paths = ExtractPaths(data_object);
        if (!CopyToDesktop(paths))
        {
            accepted_ = false;
            return S_OK;
        }

        *effect = DROPEFFECT_COPY;
        accepted_ = false;
        if (target_ != nullptr && IsWindow(target_))
        {
            InvalidateRect(target_, nullptr, FALSE);
        }
        CloudOSNativeNotificationCenter::Post(
            L"Arquivos recebidos",
            std::to_wstring(paths.size()) +
                (paths.size() == 1 ? L" item copiado para o Desktop." : L" itens copiados para o Desktop."));
        return S_OK;
    }

private:
    ~DesktopDropTarget() = default;

    LONG references_{1};
    HWND target_{};
    bool accepted_{};
};
} // namespace

bool NativeDesktopDropTarget::Register(HWND window)
{
    if (window == nullptr || !IsWindow(window))
    {
        return false;
    }

    std::scoped_lock lock(g_targets_mutex);
    if (g_targets.find(window) != g_targets.end())
    {
        return true;
    }

    auto* target = new (std::nothrow) DesktopDropTarget(window);
    if (target == nullptr)
    {
        return false;
    }

    const HRESULT result = RegisterDragDrop(window, target);
    if (FAILED(result))
    {
        target->Release();
        return false;
    }

    g_targets.emplace(window, target);
    return true;
}

void NativeDesktopDropTarget::Unregister(HWND window) noexcept
{
    std::scoped_lock lock(g_targets_mutex);
    const auto iterator = g_targets.find(window);
    if (iterator == g_targets.end())
    {
        return;
    }

    (void)RevokeDragDrop(window);
    iterator->second->Release();
    g_targets.erase(iterator);
}
} // namespace CloudOS
