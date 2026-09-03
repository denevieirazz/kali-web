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
    std::string platform;
    std::string subtitle;
    std::string distro;
    std::string category;
    std::string source;
    bool can_launch{true};
    bool pinned{false};
    bool recent{false};
};

struct NativeFileItem final
{
    std::string name;
    std::string path;
    bool is_folder{};
    std::string size_formatted;
    std::string modified_formatted;
    std::string source;
    std::string extension;
    std::string entry_id;
};

struct NativeWslDistributionSnapshot final
{
    std::string name;
    int version{0};
    bool is_default{false};
    bool base_path_present{false};
    bool base_path_evidence_known{false};
    bool is_security_candidate{false};
    bool security_candidate_evidence_known{false};
};

struct NativeSystemSnapshot final
{
    std::string device_name;
    bool network_available{false};
    std::string network_name;
    bool volume_available{false};
    double volume{};
    bool brightness_available{false};
    double brightness{};
    bool battery_available{false};
    int battery_percent{};

    bool wsl_available{false};
    bool wsl_engine_available{false};
    bool wsl_passive_ready{false};
    bool wsl_passive_ready_known{false};
    std::vector<std::string> distros;
    std::string default_distro;
    std::vector<NativeWslDistributionSnapshot> wsl_distros;
    std::string preferred_security_distro;
    uint32_t wsl_registered_count{0};
    uint32_t wsl_launch_candidate_count{0};
    uint32_t wsl1_count{0};
    uint32_t wsl2_count{0};

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
    bool GetFiles(const std::string& location, std::vector<NativeFileItem>& out_files);
    bool GetFilesEntry(const std::string& entry_id, std::vector<NativeFileItem>& out_files);
    bool OpenFileEntry(const std::string& entry_id);
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
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    mutable std::mutex mutex_;
    std::vector<NativeAppItem> cached_apps_;
    NativeSystemSnapshot cached_snapshot_;
};

} // namespace CloudOS
