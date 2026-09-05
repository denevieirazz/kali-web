#pragma once

#include "protocol_v21.h"

#include <string>
#include <vector>

namespace CloudOS
{

struct PowerStatusV25 final
{
    bool ac_online{true};
    bool battery_present{false};
    int battery_percent{100};
    bool is_charging{false};
    bool battery_saver{false};
    int remaining_sec{-1};
    std::string power_source{"AC"};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct NetworkInterfaceV25 final
{
    std::string id;
    std::string name;
    std::string friendly_name;
    std::string type{"Ethernet"};
    std::string status{"Up"};
    std::string ipv4;
    std::string ipv6;
    std::string gateway;
    std::string dns;
    bool is_internet_connected{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct WifiNetworkV25 final
{
    std::string ssid;
    int signal_quality{0}; // 0 - 100%
    std::string security;
    bool is_connected{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct BluetoothStatusV25 final
{
    bool available{false};
    bool enabled{false};
    std::string radio_name;
    std::string address;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct StorageDriveV25 final
{
    std::string drive_letter;
    std::string volume_name;
    std::string file_system;
    std::string drive_type;
    uint64_t total_bytes{0};
    uint64_t free_bytes{0};
    uint64_t used_bytes{0};
    double percent_used{0.0};
    bool is_removable{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct PersonalizationSettingsV25 final
{
    std::string theme{"dark"}; // "dark" | "light" | "system"
    std::string accent_color{"#2563EB"};
    bool transparency_enabled{true};
    bool animations_enabled{true};
    std::string wallpaper_path;
    std::string taskbar_alignment{"center"}; // "center" | "left"

    [[nodiscard]] JsonObject ToJsonObject() const;
    static PersonalizationSettingsV25 FromJsonObject(const JsonObject& obj);
};

struct DateTimeLocaleV25 final
{
    std::string local_time;
    std::string timezone_name;
    int bias_minutes{0};
    std::string locale_name;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class SystemSettingsServiceV25 final
{
public:
    static SystemSettingsServiceV25& Instance();

    SystemSettingsServiceV25(const SystemSettingsServiceV25&) = delete;
    SystemSettingsServiceV25& operator=(const SystemSettingsServiceV25&) = delete;

    [[nodiscard]] PowerStatusV25 GetPowerStatus();
    [[nodiscard]] std::vector<NetworkInterfaceV25> GetNetworkInterfaces();
    [[nodiscard]] std::vector<WifiNetworkV25> GetWifiNetworks();
    [[nodiscard]] BluetoothStatusV25 GetBluetoothStatus();
    [[nodiscard]] std::vector<StorageDriveV25> GetStorageDrives();

    [[nodiscard]] PersonalizationSettingsV25 GetPersonalization();
    bool SetPersonalization(const PersonalizationSettingsV25& settings, std::string* error = nullptr);

    [[nodiscard]] DateTimeLocaleV25 GetDateTimeLocale();

private:
    SystemSettingsServiceV25();
    ~SystemSettingsServiceV25() = default;

    std::wstring GetConfigFilePath() const;
};

} // namespace CloudOS
