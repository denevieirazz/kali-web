#include "native_search_engine.h"
#include <algorithm>

namespace CloudOS
{
bool NativeSearchEngine::Matches(const AppItem& app, const std::wstring& query)
{
    if (query.empty()) return true;

    std::wstring name_lower = app.name;
    std::wstring desc_lower = app.desc;
    std::wstring id_lower = app.id;
    std::transform(name_lower.begin(), name_lower.end(), name_lower.begin(), ::towlower);
    std::transform(desc_lower.begin(), desc_lower.end(), desc_lower.begin(), ::towlower);
    std::transform(id_lower.begin(), id_lower.end(), id_lower.begin(), ::towlower);

    if (name_lower.find(query) != std::wstring::npos ||
        desc_lower.find(query) != std::wstring::npos ||
        id_lower.find(query) != std::wstring::npos)
    {
        return true;
    }

    if (query == L"web" || query == L"net" || query == L"chrome" || query == L"edge" || query == L"browser")
    {
        if (std::wstring_view(app.id) == L"browser") return true;
    }
    if (query == L"cmd" || query == L"terminal" || query == L"bash" || query == L"sh" || query == L"conpty")
    {
        if (std::wstring_view(app.id) == L"terminal" || std::wstring_view(app.id) == L"projects" || std::wstring_view(app.id) == L"powershell") return true;
    }
    if (query == L"linux" || query == L"kali" || query == L"wsl" || query == L"wsl2")
    {
        if (std::wstring_view(app.id) == L"projects") return true;
    }
    if (query == L"txt" || query == L"nota" || query == L"notas" || query == L"editor" || query == L"mail")
    {
        if (std::wstring_view(app.id) == L"notepad" || std::wstring_view(app.id) == L"code") return true;
    }
    if (query == L"calc" || query == L"calculadora" || query == L"math")
    {
        if (std::wstring_view(app.id) == L"calc") return true;
    }
    if (query == L"pasta" || query == L"pastas" || query == L"arquivo" || query == L"explorer" || query == L"disco" || query == L"hd")
    {
        if (std::wstring_view(app.id) == L"files" || std::wstring_view(app.id) == L"drive") return true;
    }
    if (query == L"cpu" || query == L"ram" || query == L"processo" || query == L"monitor" || query == L"task")
    {
        if (std::wstring_view(app.id) == L"sysmon") return true;
    }
    if (query == L"config" || query == L"painel" || query == L"ajustes" || query == L"settings")
    {
        if (std::wstring_view(app.id) == L"settings") return true;
    }
    if (query == L"paint" || query == L"desenho" || query == L"arte" || query == L"foto")
    {
        if (std::wstring_view(app.id) == L"paint") return true;
    }
    if (query == L"print" || query == L"captura" || query == L"snip" || query == L"screenshot")
    {
        if (std::wstring_view(app.id) == L"snip") return true;
    }
    return false;
}

std::vector<int> NativeSearchEngine::FilterApps(const std::wstring& query)
{
    std::vector<int> indices;
    std::wstring lower = query;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::towlower);
    while (!lower.empty() && lower.back() == L' ') lower.pop_back();
    while (!lower.empty() && lower.front() == L' ') lower.erase(lower.begin());

    for (std::size_t i = 0; i < kAllApps.size(); ++i)
    {
        if (Matches(kAllApps[i], lower))
        {
            indices.push_back(static_cast<int>(i));
        }
    }
    return indices;
}

} // namespace CloudOS
