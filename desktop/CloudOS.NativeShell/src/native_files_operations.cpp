#include "native_files_window.h"
#include "native_files_internal.h"

#include "native_cloudos_drive.h"
#include "native_cloudos_trash_window.h"
#include "native_shell_platform.h"
#include "native_theme.h"

#include <ShlObj.h>
#include <Shellapi.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <new>
#include <string_view>
#include <utility>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

void CloudOSNativeFilesWindow::PopulateCustomList()
{
    entries_.clear();
    ListView_DeleteAllItems(list_);
    if (IsCurrentCloudOSDrive()) PopulateCloudOSDriveList();
    else PopulateFallbackList();
    RenderCustomList();
    UpdateStatus();
}

void CloudOSNativeFilesWindow::PopulateCloudOSDriveList()
{
    std::vector<std::wstring> segments;
    std::wstring error;
    if (!CurrentDriveSegments(&segments, &error)) return;
    std::vector<CloudOS::CloudOSDriveEntry> items;
    if (!CloudOS::NativeCloudOSDrive::List(segments, &items, &error))
    {
        ShowError(window_, L"Falha ao listar CloudOS Drive.", error);
        return;
    }
    for (const auto& source : items)
    {
        Entry entry{};
        entry.name = source.name;
        entry.full_path = JoinPath(current_path_, source.name);
        entry.directory = source.directory;
        entry.reparse_point = source.reparse_point;
        entry.size = static_cast<ULONGLONG>(source.size);
        entry.modified = source.modified;
        entry.image_index = ShellIconIndex(entry.full_path, entry.directory, entry.reparse_point);
        entries_.push_back(std::move(entry));
    }
}

void CloudOSNativeFilesWindow::PopulateFallbackList()
{
    const std::wstring pattern = JoinPath(current_path_, L"*");
    WIN32_FIND_DATAW data{};
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return;
    do
    {
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) continue;
        Entry entry{};
        entry.name = data.cFileName;
        entry.full_path = JoinPath(current_path_, entry.name);
        entry.directory = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        entry.reparse_point = (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        entry.size = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32u) | data.nFileSizeLow;
        entry.modified = data.ftLastWriteTime;
        entry.image_index = ShellIconIndex(entry.full_path, entry.directory, false);
        entries_.push_back(std::move(entry));
    } while (FindNextFileW(find, &data));
    FindClose(find);
    std::sort(entries_.begin(), entries_.end(), [](const Entry& a, const Entry& b)
    {
        if (a.directory != b.directory) return a.directory > b.directory;
        return _wcsicmp(a.name.c_str(), b.name.c_str()) < 0;
    });
}

void CloudOSNativeFilesWindow::RenderCustomList()
{
    for (std::size_t index = 0; index < entries_.size(); ++index)
    {
        Entry& entry = entries_[index];
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        if (entry.image_index >= 0)
        {
            item.mask |= LVIF_IMAGE;
            item.iImage = entry.image_index;
        }
        item.iItem = static_cast<int>(index);
        item.pszText = entry.name.data();
        ListView_InsertItem(list_, &item);
    }
}

void CloudOSNativeFilesWindow::ActivateCustomSelection()
{
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= entries_.size()) return;
    Entry& entry = entries_[static_cast<std::size_t>(row)];
    if (IsCurrentCloudOSDrive() && entry.reparse_point)
    {
        ShowError(window_, L"Links e pontos de reparo nao sao abertos pelo CloudOS Drive.");
        return;
    }
    if (entry.directory)
    {
        Navigate(entry.full_path);
        return;
    }
    HINSTANCE result = ShellExecuteW(nullptr, L"open", entry.full_path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(result) <= 32)
    {
        ShowError(window_, L"O Windows nao encontrou um aplicativo para abrir este arquivo.");
    }
}

void CloudOSNativeFilesWindow::CreateNewFolder()
{
    std::wstring name = L"Nova pasta";
    unsigned suffix = 2;
    if (IsCurrentCloudOSDrive())
    {
        std::vector<std::wstring> parent;
        std::wstring error;
        if (!CurrentDriveSegments(&parent, &error))
        {
            ShowError(window_, L"Nao foi possivel criar a pasta.", error);
            return;
        }
        for (;;)
        {
            auto candidate = parent;
            candidate.push_back(name);
            const std::wstring path = CloudOS::NativeCloudOSDrive::AbsolutePath(candidate);
            if (path.empty() || GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) break;
            name = L"Nova pasta (" + std::to_wstring(suffix++) + L")";
        }
        auto target = parent;
        target.push_back(name);
        if (!CloudOS::NativeCloudOSDrive::Mkdir(target, &error))
        {
            ShowError(window_, L"Nao foi possivel criar a pasta no CloudOS Drive.", error);
            return;
        }
        PopulateCustomList();
    }
    else
    {
        if (!DirectoryExists(current_path_))
        {
            ShowError(window_, L"Este local nao aceita criacao direta de pastas.");
            return;
        }
        std::wstring target = JoinPath(current_path_, name);
        while (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES)
        {
            name = L"Nova pasta (" + std::to_wstring(suffix++) + L")";
            target = JoinPath(current_path_, name);
        }
        if (!CreateDirectoryW(target.c_str(), nullptr))
        {
            ShowError(window_, L"Nao foi possivel criar a pasta neste local.");
            return;
        }
        if (content_mode_ == ContentMode::Shell && shell_available_)
        {
            (void)shell_view_.Refresh();
            return;
        }
        PopulateCustomList();
    }
}

void CloudOSNativeFilesWindow::BeginRename()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        if (!shell_view_.BeginRenameSelection())
        {
            ShowError(window_, L"Selecione um item renomeavel no Windows Shell.");
        }
        return;
    }
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row >= 0) ListView_EditLabel(list_, row);
}

bool CloudOSNativeFilesWindow::CommitRename(int row, const wchar_t* new_name)
{
    if (row < 0 || static_cast<std::size_t>(row) >= entries_.size() || !IsSafeLeafName(new_name)) return false;
    Entry& entry = entries_[static_cast<std::size_t>(row)];
    if (_wcsicmp(entry.name.c_str(), new_name) == 0) return true;
    if (IsCurrentCloudOSDrive())
    {
        if (entry.reparse_point) return false;
        std::vector<std::wstring> parent;
        std::wstring error;
        if (!CurrentDriveSegments(&parent, &error)) return false;
        auto source = parent;
        source.push_back(entry.name);
        auto destination = parent;
        destination.emplace_back(new_name);
        if (!CloudOS::NativeCloudOSDrive::Move(source, destination, &error))
        {
            ShowError(window_, L"Nao foi possivel renomear o item.", error);
            return false;
        }
    }
    else
    {
        const std::wstring destination = JoinPath(current_path_, new_name);
        if (!MoveFileW(entry.full_path.c_str(), destination.c_str())) return false;
    }
    entry.name = new_name;
    entry.full_path = JoinPath(current_path_, new_name);
    return true;
}

void CloudOSNativeFilesWindow::DeleteSelection()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        if (!shell_view_.DeleteSelection())
        {
            ShowError(window_, L"Selecione um item que possa ser excluido pelo Windows Shell.");
        }
        return;
    }
    const int row = ListView_GetNextItem(list_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= entries_.size()) return;
    const Entry& entry = entries_[static_cast<std::size_t>(row)];

    if (IsCurrentCloudOSDrive())
    {
        if (entry.reparse_point)
        {
            ShowError(window_, L"Exclusao de link ou ponto de reparo bloqueada pelo CloudOS Drive.");
            return;
        }
        if (MessageBoxW(
                window_,
                L"Mover o item para a Lixeira do CloudOS Drive?",
                L"CloudOS Drive",
                MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
        {
            return;
        }
        std::vector<std::wstring> segments;
        std::wstring error;
        if (!CurrentDriveSegments(&segments, &error)) return;
        segments.push_back(entry.name);
        if (!CloudOS::NativeCloudOSDrive::Trash(segments, nullptr, &error))
        {
            ShowError(window_, L"Nao foi possivel mover o item para a lixeira.", error);
            return;
        }
        PopulateCustomList();
        return;
    }

    std::wstring double_null = entry.full_path;
    double_null.push_back(L'\0');
    double_null.push_back(L'\0');
    SHFILEOPSTRUCTW operation{};
    operation.hwnd = window_;
    operation.wFunc = FO_DELETE;
    operation.pFrom = double_null.c_str();
    operation.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMMKDIR | FOF_NOERRORUI;
    if (SHFileOperationW(&operation) != 0 || operation.fAnyOperationsAborted)
    {
        ShowError(window_, L"Nao foi possivel excluir o item.");
    }
    PopulateCustomList();
}

void CloudOSNativeFilesWindow::Refresh()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        (void)shell_view_.Refresh();
    }
    else
    {
        PopulateCustomList();
    }
}

bool CloudOSNativeFilesWindow::IsCurrentCloudOSDrive() const
{
    return content_mode_ == ContentMode::CloudOSDrive && CloudOS::NativeCloudOSDrive::IsPathInside(current_path_);
}

bool CloudOSNativeFilesWindow::CurrentDriveSegments(std::vector<std::wstring>* segments, std::wstring* error) const
{
    return CloudOS::NativeCloudOSDrive::SegmentsFromAbsolutePath(current_path_, segments, error);
}
