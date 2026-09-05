#pragma once

#include "protocol_v21.h"

#include <string>
#include <vector>

namespace CloudOS
{

struct AudioEndpointInfoV25 final
{
    std::string id;
    std::string name;
    bool is_default{false};
    bool is_input{false};

    [[nodiscard]] JsonObject ToJsonObject() const;
};

struct AudioStateV25 final
{
    bool available{false};
    double volume{0.0};
    bool is_muted{false};
    std::string default_device_name;
    std::vector<AudioEndpointInfoV25> endpoints;

    [[nodiscard]] JsonObject ToJsonObject() const;
};

class AudioServiceV25 final
{
public:
    static AudioServiceV25& Instance();

    AudioServiceV25(const AudioServiceV25&) = delete;
    AudioServiceV25& operator=(const AudioServiceV25&) = delete;

    [[nodiscard]] AudioStateV25 GetAudioState();
    bool SetVolume(double volume);
    bool SetMute(bool mute);

private:
    AudioServiceV25() = default;
    ~AudioServiceV25() = default;
};

} // namespace CloudOS
