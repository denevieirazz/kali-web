#pragma once
#include "native_system_control_backend.h"
#include "native_audio_mixer_v7.h"
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace CloudOS
{
constexpr UINT WM_CLOUDOS_QUICK_DATA_V12 = WM_APP + 0x617;
struct NativeQuickSnapshotV12
{
    NativeAudioState audio; NativeBrightnessState brightness; NativePowerState power;
    std::vector<NativeAudioSessionV7> sessions; std::vector<NativeWifiNetwork> wifi;
};
class NativeQuickModelV12 final
{
public:
    struct Result { std::wstring title, error; bool success{}; };
private:
    struct Operation { std::wstring title; std::function<bool(std::wstring&)> run; };
    std::mutex mutex_; std::condition_variable condition_;
    NativeQuickSnapshotV12 snapshot_; std::thread worker_;
    std::deque<Operation> actions_; std::vector<Result> results_;
    bool stop_{}, requested_{}, force_{}; HWND target_{};
    void Work()
    {
        const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        ULONGLONG last_radios{};
        for (;;)
        {
            std::deque<Operation> actions; HWND target{}; bool force{};
            { std::unique_lock lock(mutex_);
              condition_.wait(lock,[this]{return stop_ || requested_;});
              if(stop_) break;
              requested_=false; force=force_; force_=false; target=target_; actions.swap(actions_); }
            std::vector<Result> completed;
            for(auto& action : actions)
            { Result result{action.title,{},false}; result.success=action.run(result.error); completed.push_back(std::move(result)); }
            auto next=Snapshot();
            next.audio=NativeSystemControlBackend::QueryAudio();
            next.power=NativeSystemControlBackend::QueryPower();
            next.sessions=NativeAudioMixerV7::Enumerate();
            const auto now=GetTickCount64();
            if(force || !last_radios || now-last_radios>=30000)
            { next.wifi=NativeSystemControlBackend::ScanWifi(); next.brightness=NativeSystemControlBackend::QueryBrightness(); last_radios=now; }
            { std::scoped_lock lock(mutex_); snapshot_=std::move(next);
              for(auto& result:completed) results_.push_back(std::move(result)); }
            PostMessageW(target,WM_CLOUDOS_QUICK_DATA_V12,0,0);
        }
        if(SUCCEEDED(com)) CoUninitialize();
    }
public:
    ~NativeQuickModelV12() { Stop(); }
    void Stop()
    {
        { std::scoped_lock lock(mutex_); stop_=true; actions_.clear(); }
        condition_.notify_all(); if(worker_.joinable()) worker_.join();
    }
    NativeQuickSnapshotV12 Snapshot() { std::scoped_lock lock(mutex_); return snapshot_; }
    std::vector<Result> TakeResults() { std::scoped_lock lock(mutex_); std::vector<Result> results; results.swap(results_); return results; }
    void Request(HWND target,bool force=false)
    {
        { std::scoped_lock lock(mutex_); if(stop_) return;
          target_=target; force_=force_||force; requested_=true;
          if(!worker_.joinable()) worker_=std::thread([this]{Work();}); }
        condition_.notify_one();
    }
    void Action(HWND target,std::wstring title,std::function<bool(std::wstring&)> action,bool force=false)
    {
        { std::scoped_lock lock(mutex_); if(stop_) return; actions_.push_back({std::move(title),std::move(action)}); }
        Request(target,force);
    }
};
}
