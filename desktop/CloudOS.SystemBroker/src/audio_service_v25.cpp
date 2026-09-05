#include "audio_service_v25.h"
#include "event_bus_v21.h"

#include <Windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <functiondiscoverykeys_devpkey.h>

#include <algorithm>

namespace CloudOS
{

JsonObject AudioEndpointInfoV25::ToJsonObject() const
{
    JsonObject obj;
    obj["id"] = JsonValue(id);
    obj["name"] = JsonValue(name);
    obj["isDefault"] = JsonValue(is_default);
    obj["isInput"] = JsonValue(is_input);
    return obj;
}

JsonObject AudioStateV25::ToJsonObject() const
{
    JsonObject obj;
    obj["available"] = JsonValue(available);
    obj["volume"] = JsonValue(volume);
    obj["isMuted"] = JsonValue(is_muted);
    obj["defaultDevice"] = JsonValue(default_device_name);

    JsonArray eps;
    for (const auto& ep : endpoints)
    {
        eps.push_back(JsonValue(ep.ToJsonObject()));
    }
    obj["endpoints"] = JsonValue(std::move(eps));
    return obj;
}

AudioServiceV25& AudioServiceV25::Instance()
{
    static AudioServiceV25 instance;
    return instance;
}

namespace
{
class ComScope final
{
public:
    ComScope() : hr_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
    ~ComScope() { if (SUCCEEDED(hr_)) CoUninitialize(); }
    [[nodiscard]] bool Usable() const { return SUCCEEDED(hr_) || hr_ == RPC_E_CHANGED_MODE; }
private:
    HRESULT hr_;
};

static std::string WStringToUtf8(const std::wstring& ws)
{
    if (ws.empty()) return {};
    int len = WideCharToMultiByte(CP_UTF8, 0, ws.data(), static_cast<int>(ws.size()), nullptr, 0, nullptr, nullptr);
    std::string str(len, 0);
    WideCharToMultiByte(CP_UTF8, 0, ws.data(), static_cast<int>(ws.size()), str.data(), len, nullptr, nullptr);
    return str;
}
} // namespace

AudioStateV25 AudioServiceV25::GetAudioState()
{
    AudioStateV25 state;
    ComScope com;
    if (!com.Usable()) return state;

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || !enumerator) return state;

    // Default Render Device
    IMMDevice* default_dev = nullptr;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &default_dev)) && default_dev)
    {
        IPropertyStore* props = nullptr;
        if (SUCCEEDED(default_dev->OpenPropertyStore(STGM_READ, &props)) && props)
        {
            PROPVARIANT var_name;
            PropVariantInit(&var_name);
            if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &var_name)) && var_name.pwszVal)
            {
                state.default_device_name = WStringToUtf8(var_name.pwszVal);
            }
            PropVariantClear(&var_name);
            props->Release();
        }

        IAudioEndpointVolume* endpoint_vol = nullptr;
        if (SUCCEEDED(default_dev->Activate(
                __uuidof(IAudioEndpointVolume),
                CLSCTX_ALL,
                nullptr,
                reinterpret_cast<void**>(&endpoint_vol))) && endpoint_vol)
        {
            float vol = 0.0f;
            if (SUCCEEDED(endpoint_vol->GetMasterVolumeLevelScalar(&vol)))
            {
                state.volume = static_cast<double>(vol);
                state.available = true;
            }

            BOOL muted = FALSE;
            if (SUCCEEDED(endpoint_vol->GetMute(&muted)))
            {
                state.is_muted = (muted != FALSE);
            }
            endpoint_vol->Release();
        }
        default_dev->Release();
    }

    // List all active render devices
    IMMDeviceCollection* collection = nullptr;
    if (SUCCEEDED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection)) && collection)
    {
        UINT count = 0;
        collection->GetCount(&count);
        for (UINT i = 0; i < count; ++i)
        {
            IMMDevice* dev = nullptr;
            if (SUCCEEDED(collection->Item(i, &dev)) && dev)
            {
                AudioEndpointInfoV25 ep_info;
                ep_info.is_input = false;

                LPWSTR dev_id = nullptr;
                if (SUCCEEDED(dev->GetId(&dev_id)) && dev_id)
                {
                    ep_info.id = WStringToUtf8(dev_id);
                    CoTaskMemFree(dev_id);
                }

                IPropertyStore* props = nullptr;
                if (SUCCEEDED(dev->OpenPropertyStore(STGM_READ, &props)) && props)
                {
                    PROPVARIANT var;
                    PropVariantInit(&var);
                    if (SUCCEEDED(props->GetValue(PKEY_Device_FriendlyName, &var)) && var.pwszVal)
                    {
                        ep_info.name = WStringToUtf8(var.pwszVal);
                    }
                    PropVariantClear(&var);
                    props->Release();
                }

                if (ep_info.name == state.default_device_name)
                {
                    ep_info.is_default = true;
                }
                state.endpoints.push_back(std::move(ep_info));
                dev->Release();
            }
        }
        collection->Release();
    }

    enumerator->Release();
    return state;
}

bool AudioServiceV25::SetVolume(double volume)
{
    const double clamped = std::clamp(volume, 0.0, 1.0);
    ComScope com;
    if (!com.Usable()) return false;

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || !enumerator) return false;

    IMMDevice* device = nullptr;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    enumerator->Release();
    if (FAILED(hr) || !device) return false;

    IAudioEndpointVolume* endpoint = nullptr;
    hr = device->Activate(
        __uuidof(IAudioEndpointVolume),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&endpoint));
    device->Release();
    if (FAILED(hr) || !endpoint) return false;

    hr = endpoint->SetMasterVolumeLevelScalar(static_cast<float>(clamped), nullptr);
    endpoint->Release();

    if (SUCCEEDED(hr))
    {
        JsonObject payload;
        payload["volume"] = JsonValue(clamped);
        EventBusV21::Instance().Publish("audio.changed", payload);
        return true;
    }
    return false;
}

bool AudioServiceV25::SetMute(bool mute)
{
    ComScope com;
    if (!com.Usable()) return false;

    IMMDeviceEnumerator* enumerator = nullptr;
    HRESULT hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr) || !enumerator) return false;

    IMMDevice* device = nullptr;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
    enumerator->Release();
    if (FAILED(hr) || !device) return false;

    IAudioEndpointVolume* endpoint = nullptr;
    hr = device->Activate(
        __uuidof(IAudioEndpointVolume),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&endpoint));
    device->Release();
    if (FAILED(hr) || !endpoint) return false;

    hr = endpoint->SetMute(mute ? TRUE : FALSE, nullptr);
    endpoint->Release();

    if (SUCCEEDED(hr))
    {
        JsonObject payload;
        payload["isMuted"] = JsonValue(mute);
        EventBusV21::Instance().Publish("audio.changed", payload);
        return true;
    }
    return false;
}

} // namespace CloudOS
