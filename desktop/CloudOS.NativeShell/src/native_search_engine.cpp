#include "native_search_engine.h"

#include <algorithm>
#include <cwctype>
#include <string_view>

namespace CloudOS
{
namespace
{
void Lowercase(std::wstring& value)
{
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t character)
        {
            return static_cast<wchar_t>(std::towlower(character));
        });
}

bool IsAny(
    std::wstring_view query,
    std::initializer_list<std::wstring_view> values)
{
    return std::find(values.begin(), values.end(), query) != values.end();
}
}

bool NativeSearchEngine::Matches(const AppItem& app, const std::wstring& query)
{
    if (query.empty())
    {
        return true;
    }

    std::wstring name_lower = app.name;
    std::wstring description_lower = app.desc;
    std::wstring id_lower = app.id;
    Lowercase(name_lower);
    Lowercase(description_lower);
    Lowercase(id_lower);

    if (name_lower.find(query) != std::wstring::npos ||
        description_lower.find(query) != std::wstring::npos ||
        id_lower.find(query) != std::wstring::npos)
    {
        return true;
    }

    const std::wstring_view id(app.id);
    const std::wstring_view query_view(query);

    if (IsAny(query_view, {L"central", L"comando", L"comandos", L"acoes", L"acao", L"controle", L"command", L"control"}))
    {
        return id == L"control";
    }
    if (IsAny(query_view, {L"web", L"net", L"chrome", L"edge", L"browser", L"navegador"}))
    {
        return id == L"browser";
    }
    if (IsAny(query_view, {L"cmd", L"terminal", L"bash", L"sh", L"conpty", L"powershell"}))
    {
        return id == L"terminal" || id == L"wsl" || id == L"powershell";
    }
    if (IsAny(query_view, {L"linux", L"kali", L"wsl", L"wsl2"}))
    {
        return id == L"wsl";
    }
    if (IsAny(query_view, {L"projeto", L"projetos", L"project", L"projects", L"workspace", L"codigo"}))
    {
        return id == L"projects" || id == L"code";
    }
    if (IsAny(query_view, {L"txt", L"nota", L"notas", L"editor"}))
    {
        return id == L"notepad" || id == L"code";
    }
    if (IsAny(query_view, {L"calc", L"calculadora", L"math"}))
    {
        return id == L"calc";
    }
    if (IsAny(query_view, {L"cloudos drive", L"drive", L"armazenamento", L"storage", L"home"}))
    {
        return id == L"drive";
    }
    if (IsAny(query_view, {L"pasta", L"pastas", L"arquivo", L"arquivos", L"explorer", L"disco", L"hd"}))
    {
        return id == L"files" || id == L"drive" || id == L"systemdrive";
    }
    if (IsAny(query_view, {L"cpu", L"ram", L"processo", L"monitor", L"task"}))
    {
        return id == L"sysmon" || id == L"control";
    }
    if (IsAny(query_view, {L"config", L"painel", L"ajustes", L"settings", L"configuracoes"}))
    {
        return id == L"settings" || id == L"control";
    }
    if (IsAny(query_view, {L"saude", L"health", L"doctor", L"diagnostico"}))
    {
        return id == L"health";
    }
    if (IsAny(query_view, {L"paint", L"desenho", L"arte", L"foto"}))
    {
        return id == L"paint";
    }
    if (IsAny(query_view, {L"print", L"captura", L"snip", L"screenshot"}))
    {
        return id == L"snip";
    }
    return false;
}

std::vector<int> NativeSearchEngine::FilterApps(const std::wstring& query)
{
    std::vector<int> indices;
    std::wstring lower = query;
    Lowercase(lower);

    while (!lower.empty() && std::iswspace(lower.back()))
    {
        lower.pop_back();
    }
    while (!lower.empty() && std::iswspace(lower.front()))
    {
        lower.erase(lower.begin());
    }

    indices.reserve(kAllApps.size());
    for (std::size_t index = 0; index < kAllApps.size(); ++index)
    {
        if (Matches(kAllApps[index], lower))
        {
            indices.push_back(static_cast<int>(index));
        }
    }
    return indices;
}

} // namespace CloudOS
