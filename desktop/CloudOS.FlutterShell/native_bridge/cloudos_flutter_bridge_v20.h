#pragma once

#include "cloudos_broker_client_v21.h"

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <Windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct NativeAppItem final
{
    std::string id;
    std::string name;
    std::string platform; // "windows", "linux", "cloudos"
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    bool can_launch{true};
    bool pinned{false};
    bool recent{false};
};

struct NativeSystemSnapshot final
{
    std::string device_name;
    std::string user_name;
    uint32_t session_id{1};
    bool battery_available{false};
    int battery_percent{100};
    bool network_available{false};
    std::string network_name;
    bool volume_available{false};
    double volume{0.0};
    bool brightness_available{false};
    double brightness{0.0};
    bool wsl_available{false};
    std::vector<std::string> distros;
    int current_workspace{1};
};

class CloudOSFlutterBridgeV20 final
{
public:
    static void RegisterWithMessenger(
        flutter::BinaryMessenger* messenger,
        HWND window_handle);

    static CloudOSFlutterBridgeV20& Instance();

    CloudOSFlutterBridgeV20(const CloudOSFlutterBridgeV20&) = delete;
    CloudOSFlutterBridgeV20& operator=(const CloudOSFlutterBridgeV20&) = delete;

    void Initialize(HWND window_handle);

    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    std::vector<NativeAppItem> GetApps();
    NativeSystemSnapshot GetSystemSnapshot();
    bool LaunchApp(const std::string& app_id);
    bool SetVolume(double volume);
    bool SetBrightness(double brightness);

    [[nodiscard]] bool IsRegistered() const noexcept { return is_registered_.load(); }

private:
    CloudOSFlutterBridgeV20() = default;
    ~CloudOSFlutterBridgeV20() = default;

    void RefreshAppCatalog();
    void RefreshSystemSnapshot();

    HWND window_handle_{nullptr};
    std::atomic_bool is_registered_{false};
    mutable std::mutex mutex_;
    std::vector<NativeAppItem> cached_apps_;
    NativeSystemSnapshot cached_snapshot_;
};

} // namespace CloudOS
