#pragma once

#include <windows.h>

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#pragma comment(lib, "windowsapp.lib")

namespace CloudOS
{
struct NativeBluetoothDeviceV7 final
{
    std::wstring id;
    std::wstring name;
    bool paired{};
    bool can_pair{};
    bool low_energy{};
};

class NativeBluetoothV7 final
{
public:
    static std::vector<NativeBluetoothDeviceV7> Snapshot()
    {
        std::scoped_lock lock(Mutex());
        return Devices();
    }

    static void RefreshAsync()
    {
        bool expected = false;
        if (!Refreshing().compare_exchange_strong(expected, true)) return;
        std::thread([]
        {
            std::vector<NativeBluetoothDeviceV7> next;
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Devices::Bluetooth;
                Collect(BluetoothDevice::GetDeviceSelector(), false, &next);
                Collect(BluetoothLEDevice::GetDeviceSelector(), true, &next);
            }
            catch (...)
            {
            }
            {
                std::scoped_lock lock(Mutex());
                Devices() = std::move(next);
            }
            Refreshing().store(false);
        }).detach();
    }

    static void PairAsync(std::wstring device_id)
    {
        if (device_id.empty()) return;
        std::thread([device_id = std::move(device_id)]
        {
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Devices::Enumeration;
                const auto device = DeviceInformation::CreateFromIdAsync(winrt::hstring(device_id)).get();
                if (device && device.Pairing().CanPair())
                    (void)device.Pairing().PairAsync().get();
            }
            catch (...)
            {
            }
            RefreshAsync();
        }).detach();
    }

    static void UnpairAsync(std::wstring device_id)
    {
        if (device_id.empty()) return;
        std::thread([device_id = std::move(device_id)]
        {
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Devices::Enumeration;
                const auto device = DeviceInformation::CreateFromIdAsync(winrt::hstring(device_id)).get();
                if (device && device.Pairing().IsPaired())
                    (void)device.Pairing().UnpairAsync().get();
            }
            catch (...)
            {
            }
            RefreshAsync();
        }).detach();
    }

private:
    static std::vector<NativeBluetoothDeviceV7>& Devices()
    {
        static std::vector<NativeBluetoothDeviceV7> devices;
        return devices;
    }

    static std::mutex& Mutex()
    {
        static std::mutex mutex;
        return mutex;
    }

    static std::atomic_bool& Refreshing()
    {
        static std::atomic_bool refreshing{false};
        return refreshing;
    }

    static void Collect(
        const winrt::hstring& selector,
        bool low_energy,
        std::vector<NativeBluetoothDeviceV7>* output)
    {
        if (output == nullptr) return;
        using namespace winrt::Windows::Devices::Enumeration;
        const auto found = DeviceInformation::FindAllAsync(selector).get();
        std::unordered_set<std::wstring> existing;
        for (const auto& item : *output) existing.insert(item.id);

        const uint32_t count = found.Size();
        for (uint32_t index = 0; index < count && output->size() < 96u; ++index)
        {
            const DeviceInformation device = found.GetAt(index);
            const std::wstring id = device.Id().c_str();
            if (id.empty() || existing.contains(id)) continue;
            NativeBluetoothDeviceV7 item{};
            item.id = id;
            item.name = device.Name().c_str();
            item.paired = device.Pairing().IsPaired();
            item.can_pair = device.Pairing().CanPair();
            item.low_energy = low_energy;
            output->push_back(std::move(item));
            existing.insert(id);
        }
    }
};
} // namespace CloudOS