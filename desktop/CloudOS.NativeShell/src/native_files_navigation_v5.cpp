#include "native_files_window.h"
#include "native_files_internal.h"

#include "native_cloudos_drive.h"
#include "native_cloudos_trash_window.h"
#include "native_file_operations_window.h"
#include "native_files_search_window.h"
#include "native_shell_platform.h"

#include <ShlObj.h>

#include <algorithm>
#include <utility>

namespace
{
constexpr std::size_t kMaximumHistoryEntries = 64;
}

void CloudOSNativeFilesWindow::LoadV5State()
{
    persisted_state_ = CloudOS::NativeFilesStateStore::Load();
    preview_visible_ = persisted_state_.preview_visible;
    tab_states_.clear();

    if (initial_path_explicit_)
    {
        TabState tab{};
        tab.path = current_path_;
        tab_states_.push_back(std::move(tab));
        active_tab_ = 0;
        return;
    }

    for (const auto& path : persisted_state_.tabs)
    {
        if (path.empty()) continue;
        TabState tab{};
        tab.path = path;
        tab_states_.push_back(std::move(tab));
        if (tab_states_.size() >= CloudOS::NativeFilesStateStore::MaximumTabs) break;
    }

    if (tab_states_.empty())
    {
        TabState tab{};
        tab.path = current_path_;
        tab_states_.push_back(std::move(tab));
        active_tab_ = 0;
    }
    else
    {
        active_tab_ = std::min(persisted_state_.active_tab, tab_states_.size() - 1);
        current_path_ = tab_states_[active_tab_].path;
    }
}

void CloudOSNativeFilesWindow::PersistV5State() noexcept
{
    persisted_state_.tabs.clear();
    persisted_state_.tabs.reserve(tab_states_.size());
    for (const auto& tab : tab_states_)
    {
        if (!tab.path.empty()) persisted_state_.tabs.push_back(tab.path);
    }
    persisted_state_.active_tab = persisted_state_.tabs.empty()
        ? 0
        : std::min(active_tab_, persisted_state_.tabs.size() - 1);
    persisted_state_.preview_visible = preview_visible_;
    (void)CloudOS::NativeFilesStateStore::Save(persisted_state_);
}

void CloudOSNativeFilesWindow::SyncTabStrip()
{
    if (tab_strip_ == nullptr) return;
    TabCtrl_DeleteAllItems(tab_strip_);
    for (std::size_t index = 0; index < tab_states_.size(); ++index)
    {
        std::wstring label = LeafName(tab_states_[index].path);
        if (label.empty()) label = tab_states_[index].path;
        if (label.size() > 28)
        {
            label.resize(25);
            label += L"…";
        }
        TCITEMW item{};
        item.mask = TCIF_TEXT;
        item.pszText = label.data();
        TabCtrl_InsertItem(tab_strip_, static_cast<int>(index), &item);
    }
    if (!tab_states_.empty())
        TabCtrl_SetCurSel(tab_strip_, static_cast<int>(std::min(active_tab_, tab_states_.size() - 1)));
}

void CloudOSNativeFilesWindow::NewTab()
{
    if (tab_states_.size() >= CloudOS::NativeFilesStateStore::MaximumTabs)
    {
        ShowError(window_, L"O limite de 24 abas foi atingido.");
        return;
    }
    TabState tab{};
    tab.path = current_path_.empty() ? KnownFolderPath(FOLDERID_Profile) : current_path_;
    if (tab.path.empty()) tab.path = CloudOS::NativeShellPlatform::WindowsVolumeRoot();
    if (tab.path.empty()) return;
    tab_states_.push_back(std::move(tab));
    active_tab_ = tab_states_.size() - 1;
    suppressed_history_target_ = tab_states_[active_tab_].path;
    SyncTabStrip();
    PersistV5State();
    Navigate(tab_states_[active_tab_].path);
}

void CloudOSNativeFilesWindow::CloseActiveTab()
{
    if (tab_states_.size() <= 1)
    {
        MessageBeep(MB_ICONINFORMATION);
        return;
    }
    active_tab_ = std::min(active_tab_, tab_states_.size() - 1);
    tab_states_.erase(tab_states_.begin() + static_cast<std::ptrdiff_t>(active_tab_));
    if (active_tab_ >= tab_states_.size()) active_tab_ = tab_states_.size() - 1;
    const std::wstring target = tab_states_[active_tab_].path;
    suppressed_history_target_ = target;
    SyncTabStrip();
    PersistV5State();
    Navigate(target);
}

void CloudOSNativeFilesWindow::SelectTab(std::size_t index)
{
    if (index >= tab_states_.size() || index == active_tab_) return;
    active_tab_ = index;
    const std::wstring target = tab_states_[active_tab_].path;
    suppressed_history_target_ = target;
    SyncTabStrip();
    PersistV5State();
    Navigate(target);
}

void CloudOSNativeFilesWindow::CommitNavigatedPath(const std::wstring& path)
{
    if (path.empty()) return;
    if (tab_states_.empty())
    {
        TabState tab{};
        tab.path = path;
        tab_states_.push_back(std::move(tab));
        active_tab_ = 0;
    }
    active_tab_ = std::min(active_tab_, tab_states_.size() - 1);
    TabState& tab = tab_states_[active_tab_];

    const bool suppressed = !suppressed_history_target_.empty() &&
        PathsEqual(suppressed_history_target_, path);
    if (!suppressed && !tab.path.empty() && !PathsEqual(tab.path, path))
    {
        if (tab.back.empty() || !PathsEqual(tab.back.back(), tab.path))
            tab.back.push_back(tab.path);
        if (tab.back.size() > kMaximumHistoryEntries) tab.back.erase(tab.back.begin());
        tab.forward.clear();
    }

    tab.path = path;
    current_path_ = path;
    suppressed_history_target_.clear();
    SetWindowTextW(path_edit_, current_path_.c_str());
    const bool favorite = CloudOS::NativeFilesStateStore::ContainsFavorite(persisted_state_, current_path_);
    SetWindowTextW(favorite_button_, favorite ? L"★" : L"☆");
    SyncTabStrip();
    PersistV5State();
    SelectSidebarForCurrentPath();
    UpdateStatus();
}

void CloudOSNativeFilesWindow::ToggleFavorite()
{
    if (current_path_.empty()) return;
    const bool exists = CloudOS::NativeFilesStateStore::ContainsFavorite(persisted_state_, current_path_);
    bool changed = false;
    if (exists)
        changed = CloudOS::NativeFilesStateStore::RemoveFavorite(&persisted_state_, current_path_);
    else
        changed = CloudOS::NativeFilesStateStore::AddFavorite(&persisted_state_, current_path_);
    if (!changed)
    {
        if (!exists) ShowError(window_, L"Nao foi possivel adicionar este local ao Quick Access.");
        return;
    }
    SetWindowTextW(favorite_button_, exists ? L"☆" : L"★");
    PersistV5State();
    BuildSidebar();
}

void CloudOSNativeFilesWindow::TogglePreview()
{
    preview_visible_ = !preview_visible_;
    SetWindowTextW(preview_button_, preview_visible_ ? L"Ocultar preview" : L"Preview");
    preview_.Show(preview_visible_);
    if (!preview_visible_)
    {
        preview_selection_.clear();
        preview_.Clear();
    }
    PersistV5State();
    Layout();
    if (preview_visible_) RefreshPreview();
}

void CloudOSNativeFilesWindow::OpenSearch()
{
    const std::wstring query = ReadEditText(search_edit_);
    if (query.empty())
    {
        SetFocus(search_edit_);
        return;
    }
    if (current_path_.empty()) return;
    if (CloudOS::CloudOSNativeFilesSearchWindow::Open(instance_, current_path_, query, window_) == nullptr)
        ShowError(window_, L"Nao foi possivel iniciar a pesquisa neste local.");
}

void CloudOSNativeFilesWindow::OpenOperations()
{
    CloudOS::CloudOSNativeFileOperationsWindow::Open(instance_, current_path_);
}

std::vector<std::wstring> CloudOSNativeFilesWindow::SelectedPaths() const
{
    if (content_mode_ == ContentMode::Shell && shell_available_)
        return shell_view_.SelectedPaths();

    std::vector<std::wstring> selected;
    int row = -1;
    while ((row = ListView_GetNextItem(list_, row, LVNI_SELECTED)) >= 0)
    {
        if (static_cast<std::size_t>(row) >= entries_.size()) continue;
        selected.push_back(entries_[static_cast<std::size_t>(row)].full_path);
        if (selected.size() >= 256) break;
    }
    return selected;
}

void CloudOSNativeFilesWindow::RefreshPreview()
{
    if (!preview_visible_ || preview_.Window() == nullptr) return;
    const auto selected = SelectedPaths();
    const std::wstring next = selected.empty() ? std::wstring{} : selected.front();
    if (next.empty())
    {
        if (!preview_selection_.empty())
        {
            preview_selection_.clear();
            preview_.Clear();
        }
        return;
    }
    if (!preview_selection_.empty() && PathsEqual(preview_selection_, next)) return;
    preview_selection_ = next;
    preview_.SetPath(next);
}

void CloudOSNativeFilesWindow::Navigate(const std::wstring& path)
{
    if (path.empty()) return;
    if (CloudOS::NativeCloudOSDrive::IsPathInside(path))
    {
        NavigateCloudOSDrive(path);
        return;
    }
    if (!NavigateShell(path)) NavigateFallback(path);
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
    PopulateCustomList();
    CommitNavigatedPath(current_path_);
}

void CloudOSNativeFilesWindow::NavigateFallback(const std::wstring& path)
{
    if (!IsWslRootPath(path) && !DirectoryExists(path))
    {
        ShowError(window_, L"Pasta nao encontrada ou sem acesso.");
        suppressed_history_target_.clear();
        return;
    }
    current_path_ = path;
    content_mode_ = ContentMode::FallbackFileSystem;
    ShowWindow(shell_host_, SW_HIDE);
    ShowWindow(list_, SW_SHOW);
    SetWindowTextW(window_, L"Arquivos - CloudOS");
    PopulateCustomList();
    CommitNavigatedPath(current_path_);
}

void CloudOSNativeFilesWindow::NavigateBack()
{
    if (tab_states_.empty()) return;
    active_tab_ = std::min(active_tab_, tab_states_.size() - 1);
    TabState& tab = tab_states_[active_tab_];
    if (tab.back.empty()) return;
    const std::wstring target = tab.back.back();
    tab.back.pop_back();
    if (!tab.path.empty())
    {
        tab.forward.push_back(tab.path);
        if (tab.forward.size() > kMaximumHistoryEntries) tab.forward.erase(tab.forward.begin());
    }
    suppressed_history_target_ = target;
    PersistV5State();
    Navigate(target);
}

void CloudOSNativeFilesWindow::NavigateForward()
{
    if (tab_states_.empty()) return;
    active_tab_ = std::min(active_tab_, tab_states_.size() - 1);
    TabState& tab = tab_states_[active_tab_];
    if (tab.forward.empty()) return;
    const std::wstring target = tab.forward.back();
    tab.forward.pop_back();
    if (!tab.path.empty())
    {
        tab.back.push_back(tab.path);
        if (tab.back.size() > kMaximumHistoryEntries) tab.back.erase(tab.back.begin());
    }
    suppressed_history_target_ = target;
    PersistV5State();
    Navigate(target);
}

void CloudOSNativeFilesWindow::NavigateParent()
{
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
    if (!parent.empty() && !PathsEqual(parent, current_path_)) Navigate(parent);
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
    ShowWindow(list_, SW_HIDE);
    ShowWindow(shell_host_, SW_SHOW);
    CommitNavigatedPath(path);
    RefreshPreview();
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
