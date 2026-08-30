#pragma once

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{
enum class ShellPinKind : std::uint32_t
{
    CloudOSApp = 1,
    WindowsTarget = 2,
};

struct ShellPinItem final
{
    ShellPinKind kind{ShellPinKind::CloudOSApp};
    std::wstring id;
    std::wstring title;
    std::wstring subtitle;
    std::wstring target;
};

class ShellPinStore final
{
public:
    static ShellPinStore& Instance();

    ShellPinStore(const ShellPinStore&) = delete;
    ShellPinStore& operator=(const ShellPinStore&) = delete;

    [[nodiscard]] std::vector<ShellPinItem> StartPins() const;
    [[nodiscard]] std::vector<ShellPinItem> TaskbarPins() const;

    [[nodiscard]] bool IsStartPinned(const ShellPinItem& item) const;
    [[nodiscard]] bool IsTaskbarPinned(const ShellPinItem& item) const;

    void PinStart(const ShellPinItem& item);
    void UnpinStart(const ShellPinItem& item);
    void ToggleStart(const ShellPinItem& item);

    void PinTaskbar(const ShellPinItem& item);
    void UnpinTaskbar(const ShellPinItem& item);
    void ToggleTaskbar(const ShellPinItem& item);

    void MoveStart(std::size_t from, std::size_t to);
    void MoveTaskbar(std::size_t from, std::size_t to);

    static bool SameIdentity(const ShellPinItem& left, const ShellPinItem& right) noexcept;

private:
    ShellPinStore();

    void Load();
    void SaveLocked() const;
    void EnsureDefaultsLocked();

    static bool IsUsable(const ShellPinItem& item) noexcept;
    static std::wstring StoragePath();

    mutable std::mutex mutex_;
    std::vector<ShellPinItem> start_pins_;
    std::vector<ShellPinItem> taskbar_pins_;
    std::wstring storage_path_;
};

} // namespace CloudOS
