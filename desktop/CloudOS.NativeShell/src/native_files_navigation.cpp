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

void CloudOSNativeFilesWindow::Navigate(const std::wstring& path)
{
    if (path.empty()) return;
    if (CloudOS::NativeCloudOSDrive::IsPathInside(path))
    {
        NavigateCloudOSDrive(path);
        return;
    }
    if (!NavigateShell(path))
    {
        NavigateFallback(path);
    }
}

bool CloudOSNativeFilesWindow::NavigateShell(const std::wstring& path)
{
    if (!shell_available_ || !shell_view_.Navigate(path)) return false;
    content_mode_ = ContentMode::Shell;
    current_path_ = path;
    ShowWindow(list_, SW_HIDE);
    ShowWindow(shell_host_, SW_SHOW);
    SetWindowTextW(window_, L"Arquivos - CloudOS");
    SetWindowTextW(path_edit_, path.c_str());
    UpdateStatus();
    SelectSidebarForCurrentPath();
    return true;
}

void CloudOSNativeFilesWindow::NavigateCloudOSDrive(const std::wstring& path)
{
    std::vector<std::wstring> segments;
    std::wstring error;
    if (!CloudOS::NativeCloudOSDrive::SegmentsFromAbsolutePath(path, &segments, &error))
    {
        ShowError(window_, L"Caminho bloqueado pelo CloudOS Drive.", error);
        return;
    }
    std::vector<CloudOS::CloudOSDriveEntry> probe;
    if (!CloudOS::NativeCloudOSDrive::List(segments, &probe, &error))
    {
        ShowError(window_, L"Pasta do CloudOS Drive indisponivel.", error);
        return;
    }

    current_path_ = CloudOS::NativeCloudOSDrive::AbsolutePath(segments);
    content_mode_ = ContentMode::CloudOSDrive;
    ShowWindow(shell_host_, SW_HIDE);
    ShowWindow(list_, SW_SHOW);
    SetWindowTextW(window_, L"CloudOS Drive - Arquivos");
    SetWindowTextW(path_edit_, current_path_.c_str());
    PopulateCustomList();
    SelectSidebarForCurrentPath();
}

void CloudOSNativeFilesWindow::NavigateFallback(const std::wstring& path)
{
    if (!IsWslRootPath(path) && !DirectoryExists(path))
    {
        ShowError(window_, L"Pasta nao encontrada ou sem acesso.");
        return;
    }
    current_path_ = path;
    content_mode_ = ContentMode::FallbackFileSystem;
    ShowWindow(shell_host_, SW_HIDE);
    ShowWindow(list_, SW_SHOW);
    SetWindowTextW(window_, L"Arquivos - CloudOS");
    SetWindowTextW(path_edit_, path.c_str());
    PopulateCustomList();
    SelectSidebarForCurrentPath();
}

void CloudOSNativeFilesWindow::NavigateBack()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        (void)shell_view_.NavigateBack();
    }
}

void CloudOSNativeFilesWindow::NavigateForward()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        (void)shell_view_.NavigateForward();
    }
}

void CloudOSNativeFilesWindow::NavigateParent()
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
    {
        (void)shell_view_.NavigateParent();
        return;
    }
    if (IsCurrentCloudOSDrive())
    {
        std::vector<std::wstring> segments;
        std::wstring error;
        if (!CurrentDriveSegments(&segments, &error))
        {
            ShowError(window_, L"Nao foi possivel resolver o caminho atual.", error);
            return;
        }
        if (!segments.empty()) segments.pop_back();
        Navigate(CloudOS::NativeCloudOSDrive::AbsolutePath(segments));
        return;
    }
    const std::wstring parent = ParentPath(current_path_);
    if (!parent.empty() && _wcsicmp(parent.c_str(), current_path_.c_str()) != 0)
    {
        Navigate(parent);
    }
}

void CloudOSNativeFilesWindow::OnShellNavigationComplete(const std::wstring& path)
{
    if (path.empty()) return;
    if (CloudOS::NativeCloudOSDrive::IsPathInside(path))
    {
        NavigateCloudOSDrive(path);
        return;
    }
    current_path_ = path;
    content_mode_ = ContentMode::Shell;
    SetWindowTextW(path_edit_, path.c_str());
    ShowWindow(list_, SW_HIDE);
    ShowWindow(shell_host_, SW_SHOW);
    UpdateStatus();
    SelectSidebarForCurrentPath();
}

void CloudOSNativeFilesWindow::SelectSidebarForCurrentPath()
{
    int best = -1;
    std::size_t best_length = 0;
    for (std::size_t index = 0; index < sidebar_items_.size(); ++index)
    {
        const SidebarItem& item = sidebar_items_[index];
        if (!item.opens_trash && StartsWithInsensitive(current_path_, item.path) && item.path.size() >= best_length)
        {
            best = static_cast<int>(index);
            best_length = item.path.size();
        }
    }
    sidebar_syncing_ = true;
    for (int row = 0; row < ListView_GetItemCount(sidebar_); ++row)
    {
        ListView_SetItemState(
            sidebar_, row,
            row == best ? LVIS_SELECTED | LVIS_FOCUSED : 0,
            LVIS_SELECTED | LVIS_FOCUSED);
    }
    sidebar_syncing_ = false;
}

void CloudOSNativeFilesWindow::ActivateSidebarSelection()
{
    if (sidebar_syncing_) return;
    const int row = ListView_GetNextItem(sidebar_, -1, LVNI_SELECTED);
    if (row < 0 || static_cast<std::size_t>(row) >= sidebar_items_.size()) return;
    const SidebarItem& item = sidebar_items_[static_cast<std::size_t>(row)];
    if (item.opens_trash)
    {
        CloudOS::CloudOSNativeDriveTrashWindow::Open(instance_);
        return;
    }
    Navigate(item.path);
}
