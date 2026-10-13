#pragma once
// Host-neutral metadata adapter. Fields mirror pinned DualSynth types;
// no host frame ownership or plugin ABI is claimed by this standalone target.
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>
struct DSFormat {
    bool IsFamilyYUV{true}, IsFamilyRGB{false}, IsFamilyYCC{false};
    bool IsInteger{true}, IsFloat{false};
    int SSW{0}, SSH{0}, BitsPerSample{8}, BytesPerSample{1}, Planes{3};
};
struct DSVideoInfo {
    DSFormat Format;
    int64_t FPSNum{1}, FPSDenom{1};
    int Width{0}, Height{0}, Frames{0};
    int Audio_SPS{0}, Audio_SType{0};
    int64_t Audio_NSamples{0};
    int Audio_NChannels{0}, Field{0};
};
