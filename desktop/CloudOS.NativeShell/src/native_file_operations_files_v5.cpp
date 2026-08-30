#include "native_file_operations_window.h"

#include <algorithm>
#include <cwchar>
#include <new>
#include <utility>

namespace CloudOS
{
namespace
{
constexpr std::size_t kMaximumPreseedSources = 256;
constexpr std::size_t kMaximumPreseedPathCharacters = 32767;

bool SamePath(const std::wstring& left, const std::wstring& right) noexcept
{
    return left.size() == right.size() && _wcsicmp(left.c_str(), right.c_str()) == 0;
}

bool IsEligiblePreseedSource(const std::wstring& path) noexcept
{
    if (path.empty() || path.size() > kMaximumPreseedPathCharacters) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) return false;
    return (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}
}

void CloudOSNativeFileOperationsWindow::OpenWithSources(
    HINSTANCE instance,
    const std::vector<std::wstring>& sources,
    const std::wstring& initial_destination)
{
    auto* window = new (std::nothrow) CloudOSNativeFileOperationsWindow(
        instance,
        initial_destination);
    if (window == nullptr)
    {
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Operacoes de Arquivos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
        return;
    }

    window->sources_.reserve((std::min)(sources.size(), kMaximumPreseedSources));
    for (const auto& source : sources)
    {
        if (window->sources_.size() >= kMaximumPreseedSources) break;
        if (!IsEligiblePreseedSource(source)) continue;
        const bool duplicate = std::any_of(
            window->sources_.begin(),
            window->sources_.end(),
            [&source](const std::wstring& existing)
            {
                return SamePath(existing, source);
            });
        if (!duplicate) window->sources_.push_back(source);
    }

    if (!window->Create())
    {
        delete window;
        MessageBoxW(
            nullptr,
            L"Nao foi possivel abrir Operacoes de Arquivos.",
            L"CloudOS",
            MB_OK | MB_ICONERROR);
        return;
    }

    window->RefreshSourceList();
}
} // namespace CloudOS
