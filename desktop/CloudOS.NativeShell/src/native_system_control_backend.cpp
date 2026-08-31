#include <winsock2.h>
#include <ws2tcpip.h>

#include "native_system_control_backend.h"

#include <endpointvolume.h>
#include <functiondiscoverykeys_devpkey.h>
#include <highlevelmonitorconfigurationapi.h>
#include <iphlpapi.h>
#include <mmdeviceapi.h>
#include <physicalmonitorenumerationapi.h>
#include <powrprof.h>
#include <psapi.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <wlanapi.h>
#include <wbemidl.h>

#include <algorithm>
#include <array>
#include <cwchar>
#include <memory>
#include <sstream>
#include <vector>

#pragma comment(lib, "dxva2.lib")
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "powrprof.lib")
#pragma comment(lib, "psapi.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "wlanapi.lib")
#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "ws2_32.lib")

namespace CloudOS
{
namespace
{
struct WlanHandle final
{
    HANDLE value{};
    ~WlanHandle()
    {
        if (value != nullptr)
        {
            WlanCloseHandle(value, nullptr);
        }
    }
};

struct ComBalance final
{
    HRESULT result{};
    ComBalance()
        : result(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))
    {
    }
    ~ComBalance()
    {
        if (SUCCEEDED(result))
        {
            CoUninitialize();
        }
    }
    [[nodiscard]] bool Usable() const noexcept
    {
        return SUCCEEDED(result) || result == RPC_E_CHANGED_MODE;
    }
};

std::wstring ErrorCodeText(DWORD code)
{
    if (code == ERROR_SUCCESS)
    {
        return {};
    }

    wchar_t* raw = nullptr;
    const DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
            FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        code,
        0,
        reinterpret_cast<LPWSTR>(&raw),
        0,
        nullptr);
    std::wstring text;
    if (length != 0 && raw != nullptr)
    {
        text.assign(raw, length);
        while (!text.empty() &&
               (text.back() == L'\r' || text.back() == L'\n' || text.back() == L' '))
        {
            text.pop_back();
        }
    }
    if (raw != nullptr)
    {
        LocalFree(raw);
    }
    if (text.empty())
    {
        text = L"Erro Windows ";
        text += std::to_wstring(code);
    }
    return text;
}

void SetError(std::wstring* error, const std::wstring& value)
{
    if (error != nullptr)
    {
        *error = value;
    }
}

std::wstring SsidToString(const DOT11_SSID& ssid)
{
    if (ssid.uSSIDLength == 0)
    {
        return L"(rede oculta)";
    }

    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char*>(ssid.ucSSID),
        static_cast<int>(ssid.uSSIDLength),
        nullptr,
        0);
    if (required > 0)
    {
        std::wstring result(static_cast<std::size_t>(required), L'\0');
        MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            reinterpret_cast<const char*>(ssid.ucSSID),
            static_cast<int>(ssid.uSSIDLength),
            result.data(),
            required);
        return result;
    }

    const int ansi_required = MultiByteToWideChar(
        CP_ACP,
        0,
        reinterpret_cast<const char*>(ssid.ucSSID),
        static_cast<int>(ssid.uSSIDLength),
        nullptr,
        0);
    if (ansi_required <= 0)
    {
        return L"(SSID invalido)";
    }
    std::wstring result(static_cast<std::size_t>(ansi_required), L'\0');
    MultiByteToWideChar(
        CP_ACP,
        0,
        reinterpret_cast<const char*>(ssid.ucSSID),
        static_cast<int>(ssid.uSSIDLength),
        result.data(),
        ansi_required);
    return result;
}

bool OpenWlan(WlanHandle* out, DWORD* negotiated_version, std::wstring* error)
{
    if (out == nullptr || negotiated_version == nullptr)
    {
        SetError(error, L"Parametros invalidos para WLAN.");
        return false;
    }
    DWORD version = 0;
    HANDLE handle = nullptr;
    const DWORD result = WlanOpenHandle(
        WLAN_API_VERSION_2_0,
        nullptr,
        &version,
        &handle);
    if (result != ERROR_SUCCESS)
    {
        SetError(error, ErrorCodeText(result));
        return false;
    }
    out->value = handle;
    *negotiated_version = version;
    return true;
}

std::wstring GuidName(const GUID& guid)
{
    wchar_t buffer[64]{};
    if (StringFromGUID2(guid, buffer, static_cast<int>(std::size(buffer))) <= 0)
    {
        return L"interface";
    }
    return buffer;
}

std::wstring AudioFriendlyName(IMMDevice* device)
{
    if (device == nullptr)
    {
        return {};
    }
    IPropertyStore* store = nullptr;
    if (FAILED(device->OpenPropertyStore(STGM_READ, &store)) || store == nullptr)
    {
        return {};
    }
    PROPVARIANT value;
    PropVariantInit(&value);
    std::wstring result;
    if (SUCCEEDED(store->GetValue(PKEY_Device_FriendlyName, &value)) &&
        value.vt == VT_LPWSTR && value.pwszVal != nullptr)
    {
        result = value.pwszVal;
    }
    PropVariantClear(&value);
    store->Release();
    return result;
}

bool WithEndpointVolume(
    const std::function<bool(IAudioEndpointVolume*, IMMDevice*)>& callback,
    std::wstring* error)
{
    ComBalance com;
    if (!com.Usable())
    {
        SetError(error, L"COM indisponivel para audio.");
        return false;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || enumerator == nullptr)
    {
        SetError(error, L"Nao foi possivel acessar os dispositivos de audio.");
        return false;
    }

    IMMDevice* device = nullptr;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    enumerator->Release();
    if (FAILED(hr) || device == nullptr)
    {
        SetError(error, L"Nenhuma saida de audio padrao encontrada.");
        return false;
    }

    IAudioEndpointVolume* endpoint = nullptr;
    hr = device->Activate(
        __uuidof(IAudioEndpointVolume),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&endpoint));
    if (FAILED(hr) || endpoint == nullptr)
    {
        device->Release();
        SetError(error, L"O volume master nao esta disponivel.");
        return false;
    }

    const bool ok = callback(endpoint, device);
    endpoint->Release();
    device->Release();
    return ok;
}

struct DdcBrightnessContext final
{
    bool found{};
    unsigned current{};
    std::wstring description;
};

BOOL CALLBACK QueryDdcMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data)
{
    auto* context = reinterpret_cast<DdcBrightnessContext*>(data);
    if (context == nullptr || context->found)
    {
        return FALSE;
    }

    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0)
    {
        return TRUE;
    }

    std::vector<PHYSICAL_MONITOR> physical(count);
    if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical.data()))
    {
        return TRUE;
    }

    for (DWORD index = 0; index < count; ++index)
    {
        DWORD minimum = 0;
        DWORD current = 0;
        DWORD maximum = 0;
        if (GetMonitorBrightness(
                physical[index].hPhysicalMonitor,
                &minimum,
                &current,
                &maximum) &&
            maximum > minimum)
        {
            context->current = static_cast<unsigned>(
                ((current - minimum) * 100ull) / (maximum - minimum));
            context->description = physical[index].szPhysicalMonitorDescription;
            context->found = true;
            break;
        }
    }

    DestroyPhysicalMonitors(count, physical.data());
    return context->found ? FALSE : TRUE;
}

struct DdcSetContext final
{
    unsigned percent{};
    bool changed{};
};

BOOL CALLBACK SetDdcMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data)
{
    auto* context = reinterpret_cast<DdcSetContext*>(data);
    if (context == nullptr)
    {
        return FALSE;
    }

    DWORD count = 0;
    if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) || count == 0)
    {
        return TRUE;
    }

    std::vector<PHYSICAL_MONITOR> physical(count);
    if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical.data()))
    {
        return TRUE;
    }

    for (DWORD index = 0; index < count; ++index)
    {
        DWORD minimum = 0;
        DWORD current = 0;
        DWORD maximum = 0;
        if (GetMonitorBrightness(
                physical[index].hPhysicalMonitor,
                &minimum,
                &current,
                &maximum) &&
            maximum > minimum)
        {
            const DWORD target = minimum + static_cast<DWORD>(
                ((maximum - minimum) * static_cast<unsigned long long>(context->percent)) / 100ull);
            if (SetMonitorBrightness(physical[index].hPhysicalMonitor, target))
            {
                context->changed = true;
            }
        }
    }
    DestroyPhysicalMonitors(count, physical.data());
    return TRUE;
}

bool PrepareWmi(IWbemServices** services)
{
    if (services == nullptr)
    {
        return false;
    }
    *services = nullptr;

    IWbemLocator* locator = nullptr;
    HRESULT hr = CoCreateInstance(
        CLSID_WbemLocator,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IWbemLocator,
        reinterpret_cast<void**>(&locator));
    if (FAILED(hr) || locator == nullptr)
    {
        return false;
    }

    BSTR name_space = SysAllocString(L"ROOT\\WMI");
    IWbemServices* service = nullptr;
    hr = locator->ConnectServer(
        name_space,
        nullptr,
        nullptr,
        nullptr,
        0,
        nullptr,
        nullptr,
        &service);
    SysFreeString(name_space);
    locator->Release();
    if (FAILED(hr) || service == nullptr)
    {
        return false;
    }

    hr = CoSetProxyBlanket(
        service,
        RPC_C_AUTHN_WINNT,
        RPC_C_AUTHZ_NONE,
        nullptr,
        RPC_C_AUTHN_LEVEL_CALL,
        RPC_C_IMP_LEVEL_IMPERSONATE,
        nullptr,
        EOAC_NONE);
    if (FAILED(hr))
    {
        service->Release();
        return false;
    }
    *services = service;
    return true;
}

bool QueryWmiBrightness(unsigned* percent, std::wstring* instance_name)
{
    if (percent == nullptr)
    {
        return false;
    }

    ComBalance com;
    if (!com.Usable())
    {
        return false;
    }
    IWbemServices* services = nullptr;
    if (!PrepareWmi(&services))
    {
        return false;
    }

    IEnumWbemClassObject* enumerator = nullptr;
    BSTR language = SysAllocString(L"WQL");
    BSTR query = SysAllocString(L"SELECT CurrentBrightness,InstanceName FROM WmiMonitorBrightness WHERE Active=TRUE");
    const HRESULT hr = services->ExecQuery(
        language,
        query,
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        nullptr,
        &enumerator);
    SysFreeString(language);
    SysFreeString(query);
    if (FAILED(hr) || enumerator == nullptr)
    {
        services->Release();
        return false;
    }

    IWbemClassObject* object = nullptr;
    ULONG returned = 0;
    const HRESULT next = enumerator->Next(1200, 1, &object, &returned);
    bool ok = false;
    if (SUCCEEDED(next) && returned == 1 && object != nullptr)
    {
        VARIANT brightness;
        VariantInit(&brightness);
        if (SUCCEEDED(object->Get(L"CurrentBrightness", 0, &brightness, nullptr, nullptr)))
        {
            if (brightness.vt == VT_UI1)
            {
                *percent = brightness.bVal;
                ok = true;
            }
            else if (brightness.vt == VT_I4)
            {
                *percent = static_cast<unsigned>(std::clamp<LONG>(brightness.lVal, 0, 100));
                ok = true;
            }
        }
        VariantClear(&brightness);

        if (instance_name != nullptr)
        {
            VARIANT name;
            VariantInit(&name);
            if (SUCCEEDED(object->Get(L"InstanceName", 0, &name, nullptr, nullptr)) &&
                name.vt == VT_BSTR && name.bstrVal != nullptr)
            {
                *instance_name = name.bstrVal;
            }
            VariantClear(&name);
        }
        object->Release();
    }

    enumerator->Release();
    services->Release();
    return ok;
}

bool SetWmiBrightness(unsigned percent)
{
    ComBalance com;
    if (!com.Usable())
    {
        return false;
    }
    IWbemServices* services = nullptr;
    if (!PrepareWmi(&services))
    {
        return false;
    }

    IEnumWbemClassObject* enumerator = nullptr;
    BSTR language = SysAllocString(L"WQL");
    BSTR query = SysAllocString(L"SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE");
    HRESULT hr = services->ExecQuery(
        language,
        query,
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        nullptr,
        &enumerator);
    SysFreeString(language);
    SysFreeString(query);
    if (FAILED(hr) || enumerator == nullptr)
    {
        services->Release();
        return false;
    }

    IWbemClassObject* object = nullptr;
    ULONG returned = 0;
    hr = enumerator->Next(1200, 1, &object, &returned);
    bool success = false;
    if (SUCCEEDED(hr) && returned == 1 && object != nullptr)
    {
        VARIANT path;
        VariantInit(&path);
        if (SUCCEEDED(object->Get(L"__PATH", 0, &path, nullptr, nullptr)) &&
            path.vt == VT_BSTR && path.bstrVal != nullptr)
        {
            IWbemClassObject* class_object = nullptr;
            BSTR class_name = SysAllocString(L"WmiMonitorBrightnessMethods");
            if (SUCCEEDED(services->GetObject(class_name, 0, nullptr, &class_object, nullptr)) &&
                class_object != nullptr)
            {
                IWbemClassObject* in_signature = nullptr;
                BSTR method = SysAllocString(L"WmiSetBrightness");
                if (SUCCEEDED(class_object->GetMethod(method, 0, &in_signature, nullptr)) &&
                    in_signature != nullptr)
                {
                    IWbemClassObject* in_params = nullptr;
                    if (SUCCEEDED(in_signature->SpawnInstance(0, &in_params)) && in_params != nullptr)
                    {
                        VARIANT timeout;
                        VariantInit(&timeout);
                        timeout.vt = VT_UI4;
                        timeout.ulVal = 1;
                        (void)in_params->Put(L"Timeout", 0, &timeout, 0);

                        VARIANT brightness;
                        VariantInit(&brightness);
                        brightness.vt = VT_UI1;
                        brightness.bVal = static_cast<BYTE>(percent);
                        (void)in_params->Put(L"Brightness", 0, &brightness, 0);

                        IWbemClassObject* out_params = nullptr;
                        const HRESULT call = services->ExecMethod(
                            path.bstrVal,
                            method,
                            0,
                            nullptr,
                            in_params,
                            &out_params,
                            nullptr);
                        success = SUCCEEDED(call);
                        if (out_params != nullptr)
                        {
                            out_params->Release();
                        }
                        in_params->Release();
                    }
                    in_signature->Release();
                }
                SysFreeString(method);
                class_object->Release();
            }
            SysFreeString(class_name);
        }
        VariantClear(&path);
        object->Release();
    }

    enumerator->Release();
    services->Release();
    return success;
}

std::wstring AddressText(const SOCKADDR* address)
{
    if (address == nullptr)
    {
        return {};
    }
    wchar_t buffer[INET6_ADDRSTRLEN]{};
    if (address->sa_family == AF_INET)
    {
        const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(address);
        if (InetNtopW(AF_INET, const_cast<IN_ADDR*>(&ipv4->sin_addr), buffer, static_cast<DWORD>(std::size(buffer))) != nullptr)
        {
            return buffer;
        }
    }
    else if (address->sa_family == AF_INET6)
    {
        const auto* ipv6 = reinterpret_cast<const sockaddr_in6*>(address);
        if (InetNtopW(AF_INET6, const_cast<IN6_ADDR*>(&ipv6->sin6_addr), buffer, static_cast<DWORD>(std::size(buffer))) != nullptr)
        {
            return buffer;
        }
    }
    return {};
}

std::wstring MacText(const BYTE* bytes, ULONG length)
{
    if (bytes == nullptr || length == 0)
    {
        return {};
    }
    std::wstringstream stream;
    stream.setf(std::ios::hex, std::ios::basefield);
    stream.setf(std::ios::uppercase);
    stream.fill(L'0');
    for (ULONG index = 0; index < length; ++index)
    {
        if (index != 0)
        {
            stream << L'-';
        }
        stream.width(2);
        stream << static_cast<unsigned>(bytes[index]);
    }
    return stream.str();
}

std::wstring AdapterState(IF_OPER_STATUS status)
{
    switch (status)
    {
    case IfOperStatusUp: return L"Conectado";
    case IfOperStatusDown: return L"Desconectado";
    case IfOperStatusDormant: return L"Em espera";
    case IfOperStatusNotPresent: return L"Ausente";
    case IfOperStatusLowerLayerDown: return L"Camada inferior inativa";
    default: return L"Desconhecido";
    }
}

std::wstring DriveTypeLabel(UINT type)
{
    switch (type)
    {
    case DRIVE_FIXED: return L"Disco local";
    case DRIVE_REMOVABLE: return L"Removivel";
    case DRIVE_REMOTE: return L"Rede";
    case DRIVE_CDROM: return L"Optico";
    case DRIVE_RAMDISK: return L"RAM disk";
    default: return L"Outro";
    }
}

std::wstring ServiceStateLabel(DWORD state)
{
    switch (state)
    {
    case SERVICE_RUNNING: return L"Executando";
    case SERVICE_STOPPED: return L"Parado";
    case SERVICE_START_PENDING: return L"Iniciando";
    case SERVICE_STOP_PENDING: return L"Parando";
    case SERVICE_PAUSED: return L"Pausado";
    default: return L"Transicao";
    }
}

bool SetPlan(const GUID& plan, std::wstring* error)
{
    const DWORD result = PowerSetActiveScheme(nullptr, &plan);
    if (result != ERROR_SUCCESS)
    {
        SetError(error, ErrorCodeText(result));
        return false;
    }
    return true;
}

BOOL CALLBACK CountMonitor(HMONITOR, HDC, LPRECT, LPARAM data)
{
    auto* count = reinterpret_cast<unsigned*>(data);
    if (count != nullptr)
    {
        ++(*count);
    }
    return TRUE;
}
}

NativeSystemSummary NativeSystemControlBackend::QuerySummary()
{
    NativeSystemSummary summary{};
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory))
    {
        summary.memory_load_percent = memory.dwMemoryLoad;
        summary.total_memory_bytes = memory.ullTotalPhys;
        summary.available_memory_bytes = memory.ullAvailPhys;
    }

    PERFORMANCE_INFORMATION performance{};
    performance.cb = sizeof(performance);
    if (GetPerformanceInfo(&performance, sizeof(performance)))
    {
        summary.process_count = performance.ProcessCount;
    }

    unsigned monitors = 0;
    EnumDisplayMonitors(nullptr, nullptr, CountMonitor, reinterpret_cast<LPARAM>(&monitors));
    summary.monitor_count = monitors;
    summary.adapter_count = static_cast<unsigned>(QueryAdapters().size());
    summary.drive_count = static_cast<unsigned>(QueryDrives().size());
    return summary;
}

NativeWifiNetwork NativeSystemControlBackend::QueryWifiConnection()
{
    NativeWifiNetwork result{}; WlanHandle handle; DWORD version{};
    if(!OpenWlan(&handle,&version,nullptr)) return result;
    PWLAN_INTERFACE_INFO_LIST interfaces{};
    if(WlanEnumInterfaces(handle.value,nullptr,&interfaces)!=ERROR_SUCCESS || !interfaces) return result;
    for(DWORD index=0; index<interfaces->dwNumberOfItems; ++index)
    {
        const auto& info=interfaces->InterfaceInfo[index];
        result.interface_name=info.strInterfaceDescription;
        PWLAN_CONNECTION_ATTRIBUTES connection{}; DWORD size{}; WLAN_OPCODE_VALUE_TYPE opcode{};
        if(WlanQueryInterface(handle.value,&info.InterfaceGuid,wlan_intf_opcode_current_connection,nullptr,&size,reinterpret_cast<PVOID*>(&connection),&opcode)==ERROR_SUCCESS && connection)
        {
            result.connected=connection->isState==wlan_interface_state_connected;
            result.ssid=SsidToString(connection->wlanAssociationAttributes.dot11Ssid);
            result.signal_quality=connection->wlanAssociationAttributes.wlanSignalQuality;
            WlanFreeMemory(connection);
            if(result.connected) break;
        }
    }
    WlanFreeMemory(interfaces); return result;
}

std::vector<NativeWifiNetwork> NativeSystemControlBackend::ScanWifi()
{
    std::vector<NativeWifiNetwork> result;
    WlanHandle handle;
    DWORD negotiated = 0;
    if (!OpenWlan(&handle, &negotiated, nullptr))
    {
        return result;
    }

    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(handle.value, nullptr, &interfaces) != ERROR_SUCCESS || interfaces == nullptr)
    {
        return result;
    }

    for (DWORD interface_index = 0; interface_index < interfaces->dwNumberOfItems; ++interface_index)
    {
        const WLAN_INTERFACE_INFO& interface_info = interfaces->InterfaceInfo[interface_index];
        std::wstring connected_ssid;
        std::wstring connected_profile;

        PWLAN_CONNECTION_ATTRIBUTES connection = nullptr;
        DWORD connection_size = 0;
        WLAN_OPCODE_VALUE_TYPE opcode{};
        if (WlanQueryInterface(
                handle.value,
                &interface_info.InterfaceGuid,
                wlan_intf_opcode_current_connection,
                nullptr,
                &connection_size,
                reinterpret_cast<PVOID*>(&connection),
                &opcode) == ERROR_SUCCESS &&
            connection != nullptr)
        {
            connected_ssid = SsidToString(connection->wlanAssociationAttributes.dot11Ssid);
            connected_profile = connection->strProfileName;
            WlanFreeMemory(connection);
        }

        PWLAN_AVAILABLE_NETWORK_LIST networks = nullptr;
        const DWORD scan = WlanGetAvailableNetworkList(
            handle.value,
            &interface_info.InterfaceGuid,
            WLAN_AVAILABLE_NETWORK_INCLUDE_ALL_MANUAL_HIDDEN_PROFILES,
            nullptr,
            &networks);
        if (scan != ERROR_SUCCESS || networks == nullptr)
        {
            continue;
        }

        for (DWORD index = 0; index < networks->dwNumberOfItems; ++index)
        {
            const WLAN_AVAILABLE_NETWORK& network = networks->Network[index];
            NativeWifiNetwork item{};
            item.interface_guid = interface_info.InterfaceGuid;
            item.interface_name = interface_info.strInterfaceDescription;
            if (item.interface_name.empty())
            {
                item.interface_name = GuidName(interface_info.InterfaceGuid);
            }
            item.ssid = SsidToString(network.dot11Ssid);
            item.profile_name = network.strProfileName;
            item.signal_quality = std::min<unsigned>(100u, network.wlanSignalQuality);
            item.secure = network.bSecurityEnabled != FALSE;
            item.connected = !connected_ssid.empty() && _wcsicmp(item.ssid.c_str(), connected_ssid.c_str()) == 0;
            if (!connected_profile.empty() && !item.profile_name.empty() &&
                _wcsicmp(item.profile_name.c_str(), connected_profile.c_str()) == 0)
            {
                item.connected = true;
            }
            result.push_back(std::move(item));
        }
        WlanFreeMemory(networks);
    }
    WlanFreeMemory(interfaces);

    std::sort(
        result.begin(),
        result.end(),
        [](const NativeWifiNetwork& left, const NativeWifiNetwork& right)
        {
            if (left.connected != right.connected)
            {
                return left.connected > right.connected;
            }
            if (left.signal_quality != right.signal_quality)
            {
                return left.signal_quality > right.signal_quality;
            }
            return _wcsicmp(left.ssid.c_str(), right.ssid.c_str()) < 0;
        });
    return result;
}

bool NativeSystemControlBackend::ConnectKnownWifi(
    const NativeWifiNetwork& network,
    std::wstring* error)
{
    if (network.profile_name.empty())
    {
        SetError(error, L"Essa rede ainda nao possui perfil salvo no Windows. Abra as configuracoes de Wi-Fi para informar a senha uma vez.");
        return false;
    }

    WlanHandle handle;
    DWORD negotiated = 0;
    if (!OpenWlan(&handle, &negotiated, error))
    {
        return false;
    }

    WLAN_CONNECTION_PARAMETERS parameters{};
    parameters.wlanConnectionMode = wlan_connection_mode_profile;
    parameters.strProfile = network.profile_name.c_str();
    parameters.pDot11Ssid = nullptr;
    parameters.pDesiredBssidList = nullptr;
    parameters.dot11BssType = dot11_BSS_type_any;
    parameters.dwFlags = 0;

    const DWORD result = WlanConnect(
        handle.value,
        &network.interface_guid,
        &parameters,
        nullptr);
    if (result != ERROR_SUCCESS)
    {
        SetError(error, ErrorCodeText(result));
        return false;
    }
    return true;
}

bool NativeSystemControlBackend::DisconnectWifi(
    const GUID& interface_guid,
    std::wstring* error)
{
    WlanHandle handle;
    DWORD negotiated = 0;
    if (!OpenWlan(&handle, &negotiated, error))
    {
        return false;
    }
    const DWORD result = WlanDisconnect(handle.value, &interface_guid, nullptr);
    if (result != ERROR_SUCCESS)
    {
        SetError(error, ErrorCodeText(result));
        return false;
    }
    return true;
}

NativeAudioState NativeSystemControlBackend::QueryAudio()
{
    NativeAudioState state{};
    (void)WithEndpointVolume(
        [&state](IAudioEndpointVolume* endpoint, IMMDevice* device)
        {
            float scalar = 0.0f;
            BOOL muted = FALSE;
            if (FAILED(endpoint->GetMasterVolumeLevelScalar(&scalar)) ||
                FAILED(endpoint->GetMute(&muted)))
            {
                return false;
            }
            state.available = true;
            state.muted = muted != FALSE;
            state.volume_percent = static_cast<unsigned>(
                std::clamp<int>(static_cast<int>(scalar * 100.0f + 0.5f), 0, 100));
            state.endpoint_name = AudioFriendlyName(device);
            return true;
        },
        nullptr);
    return state;
}

bool NativeSystemControlBackend::SetMasterVolume(unsigned percent, std::wstring* error)
{
    percent = std::min<unsigned>(100u, percent);
    return WithEndpointVolume(
        [percent, error](IAudioEndpointVolume* endpoint, IMMDevice*)
        {
            const HRESULT hr = endpoint->SetMasterVolumeLevelScalar(
                static_cast<float>(percent) / 100.0f,
                nullptr);
            if (FAILED(hr))
            {
                SetError(error, L"O Windows recusou a alteracao do volume master.");
                return false;
            }
            return true;
        },
        error);
}

bool NativeSystemControlBackend::SetMasterMute(bool muted, std::wstring* error)
{
    return WithEndpointVolume(
        [muted, error](IAudioEndpointVolume* endpoint, IMMDevice*)
        {
            const HRESULT hr = endpoint->SetMute(muted ? TRUE : FALSE, nullptr);
            if (FAILED(hr))
            {
                SetError(error, L"O Windows recusou a alteracao de mute.");
                return false;
            }
            return true;
        },
        error);
}

NativeBrightnessState NativeSystemControlBackend::QueryBrightness()
{
    NativeBrightnessState state{};
    DdcBrightnessContext ddc{};
    EnumDisplayMonitors(nullptr, nullptr, QueryDdcMonitor, reinterpret_cast<LPARAM>(&ddc));
    if (ddc.found)
    {
        state.available = true;
        state.percent = std::min<unsigned>(100u, ddc.current);
        state.source = L"DDC/CI";
        state.monitor_name = ddc.description;
        return state;
    }

    unsigned wmi = 0;
    std::wstring instance;
    if (QueryWmiBrightness(&wmi, &instance))
    {
        state.available = true;
        state.percent = std::min<unsigned>(100u, wmi);
        state.source = L"WMI";
        state.monitor_name = instance.empty() ? L"Tela integrada" : instance;
    }
    return state;
}

bool NativeSystemControlBackend::SetBrightness(unsigned percent, std::wstring* error)
{
    percent = std::min<unsigned>(100u, percent);
    DdcSetContext ddc{percent, false};
    EnumDisplayMonitors(nullptr, nullptr, SetDdcMonitor, reinterpret_cast<LPARAM>(&ddc));
    if (ddc.changed)
    {
        return true;
    }
    if (SetWmiBrightness(percent))
    {
        return true;
    }
    SetError(error, L"Nenhum monitor aceitou controle de brilho por DDC/CI ou WMI. Monitores desktop podem exigir DDC/CI habilitado no menu fisico.");
    return false;
}

NativePowerState NativeSystemControlBackend::QueryPower()
{
    NativePowerState state{};
    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power))
    {
        state.battery_present = power.BatteryFlag != 128 && power.BatteryFlag != 255;
        state.on_ac = power.ACLineStatus == 1;
        state.battery_percent = power.BatteryLifePercent == 255 ? 0u : power.BatteryLifePercent;
        state.battery_life_seconds = power.BatteryLifeTime;
    }

    GUID* active = nullptr;
    if (PowerGetActiveScheme(nullptr, &active) == ERROR_SUCCESS && active != nullptr)
    {
        if (IsEqualGUID(*active, GUID_TYPICAL_POWER_SAVINGS))
        {
            state.active_plan = L"Equilibrado";
        }
        else if (IsEqualGUID(*active, GUID_MAX_POWER_SAVINGS))
        {
            state.active_plan = L"Economia de energia";
        }
        else if (IsEqualGUID(*active, GUID_MIN_POWER_SAVINGS))
        {
            state.active_plan = L"Alto desempenho";
        }
        else
        {
            state.active_plan = L"Plano personalizado";
        }
        LocalFree(active);
    }
    return state;
}

bool NativeSystemControlBackend::SetBalancedPowerPlan(std::wstring* error)
{
    return SetPlan(GUID_TYPICAL_POWER_SAVINGS, error);
}

bool NativeSystemControlBackend::SetPowerSaverPlan(std::wstring* error)
{
    return SetPlan(GUID_MAX_POWER_SAVINGS, error);
}

bool NativeSystemControlBackend::SetHighPerformancePlan(std::wstring* error)
{
    return SetPlan(GUID_MIN_POWER_SAVINGS, error);
}

std::vector<NativeNetworkAdapter> NativeSystemControlBackend::QueryAdapters()
{
    std::vector<NativeNetworkAdapter> result;
    ULONG size = 16 * 1024;
    std::vector<BYTE> storage(size);
    auto* addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(storage.data());
    ULONG call = GetAdaptersAddresses(
        AF_UNSPEC,
        GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST,
        nullptr,
        addresses,
        &size);
    if (call == ERROR_BUFFER_OVERFLOW)
    {
        storage.resize(size);
        addresses = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(storage.data());
        call = GetAdaptersAddresses(
            AF_UNSPEC,
            GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST,
            nullptr,
            addresses,
            &size);
    }
    if (call != NO_ERROR)
    {
        return result;
    }

    for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next)
    {
        if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK)
        {
            continue;
        }
        NativeNetworkAdapter item{};
        item.name = adapter->FriendlyName != nullptr ? adapter->FriendlyName : L"Adaptador";
        item.description = adapter->Description != nullptr ? adapter->Description : L"";
        item.status = AdapterState(adapter->OperStatus);
        item.mac = MacText(adapter->PhysicalAddress, adapter->PhysicalAddressLength);
        item.transmit_mbps = adapter->TransmitLinkSpeed / 1'000'000ull;
        item.receive_mbps = adapter->ReceiveLinkSpeed / 1'000'000ull;

        for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr; unicast = unicast->Next)
        {
            const std::wstring address = AddressText(unicast->Address.lpSockaddr);
            if (address.empty())
            {
                continue;
            }
            if (unicast->Address.lpSockaddr->sa_family == AF_INET && item.ipv4.empty())
            {
                item.ipv4 = address;
            }
            else if (unicast->Address.lpSockaddr->sa_family == AF_INET6 && item.ipv6.empty())
            {
                item.ipv6 = address;
            }
        }
        result.push_back(std::move(item));
    }

    std::sort(
        result.begin(),
        result.end(),
        [](const NativeNetworkAdapter& left, const NativeNetworkAdapter& right)
        {
            if (left.status != right.status)
            {
                return left.status == L"Conectado";
            }
            return _wcsicmp(left.name.c_str(), right.name.c_str()) < 0;
        });
    return result;
}

std::vector<NativeDriveInfo> NativeSystemControlBackend::QueryDrives()
{
    std::vector<NativeDriveInfo> result;
    std::array<wchar_t, 1024> drives{};
    const DWORD length = GetLogicalDriveStringsW(static_cast<DWORD>(drives.size()), drives.data());
    if (length == 0 || length >= drives.size())
    {
        return result;
    }

    const wchar_t* cursor = drives.data();
    while (*cursor != L'\0')
    {
        NativeDriveInfo item{};
        item.root = cursor;
        item.type = DriveTypeLabel(GetDriveTypeW(cursor));

        wchar_t label[MAX_PATH]{};
        wchar_t file_system[MAX_PATH]{};
        if (GetVolumeInformationW(
                cursor,
                label,
                static_cast<DWORD>(std::size(label)),
                nullptr,
                nullptr,
                nullptr,
                file_system,
                static_cast<DWORD>(std::size(file_system))))
        {
            item.label = label;
            item.file_system = file_system;
        }

        ULARGE_INTEGER free_bytes{};
        ULARGE_INTEGER total_bytes{};
        ULARGE_INTEGER total_free{};
        if (GetDiskFreeSpaceExW(cursor, &free_bytes, &total_bytes, &total_free))
        {
            item.total_bytes = total_bytes.QuadPart;
            item.free_bytes = free_bytes.QuadPart;
        }
        result.push_back(std::move(item));
        cursor += std::wcslen(cursor) + 1;
    }
    return result;
}

std::vector<NativeProcessInfo> NativeSystemControlBackend::QueryProcesses(std::size_t maximum)
{
    std::vector<NativeProcessInfo> result;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return result;
    }

    PROCESSENTRY32W process{};
    process.dwSize = sizeof(process);
    if (Process32FirstW(snapshot, &process))
    {
        do
        {
            NativeProcessInfo item{};
            item.process_id = process.th32ProcessID;
            item.name = process.szExeFile;

            HANDLE handle = OpenProcess(
                PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                FALSE,
                process.th32ProcessID);
            if (handle != nullptr)
            {
                PROCESS_MEMORY_COUNTERS_EX memory{};
                if (GetProcessMemoryInfo(
                        handle,
                        reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory),
                        sizeof(memory)))
                {
                    item.working_set_bytes = memory.WorkingSetSize;
                    item.private_bytes = memory.PrivateUsage;
                }
                CloseHandle(handle);
            }
            result.push_back(std::move(item));
        } while (Process32NextW(snapshot, &process));
    }
    CloseHandle(snapshot);

    std::sort(
        result.begin(),
        result.end(),
        [](const NativeProcessInfo& left, const NativeProcessInfo& right)
        {
            if (left.working_set_bytes != right.working_set_bytes)
            {
                return left.working_set_bytes > right.working_set_bytes;
            }
            return left.process_id < right.process_id;
        });
    if (result.size() > maximum)
    {
        result.resize(maximum);
    }
    return result;
}

std::vector<NativeServiceInfo> NativeSystemControlBackend::QueryCoreServices()
{
    struct ServiceRequest final
    {
        const wchar_t* name;
        const wchar_t* display;
    };
    static constexpr ServiceRequest requests[]{
        {L"WlanSvc", L"Wi-Fi (WLAN AutoConfig)"},
        {L"AudioSrv", L"Audio do Windows"},
        {L"bthserv", L"Bluetooth Support Service"},
        {L"Dnscache", L"Cliente DNS"},
        {L"Dhcp", L"Cliente DHCP"},
        {L"EventLog", L"Log de Eventos"},
        {L"Winmgmt", L"WMI"},
        {L"wuauserv", L"Windows Update"},
    };

    std::vector<NativeServiceInfo> result;
    SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (manager == nullptr)
    {
        return result;
    }

    for (const auto& request : requests)
    {
        NativeServiceInfo item{};
        item.name = request.name;
        item.display_name = request.display;
        SC_HANDLE service = OpenServiceW(manager, request.name, SERVICE_QUERY_STATUS);
        if (service == nullptr)
        {
            item.state = L"Indisponivel";
            result.push_back(std::move(item));
            continue;
        }

        SERVICE_STATUS_PROCESS status{};
        DWORD needed = 0;
        if (QueryServiceStatusEx(
                service,
                SC_STATUS_PROCESS_INFO,
                reinterpret_cast<LPBYTE>(&status),
                sizeof(status),
                &needed))
        {
            item.state = ServiceStateLabel(status.dwCurrentState);
        }
        else
        {
            item.state = L"Erro";
        }
        CloseServiceHandle(service);
        result.push_back(std::move(item));
    }
    CloseServiceHandle(manager);
    return result;
}

bool NativeSystemControlBackend::OpenWindowsTarget(
    HWND owner,
    const wchar_t* target,
    const wchar_t* parameters)
{
    if (target == nullptr || *target == L'\0')
    {
        return false;
    }
    const HINSTANCE result = ShellExecuteW(
        owner,
        L"open",
        target,
        parameters != nullptr && *parameters != L'\0' ? parameters : nullptr,
        nullptr,
        SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(result) > 32;
}

std::wstring NativeSystemControlBackend::FormatBytes(std::uint64_t bytes)
{
    static constexpr const wchar_t* units[]{L"B", L"KB", L"MB", L"GB", L"TB"};
    double value = static_cast<double>(bytes);
    std::size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < std::size(units))
    {
        value /= 1024.0;
        ++unit;
    }
    wchar_t buffer[64]{};
    if (unit == 0)
    {
        swprintf_s(buffer, L"%.0f %s", value, units[unit]);
    }
    else
    {
        swprintf_s(buffer, L"%.1f %s", value, units[unit]);
    }
    return buffer;
}
} // namespace CloudOS
