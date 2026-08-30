#include "native_start_index.h"

#include <KnownFolders.h>
#include <ShlObj.h>
#include <ShObjIdl.h>
#include <Shellapi.h>

#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <system_error>
#include <unordered_set>
#include <utility>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

namespace CloudOS
{
namespace
{
std::wstring Lower(std::wstring value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t ch)
        {
            return static_cast<wchar_t>(std::towlower(ch));
        });
    return value;
}

std::wstring Trim(std::wstring value)
{
    const auto is_space = [](wchar_t ch)
    {
        return std::iswspace(ch) != 0;
    };
    while (!value.empty() && is_space(value.front()))
    {
        value.erase(value.begin());
    }
    while (!value.empty() && is_space(value.back()))
    {
        value.pop_back();
    }
    return value;
}

std::vector<std::wstring> Tokens(const std::wstring& query)
{
    std::vector<std::wstring> tokens;
    std::wstring current;
    for (const wchar_t ch : Lower(Trim(query)))
    {
        if (std::iswspace(ch))
        {
            if (!current.empty())
            {
                tokens.push_back(std::move(current));
                current.clear();
            }
        }
        else
        {
            current.push_back(ch);
        }
    }
    if (!current.empty())
    {
        tokens.push_back(std::move(current));
    }
    return tokens;
}

int MatchScore(const NativeStartIndexEntry& entry, const std::vector<std::wstring>& tokens)
{
    if (tokens.empty())
    {
        return 1;
    }

    const std::wstring title = Lower(entry.title);
    const std::wstring subtitle = Lower(entry.subtitle);
    const std::wstring target = Lower(entry.launch_target);
    const std::wstring haystack = title + L" " + subtitle + L" " + target;

    int score = 0;
    for (const std::wstring& token : tokens)
    {
        const std::size_t title_pos = title.find(token);
        const std::size_t haystack_pos = haystack.find(token);
        if (haystack_pos == std::wstring::npos)
        {
            // Lightweight fuzzy fallback: every query character must appear in
            // order in the title. This catches queries such as "vscd".
            std::size_t cursor = 0;
            for (const wchar_t ch : token)
            {
                cursor = title.find(ch, cursor);
                if (cursor == std::wstring::npos)
                {
                    return -1;
                }
                ++cursor;
            }
            score += 40;
            continue;
        }

        if (title == token)
        {
            score += 1000;
        }
        else if (title_pos == 0)
        {
            score += 600;
        }
        else if (title_pos != std::wstring::npos)
        {
            score += 350;
        }
        else
        {
            score += 120;
        }
    }

    if (entry.kind == NativeStartIndexKind::PackagedApp)
    {
        score += 5;
    }
    return score;
}

bool HasSupportedExtension(const std::filesystem::path& path)
{
    const std::wstring extension = Lower(path.extension().wstring());
    return extension == L".lnk" || extension == L".url" || extension == L".exe";
}

void ScanStartFolder(
    REFKNOWNFOLDERID folder_id,
    std::vector<NativeStartIndexEntry>& entries)
{
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &raw)) || raw == nullptr)
    {
        if (raw != nullptr)
        {
            CoTaskMemFree(raw);
        }
        return;
    }

    const std::filesystem::path root(raw);
    CoTaskMemFree(raw);

    std::error_code error;
    std::filesystem::recursive_directory_iterator iterator(
        root,
        std::filesystem::directory_options::skip_permission_denied,
        error);
    const std::filesystem::recursive_directory_iterator end;
    for (; iterator != end; iterator.increment(error))
    {
        if (error)
        {
            error.clear();
            continue;
        }
        if (!iterator->is_regular_file(error) || error || !HasSupportedExtension(iterator->path()))
        {
            error.clear();
            continue;
        }

        NativeStartIndexEntry entry{};
        entry.title = iterator->path().stem().wstring();
        entry.subtitle = L"Menu Iniciar";
        entry.launch_target = iterator->path().wstring();
        entry.kind = NativeStartIndexKind::Shortcut;
        entries.push_back(std::move(entry));
    }
}

void ScanAppsFolder(std::vector<NativeStartIndexEntry>& entries)
{
    IShellItem* folder = nullptr;
    if (FAILED(SHCreateItemFromParsingName(
            L"shell:AppsFolder",
            nullptr,
            IID_PPV_ARGS(&folder))) ||
        folder == nullptr)
    {
        return;
    }

    IEnumShellItems* enumeration = nullptr;
    const HRESULT bind_result = folder->BindToHandler(
        nullptr,
        BHID_EnumItems,
        IID_PPV_ARGS(&enumeration));
    folder->Release();
    if (FAILED(bind_result) || enumeration == nullptr)
    {
        return;
    }

    for (;;)
    {
        IShellItem* item = nullptr;
        ULONG fetched = 0;
        const HRESULT next = enumeration->Next(1, &item, &fetched);
        if (next != S_OK || fetched != 1 || item == nullptr)
        {
            if (item != nullptr)
            {
                item->Release();
            }
            break;
        }

        PWSTR title = nullptr;
        PWSTR parsing = nullptr;
        const HRESULT title_result = item->GetDisplayName(SIGDN_NORMALDISPLAY, &title);
        const HRESULT parsing_result = item->GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING, &parsing);
        if (SUCCEEDED(title_result) && SUCCEEDED(parsing_result) &&
            title != nullptr && parsing != nullptr && title[0] != L'\0' && parsing[0] != L'\0')
        {
            NativeStartIndexEntry entry{};
            entry.title = title;
            entry.subtitle = L"Aplicativo do Windows";
            entry.launch_target = parsing;
            entry.kind = NativeStartIndexKind::PackagedApp;
            entries.push_back(std::move(entry));
        }

        if (title != nullptr)
        {
            CoTaskMemFree(title);
        }
        if (parsing != nullptr)
        {
            CoTaskMemFree(parsing);
        }
        item->Release();
    }

    enumeration->Release();
}
}

NativeStartIndex& NativeStartIndex::Instance()
{
    static NativeStartIndex index;
    return index;
}

NativeStartIndex::~NativeStartIndex()
{
    if (worker_.joinable())
    {
        worker_.join();
    }
}

void NativeStartIndex::StartAsync()
{
    if (ready_.load() || indexing_.load())
    {
        return;
    }
    StartWorker(false);
}

void NativeStartIndex::RefreshAsync()
{
    StartWorker(true);
}

void NativeStartIndex::StartWorker(bool force_refresh)
{
    if (indexing_.exchange(true))
    {
        return;
    }

    if (worker_.joinable())
    {
        worker_.join();
    }

    if (force_refresh)
    {
        ready_.store(false);
    }

    worker_ = std::thread(
        [this]()
        {
            BuildIndex();
            ready_.store(true);
            indexing_.store(false);
        });
}

void NativeStartIndex::BuildIndex()
{
    const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitialize = SUCCEEDED(com_result);

    std::vector<NativeStartIndexEntry> next;
    next.reserve(512);
    ScanStartFolder(FOLDERID_Programs, next);
    ScanStartFolder(FOLDERID_CommonPrograms, next);
    ScanAppsFolder(next);

    std::sort(
        next.begin(),
        next.end(),
        [](const NativeStartIndexEntry& left, const NativeStartIndexEntry& right)
        {
            const int title_compare = _wcsicmp(left.title.c_str(), right.title.c_str());
            if (title_compare != 0)
            {
                return title_compare < 0;
            }
            return _wcsicmp(left.launch_target.c_str(), right.launch_target.c_str()) < 0;
        });

    std::unordered_set<std::wstring> seen;
    std::vector<NativeStartIndexEntry> unique;
    unique.reserve(next.size());
    for (auto& entry : next)
    {
        std::wstring key = Lower(entry.launch_target);
        if (key.empty() || !seen.insert(std::move(key)).second)
        {
            continue;
        }
        unique.push_back(std::move(entry));
    }

    {
        std::scoped_lock lock(mutex_);
        entries_ = std::move(unique);
    }

    if (uninitialize)
    {
        CoUninitialize();
    }
}

bool NativeStartIndex::Ready() const noexcept
{
    return ready_.load();
}

bool NativeStartIndex::Indexing() const noexcept
{
    return indexing_.load();
}

std::size_t NativeStartIndex::Count() const
{
    std::scoped_lock lock(mutex_);
    return entries_.size();
}

std::vector<NativeStartIndexEntry> NativeStartIndex::Query(
    const std::wstring& query,
    std::size_t limit) const
{
    struct ScoredEntry final
    {
        int score{};
        NativeStartIndexEntry entry;
    };

    const auto tokens = Tokens(query);
    std::vector<ScoredEntry> scored;
    {
        std::scoped_lock lock(mutex_);
        scored.reserve(entries_.size());
        for (const auto& entry : entries_)
        {
            const int score = MatchScore(entry, tokens);
            if (score >= 0)
            {
                scored.push_back(ScoredEntry{score, entry});
            }
        }
    }

    std::stable_sort(
        scored.begin(),
        scored.end(),
        [](const ScoredEntry& left, const ScoredEntry& right)
        {
            if (left.score != right.score)
            {
                return left.score > right.score;
            }
            return _wcsicmp(left.entry.title.c_str(), right.entry.title.c_str()) < 0;
        });

    if (scored.size() > limit)
    {
        scored.resize(limit);
    }

    std::vector<NativeStartIndexEntry> result;
    result.reserve(scored.size());
    for (auto& item : scored)
    {
        result.push_back(std::move(item.entry));
    }
    return result;
}

bool NativeStartIndex::Launch(HWND owner, const NativeStartIndexEntry& entry) const
{
    if (entry.launch_target.empty())
    {
        return false;
    }

    const HINSTANCE result = ShellExecuteW(
        owner,
        L"open",
        entry.launch_target.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(result) > 32;
}
} // namespace CloudOS
