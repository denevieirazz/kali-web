#pragma once

#include <windows.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>

#include <algorithm>
#include <filesystem>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")

namespace CloudOS
{
struct NativeAudioSessionV7 final
{
    DWORD process_id{};
    std::wstring title;
    unsigned volume_percent{};
    bool muted{};
    bool active{};
    bool system_sounds{};
};

class NativeAudioMixerV7 final
{
public:
    static std::vector<NativeAudioSessionV7> Enumerate(std::size_t maximum = 32u)
    {
        std::vector<NativeAudioSessionV7> result;
        IAudioSessionManager2* manager = OpenManager();
        if (manager == nullptr) return result;

        IAudioSessionEnumerator* enumerator = nullptr;
        if (FAILED(manager->GetSessionEnumerator(&enumerator)) || enumerator == nullptr)
        {
            manager->Release();
            return result;
        }

        int count = 0;
        if (FAILED(enumerator->GetCount(&count))) count = 0;
        for (int index = 0; index < count && result.size() < maximum; ++index)
        {
            IAudioSessionControl* control = nullptr;
            if (FAILED(enumerator->GetSession(index, &control)) || control == nullptr) continue;

            IAudioSessionControl2* control2 = nullptr;
            ISimpleAudioVolume* simple = nullptr;
            if (FAILED(control->QueryInterface(IID_PPV_ARGS(&control2))) || control2 == nullptr ||
                FAILED(control->QueryInterface(IID_PPV_ARGS(&simple))) || simple == nullptr)
            {
                if (simple != nullptr) simple->Release();
                if (control2 != nullptr) control2->Release();
                control->Release();
                continue;
            }

            NativeAudioSessionV7 item{};
            (void)control2->GetProcessId(&item.process_id);
            item.system_sounds = control2->IsSystemSoundsSession() == S_OK;

            AudioSessionState state = AudioSessionStateInactive;
            if (SUCCEEDED(control->GetState(&state))) item.active = state == AudioSessionStateActive;

            float volume = 0.0f;
            BOOL muted = FALSE;
            if (SUCCEEDED(simple->GetMasterVolume(&volume)))
            {
                item.volume_percent = static_cast<unsigned>(std::clamp<int>(
                    static_cast<int>(volume * 100.0f + 0.5f), 0, 100));
            }
            if (SUCCEEDED(simple->GetMute(&muted))) item.muted = muted != FALSE;

            LPWSTR display_name = nullptr;
            if (SUCCEEDED(control->GetDisplayName(&display_name)) && display_name != nullptr)
            {
                item.title = display_name;
                CoTaskMemFree(display_name);
            }
            if(item.system_sounds) item.title=L"Sons do sistema";
            else if(!item.title.empty() && item.title.front()==L'@') item.title.clear();
            if (item.title.empty()) item.title = ProcessName(item.process_id);
            if (item.title.empty()) item.title = item.system_sounds ? L"Sons do sistema" : L"Sessao de audio";

            result.push_back(std::move(item));
            simple->Release();
            control2->Release();
            control->Release();
        }

        enumerator->Release();
        manager->Release();

        std::stable_sort(result.begin(), result.end(), [](const NativeAudioSessionV7& left, const NativeAudioSessionV7& right)
        {
            if (left.active != right.active) return left.active > right.active;
            return _wcsicmp(left.title.c_str(), right.title.c_str()) < 0;
        });
        return result;
    }

    static bool SetVolume(DWORD process_id, unsigned percent)
    {
        percent = std::min<unsigned>(100u, percent);
        return Apply(process_id, [percent](ISimpleAudioVolume* volume)
        {
            return SUCCEEDED(volume->SetMasterVolume(static_cast<float>(percent) / 100.0f, nullptr));
        });
    }

    static bool SetMute(DWORD process_id, bool muted)
    {
        return Apply(process_id, [muted](ISimpleAudioVolume* volume)
        {
            return SUCCEEDED(volume->SetMute(muted ? TRUE : FALSE, nullptr));
        });
    }

private:
    static IAudioSessionManager2* OpenManager()
    {
        IMMDeviceEnumerator* device_enumerator = nullptr;
        if (FAILED(CoCreateInstance(
                __uuidof(MMDeviceEnumerator),
                nullptr,
                CLSCTX_ALL,
                IID_PPV_ARGS(&device_enumerator))) || device_enumerator == nullptr)
        {
            return nullptr;
        }

        IMMDevice* device = nullptr;
        const HRESULT endpoint_result = device_enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
        device_enumerator->Release();
        if (FAILED(endpoint_result) || device == nullptr) return nullptr;

        IAudioSessionManager2* manager = nullptr;
        const HRESULT activate_result = device->Activate(
            __uuidof(IAudioSessionManager2),
            CLSCTX_ALL,
            nullptr,
            reinterpret_cast<void**>(&manager));
        device->Release();
        return SUCCEEDED(activate_result) ? manager : nullptr;
    }

    static std::wstring ProcessName(DWORD process_id)
    {
        if (process_id == 0) return {};
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
        if (process == nullptr) return {};

        std::wstring path(32768u, L'\0');
        DWORD size = static_cast<DWORD>(path.size());
        std::wstring result;
        if (QueryFullProcessImageNameW(process, 0, path.data(), &size) && size > 0)
        {
            path.resize(size);
            const std::filesystem::path parsed(path);
            result = parsed.stem().wstring();
        }
        CloseHandle(process);
        return result;
    }

    template <typename Callback>
    static bool Apply(DWORD process_id, Callback&& callback)
    {
        IAudioSessionManager2* manager = OpenManager();
        if (manager == nullptr) return false;
        IAudioSessionEnumerator* enumerator = nullptr;
        if (FAILED(manager->GetSessionEnumerator(&enumerator)) || enumerator == nullptr)
        {
            manager->Release();
            return false;
        }

        bool changed = false;
        int count = 0;
        if (SUCCEEDED(enumerator->GetCount(&count)))
        {
            for (int index = 0; index < count; ++index)
            {
                IAudioSessionControl* control = nullptr;
                if (FAILED(enumerator->GetSession(index, &control)) || control == nullptr) continue;
                IAudioSessionControl2* control2 = nullptr;
                ISimpleAudioVolume* simple = nullptr;
                DWORD pid = 0;
                if (SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&control2))) && control2 != nullptr)
                    (void)control2->GetProcessId(&pid);
                if (pid == process_id &&
                    SUCCEEDED(control->QueryInterface(IID_PPV_ARGS(&simple))) && simple != nullptr)
                {
                    changed = callback(simple) || changed;
                }
                if (simple != nullptr) simple->Release();
                if (control2 != nullptr) control2->Release();
                control->Release();
            }
        }
        enumerator->Release();
        manager->Release();
        return changed;
    }
};
} // namespace CloudOS
