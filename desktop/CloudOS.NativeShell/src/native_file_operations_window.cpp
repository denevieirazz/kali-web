#include "native_file_operations_window.h"

#include "native_notification_center.h"
#include "native_theme.h"

#include <CommCtrl.h>
#include <KnownFolders.h>
#include <ShlObj.h>
#include <ShObjIdl.h>

#include <algorithm>
#include <array>
#include <filesystem>
#include <new>
#include <string>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
constexpr wchar_t kClassName[] = L"CloudOS.Native.FileOperations.v1";
constexpr int kSourceListId = 9401;
constexpr int kDestinationEditId = 9402;
constexpr int kAddFilesId = 9403;
constexpr int kAddFolderId = 9404;
constexpr int kRemoveId = 9405;
constexpr int kDestinationId = 9406;
constexpr int kCopyId = 9407;
constexpr int kMoveId = 9408;
constexpr int kZipId = 9409;
constexpr int kExtractId = 9410;
constexpr int kCancelId = 9411;
constexpr int kProgressId = 9412;
constexpr int kStatusId = 9413;
constexpr UINT kProgressMessage = WM_APP + 0x640;
constexpr UINT kStatusMessage = WM_APP + 0x641;
constexpr UINT kFinishedMessage = WM_APP + 0x642;

void SetFont(HWND window, HFONT font)
{
    if (window != nullptr && font != nullptr)
    {
        SendMessageW(window, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

std::wstring FileLabel(const std::wstring& path)
{
    const std::filesystem::path value(path);
    const std::wstring name = value.filename().wstring();
    return name.empty() ? path : name;
}

bool IsDirectory(const std::wstring& path)
{
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

bool IsZip(const std::wstring& path)
{
    std::wstring extension = std::filesystem::path(path).extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(), towlower);
    return extension == L".zip";
}

std::wstring QuoteArgument(const std::wstring& value)
{
    std::wstring result = L"\"";
    for (const wchar_t ch : value)
    {
        if (ch == L'\"')
        {
            result += L"\\\"";
        }
        else
        {
            result.push_back(ch);
        }
    }
    result += L"\"";
    return result;
}

std::wstring ShellItemPath(IShellItem* item)
{
    if (item == nullptr)
    {
        return {};
    }
    PWSTR path = nullptr;
    if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) || path == nullptr)
    {
        if (path != nullptr)
        {
            CoTaskMemFree(path);
        }
        return {};
    }
    std::wstring result(path);
    CoTaskMemFree(path);
    return result;
}

bool PickFolder(HWND owner, std::wstring* output)
{
    if (output == nullptr)
    {
        return false;
    }

    IFileOpenDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_FileOpenDialog,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&dialog))) ||
        dialog == nullptr)
    {
        return false;
    }

    FILEOPENDIALOGOPTIONS options{};
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
    const HRESULT show = dialog->Show(owner);
    if (show == HRESULT_FROM_WIN32(ERROR_CANCELLED))
    {
        dialog->Release();
        return false;
    }

    IShellItem* item = nullptr;
    const HRESULT result = SUCCEEDED(show) ? dialog->GetResult(&item) : show;
    if (SUCCEEDED(result) && item != nullptr)
    {
        *output = ShellItemPath(item);
        item->Release();
    }
    dialog->Release();
    return SUCCEEDED(result) && !output->empty();
}

std::vector<std::wstring> PickFiles(HWND owner)
{
    std::vector<std::wstring> result;
    IFileOpenDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_FileOpenDialog,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&dialog))) ||
        dialog == nullptr)
    {
        return result;
    }

    FILEOPENDIALOGOPTIONS options{};
    dialog->GetOptions(&options);
    dialog->SetOptions(
        options |
        FOS_ALLOWMULTISELECT |
        FOS_FORCEFILESYSTEM |
        FOS_FILEMUSTEXIST |
        FOS_PATHMUSTEXIST);
    if (FAILED(dialog->Show(owner)))
    {
        dialog->Release();
        return result;
    }

    IShellItemArray* items = nullptr;
    if (SUCCEEDED(dialog->GetResults(&items)) && items != nullptr)
    {
        DWORD count = 0;
        items->GetCount(&count);
        result.reserve(count);
        for (DWORD index = 0; index < count; ++index)
        {
            IShellItem* item = nullptr;
            if (SUCCEEDED(items->GetItemAt(index, &item)) && item != nullptr)
            {
                std::wstring path = ShellItemPath(item);
                if (!path.empty())
                {
                    result.push_back(std::move(path));
                }
                item->Release();
            }
        }
        items->Release();
    }
    dialog->Release();
    return result;
}

class ProgressSink final : public IFileOperationProgressSink
{
public:
    ProgressSink(HWND window, std::atomic_bool* cancel)
        : window_(window), cancel_(cancel)
    {
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override
    {
        if (object == nullptr)
        {
            return E_POINTER;
        }
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IFileOperationProgressSink)
        {
            *object = static_cast<IFileOperationProgressSink*>(this);
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
        const LONG remaining = InterlockedDecrement(&references_);
        if (remaining == 0)
        {
            delete this;
        }
        return static_cast<ULONG>(remaining);
    }

    HRESULT STDMETHODCALLTYPE StartOperations() override
    {
        PostStatus(L"Preparando operacao...");
        return CancelResult();
    }

    HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT result) override
    {
        PostMessageW(window_, kProgressMessage, 100, 0);
        return result;
    }

    HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override { return CancelResult(); }
    HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override
    {
        PostStatus(L"Movendo itens...");
        return CancelResult();
    }
    HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override
    {
        PostStatus(L"Copiando itens...");
        return CancelResult();
    }
    HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD, IShellItem*) override { return CancelResult(); }
    HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*, HRESULT, IShellItem*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override { return CancelResult(); }
    HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR, DWORD, HRESULT, IShellItem*) override { return S_OK; }

    HRESULT STDMETHODCALLTYPE UpdateProgress(UINT work_total, UINT work_so_far) override
    {
        const UINT percent = work_total == 0
            ? 0u
            : static_cast<UINT>(std::min<unsigned long long>(
                100ull,
                static_cast<unsigned long long>(work_so_far) * 100ull /
                    static_cast<unsigned long long>(work_total)));
        PostMessageW(window_, kProgressMessage, percent, 0);
        return CancelResult();
    }

    HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
    HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }

private:
    ~ProgressSink() = default;

    HRESULT CancelResult() const
    {
        return cancel_ != nullptr && cancel_->load()
            ? HRESULT_FROM_WIN32(ERROR_CANCELLED)
            : S_OK;
    }

    void PostStatus(const wchar_t* text)
    {
        auto* message = new (std::nothrow) std::wstring(text == nullptr ? L"" : text);
        if (message != nullptr && !PostMessageW(
                window_,
                kStatusMessage,
                0,
                reinterpret_cast<LPARAM>(message)))
        {
            delete message;
        }
    }

    LONG references_{1};
    HWND window_{};
    std::atomic_bool* cancel_{};
};

HRESULT RunShellOperation(
    HWND window,
    const std::vector<std::wstring>& sources,
    const std::wstring& destination,
    bool move,
    std::atomic_bool* cancel)
{
    IFileOperation* operation = nullptr;
    HRESULT result = CoCreateInstance(
        CLSID_FileOperation,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&operation));
    if (FAILED(result) || operation == nullptr)
    {
        return FAILED(result) ? result : E_FAIL;
    }

    const FILEOP_FLAGS flags =
        FOF_ALLOWUNDO |
        FOF_NOCONFIRMMKDIR |
        FOFX_ADDUNDORECORD |
        FOFX_EARLYFAILURE |
        FOFX_SHOWELEVATIONPROMPT;
    operation->SetOperationFlags(flags);

    IShellItem* destination_item = nullptr;
    result = SHCreateItemFromParsingName(
        destination.c_str(),
        nullptr,
        IID_PPV_ARGS(&destination_item));
    if (FAILED(result) || destination_item == nullptr)
    {
        operation->Release();
        return FAILED(result) ? result : E_FAIL;
    }

    auto* sink = new (std::nothrow) ProgressSink(window, cancel);
    if (sink == nullptr)
    {
        destination_item->Release();
        operation->Release();
        return E_OUTOFMEMORY;
    }

    DWORD cookie = 0;
    const bool advised = SUCCEEDED(operation->Advise(sink, &cookie));
    for (const auto& source_path : sources)
    {
        if (cancel != nullptr && cancel->load())
        {
            result = HRESULT_FROM_WIN32(ERROR_CANCELLED);
            break;
        }

        IShellItem* source_item = nullptr;
        result = SHCreateItemFromParsingName(
            source_path.c_str(),
            nullptr,
            IID_PPV_ARGS(&source_item));
        if (FAILED(result) || source_item == nullptr)
        {
            break;
        }

        result = move
            ? operation->MoveItem(source_item, destination_item, nullptr, nullptr)
            : operation->CopyItem(source_item, destination_item, nullptr, nullptr);
        source_item->Release();
        if (FAILED(result))
        {
            break;
        }
    }

    if (SUCCEEDED(result))
    {
        result = operation->PerformOperations();
        BOOL aborted = FALSE;
        if (SUCCEEDED(result) && SUCCEEDED(operation->GetAnyOperationsAborted(&aborted)) && aborted)
        {
            result = HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
    }

    if (advised)
    {
        operation->Unadvise(cookie);
    }
    sink->Release();
    destination_item->Release();
    operation->Release();
    return result;
}

HRESULT RunTar(
    HWND window,
    const std::wstring& command_line,
    const std::wstring& working_directory,
    std::atomic_bool* cancel)
{
    std::wstring command = command_line;
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(
            nullptr,
            command.data(),
            nullptr,
            nullptr,
            FALSE,
            CREATE_NO_WINDOW,
            nullptr,
            working_directory.empty() ? nullptr : working_directory.c_str(),
            &startup,
            &process))
    {
        return HRESULT_FROM_WIN32(GetLastError());
    }

    CloseHandle(process.hThread);
    HRESULT result = S_OK;
    for (;;)
    {
        const DWORD wait = WaitForSingleObject(process.hProcess, 120);
        if (wait == WAIT_OBJECT_0)
        {
            DWORD exit_code = 1;
            GetExitCodeProcess(process.hProcess, &exit_code);
            result = exit_code == 0 ? S_OK : HRESULT_FROM_WIN32(ERROR_GEN_FAILURE);
            break;
        }
        if (wait == WAIT_FAILED)
        {
            result = HRESULT_FROM_WIN32(GetLastError());
            break;
        }
        if (cancel != nullptr && cancel->load())
        {
            TerminateProcess(process.hProcess, ERROR_CANCELLED);
            WaitForSingleObject(process.hProcess, 2000);
            result = HRESULT_FROM_WIN32(ERROR_CANCELLED);
            break;
        }
        PostMessageW(window, kProgressMessage, 0, 1);
    }

    CloseHandle(process.hProcess);
    return result;
}
}

CloudOSNativeFileOperationsWindow::CloudOSNativeFileOperationsWindow(
    HINSTANCE instance,
    std::wstring initial_destination)
    : instance_(instance),
      destination_(std::move(initial_destination))
{
}

CloudOSNativeFileOperationsWindow::~CloudOSNativeFileOperationsWindow()
{
    cancel_requested_.store(true);
    if (worker_.joinable())
    {
        worker_.join();
    }
    if (font_ != nullptr)
    {
        DeleteObject(font_);
        font_ = nullptr;
    }
}

void CloudOSNativeFileOperationsWindow::Open(
    HINSTANCE instance,
    const std::wstring& initial_destination)
{
    auto* window = new (std::nothrow) CloudOSNativeFileOperationsWindow(instance, initial_destination);
    if (window == nullptr || !window->Create())
    {
        delete window;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Operacoes de Arquivos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
    }
}

bool CloudOSNativeFileOperationsWindow::Create()
{
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = &CloudOSNativeFileOperationsWindow::WindowProcedure;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    window_class.lpszClassName = kClassName;
    if (RegisterClassExW(&window_class) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    {
        return false;
    }

    window_ = CreateWindowExW(
        WS_EX_APPWINDOW,
        kClassName,
        L"Operacoes de Arquivos - CloudOS",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        980,
        650,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr)
    {
        return false;
    }

    font_ = CreateFontW(
        -16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");

    source_list_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEWW,
        L"",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSourceListId)),
        instance_, nullptr);
    destination_edit_ = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        destination_.c_str(),
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDestinationEditId)),
        instance_, nullptr);

    auto create_button = [this](const wchar_t* text, int id)
    {
        return CreateWindowW(
            L"BUTTON",
            text,
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
            0, 0, 0, 0,
            window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
            instance_,
            nullptr);
    };

    add_files_button_ = create_button(L"Adicionar arquivos", kAddFilesId);
    add_folder_button_ = create_button(L"Adicionar pasta", kAddFolderId);
    remove_button_ = create_button(L"Remover", kRemoveId);
    destination_button_ = create_button(L"Destino...", kDestinationId);
    copy_button_ = create_button(L"Copiar", kCopyId);
    move_button_ = create_button(L"Mover", kMoveId);
    zip_button_ = create_button(L"Compactar ZIP", kZipId);
    extract_button_ = create_button(L"Extrair ZIP", kExtractId);
    cancel_button_ = create_button(L"Cancelar", kCancelId);

    progress_ = CreateWindowExW(
        0,
        PROGRESS_CLASSW,
        L"",
        WS_CHILD | WS_VISIBLE | PBS_SMOOTH,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kProgressId)),
        instance_, nullptr);
    status_ = CreateWindowW(
        L"STATIC",
        L"Adicione arquivos ou pastas para comecar.",
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        0, 0, 0, 0,
        window_,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStatusId)),
        instance_, nullptr);

    for (HWND child : {
             source_list_, destination_edit_, add_files_button_, add_folder_button_, remove_button_,
             destination_button_, copy_button_, move_button_, zip_button_, extract_button_, cancel_button_,
             progress_, status_})
    {
        if (child == nullptr)
        {
            DestroyWindow(window_);
            window_ = nullptr;
            return false;
        }
        SetFont(child, font_);
    }

    ListView_SetExtendedListViewStyle(
        source_list_,
        LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    LVCOLUMNW name_column{};
    name_column.mask = LVCF_TEXT | LVCF_WIDTH;
    name_column.pszText = const_cast<LPWSTR>(L"Item");
    name_column.cx = 260;
    ListView_InsertColumn(source_list_, 0, &name_column);
    LVCOLUMNW path_column{};
    path_column.mask = LVCF_TEXT | LVCF_WIDTH;
    path_column.pszText = const_cast<LPWSTR>(L"Caminho");
    path_column.cx = 620;
    ListView_InsertColumn(source_list_, 1, &path_column);

    SendMessageW(progress_, PBM_SETRANGE, 0, MAKELPARAM(0, 100));
    SendMessageW(progress_, PBM_SETPOS, 0, 0);
    EnableWindow(cancel_button_, FALSE);

    DarkWindow(window_);
    Layout();
    self_delete_ = true;
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
    return true;
}

void CloudOSNativeFileOperationsWindow::Layout()
{
    if (window_ == nullptr)
    {
        return;
    }
    RECT client{};
    GetClientRect(window_, &client);
    const UINT dpi = GetDpiForWindow(window_);
    const int margin = Scale(14, dpi);
    const int gap = Scale(8, dpi);
    const int button_height = Scale(34, dpi);
    const int width = std::max<int>(1, static_cast<int>(client.right - client.left));
    const int height = std::max<int>(1, static_cast<int>(client.bottom - client.top));

    int x = margin;
    const int top = margin;
    const int small = Scale(128, dpi);
    MoveWindow(add_files_button_, x, top, small, button_height, TRUE); x += small + gap;
    MoveWindow(add_folder_button_, x, top, small, button_height, TRUE); x += small + gap;
    MoveWindow(remove_button_, x, top, Scale(92, dpi), button_height, TRUE);

    const int list_top = top + button_height + gap;
    const int destination_height = Scale(38, dpi);
    const int operations_height = Scale(42, dpi);
    const int progress_height = Scale(22, dpi);
    const int status_height = Scale(28, dpi);
    const int bottom_reserved = destination_height + operations_height + progress_height + status_height + gap * 5;
    const int list_height = std::max(120, height - list_top - margin - bottom_reserved);
    MoveWindow(source_list_, margin, list_top, width - margin * 2, list_height, TRUE);

    int y = list_top + list_height + gap;
    MoveWindow(destination_edit_, margin, y, width - margin * 3 - Scale(110, dpi), destination_height, TRUE);
    MoveWindow(destination_button_, width - margin - Scale(110, dpi), y, Scale(110, dpi), destination_height, TRUE);

    y += destination_height + gap;
    x = margin;
    const int op_width = Scale(126, dpi);
    MoveWindow(copy_button_, x, y, op_width, operations_height, TRUE); x += op_width + gap;
    MoveWindow(move_button_, x, y, op_width, operations_height, TRUE); x += op_width + gap;
    MoveWindow(zip_button_, x, y, op_width, operations_height, TRUE); x += op_width + gap;
    MoveWindow(extract_button_, x, y, op_width, operations_height, TRUE);
    MoveWindow(cancel_button_, width - margin - Scale(110, dpi), y, Scale(110, dpi), operations_height, TRUE);

    y += operations_height + gap;
    MoveWindow(progress_, margin, y, width - margin * 2, progress_height, TRUE);
    y += progress_height + gap;
    MoveWindow(status_, margin, y, width - margin * 2, status_height, TRUE);
}

void CloudOSNativeFileOperationsWindow::RefreshSourceList()
{
    ListView_DeleteAllItems(source_list_);
    for (std::size_t index = 0; index < sources_.size(); ++index)
    {
        std::wstring label = FileLabel(sources_[index]);
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = static_cast<int>(index);
        item.pszText = label.data();
        ListView_InsertItem(source_list_, &item);
        ListView_SetItemText(source_list_, static_cast<int>(index), 1, sources_[index].data());
    }
}

void CloudOSNativeFileOperationsWindow::AddFiles()
{
    const auto picked = PickFiles(window_);
    for (const auto& path : picked)
    {
        if (std::find_if(
                sources_.begin(), sources_.end(),
                [&path](const std::wstring& existing)
                {
                    return _wcsicmp(existing.c_str(), path.c_str()) == 0;
                }) == sources_.end())
        {
            sources_.push_back(path);
        }
    }
    RefreshSourceList();
}

void CloudOSNativeFileOperationsWindow::AddFolder()
{
    std::wstring folder;
    if (PickFolder(window_, &folder))
    {
        sources_.push_back(std::move(folder));
        RefreshSourceList();
    }
}

void CloudOSNativeFileOperationsWindow::RemoveSelection()
{
    std::vector<int> selected;
    int row = -1;
    while ((row = ListView_GetNextItem(source_list_, row, LVNI_SELECTED)) >= 0)
    {
        selected.push_back(row);
    }
    std::sort(selected.begin(), selected.end(), std::greater<int>());
    for (const int index : selected)
    {
        if (index >= 0 && index < static_cast<int>(sources_.size()))
        {
            sources_.erase(sources_.begin() + index);
        }
    }
    RefreshSourceList();
}

void CloudOSNativeFileOperationsWindow::PickDestination()
{
    std::wstring folder;
    if (PickFolder(window_, &folder))
    {
        destination_ = std::move(folder);
        SetWindowTextW(destination_edit_, destination_.c_str());
    }
}

std::wstring CloudOSNativeFileOperationsWindow::ChooseZipOutput()
{
    IFileSaveDialog* dialog = nullptr;
    if (FAILED(CoCreateInstance(
            CLSID_FileSaveDialog,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&dialog))) ||
        dialog == nullptr)
    {
        return {};
    }

    COMDLG_FILTERSPEC filter{L"Arquivo ZIP", L"*.zip"};
    dialog->SetFileTypes(1, &filter);
    dialog->SetDefaultExtension(L"zip");
    dialog->SetFileName(L"CloudOS Archive.zip");

    std::wstring result;
    if (SUCCEEDED(dialog->Show(window_)))
    {
        IShellItem* item = nullptr;
        if (SUCCEEDED(dialog->GetResult(&item)) && item != nullptr)
        {
            result = ShellItemPath(item);
            item->Release();
        }
    }
    dialog->Release();
    return result;
}

std::wstring CloudOSNativeFileOperationsWindow::ChooseExtractionFolder()
{
    std::wstring folder;
    (void)PickFolder(window_, &folder);
    return folder;
}

void CloudOSNativeFileOperationsWindow::StartOperation(OperationKind kind)
{
    if (running_ || sources_.empty())
    {
        return;
    }

    std::wstring archive_path;
    if (kind == OperationKind::Copy || kind == OperationKind::Move)
    {
        if (destination_.empty())
        {
            PickDestination();
        }
        if (destination_.empty())
        {
            return;
        }
    }
    else if (kind == OperationKind::CreateZip)
    {
        archive_path = ChooseZipOutput();
        if (archive_path.empty())
        {
            return;
        }
    }
    else if (kind == OperationKind::ExtractZip)
    {
        if (sources_.size() != 1 || !IsZip(sources_.front()))
        {
            MessageBoxW(
                window_,
                L"Para extrair, mantenha exatamente um arquivo .zip na lista.",
                L"CloudOS",
                MB_OK | MB_ICONINFORMATION);
            return;
        }
        destination_ = ChooseExtractionFolder();
        if (destination_.empty())
        {
            return;
        }
        SetWindowTextW(destination_edit_, destination_.c_str());
        archive_path = sources_.front();
    }

    if (worker_.joinable())
    {
        worker_.join();
    }
    cancel_requested_.store(false);
    const bool marquee = kind == OperationKind::CreateZip || kind == OperationKind::ExtractZip;
    SetRunning(true, marquee);
    const std::vector<std::wstring> sources = sources_;
    const std::wstring destination = destination_;
    worker_ = std::thread(
        [this, kind, sources, destination, archive_path]()
        {
            WorkerMain(kind, sources, destination, archive_path);
        });
}

void CloudOSNativeFileOperationsWindow::CancelOperation()
{
    if (running_)
    {
        cancel_requested_.store(true);
        SetWindowTextW(status_, L"Cancelamento solicitado...");
    }
}

void CloudOSNativeFileOperationsWindow::SetRunning(bool running, bool marquee)
{
    running_ = running;
    for (HWND control : {
             add_files_button_, add_folder_button_, remove_button_, destination_button_,
             copy_button_, move_button_, zip_button_, extract_button_})
    {
        EnableWindow(control, running ? FALSE : TRUE);
    }
    EnableWindow(cancel_button_, running ? TRUE : FALSE);
    SendMessageW(progress_, PBM_SETMARQUEE, running && marquee ? TRUE : FALSE, 40);
    if (!marquee)
    {
        SendMessageW(progress_, PBM_SETPOS, running ? 0 : 100, 0);
    }
}

void CloudOSNativeFileOperationsWindow::FinishOperation(bool success, HRESULT result)
{
    if (worker_.joinable())
    {
        worker_.join();
    }
    SetRunning(false, false);
    cancel_requested_.store(false);

    if (result == HRESULT_FROM_WIN32(ERROR_CANCELLED))
    {
        SetWindowTextW(status_, L"Operacao cancelada.");
        return;
    }
    if (success)
    {
        SetWindowTextW(status_, L"Operacao concluida.");
        CloudOSNativeNotificationCenter::Post(
            L"Operacao de arquivos concluida",
            L"A operacao solicitada terminou com sucesso.");
        SendMessageW(progress_, PBM_SETPOS, 100, 0);
    }
    else
    {
        wchar_t message[160]{};
        swprintf_s(message, L"Falha na operacao (HRESULT 0x%08X).", static_cast<unsigned>(result));
        SetWindowTextW(status_, message);
        MessageBoxW(window_, message, L"Operacoes de Arquivos - CloudOS", MB_OK | MB_ICONERROR);
    }
}

void CloudOSNativeFileOperationsWindow::WorkerMain(
    OperationKind kind,
    std::vector<std::wstring> sources,
    std::wstring destination,
    std::wstring archive_path)
{
    const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitialize = SUCCEEDED(com_result);

    HRESULT result = E_FAIL;
    if (kind == OperationKind::Copy || kind == OperationKind::Move)
    {
        result = RunShellOperation(
            window_,
            sources,
            destination,
            kind == OperationKind::Move,
            &cancel_requested_);
    }
    else if (kind == OperationKind::CreateZip)
    {
        auto* status = new (std::nothrow) std::wstring(L"Compactando com o tar do Windows...");
        if (status != nullptr && !PostMessageW(window_, kStatusMessage, 0, reinterpret_cast<LPARAM>(status)))
        {
            delete status;
        }

        std::filesystem::path common_parent;
        bool common = !sources.empty();
        if (common)
        {
            common_parent = std::filesystem::path(sources.front()).parent_path();
            for (const auto& source : sources)
            {
                if (_wcsicmp(
                        common_parent.c_str(),
                        std::filesystem::path(source).parent_path().c_str()) != 0)
                {
                    common = false;
                    break;
                }
            }
        }

        std::wstring command = L"tar.exe -a -c -f ";
        command += QuoteArgument(archive_path);
        for (const auto& source : sources)
        {
            command += L" ";
            command += QuoteArgument(
                common
                    ? std::filesystem::path(source).filename().wstring()
                    : source);
        }
        result = RunTar(
            window_,
            command,
            common ? common_parent.wstring() : std::wstring{},
            &cancel_requested_);
    }
    else if (kind == OperationKind::ExtractZip)
    {
        auto* status = new (std::nothrow) std::wstring(L"Extraindo ZIP com o tar do Windows...");
        if (status != nullptr && !PostMessageW(window_, kStatusMessage, 0, reinterpret_cast<LPARAM>(status)))
        {
            delete status;
        }
        std::wstring command = L"tar.exe -xf ";
        command += QuoteArgument(archive_path);
        command += L" -C ";
        command += QuoteArgument(destination);
        result = RunTar(window_, command, {}, &cancel_requested_);
    }

    if (uninitialize)
    {
        CoUninitialize();
    }

    PostMessageW(
        window_,
        kFinishedMessage,
        SUCCEEDED(result) ? TRUE : FALSE,
        static_cast<LPARAM>(result));
}

LRESULT CloudOSNativeFileOperationsWindow::HandleMessage(
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
    case WM_COMMAND:
        switch (LOWORD(w_param))
        {
        case kAddFilesId: AddFiles(); return 0;
        case kAddFolderId: AddFolder(); return 0;
        case kRemoveId: RemoveSelection(); return 0;
        case kDestinationId: PickDestination(); return 0;
        case kCopyId: StartOperation(OperationKind::Copy); return 0;
        case kMoveId: StartOperation(OperationKind::Move); return 0;
        case kZipId: StartOperation(OperationKind::CreateZip); return 0;
        case kExtractId: StartOperation(OperationKind::ExtractZip); return 0;
        case kCancelId: CancelOperation(); return 0;
        default: break;
        }
        break;
    case kProgressMessage:
        if (l_param == 0)
        {
            SendMessageW(progress_, PBM_SETPOS, static_cast<int>(w_param), 0);
        }
        return 0;
    case kStatusMessage:
    {
        auto* text = reinterpret_cast<std::wstring*>(l_param);
        if (text != nullptr)
        {
            SetWindowTextW(status_, text->c_str());
            delete text;
        }
        return 0;
    }
    case kFinishedMessage:
        FinishOperation(w_param != FALSE, static_cast<HRESULT>(l_param));
        return 0;
    case WM_CLOSE:
        if (running_)
        {
            if (MessageBoxW(
                    window_,
                    L"Existe uma operacao em andamento. Cancelar e fechar?",
                    L"CloudOS",
                    MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
            {
                return 0;
            }
            cancel_requested_.store(true);
        }
        DestroyWindow(window_);
        return 0;
    case WM_NCDESTROY:
    {
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        window_ = nullptr;
        const LRESULT result = DefWindowProcW(window, message, w_param, l_param);
        const bool remove = self_delete_;
        self_delete_ = false;
        if (remove)
        {
            delete this;
        }
        return result;
    }
    default:
        break;
    }
    return DefWindowProcW(window, message, w_param, l_param);
}

LRESULT CALLBACK CloudOSNativeFileOperationsWindow::WindowProcedure(
    HWND window,
    UINT message,
    WPARAM w_param,
    LPARAM l_param)
{
    CloudOSNativeFileOperationsWindow* self = nullptr;
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(l_param);
        self = static_cast<CloudOSNativeFileOperationsWindow*>(create->lpCreateParams);
        if (self != nullptr)
        {
            self->window_ = window;
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
    }
    else
    {
        self = reinterpret_cast<CloudOSNativeFileOperationsWindow*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    }

    return self != nullptr
        ? self->HandleMessage(window, message, w_param, l_param)
        : DefWindowProcW(window, message, w_param, l_param);
}
} // namespace CloudOS
