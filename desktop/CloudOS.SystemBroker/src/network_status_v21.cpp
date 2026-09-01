#include <winsock2.h>
#include <ws2tcpip.h>

#include "network_status_v21.h"

#include <Windows.h>
#include <iphlpapi.h>
#include <wlanapi.h>

#include <algorithm>
#include <string>
#include <vector>

namespace CloudOS
{
namespace
{
std::string WideToUtf8(const std::wstring& value)
{
    if (value.empty()) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};

    std::string result(static_cast<std::size_t>(required), '\0');
    WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        required,
        nullptr,
        nullptr);
    return result;
}

std::string SsidToUtf8(const DOT11_SSID& ssid)
{
    if (ssid.uSSIDLength == 0) return {};

    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(ssid.ucSSID),
        static_cast<int>(ssid.uSSIDLength),
        nullptr,
        0);
    if (required <= 0)
    {
        return std::string(
            reinterpret_cast<const char*>(ssid.ucSSID),
            reinterpret_cast<const char*>(ssid.ucSSID) + ssid.uSSIDLength);
    }

    std::wstring wide(static_cast<std::size_t>(required), L'\0');
    MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(ssid.ucSSID),
        static_cast<int>(ssid.uSSIDLength),
        wide.data(),
        required);
    return WideToUtf8(wide);
}

NetworkStatusV21 QueryWifi()
{
    NetworkStatusV21 status{};
    DWORD negotiated_version = 0;
    HANDLE wlan = nullptr;
    if (WlanOpenHandle(
            WLAN_API_VERSION_2_0,
            nullptr,
            &negotiated_version,
            &wlan) != ERROR_SUCCESS ||
        wlan == nullptr)
    {
        return status;
    }

    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(wlan, nullptr, &interfaces) == ERROR_SUCCESS &&
        interfaces != nullptr)
    {
        for (DWORD index = 0; index < interfaces->dwNumberOfItems; ++index)
        {
            const WLAN_INTERFACE_INFO& info = interfaces->InterfaceInfo[index];
            if (info.isState != wlan_interface_state_connected)
            {
                continue;
            }

            PWLAN_CONNECTION_ATTRIBUTES connection = nullptr;
            DWORD size = 0;
            WLAN_OPCODE_VALUE_TYPE opcode{};
            if (WlanQueryInterface(
                    wlan,
                    &info.InterfaceGuid,
                    wlan_intf_opcode_current_connection,
                    nullptr,
                    &size,
                    reinterpret_cast<PVOID*>(&connection),
                    &opcode) == ERROR_SUCCESS &&
                connection != nullptr)
            {
                status.available = true;
                status.name = SsidToUtf8(
                    connection->wlanAssociationAttributes.dot11Ssid);
                if (status.name.empty())
                {
                    status.name = WideToUtf8(info.strInterfaceDescription);
                }
                status.transport = "wifi";
                WlanFreeMemory(connection);
                break;
            }
        }
        WlanFreeMemory(interfaces);
    }

    WlanCloseHandle(wlan, nullptr);
    return status;
}

NetworkStatusV21 QueryActiveAdapter()
{
    NetworkStatusV21 status{};
    ULONG size = 16 * 1024;
    std::vector<BYTE> storage(size);
    auto* addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(storage.data());

    ULONG result = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr,
        addresses,
        &size);
    if (result == ERROR_BUFFER_OVERFLOW)
    {
        storage.resize(size);
        addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(storage.data());
        result = GetAdaptersAddresses(
            AF_UNSPEC,
            GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
            nullptr,
            addresses,
            &size);
    }
    if (result != NO_ERROR)
    {
        return status;
    }

    for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next)
    {
        if (adapter->OperStatus != IfOperStatusUp ||
            adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
            adapter->FirstUnicastAddress == nullptr)
        {
            continue;
        }

        status.available = true;
        status.name = adapter->FriendlyName != nullptr
            ? WideToUtf8(adapter->FriendlyName)
            : "Rede Windows";
        status.transport = adapter->IfType == IF_TYPE_IEEE80211
            ? "wifi"
            : adapter->IfType == IF_TYPE_ETHERNET_CSMACD
                ? "ethernet"
                : "network";
        break;
    }
    return status;
}
} // namespace

NetworkStatusV21 NetworkStatusServiceV21::Query()
{
    NetworkStatusV21 status = QueryWifi();
    if (status.available)
    {
        return status;
    }
    return QueryActiveAdapter();
}

} // namespace CloudOS
