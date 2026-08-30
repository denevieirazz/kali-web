#pragma once

#include <Windows.h>

#include <atomic>
#include <cstddef>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{
enum class NativeStartIndexKind
{
    Shortcut,
    PackagedApp,
    IndexedItem,
};

struct NativeStartIndexEntry final
{
    std::wstring title;
    std::wstring subtitle;
    std::wstring launch_target;
    NativeStartIndexKind kind{NativeStartIndexKind::Shortcut};
};

class NativeStartIndex final
{
public:
    static NativeStartIndex& Instance();

    NativeStartIndex(const NativeStartIndex&) = delete;
    NativeStartIndex& operator=(const NativeStartIndex&) = delete;

    void StartAsync();
    void RefreshAsync();

    [[nodiscard]] bool Ready() const noexcept;
    [[nodiscard]] bool Indexing() const noexcept;
    [[nodiscard]] std::size_t Count() const;
    [[nodiscard]] std::vector<NativeStartIndexEntry> Query(
        const std::wstring& query,
        std::size_t limit = 80) const;

    bool Launch(HWND owner, const NativeStartIndexEntry& entry) const;

private:
    NativeStartIndex() = default;
    ~NativeStartIndex();

    void StartWorker(bool force_refresh);
    void BuildIndex();
    void RequestUniversalSearch(const std::wstring& query) const;
    void UniversalSearchLoop() const;

    mutable std::mutex mutex_;
    std::vector<NativeStartIndexEntry> entries_;
    std::thread worker_;
    std::atomic_bool indexing_{false};
    std::atomic_bool ready_{false};

    // Windows Search is queried asynchronously. Query() only reads this cache,
    // so typing in Start never blocks the Win32 UI thread on OLE DB/SystemIndex.
    mutable std::mutex universal_mutex_;
    mutable std::thread universal_worker_;
    mutable std::atomic_bool universal_searching_{false};
    mutable std::wstring universal_requested_query_;
    mutable std::wstring universal_completed_query_;
    mutable std::vector<NativeStartIndexEntry> universal_entries_;
};
} // namespace CloudOS
