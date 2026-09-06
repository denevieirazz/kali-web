#pragma once

#include "protocol_v21.h"

#include <Windows.h>

#include <string>
#include <vector>

namespace CloudOS
{

struct DisplayModeInfoV25 final
{
    int width{0};
    int height{0};
    int frequency{0};
    int orientation{0};
    int bits_per_pel{32};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct MonitorInfoV25 final
{
    std::wstring device_name;
    std::wstring friendly_name;
    bool is_primary{false};
    int width{0};
    int height{0};
    int frequency{0};
    int orientation{0};
    int bits_per_pel{32};
    int dpi_x{96};
    int dpi_y{96};
    double scale{1.0};
    RECT bounds{0, 0, 0, 0};
    RECT work_area{0, 0, 0, 0};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class DisplayServiceV25 final
{
public:
    static DisplayServiceV25& Instance();

    DisplayServiceV25(const DisplayServiceV25&) = delete;
    DisplayServiceV25& operator=(const DisplayServiceV25&) = delete;

    [[nodiscard]] std::vector<MonitorInfoV25> ListMonitors();
    [[nodiscard]] std::vector<DisplayModeInfoV25> ListSupportedModes(const std::wstring& device_name);
    bool SetDisplayMode(
        const std::wstring& device_name,
        int width,
        int height,
        int frequency,
        int orientation,
        std::string* error = nullptr);

    bool ApplyDisplayModeId(
        const std::wstring& device_name,
        const std::string& mode_id,
        std::string* error = nullptr);

    bool RestoreBaseline(std::string* error = nullptr);

private:
    DisplayServiceV25();
    ~DisplayServiceV25() = default;

    std::wstring baseline_device_{L"\\\\.\\DISPLAY1"};
    DEVMODEW baseline_mode_{0};
    bool baseline_saved_{false};
};

} // namespace CloudOS
