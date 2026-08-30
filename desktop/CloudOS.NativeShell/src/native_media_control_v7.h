#pragma once

#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "windowsapp.lib")

namespace CloudOS
{
struct NativeMediaSnapshot final
{
    bool available{};
    bool playing{};
    bool can_toggle{};
    bool can_next{};
    bool can_previous{};
    bool can_seek{};
    std::int64_t position_ms{};
    std::int64_t duration_ms{};
    std::wstring title;
    std::wstring artist;
    std::wstring album;
    std::wstring source_app_id;
    std::vector<std::uint8_t> artwork;
};

class NativeMediaControlV7 final
{
public:
    static NativeMediaSnapshot Snapshot()
    {
        std::scoped_lock lock(Mutex());
        return State();
    }

    // GSMTC is asynchronous. UI surfaces never block the Win32 message thread;
    // they read the cached snapshot and ask a short-lived MTA worker to refresh.
    static void RefreshAsync()
    {
        bool expected = false;
        if (!Refreshing().compare_exchange_strong(expected, true)) return;
        std::thread([]
        {
            NativeMediaSnapshot next{};
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Media::Control;
                using namespace winrt::Windows::Storage::Streams;

                const auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
                const auto session = manager.GetCurrentSession();
                if (session)
                {
                    next.available = true;
                    next.source_app_id = session.SourceAppUserModelId().c_str();
                    const auto media = session.TryGetMediaPropertiesAsync().get();
                    next.title = media.Title().c_str();
                    next.artist = media.Artist().c_str();
                    next.album = media.AlbumTitle().c_str();

                    const auto playback = session.GetPlaybackInfo();
                    next.playing = playback.PlaybackStatus() ==
                        GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
                    const auto controls = playback.Controls();
                    next.can_toggle = controls.IsPlayPauseToggleEnabled();
                    next.can_next = controls.IsNextEnabled();
                    next.can_previous = controls.IsPreviousEnabled();
                    next.can_seek = controls.IsPlaybackPositionEnabled();

                    const auto timeline = session.GetTimelineProperties();
                    next.position_ms = std::max<std::int64_t>(
                        0,
                        std::chrono::duration_cast<std::chrono::milliseconds>(timeline.Position()).count());
                    const auto start_ms = std::chrono::duration_cast<std::chrono::milliseconds>(timeline.StartTime()).count();
                    const auto end_ms = std::chrono::duration_cast<std::chrono::milliseconds>(timeline.EndTime()).count();
                    next.duration_ms = std::max<std::int64_t>(0, end_ms - start_ms);
                    if (next.duration_ms > 0)
                        next.position_ms = std::min(next.position_ms, next.duration_ms);

                    const auto thumbnail = media.Thumbnail();
                    if (thumbnail)
                    {
                        const auto stream = thumbnail.OpenReadAsync().get();
                        constexpr std::uint64_t kArtworkLimit = 4ull * 1024ull * 1024ull;
                        const std::uint64_t size = std::min<std::uint64_t>(stream.Size(), kArtworkLimit);
                        if (size > 0 && size <= UINT32_MAX)
                        {
                            DataReader reader(stream.GetInputStreamAt(0));
                            const std::uint32_t loaded = reader.LoadAsync(static_cast<std::uint32_t>(size)).get();
                            if (loaded > 0)
                            {
                                next.artwork.resize(loaded);
                                reader.ReadBytes(winrt::array_view<std::uint8_t>(next.artwork));
                            }
                            reader.Close();
                        }
                    }
                }
            }
            catch (...)
            {
                // Unpackaged/full-trust environments can deny the WinRT
                // capability. Keep the shell usable and expose unavailable.
            }
            {
                std::scoped_lock lock(Mutex());
                State() = std::move(next);
            }
            Refreshing().store(false);
        }).detach();
    }

    static void TogglePlayPauseAsync() { Dispatch(ControlKind::Toggle); }
    static void NextAsync() { Dispatch(ControlKind::Next); }
    static void PreviousAsync() { Dispatch(ControlKind::Previous); }

    static void SeekAsync(std::int64_t position_ms)
    {
        std::thread([position_ms]
        {
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Media::Control;
                const auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
                const auto session = manager.GetCurrentSession();
                if (!session) return;
                const std::int64_t safe_ms = std::max<std::int64_t>(0, position_ms);
                (void)session.TryChangePlaybackPositionAsync(safe_ms * 10000LL).get();
                RefreshAsync();
            }
            catch (...)
            {
            }
        }).detach();
    }

private:
    enum class ControlKind { Toggle, Next, Previous };

    static NativeMediaSnapshot& State()
    {
        static NativeMediaSnapshot state;
        return state;
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

    static void Dispatch(ControlKind kind)
    {
        std::thread([kind]
        {
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Media::Control;
                const auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
                const auto session = manager.GetCurrentSession();
                if (!session) return;
                switch (kind)
                {
                case ControlKind::Toggle:
                    (void)session.TryTogglePlayPauseAsync().get();
                    break;
                case ControlKind::Next:
                    (void)session.TrySkipNextAsync().get();
                    break;
                case ControlKind::Previous:
                    (void)session.TrySkipPreviousAsync().get();
                    break;
                }
                RefreshAsync();
            }
            catch (...)
            {
            }
        }).detach();
    }
};
} // namespace CloudOS
