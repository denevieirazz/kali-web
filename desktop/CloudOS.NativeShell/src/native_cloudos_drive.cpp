#include "native_cloudos_drive.h"

#include <objbase.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <string_view>
#include <system_error>
#include <utility>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

namespace CloudOS
{
namespace
{
namespace fs = std::filesystem;

constexpr std::wstring_view kInternalRoot = L".cloudos-system";
constexpr std::wstring_view kTrashName = L"trash";
constexpr std::size_t kMaxSegments = 64;
constexpr int kMaxUtf8NameBytes = 255;

std::recursive_mutex g_drive_mutex;

void SetError(std::wstring* error, std::wstring_view message)
{
    if (error != nullptr)
    {
        *error = message;
    }
}

std::wstring Win32ErrorMessage(DWORD code, std::wstring_view fallback)
{
    wchar_t* raw = nullptr;
    const DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
            FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        code,
        0,
        reinterpret_cast<wchar_t*>(&raw),
        0,
        nullptr);

    std::wstring message;
    if (length != 0 && raw != nullptr)
    {
        message.assign(raw, raw + length);
        while (!message.empty() &&
            (message.back() == L'\r' || message.back() == L'\n' ||
             message.back() == L' ' || message.back() == L'.'))
        {
            message.pop_back();
        }
        LocalFree(raw);
    }

    if (message.empty())
    {
        message.assign(fallback);
    }
    return message;
}

std::wstring JoinError(std::wstring_view prefix, DWORD code)
{
    std::wstring result(prefix);
    result += L": ";
    result += Win32ErrorMessage(code, L"erro do Windows");
    return result;
}

std::string WideToUtf8(std::wstring_view value)
{
    if (value.empty())
    {
        return {};
    }

    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0)
    {
        return {};
    }

    std::string output(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required,
            nullptr,
            nullptr) != required)
    {
        return {};
    }
    return output;
}

std::wstring Utf8ToWide(std::string_view value)
{
    if (value.empty())
    {
        return {};
    }

    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (required <= 0)
    {
        return {};
    }

    std::wstring output(static_cast<std::size_t>(required), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            output.data(),
            required) != required)
    {
        return {};
    }
    return output;
}

std::string JsonEscape(std::wstring_view value)
{
    const std::string utf8 = WideToUtf8(value);
    std::string output;
    output.reserve(utf8.size() + 8u);
    for (const unsigned char ch : utf8)
    {
        switch (ch)
        {
        case '"': output += "\\\""; break;
        case '\\': output += "\\\\"; break;
        case '\b': output += "\\b"; break;
        case '\f': output += "\\f"; break;
        case '\n': output += "\\n"; break;
        case '\r': output += "\\r"; break;
        case '\t': output += "\\t"; break;
        default:
            if (ch < 0x20u)
            {
                constexpr char hex[] = "0123456789abcdef";
                output += "\\u00";
                output.push_back(hex[(ch >> 4u) & 0x0fu]);
                output.push_back(hex[ch & 0x0fu]);
            }
            else
            {
                output.push_back(static_cast<char>(ch));
            }
            break;
        }
    }
    return output;
}

void SkipJsonSpace(std::string_view text, std::size_t* offset)
{
    while (*offset < text.size())
    {
        const char ch = text[*offset];
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
        {
            break;
        }
        ++(*offset);
    }
}

int HexDigit(char ch)
{
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
    if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
    return -1;
}

void AppendUtf8Codepoint(unsigned codepoint, std::string* output)
{
    if (codepoint <= 0x7fu)
    {
        output->push_back(static_cast<char>(codepoint));
    }
    else if (codepoint <= 0x7ffu)
    {
        output->push_back(static_cast<char>(0xc0u | (codepoint >> 6u)));
        output->push_back(static_cast<char>(0x80u | (codepoint & 0x3fu)));
    }
    else
    {
        output->push_back(static_cast<char>(0xe0u | (codepoint >> 12u)));
        output->push_back(static_cast<char>(0x80u | ((codepoint >> 6u) & 0x3fu)));
        output->push_back(static_cast<char>(0x80u | (codepoint & 0x3fu)));
    }
}

bool ParseJsonString(std::string_view text, std::size_t* offset, std::string* output)
{
    SkipJsonSpace(text, offset);
    if (*offset >= text.size() || text[*offset] != '"')
    {
        return false;
    }
    ++(*offset);
    output->clear();

    while (*offset < text.size())
    {
        char ch = text[(*offset)++];
        if (ch == '"')
        {
            return true;
        }
        if (ch != '\\')
        {
            output->push_back(ch);
            continue;
        }
        if (*offset >= text.size())
        {
            return false;
        }

        ch = text[(*offset)++];
        switch (ch)
        {
        case '"': output->push_back('"'); break;
        case '\\': output->push_back('\\'); break;
        case '/': output->push_back('/'); break;
        case 'b': output->push_back('\b'); break;
        case 'f': output->push_back('\f'); break;
        case 'n': output->push_back('\n'); break;
        case 'r': output->push_back('\r'); break;
        case 't': output->push_back('\t'); break;
        case 'u':
        {
            if (*offset + 4u > text.size())
            {
                return false;
            }
            unsigned codepoint = 0;
            for (int index = 0; index < 4; ++index)
            {
                const int digit = HexDigit(text[*offset + static_cast<std::size_t>(index)]);
                if (digit < 0)
                {
                    return false;
                }
                codepoint = (codepoint << 4u) | static_cast<unsigned>(digit);
            }
            *offset += 4u;
            AppendUtf8Codepoint(codepoint, output);
            break;
        }
        default:
            return false;
        }
    }
    return false;
}

bool FindJsonValueOffset(
    std::string_view text,
    std::string_view key,
    std::size_t* offset)
{
    std::string needle = "\"";
    needle.append(key);
    needle += "\"";
    const std::size_t key_pos = text.find(needle);
    if (key_pos == std::string_view::npos)
    {
        return false;
    }
    std::size_t cursor = key_pos + needle.size();
    SkipJsonSpace(text, &cursor);
    if (cursor >= text.size() || text[cursor] != ':')
    {
        return false;
    }
    ++cursor;
    SkipJsonSpace(text, &cursor);
    *offset = cursor;
    return true;
}

bool FindJsonString(
    std::string_view text,
    std::string_view key,
    std::wstring* output)
{
    std::size_t cursor = 0;
    if (!FindJsonValueOffset(text, key, &cursor))
    {
        return false;
    }
    std::string utf8;
    if (!ParseJsonString(text, &cursor, &utf8))
    {
        return false;
    }
    *output = Utf8ToWide(utf8);
    return !utf8.empty() ? !output->empty() : true;
}

bool FindJsonStringArray(
    std::string_view text,
    std::string_view key,
    std::vector<std::wstring>* output)
{
    std::size_t cursor = 0;
    if (!FindJsonValueOffset(text, key, &cursor) ||
        cursor >= text.size() || text[cursor] != '[')
    {
        return false;
    }
    ++cursor;
    output->clear();

    while (true)
    {
        SkipJsonSpace(text, &cursor);
        if (cursor >= text.size())
        {
            return false;
        }
        if (text[cursor] == ']')
        {
            ++cursor;
            return true;
        }

        std::string utf8;
        if (!ParseJsonString(text, &cursor, &utf8))
        {
            return false;
        }
        const std::wstring value = Utf8ToWide(utf8);
        if (!utf8.empty() && value.empty())
        {
            return false;
        }
        output->push_back(value);

        SkipJsonSpace(text, &cursor);
        if (cursor >= text.size())
        {
            return false;
        }
        if (text[cursor] == ',')
        {
            ++cursor;
            continue;
        }
        if (text[cursor] == ']')
        {
            ++cursor;
            return true;
        }
        return false;
    }
}

bool IsHexId(std::wstring_view id)
{
    if (id.size() != 32u)
    {
        return false;
    }
    return std::all_of(
        id.begin(),
        id.end(),
        [](wchar_t ch)
        {
            return (ch >= L'0' && ch <= L'9') ||
                (ch >= L'a' && ch <= L'f') ||
                (ch >= L'A' && ch <= L'F');
        });
}

std::wstring GenerateId()
{
    GUID guid{};
    if (FAILED(CoCreateGuid(&guid)))
    {
        return {};
    }

    wchar_t buffer[33]{};
    swprintf_s(
        buffer,
        L"%08lx%04hx%04hx%02x%02x%02x%02x%02x%02x%02x%02x",
        guid.Data1,
        guid.Data2,
        guid.Data3,
        static_cast<unsigned>(guid.Data4[0]),
        static_cast<unsigned>(guid.Data4[1]),
        static_cast<unsigned>(guid.Data4[2]),
        static_cast<unsigned>(guid.Data4[3]),
        static_cast<unsigned>(guid.Data4[4]),
        static_cast<unsigned>(guid.Data4[5]),
        static_cast<unsigned>(guid.Data4[6]),
        static_cast<unsigned>(guid.Data4[7]));
    return buffer;
}

std::wstring IsoTimestampUtc()
{
    SYSTEMTIME now{};
    GetSystemTime(&now);
    wchar_t buffer[32]{};
    swprintf_s(
        buffer,
        L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        static_cast<unsigned>(now.wYear),
        static_cast<unsigned>(now.wMonth),
        static_cast<unsigned>(now.wDay),
        static_cast<unsigned>(now.wHour),
        static_cast<unsigned>(now.wMinute),
        static_cast<unsigned>(now.wSecond),
        static_cast<unsigned>(now.wMilliseconds));
    return buffer;
}

fs::path ResolveRootPath()
{
    std::array<wchar_t, 32768> override_path{};
    const DWORD override_length = GetEnvironmentVariableW(
        L"CLOUDOS_DRIVE_DIR",
        override_path.data(),
        static_cast<DWORD>(override_path.size()));
    if (override_length > 0 && override_length < override_path.size())
    {
        std::error_code ec;
        return fs::absolute(fs::path(override_path.data()), ec).lexically_normal();
    }

    PWSTR raw = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(
            FOLDERID_LocalAppData,
            KF_FLAG_DEFAULT,
            nullptr,
            &raw)) && raw != nullptr)
    {
        fs::path result(raw);
        CoTaskMemFree(raw);
        result /= L"CloudOS";
        result /= L"Drive";
        return result.lexically_normal();
    }

    std::array<wchar_t, 32768> temp{};
    const DWORD temp_length = GetTempPathW(
        static_cast<DWORD>(temp.size()),
        temp.data());
    if (temp_length > 0 && temp_length < temp.size())
    {
        return (fs::path(temp.data()) / L"CloudOS" / L"Drive").lexically_normal();
    }
    return {};
}

bool EqualInsensitive(wchar_t left, wchar_t right)
{
    return std::towlower(left) == std::towlower(right);
}

std::wstring TrimTrailingSeparators(std::wstring value)
{
    while (value.size() > 3u &&
        (value.back() == L'\\' || value.back() == L'/'))
    {
        value.pop_back();
    }
    return value;
}

bool IsInsidePath(const fs::path& root, const fs::path& candidate)
{
    const std::wstring root_text =
        TrimTrailingSeparators(root.lexically_normal().wstring());
    const std::wstring candidate_text =
        TrimTrailingSeparators(candidate.lexically_normal().wstring());

    if (candidate_text.size() < root_text.size() ||
        !std::equal(
            root_text.begin(),
            root_text.end(),
            candidate_text.begin(),
            EqualInsensitive))
    {
        return false;
    }
    return candidate_text.size() == root_text.size() ||
        candidate_text[root_text.size()] == L'\\' ||
        candidate_text[root_text.size()] == L'/';
}

bool ValidateSegment(std::wstring_view segment, std::wstring* error)
{
    if (segment.empty() || segment == L"." || segment == L".." ||
        _wcsicmp(std::wstring(segment).c_str(), std::wstring(kInternalRoot).c_str()) == 0)
    {
        SetError(error, L"Caminho invalido no CloudOS Drive.");
        return false;
    }

    for (const wchar_t ch : segment)
    {
        if (ch < 32 || ch == L'/' || ch == L'\\' || ch == L':' ||
            ch == L'*' || ch == L'?' || ch == L'"' || ch == L'<' ||
            ch == L'>' || ch == L'|')
        {
            SetError(error, L"Nome invalido no CloudOS Drive.");
            return false;
        }
    }

    const std::string utf8 = WideToUtf8(segment);
    if ((segment.size() > 0u && utf8.empty()) ||
        utf8.size() > static_cast<std::size_t>(kMaxUtf8NameBytes))
    {
        SetError(error, L"Nome excede o limite do CloudOS Drive.");
        return false;
    }
    return true;
}

bool ValidateSegments(
    const std::vector<std::wstring>& segments,
    bool allow_empty,
    std::wstring* error)
{
    if ((!allow_empty && segments.empty()) || segments.size() > kMaxSegments)
    {
        SetError(error, L"Caminho invalido no CloudOS Drive.");
        return false;
    }
    for (const std::wstring& segment : segments)
    {
        if (!ValidateSegment(segment, error))
        {
            return false;
        }
    }
    return true;
}

fs::path BuildPath(
    const fs::path& root,
    const std::vector<std::wstring>& segments)
{
    fs::path result = root;
    for (const std::wstring& segment : segments)
    {
        result /= segment;
    }
    return result.lexically_normal();
}

bool IsReparsePoint(const fs::path& path)
{
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

bool EnsureDirectoryTree(const fs::path& path, std::wstring* error)
{
    std::error_code ec;
    fs::create_directories(path, ec);
    if (ec)
    {
        SetError(error, L"Nao foi possivel preparar o CloudOS Drive.");
        return false;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"A raiz do CloudOS Drive nao e um diretorio fisico confiavel.");
        return false;
    }
    return true;
}

bool EnsureReadyUnlocked(fs::path* root, std::wstring* error)
{
    const fs::path resolved = ResolveRootPath();
    if (resolved.empty())
    {
        SetError(error, L"Nao foi possivel resolver LocalAppData para o CloudOS Drive.");
        return false;
    }

    if (!EnsureDirectoryTree(resolved, error))
    {
        return false;
    }

    const std::array<std::vector<std::wstring>, 9> standard_directories{{
        {L"Home"},
        {L"Home", L"Desktop"},
        {L"Home", L"Documents"},
        {L"Home", L"Downloads"},
        {L"Home", L"Projects"},
        {L"Shared"},
        {L"Apps"},
        {L"Apps", L"windows"},
        {L"Apps", L"linux"},
    }};

    for (const auto& segments : standard_directories)
    {
        const fs::path directory = BuildPath(resolved, segments);
        if (!EnsureDirectoryTree(directory, error))
        {
            return false;
        }
    }

    const fs::path internal = resolved / std::wstring(kInternalRoot);
    const fs::path trash = internal / std::wstring(kTrashName);
    if (!EnsureDirectoryTree(internal, error) ||
        !EnsureDirectoryTree(trash, error))
    {
        return false;
    }

    (void)SetFileAttributesW(
        internal.c_str(),
        GetFileAttributesW(internal.c_str()) | FILE_ATTRIBUTE_HIDDEN);

    if (root != nullptr)
    {
        *root = resolved;
    }
    return true;
}

bool ExistingSafePath(
    const fs::path& root,
    const std::vector<std::wstring>& segments,
    bool allow_empty,
    fs::path* result,
    DWORD* final_attributes,
    std::wstring* error)
{
    if (!ValidateSegments(segments, allow_empty, error))
    {
        return false;
    }

    fs::path current = root;
    DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"Raiz invalida do CloudOS Drive.");
        return false;
    }

    for (const std::wstring& segment : segments)
    {
        current /= segment;
        attributes = GetFileAttributesW(current.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES)
        {
            SetError(error, L"Arquivo ou pasta nao encontrado no CloudOS Drive.");
            return false;
        }
        if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        {
            SetError(error, L"Links e pontos de reparo nao sao seguidos pelo CloudOS Drive.");
            return false;
        }
    }

    if (!IsInsidePath(root, current))
    {
        SetError(error, L"Tentativa de sair da raiz do CloudOS Drive bloqueada.");
        return false;
    }

    if (result != nullptr)
    {
        *result = current.lexically_normal();
    }
    if (final_attributes != nullptr)
    {
        *final_attributes = attributes;
    }
    return true;
}

bool DestinationSafePath(
    const fs::path& root,
    const std::vector<std::wstring>& segments,
    fs::path* result,
    bool* exists,
    DWORD* attributes,
    std::wstring* error)
{
    if (!ValidateSegments(segments, false, error))
    {
        return false;
    }

    std::vector<std::wstring> parent_segments(
        segments.begin(),
        segments.end() - 1);
    fs::path parent;
    DWORD parent_attributes = 0;
    if (!ExistingSafePath(
            root,
            parent_segments,
            true,
            &parent,
            &parent_attributes,
            error) ||
        (parent_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        if (error != nullptr && error->empty())
        {
            *error = L"A pasta de destino nao existe.";
        }
        return false;
    }

    fs::path candidate = (parent / segments.back()).lexically_normal();
    if (!IsInsidePath(root, candidate))
    {
        SetError(error, L"Destino fora do CloudOS Drive bloqueado.");
        return false;
    }

    const DWORD candidate_attributes = GetFileAttributesW(candidate.c_str());
    const bool candidate_exists = candidate_attributes != INVALID_FILE_ATTRIBUTES;
    if (candidate_exists &&
        (candidate_attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"Links e pontos de reparo nao sao aceitos pelo CloudOS Drive.");
        return false;
    }

    if (result != nullptr)
    {
        *result = candidate;
    }
    if (exists != nullptr)
    {
        *exists = candidate_exists;
    }
    if (attributes != nullptr)
    {
        *attributes = candidate_exists ? candidate_attributes : 0;
    }
    return true;
}

bool CopyTreeSafe(
    const fs::path& source,
    const fs::path& destination,
    std::wstring* error)
{
    const DWORD attributes = GetFileAttributesW(source.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        SetError(error, L"Origem nao encontrada durante a copia.");
        return false;
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"Copia de links ou pontos de reparo foi bloqueada.");
        return false;
    }

    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        if (!CopyFileW(source.c_str(), destination.c_str(), TRUE))
        {
            SetError(error, JoinError(L"Falha ao copiar arquivo", GetLastError()));
            return false;
        }
        return true;
    }

    if (!CreateDirectoryW(destination.c_str(), nullptr))
    {
        SetError(error, JoinError(L"Falha ao criar pasta de destino", GetLastError()));
        return false;
    }

    std::error_code ec;
    for (fs::directory_iterator it(source, ec), end; !ec && it != end; it.increment(ec))
    {
        const fs::path child_source = it->path();
        const fs::path child_destination = destination / child_source.filename();
        if (!CopyTreeSafe(child_source, child_destination, error))
        {
            std::error_code cleanup_error;
            fs::remove_all(destination, cleanup_error);
            return false;
        }
    }
    if (ec)
    {
        std::error_code cleanup_error;
        fs::remove_all(destination, cleanup_error);
        SetError(error, L"Falha ao enumerar a pasta durante a copia.");
        return false;
    }
    return true;
}

bool RemoveTreeSafe(const fs::path& target, std::wstring* error)
{
    const DWORD attributes = GetFileAttributesW(target.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        return true;
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"Exclusao de link ou ponto de reparo foi bloqueada.");
        return false;
    }

    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        if (!DeleteFileW(target.c_str()))
        {
            SetError(error, JoinError(L"Falha ao excluir arquivo", GetLastError()));
            return false;
        }
        return true;
    }

    std::error_code ec;
    for (fs::directory_iterator it(target, ec), end; !ec && it != end; it.increment(ec))
    {
        if (!RemoveTreeSafe(it->path(), error))
        {
            return false;
        }
    }
    if (ec)
    {
        SetError(error, L"Falha ao enumerar pasta para exclusao.");
        return false;
    }
    if (!RemoveDirectoryW(target.c_str()))
    {
        SetError(error, JoinError(L"Falha ao excluir pasta", GetLastError()));
        return false;
    }
    return true;
}

bool WriteMetadata(
    const fs::path& path,
    const CloudOSDriveTrashEntry& entry,
    std::wstring* error)
{
    std::string json = "{\"id\":\"";
    json += JsonEscape(entry.id);
    json += "\",\"storedName\":\"";
    json += JsonEscape(entry.stored_name);
    json += "\",\"originalName\":\"";
    json += JsonEscape(entry.original_name);
    json += "\",\"originalPath\":[";
    for (std::size_t index = 0; index < entry.original_path.size(); ++index)
    {
        if (index != 0u)
        {
            json += ',';
        }
        json += '"';
        json += JsonEscape(entry.original_path[index]);
        json += '"';
    }
    json += "],\"deletedAt\":\"";
    json += JsonEscape(entry.deleted_at);
    json += "\"}";

    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream)
    {
        SetError(error, L"Nao foi possivel gravar metadados da lixeira.");
        return false;
    }
    stream.write(json.data(), static_cast<std::streamsize>(json.size()));
    stream.flush();
    if (!stream)
    {
        SetError(error, L"Falha ao persistir metadados da lixeira.");
        return false;
    }
    return true;
}

bool ReadAllText(const fs::path& path, std::string* output)
{
    std::ifstream stream(path, std::ios::binary);
    if (!stream)
    {
        return false;
    }
    stream.seekg(0, std::ios::end);
    const std::streamoff length = stream.tellg();
    if (length < 0 || length > 1024 * 1024)
    {
        return false;
    }
    stream.seekg(0, std::ios::beg);
    output->assign(static_cast<std::size_t>(length), '\0');
    if (length > 0)
    {
        stream.read(output->data(), length);
    }
    return static_cast<bool>(stream) || stream.eof();
}

bool LoadTrashMetadata(
    const fs::path& root,
    const std::wstring& id,
    CloudOSDriveTrashEntry* entry,
    fs::path* item_path,
    fs::path* metadata_path,
    std::wstring* error)
{
    if (!IsHexId(id))
    {
        SetError(error, L"Identificador de lixeira invalido.");
        return false;
    }

    const fs::path trash = root / std::wstring(kInternalRoot) / std::wstring(kTrashName);
    const fs::path json_path = trash / (id + L".json");
    const fs::path stored_path = trash / (id + L".item");

    std::string json;
    if (!ReadAllText(json_path, &json))
    {
        SetError(error, L"Metadados da lixeira nao encontrados.");
        return false;
    }

    CloudOSDriveTrashEntry parsed{};
    if (!FindJsonString(json, "id", &parsed.id) ||
        !FindJsonString(json, "originalName", &parsed.original_name) ||
        !FindJsonStringArray(json, "originalPath", &parsed.original_path) ||
        !FindJsonString(json, "deletedAt", &parsed.deleted_at) ||
        _wcsicmp(parsed.id.c_str(), id.c_str()) != 0 ||
        !ValidateSegments(parsed.original_path, true, error) ||
        !ValidateSegment(parsed.original_name, error))
    {
        if (error != nullptr && error->empty())
        {
            *error = L"Metadados da lixeira invalidos.";
        }
        return false;
    }

    parsed.stored_name = id + L".item";
    WIN32_FILE_ATTRIBUTE_DATA attributes{};
    if (!GetFileAttributesExW(
            stored_path.c_str(),
            GetFileExInfoStandard,
            &attributes) ||
        (attributes.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        SetError(error, L"Item da lixeira ausente ou inseguro.");
        return false;
    }

    parsed.directory =
        (attributes.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    parsed.size = parsed.directory
        ? 0ull
        : (static_cast<unsigned long long>(attributes.nFileSizeHigh) << 32ull) |
            static_cast<unsigned long long>(attributes.nFileSizeLow);

    if (entry != nullptr)
    {
        *entry = std::move(parsed);
    }
    if (item_path != nullptr)
    {
        *item_path = stored_path;
    }
    if (metadata_path != nullptr)
    {
        *metadata_path = json_path;
    }
    return true;
}

} // namespace

bool NativeCloudOSDrive::EnsureReady(std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    return EnsureReadyUnlocked(nullptr, error);
}

std::wstring NativeCloudOSDrive::Root()
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, nullptr))
    {
        return {};
    }
    return root.wstring();
}

std::wstring NativeCloudOSDrive::HomeRoot()
{
    const std::wstring root = Root();
    return root.empty() ? std::wstring{} : (fs::path(root) / L"Home").wstring();
}

std::wstring NativeCloudOSDrive::ProjectsRoot()
{
    const std::wstring root = Root();
    return root.empty()
        ? std::wstring{}
        : (fs::path(root) / L"Home" / L"Projects").wstring();
}

std::wstring NativeCloudOSDrive::TrashRoot()
{
    const std::wstring root = Root();
    return root.empty()
        ? std::wstring{}
        : (fs::path(root) / std::wstring(kInternalRoot) / std::wstring(kTrashName)).wstring();
}

bool NativeCloudOSDrive::IsPathInside(const std::wstring& absolute_path)
{
    if (absolute_path.empty())
    {
        return false;
    }
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, nullptr))
    {
        return false;
    }
    std::error_code ec;
    const fs::path candidate = fs::absolute(fs::path(absolute_path), ec).lexically_normal();
    return !ec && IsInsidePath(root, candidate);
}

bool NativeCloudOSDrive::SegmentsFromAbsolutePath(
    const std::wstring& absolute_path,
    std::vector<std::wstring>* segments,
    std::wstring* error)
{
    if (segments == nullptr || absolute_path.empty())
    {
        SetError(error, L"Caminho invalido no CloudOS Drive.");
        return false;
    }

    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    std::error_code ec;
    const fs::path candidate = fs::absolute(fs::path(absolute_path), ec).lexically_normal();
    if (ec || !IsInsidePath(root, candidate))
    {
        SetError(error, L"Caminho fora do CloudOS Drive.");
        return false;
    }

    const fs::path relative = candidate.lexically_relative(root);
    std::vector<std::wstring> parsed;
    if (!relative.empty() && relative != L".")
    {
        for (const fs::path& part : relative)
        {
            const std::wstring value = part.wstring();
            if (value.empty() || value == L".")
            {
                continue;
            }
            parsed.push_back(value);
        }
    }
    if (!ValidateSegments(parsed, true, error))
    {
        return false;
    }
    *segments = std::move(parsed);
    return true;
}

std::wstring NativeCloudOSDrive::AbsolutePath(
    const std::vector<std::wstring>& segments)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, nullptr) ||
        !ValidateSegments(segments, true, nullptr))
    {
        return {};
    }
    return BuildPath(root, segments).wstring();
}

bool NativeCloudOSDrive::List(
    const std::vector<std::wstring>& segments,
    std::vector<CloudOSDriveEntry>* entries,
    std::wstring* error)
{
    if (entries == nullptr)
    {
        SetError(error, L"Destino de listagem invalido.");
        return false;
    }

    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path directory;
    DWORD attributes = 0;
    if (!ExistingSafePath(root, segments, true, &directory, &attributes, error) ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
    {
        SetError(error, L"O caminho nao e uma pasta do CloudOS Drive.");
        return false;
    }

    std::vector<CloudOSDriveEntry> result;
    std::error_code ec;
    for (fs::directory_iterator it(directory, ec), end; !ec && it != end; it.increment(ec))
    {
        const std::wstring name = it->path().filename().wstring();
        if (segments.empty() && _wcsicmp(name.c_str(), std::wstring(kInternalRoot).c_str()) == 0)
        {
            continue;
        }

        WIN32_FILE_ATTRIBUTE_DATA data{};
        if (!GetFileAttributesExW(
                it->path().c_str(),
                GetFileExInfoStandard,
                &data))
        {
            continue;
        }

        CloudOSDriveEntry item{};
        item.name = name;
        item.directory =
            (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        item.reparse_point =
            (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
        item.size = item.directory || item.reparse_point
            ? 0ull
            : (static_cast<unsigned long long>(data.nFileSizeHigh) << 32ull) |
                static_cast<unsigned long long>(data.nFileSizeLow);
        item.modified = data.ftLastWriteTime;
        result.push_back(std::move(item));
    }
    if (ec)
    {
        SetError(error, L"Falha ao listar o CloudOS Drive.");
        return false;
    }

    std::sort(
        result.begin(),
        result.end(),
        [](const CloudOSDriveEntry& left, const CloudOSDriveEntry& right)
        {
            if (left.directory != right.directory)
            {
                return left.directory > right.directory;
            }
            return _wcsicmp(left.name.c_str(), right.name.c_str()) < 0;
        });
    *entries = std::move(result);
    return true;
}

bool NativeCloudOSDrive::Read(
    const std::vector<std::wstring>& segments,
    unsigned long long offset,
    std::size_t maximum_bytes,
    std::vector<std::uint8_t>* data,
    bool* eof,
    unsigned long long* total_size,
    std::wstring* error)
{
    if (data == nullptr || maximum_bytes == 0u)
    {
        SetError(error, L"Leitura invalida do CloudOS Drive.");
        return false;
    }

    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path target;
    DWORD attributes = 0;
    if (!ExistingSafePath(root, segments, false, &target, &attributes, error) ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        SetError(error, L"O caminho nao e um arquivo regular do CloudOS Drive.");
        return false;
    }

    HANDLE file = CreateFileW(
        target.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        SetError(error, JoinError(L"Falha ao abrir arquivo", GetLastError()));
        return false;
    }

    FILE_ATTRIBUTE_TAG_INFO tag{};
    if (!GetFileInformationByHandleEx(
            file,
            FileAttributeTagInfo,
            &tag,
            sizeof(tag)) ||
        (tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        CloseHandle(file);
        SetError(error, L"Ponto de reparo bloqueado durante a leitura.");
        return false;
    }

    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0)
    {
        const DWORD code = GetLastError();
        CloseHandle(file);
        SetError(error, JoinError(L"Falha ao consultar tamanho", code));
        return false;
    }

    const unsigned long long full_size =
        static_cast<unsigned long long>(size.QuadPart);
    const unsigned long long start = std::min(offset, full_size);
    const unsigned long long remaining = full_size - start;
    const std::size_t amount = static_cast<std::size_t>(
        std::min<unsigned long long>(
            remaining,
            static_cast<unsigned long long>(maximum_bytes)));

    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(start);
    if (!SetFilePointerEx(file, position, nullptr, FILE_BEGIN))
    {
        const DWORD code = GetLastError();
        CloseHandle(file);
        SetError(error, JoinError(L"Falha ao posicionar leitura", code));
        return false;
    }

    std::vector<std::uint8_t> result(amount);
    std::size_t completed = 0u;
    while (completed < amount)
    {
        const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(
            amount - completed,
            static_cast<std::size_t>(std::numeric_limits<DWORD>::max())));
        DWORD read = 0;
        if (!ReadFile(file, result.data() + completed, chunk, &read, nullptr))
        {
            const DWORD code = GetLastError();
            CloseHandle(file);
            SetError(error, JoinError(L"Falha durante leitura", code));
            return false;
        }
        completed += read;
        if (read == 0u)
        {
            break;
        }
    }
    CloseHandle(file);
    result.resize(completed);

    *data = std::move(result);
    if (eof != nullptr)
    {
        *eof = start + completed >= full_size;
    }
    if (total_size != nullptr)
    {
        *total_size = full_size;
    }
    return true;
}

bool NativeCloudOSDrive::Write(
    const std::vector<std::wstring>& segments,
    unsigned long long offset,
    const void* data,
    std::size_t size,
    bool truncate,
    unsigned long long* resulting_size,
    std::wstring* error)
{
    if (size > 0u && data == nullptr)
    {
        SetError(error, L"Bloco de gravacao invalido.");
        return false;
    }

    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path target;
    bool exists = false;
    DWORD attributes = 0;
    if (!DestinationSafePath(root, segments, &target, &exists, &attributes, error))
    {
        return false;
    }
    if (exists && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
    {
        SetError(error, L"O destino nao e um arquivo regular.");
        return false;
    }

    HANDLE file = CreateFileW(
        target.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ,
        nullptr,
        truncate ? CREATE_ALWAYS : OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        SetError(error, JoinError(L"Falha ao abrir arquivo para gravacao", GetLastError()));
        return false;
    }

    FILE_ATTRIBUTE_TAG_INFO tag{};
    if (!GetFileInformationByHandleEx(
            file,
            FileAttributeTagInfo,
            &tag,
            sizeof(tag)) ||
        (tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        CloseHandle(file);
        SetError(error, L"Ponto de reparo bloqueado durante a gravacao.");
        return false;
    }

    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset);
    if (!SetFilePointerEx(file, position, nullptr, FILE_BEGIN))
    {
        const DWORD code = GetLastError();
        CloseHandle(file);
        SetError(error, JoinError(L"Falha ao posicionar gravacao", code));
        return false;
    }

    const auto* bytes = static_cast<const std::uint8_t*>(data);
    std::size_t completed = 0u;
    while (completed < size)
    {
        const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(
            size - completed,
            static_cast<std::size_t>(std::numeric_limits<DWORD>::max())));
        DWORD written = 0;
        if (!WriteFile(file, bytes + completed, chunk, &written, nullptr) || written == 0u)
        {
            const DWORD code = GetLastError();
            CloseHandle(file);
            SetError(error, JoinError(L"Falha durante gravacao", code));
            return false;
        }
        completed += written;
    }

    (void)FlushFileBuffers(file);
    LARGE_INTEGER final_size{};
    if (!GetFileSizeEx(file, &final_size))
    {
        final_size.QuadPart = 0;
    }
    CloseHandle(file);

    if (resulting_size != nullptr)
    {
        *resulting_size = final_size.QuadPart > 0
            ? static_cast<unsigned long long>(final_size.QuadPart)
            : 0ull;
    }
    return true;
}

bool NativeCloudOSDrive::Mkdir(
    const std::vector<std::wstring>& segments,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path target;
    bool exists = false;
    if (!DestinationSafePath(root, segments, &target, &exists, nullptr, error))
    {
        return false;
    }
    if (exists)
    {
        SetError(error, L"A pasta ou arquivo de destino ja existe.");
        return false;
    }
    if (!CreateDirectoryW(target.c_str(), nullptr))
    {
        SetError(error, JoinError(L"Falha ao criar pasta", GetLastError()));
        return false;
    }
    return true;
}

bool NativeCloudOSDrive::Move(
    const std::vector<std::wstring>& source,
    const std::vector<std::wstring>& destination,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path source_path;
    DWORD source_attributes = 0;
    if (!ExistingSafePath(root, source, false, &source_path, &source_attributes, error))
    {
        return false;
    }

    fs::path destination_path;
    bool destination_exists = false;
    if (!DestinationSafePath(
            root,
            destination,
            &destination_path,
            &destination_exists,
            nullptr,
            error))
    {
        return false;
    }
    if (destination_exists)
    {
        SetError(error, L"O destino ja existe no CloudOS Drive.");
        return false;
    }
    if ((source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
        IsInsidePath(source_path, destination_path))
    {
        SetError(error, L"Nao e possivel mover uma pasta para dentro dela mesma.");
        return false;
    }

    if (!MoveFileExW(
            source_path.c_str(),
            destination_path.c_str(),
            MOVEFILE_WRITE_THROUGH))
    {
        SetError(error, JoinError(L"Falha ao mover item", GetLastError()));
        return false;
    }
    return true;
}

bool NativeCloudOSDrive::Copy(
    const std::vector<std::wstring>& source,
    const std::vector<std::wstring>& destination,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path source_path;
    DWORD source_attributes = 0;
    if (!ExistingSafePath(root, source, false, &source_path, &source_attributes, error))
    {
        return false;
    }

    fs::path destination_path;
    bool destination_exists = false;
    if (!DestinationSafePath(
            root,
            destination,
            &destination_path,
            &destination_exists,
            nullptr,
            error))
    {
        return false;
    }
    if (destination_exists)
    {
        SetError(error, L"O destino ja existe no CloudOS Drive.");
        return false;
    }
    if ((source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
        IsInsidePath(source_path, destination_path))
    {
        SetError(error, L"Nao e possivel copiar uma pasta para dentro dela mesma.");
        return false;
    }

    return CopyTreeSafe(source_path, destination_path, error);
}

bool NativeCloudOSDrive::Trash(
    const std::vector<std::wstring>& segments,
    CloudOSDriveTrashEntry* entry,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    fs::path source;
    DWORD source_attributes = 0;
    if (!ExistingSafePath(root, segments, false, &source, &source_attributes, error))
    {
        return false;
    }

    const std::wstring id = GenerateId();
    if (!IsHexId(id))
    {
        SetError(error, L"Nao foi possivel gerar o identificador da lixeira.");
        return false;
    }

    CloudOSDriveTrashEntry created{};
    created.id = id;
    created.stored_name = id + L".item";
    created.original_name = segments.back();
    created.original_path.assign(segments.begin(), segments.end() - 1);
    created.deleted_at = IsoTimestampUtc();
    created.directory = (source_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;

    if (!created.directory)
    {
        WIN32_FILE_ATTRIBUTE_DATA data{};
        if (GetFileAttributesExW(source.c_str(), GetFileExInfoStandard, &data))
        {
            created.size =
                (static_cast<unsigned long long>(data.nFileSizeHigh) << 32ull) |
                static_cast<unsigned long long>(data.nFileSizeLow);
        }
    }

    const fs::path trash = root / std::wstring(kInternalRoot) / std::wstring(kTrashName);
    const fs::path stored = trash / created.stored_name;
    const fs::path metadata = trash / (id + L".json");

    if (!MoveFileExW(source.c_str(), stored.c_str(), MOVEFILE_WRITE_THROUGH))
    {
        SetError(error, JoinError(L"Falha ao mover item para a lixeira", GetLastError()));
        return false;
    }

    if (!WriteMetadata(metadata, created, error))
    {
        (void)MoveFileExW(stored.c_str(), source.c_str(), MOVEFILE_WRITE_THROUGH);
        (void)DeleteFileW(metadata.c_str());
        return false;
    }

    if (entry != nullptr)
    {
        *entry = std::move(created);
    }
    return true;
}

bool NativeCloudOSDrive::ListTrash(
    std::vector<CloudOSDriveTrashEntry>* entries,
    std::wstring* error)
{
    if (entries == nullptr)
    {
        SetError(error, L"Destino de listagem da lixeira invalido.");
        return false;
    }

    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    const fs::path trash = root / std::wstring(kInternalRoot) / std::wstring(kTrashName);
    std::vector<CloudOSDriveTrashEntry> result;
    std::error_code ec;
    for (fs::directory_iterator it(trash, ec), end; !ec && it != end; it.increment(ec))
    {
        if (_wcsicmp(it->path().extension().c_str(), L".json") != 0)
        {
            continue;
        }
        const std::wstring id = it->path().stem().wstring();
        if (!IsHexId(id))
        {
            continue;
        }
        CloudOSDriveTrashEntry parsed{};
        if (LoadTrashMetadata(root, id, &parsed, nullptr, nullptr, nullptr))
        {
            result.push_back(std::move(parsed));
        }
    }
    if (ec)
    {
        SetError(error, L"Falha ao listar a lixeira do CloudOS Drive.");
        return false;
    }

    std::sort(
        result.begin(),
        result.end(),
        [](const CloudOSDriveTrashEntry& left, const CloudOSDriveTrashEntry& right)
        {
            return left.deleted_at > right.deleted_at;
        });
    *entries = std::move(result);
    return true;
}

bool NativeCloudOSDrive::RestoreTrash(
    const std::wstring& id,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    CloudOSDriveTrashEntry entry{};
    fs::path stored;
    fs::path metadata;
    if (!LoadTrashMetadata(root, id, &entry, &stored, &metadata, error))
    {
        return false;
    }

    std::vector<std::wstring> destination_segments = entry.original_path;
    destination_segments.push_back(entry.original_name);
    fs::path destination;
    bool exists = false;
    if (!DestinationSafePath(
            root,
            destination_segments,
            &destination,
            &exists,
            nullptr,
            error))
    {
        return false;
    }
    if (exists)
    {
        SetError(error, L"O local original ja contem um item com esse nome.");
        return false;
    }

    if (!MoveFileExW(stored.c_str(), destination.c_str(), MOVEFILE_WRITE_THROUGH))
    {
        SetError(error, JoinError(L"Falha ao restaurar item", GetLastError()));
        return false;
    }

    if (!DeleteFileW(metadata.c_str()))
    {
        const DWORD code = GetLastError();
        (void)MoveFileExW(destination.c_str(), stored.c_str(), MOVEFILE_WRITE_THROUGH);
        SetError(error, JoinError(L"Falha ao concluir restauracao", code));
        return false;
    }
    return true;
}

bool NativeCloudOSDrive::DeleteTrash(
    const std::wstring& id,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    fs::path root;
    if (!EnsureReadyUnlocked(&root, error))
    {
        return false;
    }

    CloudOSDriveTrashEntry entry{};
    fs::path stored;
    fs::path metadata;
    if (!LoadTrashMetadata(root, id, &entry, &stored, &metadata, error))
    {
        return false;
    }

    if (!RemoveTreeSafe(stored, error))
    {
        return false;
    }
    if (!DeleteFileW(metadata.c_str()))
    {
        SetError(error, JoinError(L"Falha ao excluir metadados da lixeira", GetLastError()));
        return false;
    }
    return true;
}

bool NativeCloudOSDrive::EmptyTrash(
    std::size_t* deleted_count,
    std::wstring* error)
{
    std::lock_guard<std::recursive_mutex> guard(g_drive_mutex);
    std::vector<CloudOSDriveTrashEntry> entries;
    if (!ListTrash(&entries, error))
    {
        return false;
    }

    std::size_t deleted = 0u;
    for (const CloudOSDriveTrashEntry& entry : entries)
    {
        if (!DeleteTrash(entry.id, error))
        {
            if (deleted_count != nullptr)
            {
                *deleted_count = deleted;
            }
            return false;
        }
        ++deleted;
    }
    if (deleted_count != nullptr)
    {
        *deleted_count = deleted;
    }
    return true;
}

} // namespace CloudOS
