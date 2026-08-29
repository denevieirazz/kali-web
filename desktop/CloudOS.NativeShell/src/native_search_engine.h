#pragma once

#include <string>
#include <vector>
#include "native_theme.h"

namespace CloudOS
{
class NativeSearchEngine final
{
public:
    static std::vector<int> FilterApps(const std::wstring& query);
    static bool Matches(const AppItem& app, const std::wstring& query);
};
} // namespace CloudOS
