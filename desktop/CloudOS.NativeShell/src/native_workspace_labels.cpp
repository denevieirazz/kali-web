#include "native_workspace_labels.h"

#include "native_workspace_studio_service.h"

#include <algorithm>

namespace CloudOS
{
namespace
{
int ClampWorkspace(int workspace) noexcept
{
    return std::clamp(workspace, 0, kWorkspaceStudioCount - 1);
}
}

std::wstring NativeWorkspaceLabels::Name(int workspace)
{
    workspace = ClampWorkspace(workspace);
    const auto& profiles = NativeWorkspaceStudioService::Instance().Store().Profiles();
    const std::wstring& configured = profiles[static_cast<std::size_t>(workspace)].name;
    if (!configured.empty())
    {
        return configured;
    }
    return L"Área " + std::to_wstring(workspace + 1);
}

std::wstring NativeWorkspaceLabels::NumberedName(int workspace)
{
    workspace = ClampWorkspace(workspace);
    return std::to_wstring(workspace + 1) + L" · " + Name(workspace);
}

std::wstring NativeWorkspaceLabels::CompactName(int workspace, std::size_t maximum)
{
    std::wstring value = Name(workspace);
    if (maximum == 0u)
    {
        return {};
    }
    if (value.size() <= maximum)
    {
        return value;
    }
    if (maximum <= 2u)
    {
        value.resize(maximum);
        return value;
    }
    value.resize(maximum - 1u);
    value += L"…";
    return value;
}

std::wstring NativeWorkspaceLabels::StatusText(int workspace)
{
    workspace = ClampWorkspace(workspace);
    const auto& profile = NativeWorkspaceStudioService::Instance().Store().Profiles()[
        static_cast<std::size_t>(workspace)];
    std::wstring text = NumberedName(workspace);
    text += L" · ";
    text += WorkspaceLayoutPresetName(profile.layout);
    if (profile.auto_tile)
    {
        text += L" · tiling automático";
    }
    if (profile.auto_launch)
    {
        text += L" · inicialização automática";
    }
    return text;
}
} // namespace CloudOS
