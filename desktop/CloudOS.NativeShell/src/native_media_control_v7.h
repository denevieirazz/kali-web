#pragma once

#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

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
    bool timeline_available{};
    std::int64_t timeline_start_ticks{};
    std::int64_t timeline_end_ticks{};
    std::int64_t position_ticks{};
    std::int64_t min_seek_ticks{};
    std::int64_t max_seek_ticks{};
    std::wstring title;
    std::wstring artist;
    std::wstring album;
    std::wstring source_app_id;
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
                const auto manager =
                    GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
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
                    next.timeline_start_ticks = timeline.StartTime().count();
                    next.timeline_end_ticks = timeline.EndTime().count();
                    next.position_ticks = timeline.Position().count();
                    next.min_seek_ticks = timeline.MinSeekTime().count();
                    next.max_seek_ticks = timeline.MaxSeekTime().count();
                    next.timeline_available =
                        next.timeline_end_ticks > next.timeline_start_ticks;
                    if (next.timeline_available)
                    {
                        next.position_ticks = std::clamp(
                            next.position_ticks,
                            next.timeline_start_ticks,
                            next.timeline_end_ticks);
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

    static void SeekNormalizedAsync(double normalized_position)
    {
        const double ratio = std::clamp(normalized_position, 0.0, 1.0);
        std::thread([ratio]
        {
            try
            {
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                using namespace winrt::Windows::Media::Control;
                const auto manager =
                    GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
                const auto session = manager.GetCurrentSession();
                if (!session) return;
                const auto playback = session.GetPlaybackInfo();
                if (!playback.Controls().IsPlaybackPositionEnabled()) return;

                const auto timeline = session.GetTimelineProperties();
                std::int64_t minimum = timeline.MinSeekTime().count();
                std::int64_t maximum = timeline.MaxSeekTime().count();
                if (maximum <= minimum)
                {
                    minimum = timeline.StartTime().count();
                    maximum = timeline.EndTime().count();
                }
                if (maximum <= minimum) return;

                const long double span = static_cast<long double>(maximum - minimum);
                const auto offset = static_cast<std::int64_t>(
                    span * static_cast<long double>(ratio));
                const std::int64_t requested = std::clamp(
                    minimum + offset,
                    minimum,
                    maximum);
                (void)session.TryChangePlaybackPositionAsync(requested).get();
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
                const auto manager =
                    GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
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
