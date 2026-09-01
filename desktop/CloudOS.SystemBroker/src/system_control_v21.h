#pragma once

namespace CloudOS
{

struct AudioControlStateV21 final
{
    bool available{};
    double volume{};
};

struct BrightnessControlStateV21 final
{
    bool available{};
    double brightness{};
};

class SystemControlV21 final
{
public:
    static AudioControlStateV21 QueryAudio();
    static bool SetVolume(double value);

    static BrightnessControlStateV21 QueryBrightness();
    static bool SetBrightness(double value);
};

} // namespace CloudOS
