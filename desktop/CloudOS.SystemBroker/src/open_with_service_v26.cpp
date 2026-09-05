#include "open_with_service_v26.h"
#include "app_service_v21.h"

#include <Windows.h>
#include <shellapi.h>

#include <algorithm>
#include <filesystem>

namespace CloudOS
{

namespace
{

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return {};
    const int len = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), nullptr, 0);
    if (len <= 0) return {};
    std::wstring out(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.length()), out.data(), len);
    return out;
}

std::string ToLower(std::string str)
{
    std::transform(str.begin(), str.end(), str.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return str;
}

} // namespace

JsonObject FileAssociationV26::ToJsonObject() const
{
    JsonObject obj;
    obj["extension"] = JsonValue(extension);
    obj["default_app_id"] = JsonValue(default_app_id);
    obj["friendly_name"] = JsonValue(friendly_name);

    JsonArray apps;
    for (const auto& a : candidate_apps)
    {
        apps.push_back(JsonValue(a));
    }
    obj["candidate_apps"] = JsonValue(std::move(apps));
    return obj;
}

OpenWithServiceV26& OpenWithServiceV26::Instance()
{
    static OpenWithServiceV26 instance;
    return instance;
}

OpenWithServiceV26::OpenWithServiceV26()
{
    InitDefaultAssociations();
}

void OpenWithServiceV26::InitDefaultAssociations()
{
    associations_ = {
        {".txt", "windows:notepad", "Documento de Texto", {"windows:notepad", "cloudos:terminal"}},
        {".log", "windows:notepad", "Arquivo de Log", {"windows:notepad", "cloudos:terminal"}},
        {".md", "windows:notepad", "Documento Markdown", {"windows:notepad", "cloudos:browser"}},
        {".json", "windows:notepad", "Arquivo JSON", {"windows:notepad", "cloudos:browser"}},
        {".xml", "windows:notepad", "Documento XML", {"windows:notepad", "cloudos:browser"}},
        {".ini", "windows:notepad", "Arquivo de Configuração", {"windows:notepad"}},
        {".cfg", "windows:notepad", "Arquivo de Configuração", {"windows:notepad"}},
        {".html", "cloudos:browser", "Página Web HTML", {"cloudos:browser", "windows:notepad"}},
        {".htm", "cloudos:browser", "Página Web HTML", {"cloudos:browser", "windows:notepad"}},
        {".svg", "cloudos:browser", "Imagem Vetorial SVG", {"cloudos:browser", "windows:notepad"}},
        {".pdf", "cloudos:browser", "Documento PDF", {"cloudos:browser"}},
        {".png", "windows:photos", "Imagem PNG", {"windows:photos", "cloudos:browser"}},
        {".jpg", "windows:photos", "Imagem JPEG", {"windows:photos", "cloudos:browser"}},
        {".jpeg", "windows:photos", "Imagem JPEG", {"windows:photos", "cloudos:browser"}},
        {".bmp", "windows:photos", "Imagem Bitmap", {"windows:photos"}},
        {".sh", "cloudos:terminal", "Script Shell Linux", {"cloudos:terminal", "windows:notepad"}},
        {".bash", "cloudos:terminal", "Script Bash", {"cloudos:terminal", "windows:notepad"}},
        {".ps1", "cloudos:terminal", "Script PowerShell", {"cloudos:terminal", "windows:notepad"}},
        {".bat", "windows:notepad", "Script em Lote Windows", {"windows:notepad", "cloudos:terminal"}},
        {".cmd", "windows:notepad", "Script de Comando Windows", {"windows:notepad", "cloudos:terminal"}}
    };
}

std::vector<FileAssociationV26> OpenWithServiceV26::GetAssociations() const
{
    return associations_;
}

std::string OpenWithServiceV26::GetDefaultApp(const std::string& extension) const
{
    const std::string ext = ToLower(extension);
    for (const auto& assoc : associations_)
    {
        if (assoc.extension == ext)
        {
            return assoc.default_app_id;
        }
    }
    return {};
}

bool OpenWithServiceV26::SetDefaultApp(const std::string& extension, const std::string& app_id)
{
    const std::string ext = ToLower(extension);
    for (auto& assoc : associations_)
    {
        if (assoc.extension == ext)
        {
            assoc.default_app_id = app_id;
            return true;
        }
    }
    FileAssociationV26 newAssoc;
    newAssoc.extension = ext;
    newAssoc.default_app_id = app_id;
    newAssoc.friendly_name = "Arquivo " + ext;
    newAssoc.candidate_apps = {app_id};
    associations_.push_back(std::move(newAssoc));
    return true;
}

bool OpenWithServiceV26::OpenFile(
    const std::string& path,
    const std::string& preferred_app_id,
    std::string* error)
{
    if (path.empty())
    {
        if (error) *error = "Path is empty";
        return false;
    }

    std::filesystem::path fp = Utf8ToWide(path);
    std::string ext = ToLower(fp.extension().string());

    std::string targetApp = preferred_app_id;
    if (targetApp.empty())
    {
        targetApp = GetDefaultApp(ext);
    }

    if (targetApp == "windows:notepad")
    {
        HINSTANCE hInst = ShellExecuteW(
            nullptr,
            L"open",
            L"notepad.exe",
            Utf8ToWide(path).c_str(),
            nullptr,
            SW_SHOWNORMAL);
        if (reinterpret_cast<intptr_t>(hInst) <= 32)
        {
            if (error) *error = "Failed to launch Notepad: " + std::to_string(reinterpret_cast<intptr_t>(hInst));
            return false;
        }
        return true;
    }

    if (targetApp == "cloudos:browser" || targetApp == "browser")
    {
        LaunchStatus status;
        std::string err;
        return AppServiceV21::Instance().LaunchAppStructured("cloudos:browser", status, err);
    }

    if (targetApp == "cloudos:terminal" || targetApp == "terminal")
    {
        LaunchStatus status;
        std::string err;
        return AppServiceV21::Instance().LaunchAppStructured("cloudos:terminal", status, err);
    }

    // Default system open
    HINSTANCE hInst = ShellExecuteW(
        nullptr,
        L"open",
        Utf8ToWide(path).c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);

    if (reinterpret_cast<intptr_t>(hInst) <= 32)
    {
        // If standard open failed, trigger Open With dialog
        return ShowOpenWithDialog(path, error);
    }

    return true;
}

bool OpenWithServiceV26::ShowOpenWithDialog(const std::string& path, std::string* error)
{
    std::wstring wpath = Utf8ToWide(path);
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.lpVerb = L"openas";
    sei.lpFile = wpath.c_str();
    sei.nShow = SW_SHOWNORMAL;
    sei.fMask = SEE_MASK_INVOKEIDLIST;

    if (!ShellExecuteExW(&sei))
    {
        if (error) *error = "Failed to show Open With dialog: " + std::to_string(GetLastError());
        return false;
    }
    return true;
}

} // namespace CloudOS
