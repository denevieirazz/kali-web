#include "display_service_v25.h"
#include "event_bus_v21.h"

#include <ShellScalingApi.h>

#include <algorithm>
#include <iostream>
#include <set>

namespace CloudOS
{

JsonObject DisplayModeInfoV25::ToJsonObject() const
{
    JsonObject obj;
    obj["width"] = JsonValue(static_cast<double>(width));
    obj["height"] = JsonValue(static_cast<double>(height));
    obj["frequency"] = JsonValue(static_cast<double>(frequency));
    obj["orientation"] = JsonValue(static_cast<double>(orientation));
    obj["bitsPerPel"] = JsonValue(static_cast<double>(bits_per_pel));
    return obj;
}

static std::string WStringToString(const std::wstring& ws)
{
    if (ws.empty()) return {};
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, ws.data(), static_cast<int>(ws.size()), nullptr, 0, nullptr, nullptr);
    std::string str(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, ws.data(), static_cast<int>(ws.size()), str.data(), size_needed, nullptr, nullptr);
    return str;
}

JsonObject MonitorInfoV25::ToJsonObject() const
{
    JsonObject obj;
    obj["deviceName"] = JsonValue(WStringToString(device_name));
    obj["friendlyName"] = JsonValue(WStringToString(friendly_name));
    obj["isPrimary"] = JsonValue(is_primary);
    obj["width"] = JsonValue(static_cast<double>(width));
    obj["height"] = JsonValue(static_cast<double>(height));
    obj["frequency"] = JsonValue(static_cast<double>(frequency));
    obj["orientation"] = JsonValue(static_cast<double>(orientation));
    obj["bitsPerPel"] = JsonValue(static_cast<double>(bits_per_pel));
    obj["dpiX"] = JsonValue(static_cast<double>(dpi_x));
    obj["dpiY"] = JsonValue(static_cast<double>(dpi_y));
    obj["scale"] = JsonValue(scale);

    JsonObject bObj;
    bObj["left"] = JsonValue(static_cast<double>(bounds.left));
    bObj["top"] = JsonValue(static_cast<double>(bounds.top));
    bObj["right"] = JsonValue(static_cast<double>(bounds.right));
    bObj["bottom"] = JsonValue(static_cast<double>(bounds.bottom));
    bObj["width"] = JsonValue(static_cast<double>(bounds.right - bounds.left));
    bObj["height"] = JsonValue(static_cast<double>(bounds.bottom - bounds.top));
    obj["bounds"] = JsonValue(std::move(bObj));

    JsonObject wObj;
    wObj["left"] = JsonValue(static_cast<double>(work_area.left));
    wObj["top"] = JsonValue(static_cast<double>(work_area.top));
    wObj["right"] = JsonValue(static_cast<double>(work_area.right));
    wObj["bottom"] = JsonValue(static_cast<double>(work_area.bottom));
    wObj["width"] = JsonValue(static_cast<double>(work_area.right - work_area.left));
    wObj["height"] = JsonValue(static_cast<double>(work_area.bottom - work_area.top));
    obj["workArea"] = JsonValue(std::move(wObj));

    return obj;
}

DisplayServiceV25& DisplayServiceV25::Instance()
{
    static DisplayServiceV25 instance;
    return instance;
}

DisplayServiceV25::DisplayServiceV25()
{
    baseline_mode_.dmSize = sizeof(DEVMODEW);
    if (EnumDisplaySettingsW(baseline_device_.c_str(), ENUM_CURRENT_SETTINGS, &baseline_mode_))
    {
        baseline_saved_ = true;
    }
}

namespace
{
struct MonitorEnumData
{
    std::vector<MonitorInfoV25> monitors;
};

BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC, LPRECT, LPARAM dwData)
{
    auto* data = reinterpret_cast<MonitorEnumData*>(dwData);
    if (!data) return FALSE;

    MONITORINFOEXW mi;
    mi.cbSize = sizeof(MONITORINFOEXW);
    if (!GetMonitorInfoW(hMonitor, &mi)) return TRUE;

    MonitorInfoV25 info;
    info.device_name = mi.szDevice;
    info.is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
    info.bounds = mi.rcMonitor;
    info.work_area = mi.rcWork;

    // Friendly name from DISPLAY_DEVICEW
    DISPLAY_DEVICEW dd;
    dd.cb = sizeof(DISPLAY_DEVICEW);
    if (EnumDisplayDevicesW(mi.szDevice, 0, &dd, 0))
    {
        info.friendly_name = dd.DeviceString;
    }
    if (info.friendly_name.empty())
    {
        info.friendly_name = info.is_primary ? L"Monitor Principal" : L"Monitor Secundário";
    }

    // Current display settings
    DEVMODEW dm;
    dm.dmSize = sizeof(DEVMODEW);
    if (EnumDisplaySettingsW(mi.szDevice, ENUM_CURRENT_SETTINGS, &dm))
    {
        info.width = dm.dmPelsWidth;
        info.height = dm.dmPelsHeight;
        info.frequency = dm.dmDisplayFrequency;
        info.orientation = dm.dmDisplayOrientation;
        info.bits_per_pel = dm.dmBitsPerPel;
    }
    else
    {
        info.width = mi.rcMonitor.right - mi.rcMonitor.left;
        info.height = mi.rcMonitor.bottom - mi.rcMonitor.top;
        info.frequency = 60;
        info.orientation = 0;
        info.bits_per_pel = 32;
    }

    // DPI query
    HMODULE shcore = LoadLibraryW(L"Shcore.dll");
    bool dpi_queried = false;
    if (shcore)
    {
        using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, MONITOR_DPI_TYPE, UINT*, UINT*);
        auto fn = reinterpret_cast<GetDpiForMonitorFn>(GetProcAddress(shcore, "GetDpiForMonitor"));
        if (fn)
        {
            UINT dpiX = 96, dpiY = 96;
            if (SUCCEEDED(fn(hMonitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)))
            {
                info.dpi_x = static_cast<int>(dpiX);
                info.dpi_y = static_cast<int>(dpiY);
                info.scale = static_cast<double>(dpiX) / 96.0;
                dpi_queried = true;
            }
        }
        FreeLibrary(shcore);
    }
    if (!dpi_queried)
    {
        HDC screen = GetDC(nullptr);
        if (screen)
        {
            info.dpi_x = GetDeviceCaps(screen, LOGPIXELSX);
            info.dpi_y = GetDeviceCaps(screen, LOGPIXELSY);
            info.scale = static_cast<double>(info.dpi_x) / 96.0;
            ReleaseDC(nullptr, screen);
        }
    }

    data->monitors.push_back(std::move(info));
    return TRUE;
}
} // namespace

std::vector<MonitorInfoV25> DisplayServiceV25::ListMonitors()
{
    MonitorEnumData data;
    EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc, reinterpret_cast<LPARAM>(&data));
    return data.monitors;
}

std::vector<DisplayModeInfoV25> DisplayServiceV25::ListSupportedModes(const std::wstring& device_name)
{
    std::vector<DisplayModeInfoV25> modes;
    std::set<std::tuple<int, int, int>> seen;

    DEVMODEW dm;
    dm.dmSize = sizeof(DEVMODEW);
    for (DWORD i = 0; EnumDisplaySettingsW(device_name.c_str(), i, &dm); ++i)
    {
        auto key = std::make_tuple(
            static_cast<int>(dm.dmPelsWidth),
            static_cast<int>(dm.dmPelsHeight),
            static_cast<int>(dm.dmDisplayFrequency));
        if (seen.find(key) == seen.end())
        {
            seen.insert(key);
            DisplayModeInfoV25 mode;
            mode.width = dm.dmPelsWidth;
            mode.height = dm.dmPelsHeight;
            mode.frequency = dm.dmDisplayFrequency;
            mode.orientation = dm.dmDisplayOrientation;
            mode.bits_per_pel = dm.dmBitsPerPel;
            modes.push_back(mode);
        }
    }
    return modes;
}

bool DisplayServiceV25::SetDisplayMode(
    const std::wstring& device_name,
    int width,
    int height,
    int frequency,
    int orientation,
    std::string* error)
{
    DEVMODEW target = {0};
    target.dmSize = sizeof(DEVMODEW);
    bool found = false;

    DEVMODEW dm;
    dm.dmSize = sizeof(DEVMODEW);
    for (DWORD i = 0; EnumDisplaySettingsW(device_name.c_str(), i, &dm); ++i)
    {
        if (static_cast<int>(dm.dmPelsWidth) == width &&
            static_cast<int>(dm.dmPelsHeight) == height &&
            (frequency == 0 || static_cast<int>(dm.dmDisplayFrequency) == frequency))
        {
            target = dm;
            found = true;
            break;
        }
    }

    if (!found)
    {
        if (error) *error = "Requested display mode is not supported by monitor hardware";
        return false;
    }

    target.dmDisplayOrientation = orientation;
    target.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYORIENTATION;

    // Test first
    LONG test_res = ChangeDisplaySettingsExW(device_name.c_str(), &target, nullptr, CDS_TEST, nullptr);
    LONG apply_res = DISP_CHANGE_FAILED;

    if (test_res == DISP_CHANGE_SUCCESSFUL)
    {
        apply_res = ChangeDisplaySettingsExW(device_name.c_str(), &target, nullptr, 0, nullptr);
    }
    else
    {
        // Try staging for multi-monitor setups
        LONG stage_res = ChangeDisplaySettingsExW(
            device_name.c_str(),
            &target,
            nullptr,
            CDS_UPDATEREGISTRY | CDS_NORESET,
            nullptr);
        if (stage_res == DISP_CHANGE_SUCCESSFUL)
        {
            apply_res = ChangeDisplaySettingsExW(nullptr, nullptr, nullptr, 0, nullptr);
        }
        else
        {
            apply_res = test_res;
        }
    }

    if (apply_res != DISP_CHANGE_SUCCESSFUL)
    {
        if (error) *error = "Hardware or driver rejected display change (code: " + std::to_string(apply_res) + ")";
        return false;
    }

    // Notify listeners
    JsonObject payload;
    payload["device"] = JsonValue(WStringToString(device_name));
    payload["width"] = JsonValue(static_cast<double>(width));
    payload["height"] = JsonValue(static_cast<double>(height));
    payload["frequency"] = JsonValue(static_cast<double>(target.dmDisplayFrequency));
    EventBusV21::Instance().Publish("display.changed", payload);

    return true;
}

bool DisplayServiceV25::RestoreBaseline(std::string* error)
{
    if (!baseline_saved_)
    {
        ChangeDisplaySettingsExW(baseline_device_.c_str(), nullptr, nullptr, 0, nullptr);
        return true;
    }

    LONG res = ChangeDisplaySettingsExW(baseline_device_.c_str(), &baseline_mode_, nullptr, 0, nullptr);
    if (res != DISP_CHANGE_SUCCESSFUL)
    {
        // Fallback to default
        ChangeDisplaySettingsExW(baseline_device_.c_str(), nullptr, nullptr, 0, nullptr);
        if (error) *error = "Restored with fallback default";
        return false;
    }

    JsonObject payload;
    payload["device"] = JsonValue(WStringToString(baseline_device_));
    payload["width"] = JsonValue(static_cast<double>(baseline_mode_.dmPelsWidth));
    payload["height"] = JsonValue(static_cast<double>(baseline_mode_.dmPelsHeight));
    EventBusV21::Instance().Publish("display.changed", payload);
    return true;
}

} // namespace CloudOS
