#include "system_settings_service_v25.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <wlanapi.h>
#include <bluetoothapis.h>
#include <windows.h>
#include <shlobj.h>

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "bthprops.lib")

namespace CloudOS
{

namespace
{

std::string WideToUtf8(const std::wstring& wide)
{
    if (wide.empty()) return {};
    const int len = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), nullptr, 0, nullptr, nullptr);
    if (len <= 0) return {};
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()), out.data(), len, nullptr, nullptr);
    return out;
}

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return {};
    const int len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), nullptr, 0);
    if (len <= 0) return {};
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), out.data(), len);
    return out;
}

} // namespace

JsonObject PowerStatusV25::ToJsonObject() const
{
    JsonObject obj;
    obj["ac_online"] = ac_online;
    obj["battery_present"] = battery_present;
    obj["battery_percent"] = battery_percent;
    obj["is_charging"] = is_charging;
    obj["battery_saver"] = battery_saver;
    obj["remaining_sec"] = remaining_sec;
    obj["power_source"] = power_source;
    return obj;
}


JsonObject NetworkInterfaceV25::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = id;
    obj["name"] = name;
    obj["friendly_name"] = friendly_name;
    obj["type"] = type;
    obj["status"] = status;
    obj["ipv4"] = ipv4;
    obj["ipv6"] = ipv6;
    obj["gateway"] = gateway;
    obj["dns"] = dns;
    obj["is_internet_connected"] = is_internet_connected;
    return obj;
}

JsonObject WifiNetworkV25::ToJsonObject() const
{
    JsonObject obj;
    obj["ssid"] = ssid;
    obj["signal_quality"] = signal_quality;
    obj["security"] = security;
    obj["is_connected"] = is_connected;
    return obj;
}

JsonObject BluetoothStatusV25::ToJsonObject() const
{
    JsonObject obj;
    obj["available"] = available;
    obj["enabled"] = enabled;
    obj["radio_name"] = radio_name;
    obj["address"] = address;
    return obj;
}

JsonObject StorageDriveV25::ToJsonObject() const
{
    JsonObject obj;
    obj["drive_letter"] = drive_letter;
    obj["volume_name"] = volume_name;
    obj["file_system"] = file_system;
    obj["drive_type"] = drive_type;
    obj["total_bytes"] = static_cast<double>(total_bytes);
    obj["free_bytes"] = static_cast<double>(free_bytes);
    obj["used_bytes"] = static_cast<double>(used_bytes);
    obj["percent_used"] = percent_used;
    obj["is_removable"] = is_removable;
    return obj;
}

JsonObject PersonalizationSettingsV25::ToJsonObject() const
{
    JsonObject obj;
    obj["theme"] = theme;
    obj["accent_color"] = accent_color;
    obj["transparency_enabled"] = transparency_enabled;
    obj["animations_enabled"] = animations_enabled;
    obj["wallpaper_path"] = wallpaper_path;
    obj["taskbar_alignment"] = taskbar_alignment;
    return obj;
}

PersonalizationSettingsV25 PersonalizationSettingsV25::FromJsonObject(const JsonObject& obj)
{
    PersonalizationSettingsV25 s;
    if (obj.count("theme") && obj.at("theme").IsString())
    {
        s.theme = obj.at("theme").AsString();
    }
    if (obj.count("accent_color") && obj.at("accent_color").IsString())
    {
        s.accent_color = obj.at("accent_color").AsString();
    }
    if (obj.count("transparency_enabled") && obj.at("transparency_enabled").IsBool())
    {
        s.transparency_enabled = obj.at("transparency_enabled").AsBool();
    }
    if (obj.count("animations_enabled") && obj.at("animations_enabled").IsBool())
    {
        s.animations_enabled = obj.at("animations_enabled").AsBool();
    }
    if (obj.count("wallpaper_path") && obj.at("wallpaper_path").IsString())
    {
        s.wallpaper_path = obj.at("wallpaper_path").AsString();
    }
    if (obj.count("taskbar_alignment") && obj.at("taskbar_alignment").IsString())
    {
        s.taskbar_alignment = obj.at("taskbar_alignment").AsString();
    }
    return s;
}

JsonObject DateTimeLocaleV25::ToJsonObject() const
{
    JsonObject obj;
    obj["local_time"] = local_time;
    obj["timezone_name"] = timezone_name;
    obj["bias_minutes"] = bias_minutes;
    obj["locale_name"] = locale_name;
    return obj;
}

SystemSettingsServiceV25& SystemSettingsServiceV25::Instance()
{
    static SystemSettingsServiceV25 instance;
    return instance;
}

SystemSettingsServiceV25::SystemSettingsServiceV25() = default;

std::wstring SystemSettingsServiceV25::GetConfigFilePath() const
{
    PWSTR localAppData = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &localAppData)))
    {
        std::filesystem::path dir = localAppData;
        CoTaskMemFree(localAppData);
        dir /= L"CloudOS";
        std::error_code ec;
        std::filesystem::create_directories(dir, ec);
        return (dir / L"personalization.json").wstring();
    }
    return L"personalization.json";
}

PowerStatusV25 SystemSettingsServiceV25::GetPowerStatus()
{
    PowerStatusV25 status;
    SYSTEM_POWER_STATUS sps{};
    if (GetSystemPowerStatus(&sps))
    {
        status.ac_online = (sps.ACLineStatus == 1);
        status.battery_present = (sps.BatteryFlag != 128 && sps.BatteryFlag != 255);
        if (sps.BatteryLifePercent != 255)
        {
            status.battery_percent = static_cast<int>(sps.BatteryLifePercent);
        }
        else
        {
            status.battery_percent = status.battery_present ? 50 : 100;
        }

        status.is_charging = (sps.BatteryFlag & 8) != 0;
        status.battery_saver = (sps.SystemStatusFlag == 1);
        status.remaining_sec = (sps.BatteryLifeTime != static_cast<DWORD>(-1)) ? static_cast<int>(sps.BatteryLifeTime) : -1;
        status.power_source = status.ac_online ? "AC" : "Battery";
    }
    return status;
}

std::vector<NetworkInterfaceV25> SystemSettingsServiceV25::GetNetworkInterfaces()
{
    std::vector<NetworkInterfaceV25> results;
    ULONG outBufLen = 15000;
    std::vector<BYTE> buffer(outBufLen);
    PIP_ADAPTER_ADDRESSES pAddresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());

    ULONG flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_INCLUDE_PREFIX;
    ULONG retVal = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, pAddresses, &outBufLen);
    if (retVal == ERROR_BUFFER_OVERFLOW)
    {
        buffer.resize(outBufLen);
        pAddresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());
        retVal = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, pAddresses, &outBufLen);
    }

    if (retVal == NO_ERROR)
    {
        for (PIP_ADAPTER_ADDRESSES pCurrAddresses = pAddresses; pCurrAddresses != nullptr; pCurrAddresses = pCurrAddresses->Next)
        {
            if (pCurrAddresses->IfType == IF_TYPE_SOFTWARE_LOOPBACK)
            {
                continue;
            }

            NetworkInterfaceV25 iface;
            iface.id = pCurrAddresses->AdapterName ? pCurrAddresses->AdapterName : "";
            if (pCurrAddresses->FriendlyName)
            {
                iface.friendly_name = WideToUtf8(pCurrAddresses->FriendlyName);
            }
            if (pCurrAddresses->Description)
            {
                iface.name = WideToUtf8(pCurrAddresses->Description);
            }
            else
            {
                iface.name = iface.friendly_name;
            }

            switch (pCurrAddresses->IfType)
            {
            case IF_TYPE_ETHERNET_CSMACD:
                iface.type = "Ethernet";
                break;
            case IF_TYPE_IEEE80211:
                iface.type = "Wi-Fi";
                break;
            default:
                iface.type = "Other";
                break;
            }

            iface.status = (pCurrAddresses->OperStatus == IfOperStatusUp) ? "Up" : "Down";

            // Parse IP addresses
            for (PIP_ADAPTER_UNICAST_ADDRESS pUnicast = pCurrAddresses->FirstUnicastAddress; pUnicast != nullptr; pUnicast = pUnicast->Next)
            {
                if (!pUnicast->Address.lpSockaddr) continue;
                char ipStr[INET6_ADDRSTRLEN] = {0};
                if (pUnicast->Address.lpSockaddr->sa_family == AF_INET)
                {
                    sockaddr_in* sa4 = reinterpret_cast<sockaddr_in*>(pUnicast->Address.lpSockaddr);
                    inet_ntop(AF_INET, &(sa4->sin_addr), ipStr, sizeof(ipStr));
                    if (iface.ipv4.empty()) iface.ipv4 = ipStr;
                }
                else if (pUnicast->Address.lpSockaddr->sa_family == AF_INET6)
                {
                    sockaddr_in6* sa6 = reinterpret_cast<sockaddr_in6*>(pUnicast->Address.lpSockaddr);
                    inet_ntop(AF_INET6, &(sa6->sin6_addr), ipStr, sizeof(ipStr));
                    if (iface.ipv6.empty()) iface.ipv6 = ipStr;
                }
            }

            // Gateway
            if (pCurrAddresses->FirstGatewayAddress && pCurrAddresses->FirstGatewayAddress->Address.lpSockaddr)
            {
                char gwStr[INET6_ADDRSTRLEN] = {0};
                if (pCurrAddresses->FirstGatewayAddress->Address.lpSockaddr->sa_family == AF_INET)
                {
                    sockaddr_in* sa4 = reinterpret_cast<sockaddr_in*>(pCurrAddresses->FirstGatewayAddress->Address.lpSockaddr);
                    inet_ntop(AF_INET, &(sa4->sin_addr), gwStr, sizeof(gwStr));
                    iface.gateway = gwStr;
                }
            }

            iface.is_internet_connected = (iface.status == "Up" && !iface.gateway.empty());
            results.push_back(std::move(iface));
        }
    }

    return results;
}

std::vector<WifiNetworkV25> SystemSettingsServiceV25::GetWifiNetworks()
{
    std::vector<WifiNetworkV25> results;
    HANDLE hClient = nullptr;
    DWORD dwCurVersion = 0;

    DWORD dwResult = WlanOpenHandle(2, nullptr, &dwCurVersion, &hClient);
    if (dwResult != ERROR_SUCCESS)
    {
        return results;
    }

    PWLAN_INTERFACE_INFO_LIST pIfList = nullptr;
    dwResult = WlanEnumInterfaces(hClient, nullptr, &pIfList);
    if (dwResult == ERROR_SUCCESS && pIfList != nullptr)
    {
        for (DWORD i = 0; i < pIfList->dwNumberOfItems; ++i)
        {
            PWLAN_INTERFACE_INFO pIfInfo = &pIfList->InterfaceInfo[i];
            PWLAN_AVAILABLE_NETWORK_LIST pBssList = nullptr;
            if (WlanGetAvailableNetworkList(hClient, &pIfInfo->InterfaceGuid, 0, nullptr, &pBssList) == ERROR_SUCCESS && pBssList != nullptr)
            {
                for (DWORD j = 0; j < pBssList->dwNumberOfItems; ++j)
                {
                    PWLAN_AVAILABLE_NETWORK pEntry = &pBssList->Network[j];
                    if (pEntry->dot11Ssid.uSSIDLength == 0) continue;

                    std::string ssid(reinterpret_cast<const char*>(pEntry->dot11Ssid.ucSSID), pEntry->dot11Ssid.uSSIDLength);
                    WifiNetworkV25 net;
                    net.ssid = ssid;
                    net.signal_quality = static_cast<int>(pEntry->wlanSignalQuality);
                    net.is_connected = (pEntry->dwFlags & WLAN_AVAILABLE_NETWORK_CONNECTED) != 0;

                    switch (pEntry->dot11DefaultAuthAlgorithm)
                    {
                    case DOT11_AUTH_ALGO_80211_OPEN:
                        net.security = "Open";
                        break;
                    case DOT11_AUTH_ALGO_RSNA_PSK:
                        net.security = "WPA2-PSK";
                        break;
                    case DOT11_AUTH_ALGO_WPA_PSK:
                        net.security = "WPA-PSK";
                        break;
                    default:
                        net.security = "Secured";
                        break;
                    }

                    results.push_back(std::move(net));
                }
                WlanFreeMemory(pBssList);
            }
        }
        WlanFreeMemory(pIfList);
    }

    WlanCloseHandle(hClient, nullptr);
    return results;
}

BluetoothStatusV25 SystemSettingsServiceV25::GetBluetoothStatus()
{
    BluetoothStatusV25 status;
    BLUETOOTH_FIND_RADIO_PARAMS params{};
    params.dwSize = sizeof(params);

    HANDLE hRadio = nullptr;
    HBLUETOOTH_RADIO_FIND hFind = BluetoothFindFirstRadio(&params, &hRadio);
    if (hFind != nullptr)
    {
        status.available = true;
        BLUETOOTH_RADIO_INFO info{};
        info.dwSize = sizeof(info);
        if (BluetoothGetRadioInfo(hRadio, &info) == ERROR_SUCCESS)
        {
            status.enabled = true;
            status.radio_name = WideToUtf8(info.szName);
            std::ostringstream oss;
            oss << std::hex << std::setfill('0')
                << std::setw(2) << static_cast<int>(info.address.rgBytes[5]) << ":"
                << std::setw(2) << static_cast<int>(info.address.rgBytes[4]) << ":"
                << std::setw(2) << static_cast<int>(info.address.rgBytes[3]) << ":"
                << std::setw(2) << static_cast<int>(info.address.rgBytes[2]) << ":"
                << std::setw(2) << static_cast<int>(info.address.rgBytes[1]) << ":"
                << std::setw(2) << static_cast<int>(info.address.rgBytes[0]);
            status.address = oss.str();
        }
        CloseHandle(hRadio);
        BluetoothFindRadioClose(hFind);
    }
    return status;
}

std::vector<StorageDriveV25> SystemSettingsServiceV25::GetStorageDrives()
{
    std::vector<StorageDriveV25> drives;
    WCHAR buffer[512] = {0};
    DWORD len = GetLogicalDriveStringsW(511, buffer);
    if (len == 0) return drives;

    const WCHAR* p = buffer;
    while (*p)
    {
        std::wstring root = p;
        StorageDriveV25 drive;
        drive.drive_letter = WideToUtf8(root);

        UINT driveType = GetDriveTypeW(root.c_str());
        switch (driveType)
        {
        case DRIVE_FIXED:
            drive.drive_type = "Fixed";
            drive.is_removable = false;
            break;
        case DRIVE_REMOVABLE:
            drive.drive_type = "Removable";
            drive.is_removable = true;
            break;
        case DRIVE_REMOTE:
            drive.drive_type = "Network";
            drive.is_removable = false;
            break;
        case DRIVE_CDROM:
            drive.drive_type = "CD-ROM";
            drive.is_removable = true;
            break;
        case DRIVE_RAMDISK:
            drive.drive_type = "RAM Disk";
            drive.is_removable = false;
            break;
        default:
            drive.drive_type = "Unknown";
            drive.is_removable = false;
            break;
        }

        WCHAR volumeName[MAX_PATH + 1] = {0};
        WCHAR fsName[MAX_PATH + 1] = {0};
        if (GetVolumeInformationW(root.c_str(), volumeName, MAX_PATH, nullptr, nullptr, nullptr, fsName, MAX_PATH))
        {
            drive.volume_name = WideToUtf8(volumeName);
            drive.file_system = WideToUtf8(fsName);
        }

        ULARGE_INTEGER freeBytesCaller{}, totalBytes{}, totalFreeBytes{};
        if (GetDiskFreeSpaceExW(root.c_str(), &freeBytesCaller, &totalBytes, &totalFreeBytes))
        {
            drive.total_bytes = totalBytes.QuadPart;
            drive.free_bytes = freeBytesCaller.QuadPart;
            if (drive.total_bytes >= drive.free_bytes)
            {
                drive.used_bytes = drive.total_bytes - drive.free_bytes;
                drive.percent_used = (drive.total_bytes > 0) ? (static_cast<double>(drive.used_bytes) / static_cast<double>(drive.total_bytes) * 100.0) : 0.0;
            }
        }

        drives.push_back(std::move(drive));
        p += root.length() + 1;
    }

    return drives;
}

PersonalizationSettingsV25 SystemSettingsServiceV25::GetPersonalization()
{
    const std::wstring filePath = GetConfigFilePath();
    {
        std::ifstream file(filePath);
        if (!file.is_open())
        {
            return PersonalizationSettingsV25{}; // defaults
        }

        std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        file.close();

        if (!content.empty())
        {
            JsonValue root;
            if (ParseJson(content, root) && root.IsObject())
            {
                return PersonalizationSettingsV25::FromJsonObject(root.AsObject());
            }

            // Corruption detected: quarantine file to .corrupt.bak and recreate defaults
            const std::wstring corruptPath = filePath + L".corrupt.bak";
            (void)MoveFileExW(filePath.c_str(), corruptPath.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
            PersonalizationSettingsV25 defaults{};
            (void)SetPersonalization(defaults, nullptr);
            return defaults;
        }
    }
    return PersonalizationSettingsV25{};
}

bool SystemSettingsServiceV25::SetPersonalization(const PersonalizationSettingsV25& settings, std::string* error)
{
    const std::wstring filePath = GetConfigFilePath();
    const std::wstring tempPath = filePath + L".tmp";

    try
    {
        {
            std::ofstream file(tempPath, std::ios::trunc);
            if (!file.is_open())
            {
                if (error) *error = "Failed to open temporary settings file for writing";
                return false;
            }
            JsonObject obj = settings.ToJsonObject();
            file << SerializeJson(JsonValue(std::move(obj)));
        }

        if (!MoveFileExW(tempPath.c_str(), filePath.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        {
            if (error) *error = "Failed to replace settings file atomically: " + std::to_string(GetLastError());
            std::error_code ec;
            std::filesystem::remove(tempPath, ec);
            return false;
        }

        return true;
    }
    catch (const std::exception& ex)
    {
        if (error) *error = ex.what();
        return false;
    }
}

DateTimeLocaleV25 SystemSettingsServiceV25::GetDateTimeLocale()
{
    DateTimeLocaleV25 res;
    SYSTEMTIME st{};
    GetLocalTime(&st);

    std::ostringstream oss;
    oss << std::setfill('0')
        << std::setw(4) << st.wYear << "-"
        << std::setw(2) << st.wMonth << "-"
        << std::setw(2) << st.wDay << "T"
        << std::setw(2) << st.wHour << ":"
        << std::setw(2) << st.wMinute << ":"
        << std::setw(2) << st.wSecond;
    res.local_time = oss.str();

    DYNAMIC_TIME_ZONE_INFORMATION dtzi{};
    if (GetDynamicTimeZoneInformation(&dtzi) != TIME_ZONE_ID_INVALID)
    {
        res.timezone_name = WideToUtf8(dtzi.TimeZoneKeyName[0] ? dtzi.TimeZoneKeyName : dtzi.StandardName);
        res.bias_minutes = dtzi.Bias;
    }

    WCHAR localeName[LOCALE_NAME_MAX_LENGTH] = {0};
    if (GetUserDefaultLocaleName(localeName, LOCALE_NAME_MAX_LENGTH) > 0)
    {
        res.locale_name = WideToUtf8(localeName);
    }

    return res;
}

} // namespace CloudOS
