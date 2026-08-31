#pragma once

#include <Windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace CloudOS
{

struct BridgeAppItem final
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

struct BridgeSystemSnapshot final
{
    std::string device_name;
    std::string network_name;
    double volume{0.72};
    double brightness{0.85};
    int battery_percent{95};
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

    std::vector<BridgeAppItem> GetApps();
    BridgeSystemSnapshot GetSystemSnapshot();
    bool LaunchApp(const std::string& app_id);
    bool SetVolume(double volume);
    bool SetBrightness(double brightness);

    [[nodiscard]] bool IsRegistered() const noexcept { return is_registered_.load(); }

private:
    CloudOSFlutterBridgeV20() = default;
    ~CloudOSFlutterBridgeV20() = default;

    void RefreshAppCatalog();
    void RefreshSystemSnapshot();
    std::vector<std::string> QueryWslDistributions();

    HWND window_handle_{nullptr};
    std::atomic_bool is_registered_{false};

    std::mutex catalog_mutex_;
    std::vector<BridgeAppItem> cached_apps_;
    std::atomic_bool catalog_initialized_{false};

    std::mutex snapshot_mutex_;
    BridgeSystemSnapshot cached_snapshot_;
    std::atomic_bool snapshot_initialized_{false};
};

} // namespace CloudOS
