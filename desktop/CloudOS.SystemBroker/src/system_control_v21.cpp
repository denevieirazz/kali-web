#include "system_control_v21.h"

#include <Windows.h>
#include <endpointvolume.h>
#include <highlevelmonitorconfigurationapi.h>
#include <mmdeviceapi.h>
#include <physicalmonitorenumerationapi.h>
#include <wbemidl.h>

#include <algorithm>
#include <vector>

namespace CloudOS
{
namespace
{
class ComScope final
{
public:
    ComScope() noexcept
        : result_(CoInitializeEx(nullptr, COINIT_MULTITHREADED))
    {
    }

    ~ComScope()
    {
        if (SUCCEEDED(result_))
        {
            CoUninitialize();
        }
    }

    [[nodiscard]] bool Usable() const noexcept
    {
        return SUCCEEDED(result_) || result_ == RPC_E_CHANGED_MODE;
    }

private:
    HRESULT result_{};
};

template <typename Callback>
bool WithEndpointVolume(Callback&& callback)
{
    ComScope com;
    if (!com.Usable())
    {
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
        return false;
    }

    IMMDevice* device = nullptr;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    enumerator->Release();
    if (FAILED(hr) || device == nullptr)
    {
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
        return false;
    }

    const bool result = callback(endpoint);
    endpoint->Release();
    device->Release();
    return result;
}

struct DdcQueryContext final
{
    bool found{};
    unsigned percent{};
};

BOOL CALLBACK QueryDdcMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM parameter)
{
    auto* context = reinterpret_cast<DdcQueryContext*>(parameter);
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
            context->percent = static_cast<unsigned>(
                ((current - minimum) * 100ull) / (maximum - minimum));
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

BOOL CALLBACK SetDdcMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM parameter)
{
    auto* context = reinterpret_cast<DdcSetContext*>(parameter);
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
                ((maximum - minimum) * static_cast<unsigned long long>(context->percent)) /
                100ull);
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

bool QueryWmiBrightness(unsigned* percent)
{
    if (percent == nullptr)
    {
        return false;
    }

    ComScope com;
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
    BSTR query = SysAllocString(
        L"SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active=TRUE");
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
    bool success = false;
    if (SUCCEEDED(next) && returned == 1 && object != nullptr)
    {
        VARIANT brightness;
        VariantInit(&brightness);
        if (SUCCEEDED(object->Get(L"CurrentBrightness", 0, &brightness, nullptr, nullptr)))
        {
            if (brightness.vt == VT_UI1)
            {
                *percent = brightness.bVal;
                success = true;
            }
            else if (brightness.vt == VT_I4)
            {
                *percent = static_cast<unsigned>(
                    std::clamp<LONG>(brightness.lVal, 0, 100));
                success = true;
            }
        }
        VariantClear(&brightness);
        object->Release();
    }

    enumerator->Release();
    services->Release();
    return success;
}

bool SetWmiBrightness(unsigned percent)
{
    ComScope com;
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
    BSTR query = SysAllocString(
        L"SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE");
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
            if (SUCCEEDED(services->GetObject(
                    class_name,
                    0,
                    nullptr,
                    &class_object,
                    nullptr)) &&
                class_object != nullptr)
            {
                IWbemClassObject* in_signature = nullptr;
                BSTR method = SysAllocString(L"WmiSetBrightness");
                if (SUCCEEDED(class_object->GetMethod(
                        method,
                        0,
                        &in_signature,
                        nullptr)) &&
                    in_signature != nullptr)
                {
                    IWbemClassObject* in_params = nullptr;
                    if (SUCCEEDED(in_signature->SpawnInstance(0, &in_params)) &&
                        in_params != nullptr)
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
} // namespace

AudioControlStateV21 SystemControlV21::QueryAudio()
{
    AudioControlStateV21 state{};
    (void)WithEndpointVolume(
        [&state](IAudioEndpointVolume* endpoint)
        {
            float scalar = 0.0f;
            if (FAILED(endpoint->GetMasterVolumeLevelScalar(&scalar)))
            {
                return false;
            }
            state.available = true;
            state.volume = std::clamp(static_cast<double>(scalar), 0.0, 1.0);
            return true;
        });
    return state;
}

bool SystemControlV21::SetVolume(double value)
{
    const double clamped = std::clamp(value, 0.0, 1.0);
    return WithEndpointVolume(
        [clamped](IAudioEndpointVolume* endpoint)
        {
            return SUCCEEDED(endpoint->SetMasterVolumeLevelScalar(
                static_cast<float>(clamped),
                nullptr));
        });
}

BrightnessControlStateV21 SystemControlV21::QueryBrightness()
{
    BrightnessControlStateV21 state{};

    DdcQueryContext ddc{};
    EnumDisplayMonitors(
        nullptr,
        nullptr,
        QueryDdcMonitor,
        reinterpret_cast<LPARAM>(&ddc));
    if (ddc.found)
    {
        state.available = true;
        state.brightness = static_cast<double>(
            std::min<unsigned>(100u, ddc.percent)) / 100.0;
        return state;
    }

    unsigned wmi = 0;
    if (QueryWmiBrightness(&wmi))
    {
        state.available = true;
        state.brightness = static_cast<double>(
            std::min<unsigned>(100u, wmi)) / 100.0;
    }
    return state;
}

bool SystemControlV21::SetBrightness(double value)
{
    const unsigned percent = static_cast<unsigned>(
        std::clamp(value, 0.0, 1.0) * 100.0 + 0.5);

    DdcSetContext ddc{percent, false};
    EnumDisplayMonitors(
        nullptr,
        nullptr,
        SetDdcMonitor,
        reinterpret_cast<LPARAM>(&ddc));
    if (ddc.changed)
    {
        return true;
    }

    return SetWmiBrightness(percent);
}

} // namespace CloudOS
