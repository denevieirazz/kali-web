#pragma once

#include <string>

namespace CloudOS
{
class NativeWorkspaceLabels final
{
public:
    static std::wstring Name(int workspace);
    static std::wstring NumberedName(int workspace);
    static std::wstring CompactName(int workspace, std::size_t maximum = 9u);
    static std::wstring StatusText(int workspace);
};
} // namespace CloudOS
