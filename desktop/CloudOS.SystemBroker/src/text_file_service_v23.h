#pragma once

#include "event_bus_v21.h"
#include "protocol_v21.h"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace CloudOS
{

class TextFileServiceV23 final
{
public:
    static constexpr int64_t kMaxTextFileBytes = 16ll * 1024ll * 1024ll;
    static constexpr int64_t kMaxChunkBytes = 64ll * 1024ll;

    static bool TryHandle(const BrokerRequest& req, BrokerResponse& res)
    {
        if (req.method == "files.text.readChunk")
        {
            res.payload = ReadChunk(req.payload);
            return true;
        }
        if (req.method == "files.text.writeChunk")
        {
            res.payload = WriteChunk(req.payload);
            return true;
        }
        if (req.method == "files.text.abortWrite")
        {
            res.payload = AbortWrite(req.payload);
            return true;
        }
        return false;
    }

private:
    static std::wstring Utf8ToUtf16(const std::string& value)
    {
        if (value.empty()) return {};
        const int count = MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0);
        if (count <= 0) return {};
        std::wstring result(static_cast<size_t>(count), L'\0');
        if (MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                value.data(),
                static_cast<int>(value.size()),
                result.data(),
                count) != count)
        {
            return {};
        }
        return result;
    }

    static std::string Utf16ToUtf8(const std::wstring& value)
    {
        if (value.empty()) return {};
        const int count = WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0,
            nullptr,
            nullptr);
        if (count <= 0) return {};
        std::string result(static_cast<size_t>(count), '\0');
        if (WideCharToMultiByte(
                CP_UTF8,
                WC_ERR_INVALID_CHARS,
                value.data(),
                static_cast<int>(value.size()),
                result.data(),
                count,
                nullptr,
                nullptr) != count)
        {
            return {};
        }
        return result;
    }

    static std::wstring Canonicalize(const std::string& raw)
    {
        std::wstring input = Utf8ToUtf16(raw);
        if (input.empty()) return {};
        std::replace(input.begin(), input.end(), L'/', L'\\');
        std::vector<wchar_t> buffer(32768);
        const DWORD length = GetFullPathNameW(
            input.c_str(),
            static_cast<DWORD>(buffer.size()),
            buffer.data(),
            nullptr);
        if (length == 0 || length >= buffer.size()) return {};
        return std::wstring(buffer.data(), length);
    }

    static bool IsValidUtf8(const std::string& value)
    {
        if (value.empty()) return true;
        return MultiByteToWideChar(
                   CP_UTF8,
                   MB_ERR_INVALID_CHARS,
                   value.data(),
                   static_cast<int>(value.size()),
                   nullptr,
                   0) > 0;
    }

    static bool IsValidTransactionId(const std::string& id)
    {
        if (id.empty() || id.size() > 64) return false;
        return std::all_of(id.begin(), id.end(), [](unsigned char ch) {
            return std::isalnum(ch) != 0 || ch == '-' || ch == '_';
        });
    }

    static JsonObject Error(const std::string& code, const std::string& message)
    {
        JsonObject result;
        result["ok"] = JsonValue(false);
        result["error"] = JsonValue(code);
        result["message"] = JsonValue(message);
        return result;
    }

    static bool ReadFileSize(HANDLE file, int64_t* out_size)
    {
        if (!out_size) return false;
        LARGE_INTEGER size{};
        if (!GetFileSizeEx(file, &size) || size.QuadPart < 0) return false;
        *out_size = size.QuadPart;
        return true;
    }

    static JsonObject ReadChunk(const JsonObject& payload)
    {
        const auto path_it = payload.find("path");
        if (path_it == payload.end() || !path_it->second.IsString())
        {
            return Error("invalid_argument", "Missing text file path");
        }

        int64_t offset = 0;
        const auto offset_it = payload.find("offsetBytes");
        if (offset_it != payload.end() && offset_it->second.IsInt())
        {
            offset = offset_it->second.AsInt();
        }
        int64_t requested = kMaxChunkBytes;
        const auto max_it = payload.find("maxBytes");
        if (max_it != payload.end() && max_it->second.IsInt())
        {
            requested = max_it->second.AsInt();
        }
        if (offset < 0 || requested <= 0 || requested > kMaxChunkBytes)
        {
            return Error("out_of_range", "Text read offset/chunk is outside the allowed range");
        }

        const std::wstring path = Canonicalize(path_it->second.AsString());
        if (path.empty()) return Error("invalid_path", "Text file path is invalid");

        const DWORD attributes = GetFileAttributesW(path.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES)
        {
            return Error("not_found", "Text file was not found");
        }
        if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        {
            return Error("is_directory", "Text read target is a directory");
        }

        HANDLE file = CreateFileW(
            path.c_str(),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return Error("open_failed", "Unable to open text file for reading");
        }

        int64_t total_bytes = 0;
        if (!ReadFileSize(file, &total_bytes))
        {
            CloseHandle(file);
            return Error("size_failed", "Unable to determine text file size");
        }
        if (total_bytes > kMaxTextFileBytes)
        {
            CloseHandle(file);
            return Error("file_too_large", "Text file exceeds the 16 MB editor limit");
        }
        if (offset > total_bytes)
        {
            CloseHandle(file);
            return Error("offset_out_of_range", "Text read offset exceeds file size");
        }

        int64_t effective_offset = offset;
        if (offset == 0 && total_bytes >= 2)
        {
            unsigned char bom[3]{};
            DWORD bom_read = 0;
            LARGE_INTEGER zero{};
            SetFilePointerEx(file, zero, nullptr, FILE_BEGIN);
            ReadFile(file, bom, static_cast<DWORD>(std::min<int64_t>(3, total_bytes)), &bom_read, nullptr);
            if (bom_read >= 2 &&
                ((bom[0] == 0xFF && bom[1] == 0xFE) ||
                 (bom[0] == 0xFE && bom[1] == 0xFF)))
            {
                CloseHandle(file);
                return Error("unsupported_encoding", "UTF-16 text is not supported by the internal editor");
            }
            if (bom_read >= 3 && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF)
            {
                effective_offset = 3;
            }
        }

        LARGE_INTEGER seek{};
        seek.QuadPart = effective_offset;
        if (!SetFilePointerEx(file, seek, nullptr, FILE_BEGIN))
        {
            CloseHandle(file);
            return Error("seek_failed", "Unable to seek text file");
        }

        const int64_t remaining = std::max<int64_t>(0, total_bytes - effective_offset);
        const DWORD to_read = static_cast<DWORD>(std::min<int64_t>(requested, remaining));
        std::string chunk(static_cast<size_t>(to_read), '\0');
        DWORD bytes_read = 0;
        if (to_read > 0 && !ReadFile(file, chunk.data(), to_read, &bytes_read, nullptr))
        {
            CloseHandle(file);
            return Error("read_failed", "Unable to read text file chunk");
        }
        CloseHandle(file);
        chunk.resize(bytes_read);

        size_t trim = 0;
        while (!IsValidUtf8(chunk) && trim < 3 && !chunk.empty())
        {
            chunk.pop_back();
            ++trim;
        }
        if (!IsValidUtf8(chunk))
        {
            return Error("invalid_utf8", "Text file is not valid UTF-8");
        }

        const int64_t next_offset = effective_offset + static_cast<int64_t>(chunk.size());
        JsonObject result;
        result["ok"] = JsonValue(true);
        result["path"] = JsonValue(Utf16ToUtf8(path));
        result["content"] = JsonValue(std::move(chunk));
        result["nextOffsetBytes"] = JsonValue(next_offset);
        result["totalBytes"] = JsonValue(total_bytes);
        result["eof"] = JsonValue(next_offset >= total_bytes);
        result["encoding"] = JsonValue("utf-8");
        return result;
    }

    static JsonObject WriteChunk(const JsonObject& payload)
    {
        const auto path_it = payload.find("path");
        const auto tx_it = payload.find("transactionId");
        const auto content_it = payload.find("content");
        if (path_it == payload.end() || !path_it->second.IsString() ||
            tx_it == payload.end() || !tx_it->second.IsString() ||
            content_it == payload.end() || !content_it->second.IsString())
        {
            return Error("invalid_argument", "Text write requires path, transactionId, and content");
        }

        const std::string transaction_id = tx_it->second.AsString();
        if (!IsValidTransactionId(transaction_id))
        {
            return Error("invalid_transaction", "Text write transaction ID is invalid");
        }

        int64_t offset = 0;
        const auto offset_it = payload.find("offsetBytes");
        if (offset_it != payload.end() && offset_it->second.IsInt())
        {
            offset = offset_it->second.AsInt();
        }
        const bool final_chunk =
            payload.find("finalChunk") != payload.end() && payload.at("finalChunk").AsBool(false);
        const bool create_parents =
            payload.find("createParents") != payload.end() && payload.at("createParents").AsBool(false);
        const bool overwrite =
            payload.find("overwrite") == payload.end() || payload.at("overwrite").AsBool(true);

        const std::string content = content_it->second.AsString();
        if (offset < 0 || static_cast<int64_t>(content.size()) > kMaxChunkBytes ||
            offset > kMaxTextFileBytes ||
            static_cast<int64_t>(content.size()) > kMaxTextFileBytes - offset)
        {
            return Error("out_of_range", "Text write exceeds chunk or file size limits");
        }
        if (!IsValidUtf8(content))
        {
            return Error("invalid_utf8", "Text write content is not valid UTF-8");
        }

        const std::wstring target = Canonicalize(path_it->second.AsString());
        if (target.empty()) return Error("invalid_path", "Text write path is invalid");

        const std::filesystem::path target_path(target);
        const std::filesystem::path parent = target_path.parent_path();
        if (parent.empty()) return Error("invalid_path", "Text write target has no parent directory");

        std::error_code ec;
        if (!std::filesystem::exists(parent, ec))
        {
            if (!create_parents)
            {
                return Error("parent_not_found", "Text write parent directory does not exist");
            }
            ec.clear();
            if (!std::filesystem::create_directories(parent, ec) && ec)
            {
                return Error("create_parent_failed", "Unable to create text write parent directory");
            }
        }

        const std::wstring temp = target + L".cloudos-write-" + Utf8ToUtf16(transaction_id) + L".tmp";
        const DWORD disposition = offset == 0 ? CREATE_ALWAYS : OPEN_EXISTING;
        HANDLE file = CreateFileW(
            temp.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            nullptr,
            disposition,
            FILE_ATTRIBUTE_TEMPORARY,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
        {
            return Error("open_temp_failed", "Unable to open temporary text write file");
        }

        int64_t current_size = 0;
        if (!ReadFileSize(file, &current_size) || current_size != offset)
        {
            CloseHandle(file);
            return Error("write_offset_mismatch", "Text write offset does not match temporary file size");
        }

        LARGE_INTEGER seek{};
        seek.QuadPart = offset;
        if (!SetFilePointerEx(file, seek, nullptr, FILE_BEGIN))
        {
            CloseHandle(file);
            return Error("seek_failed", "Unable to seek temporary text file");
        }

        DWORD written = 0;
        size_t total_written = 0;
        while (total_written < content.size())
        {
            const DWORD remaining = static_cast<DWORD>(content.size() - total_written);
            if (!WriteFile(file, content.data() + total_written, remaining, &written, nullptr) || written == 0)
            {
                CloseHandle(file);
                return Error("write_failed", "Unable to write text file chunk");
            }
            total_written += written;
        }

        const int64_t next_offset = offset + static_cast<int64_t>(content.size());
        if (!final_chunk)
        {
            CloseHandle(file);
            JsonObject result;
            result["ok"] = JsonValue(true);
            result["committed"] = JsonValue(false);
            result["nextOffsetBytes"] = JsonValue(next_offset);
            return result;
        }

        if (!FlushFileBuffers(file))
        {
            CloseHandle(file);
            DeleteFileW(temp.c_str());
            return Error("flush_failed", "Unable to flush text file before commit");
        }
        CloseHandle(file);

        const DWORD target_attributes = GetFileAttributesW(target.c_str());
        if (target_attributes != INVALID_FILE_ATTRIBUTES)
        {
            if ((target_attributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
            {
                DeleteFileW(temp.c_str());
                return Error("is_directory", "Text write target is a directory");
            }
            if (!overwrite)
            {
                DeleteFileW(temp.c_str());
                return Error("already_exists", "Text write target already exists");
            }
        }

        DWORD move_flags = MOVEFILE_WRITE_THROUGH;
        if (overwrite) move_flags |= MOVEFILE_REPLACE_EXISTING;
        if (!MoveFileExW(temp.c_str(), target.c_str(), move_flags))
        {
            DeleteFileW(temp.c_str());
            return Error("commit_failed", "Unable to atomically commit text file");
        }

        JsonObject event_payload;
        event_payload["action"] = JsonValue("written");
        event_payload["path"] = JsonValue(Utf16ToUtf8(target));
        EventBusV21::Instance().Publish("files.changed", event_payload);

        JsonObject result;
        result["ok"] = JsonValue(true);
        result["committed"] = JsonValue(true);
        result["path"] = JsonValue(Utf16ToUtf8(target));
        result["bytesWritten"] = JsonValue(next_offset);
        result["encoding"] = JsonValue("utf-8");
        return result;
    }

    static JsonObject AbortWrite(const JsonObject& payload)
    {
        const auto path_it = payload.find("path");
        const auto tx_it = payload.find("transactionId");
        if (path_it == payload.end() || !path_it->second.IsString() ||
            tx_it == payload.end() || !tx_it->second.IsString())
        {
            return Error("invalid_argument", "Text abort requires path and transactionId");
        }
        const std::string transaction_id = tx_it->second.AsString();
        if (!IsValidTransactionId(transaction_id))
        {
            return Error("invalid_transaction", "Text write transaction ID is invalid");
        }
        const std::wstring target = Canonicalize(path_it->second.AsString());
        if (target.empty()) return Error("invalid_path", "Text write path is invalid");
        const std::wstring temp = target + L".cloudos-write-" + Utf8ToUtf16(transaction_id) + L".tmp";
        const BOOL deleted = DeleteFileW(temp.c_str());
        const DWORD error = deleted ? ERROR_SUCCESS : GetLastError();

        JsonObject result;
        result["ok"] = JsonValue(true);
        result["deleted"] = JsonValue(deleted == TRUE);
        result["notFound"] = JsonValue(!deleted && error == ERROR_FILE_NOT_FOUND);
        return result;
    }
};

} // namespace CloudOS
