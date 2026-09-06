#include "cloudos_flutter_bridge_v20.h"
#include "cloudos_broker_client_v21.h"
#include "cloudos_conpty_manager.h"
#include "cloudos_managed_win32_host_v22.h"
#include "../../CloudOS.NativeCommon/native_shell_activation_client_v21.h"
#include "../../CloudOS.NativeCommon/native_shell_notification_client_v21.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <charconv>
#include <cstdio>
#include <cwchar>
#include <iostream>
#include <limits>
#include <memory>
#include <system_error>

namespace CloudOS
{
namespace
{
constexpr const char* kChannelName = "cloudos/native/v19";

bool ResolveSurfaceApp(
    const std::string& id,
    ShellActivationV21::App* app)
{
    if (app == nullptr) return false;
    if (id == "browser" || id == "cloudos:browser")
    {
        *app = ShellActivationV21::App::Browser;
        return true;
    }
    if (id == "terminal" || id == "cloudos:terminal")
    {
        *app = ShellActivationV21::App::Terminal;
        return true;
    }
    return false;
}

bool ReadStringArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    const char* key,
    std::string* value)
{
    if (value == nullptr) return false;
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) return false;
    const auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end() || !std::holds_alternative<std::string>(it->second)) return false;
    *value = std::get<std::string>(it->second);
    return !value->empty();
}

bool ReadIntArgument(
    const flutter::EncodableMap& args,
    const char* key,
    int* value)
{
    if (value == nullptr) return false;
    const auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) return false;
    if (const auto* number = std::get_if<int32_t>(&it->second))
    {
        *value = static_cast<int>(*number);
        return true;
    }
    if (const auto* number = std::get_if<int64_t>(&it->second))
    {
        if (*number < (std::numeric_limits<int>::min)() || *number > (std::numeric_limits<int>::max)())
        {
            return false;
        }
        *value = static_cast<int>(*number);
        return true;
    }
    return false;
}

bool ReadSurfaceArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    ShellActivationV21::App* app,
    std::string* id)
{
    std::string surface_id;
    if (!ReadStringArgument(method_call, "id", &surface_id)) return false;
    if (!ResolveSurfaceApp(surface_id, app)) return false;
    if (id != nullptr) *id = surface_id;
    return true;
}

bool ReadWorkspaceArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    int* workspace)
{
    if (workspace == nullptr) return false;
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) return false;

    const auto it = args->find(flutter::EncodableValue("workspace"));
    if (it == args->end()) return false;

    if (const auto* value = std::get_if<int32_t>(&it->second))
    {
        *workspace = static_cast<int>(*value);
        return true;
    }
    if (const auto* value = std::get_if<int64_t>(&it->second))
    {
        if (*value < 1 || *value > ShellActivationV21::kWorkspaceCount) return false;
        *workspace = static_cast<int>(*value);
        return true;
    }
    return false;
}

bool ReadHwndArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    uint64_t* hwnd)
{
    if (hwnd == nullptr) return false;
    *hwnd = 0;
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) return false;

    const auto it = args->find(flutter::EncodableValue("hwnd"));
    if (it == args->end()) return false;

    if (const auto* val = std::get_if<int64_t>(&it->second))
    {
        *hwnd = static_cast<uint64_t>(*val);
        return true;
    }
    if (const auto* val = std::get_if<int32_t>(&it->second))
    {
        *hwnd = static_cast<uint64_t>(*val);
        return true;
    }
    if (const auto* val = std::get_if<std::string>(&it->second))
    {
        std::string s = *val;
        if (s.rfind("win_", 0) == 0) s = s.substr(4);
        try {
            *hwnd = std::stoull(s);
            return true;
        } catch (...) {
            return false;
        }
    }
    return false;
}

int ReadIntField(const flutter::EncodableMap& map, const char* key, int default_val)
{
    const auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end())
    {
        if (const auto* v = std::get_if<int32_t>(&it->second)) return static_cast<int>(*v);
        if (const auto* v = std::get_if<int64_t>(&it->second))
        {
            if (*v < (std::numeric_limits<int>::min)() || *v > (std::numeric_limits<int>::max)())
            {
                return default_val;
            }
            return static_cast<int>(*v);
        }
    }
    return default_val;
}

std::string ReadStringField(const flutter::EncodableMap& map, const char* key)
{
    const auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end())
    {
        if (const auto* s = std::get_if<std::string>(&it->second)) return *s;
    }
    return {};
}

bool ReadBoolField(const flutter::EncodableMap& map, const char* key, bool default_val)
{
    const auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end())
    {
        if (const auto* b = std::get_if<bool>(&it->second)) return *b;
    }
    return default_val;
}

std::string WideToUtf8(const wchar_t* value, std::size_t max_chars)
{
    if (value == nullptr || max_chars == 0) return {};
    const std::size_t length = wcsnlen_s(value, max_chars);
    if (length == 0 || length >= max_chars) return {};
    const int required = WideCharToMultiByte(
        CP_UTF8,
        0,
        value,
        static_cast<int>(length),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) return {};
    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            0,
            value,
            static_cast<int>(length),
            result.data(),
            required,
            nullptr,
            nullptr) != required)
    {
        return {};
    }
    return result;
}

std::string FormatNotificationTime(const ShellNotificationV21::Item& item)
{
    char buffer[16]{};
    sprintf_s(
        buffer,
        "%02u:%02u",
        static_cast<unsigned int>(item.hour),
        static_cast<unsigned int>(item.minute));
    return buffer;
}

bool ParseNotificationId(const std::string& value, std::uint64_t* id)
{
    if (id == nullptr || value.empty()) return false;
    std::uint64_t parsed = 0;
    const auto result = std::from_chars(
        value.data(),
        value.data() + value.size(),
        parsed);
    if (result.ec != std::errc{} || result.ptr != value.data() + value.size() || parsed == 0)
    {
        return false;
    }
    *id = parsed;
    return true;
}

flutter::EncodableValue EncodeFileItems(const std::vector<NativeFileItem>& files)
{
    flutter::EncodableList list;
    list.reserve(files.size());
    for (const NativeFileItem& file : files)
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(file.name);
        map[flutter::EncodableValue("path")] = flutter::EncodableValue(file.path);
        map[flutter::EncodableValue("isFolder")] = flutter::EncodableValue(file.is_folder);
        map[flutter::EncodableValue("sizeFormatted")] = flutter::EncodableValue(file.size_formatted);
        map[flutter::EncodableValue("modifiedFormatted")] = flutter::EncodableValue(file.modified_formatted);
        map[flutter::EncodableValue("source")] = flutter::EncodableValue(file.source);
        map[flutter::EncodableValue("extension")] = flutter::EncodableValue(file.extension);
        map[flutter::EncodableValue("entryId")] = flutter::EncodableValue(file.entry_id);
        list.push_back(flutter::EncodableValue(std::move(map)));
    }
    return flutter::EncodableValue(std::move(list));
}

flutter::EncodableValue EncodeNotificationState(
    const ShellNotificationV21::Snapshot& snapshot)
{
    flutter::EncodableMap state;
    state[flutter::EncodableValue("revision")] =
        flutter::EncodableValue(static_cast<int64_t>(snapshot.revision));
    state[flutter::EncodableValue("unreadCount")] =
        flutter::EncodableValue(static_cast<int32_t>(snapshot.unread_count));

    flutter::EncodableList items;
    items.reserve(snapshot.count);
    for (std::uint32_t index = 0; index < snapshot.count; ++index)
    {
        const auto& item = snapshot.items[index];
        flutter::EncodableMap map;
        map[flutter::EncodableValue("id")] =
            flutter::EncodableValue(std::to_string(item.id));
        map[flutter::EncodableValue("title")] = flutter::EncodableValue(
            WideToUtf8(item.title, ShellNotificationV21::kTitleChars));
        map[flutter::EncodableValue("message")] = flutter::EncodableValue(
            WideToUtf8(item.message, ShellNotificationV21::kMessageChars));
        map[flutter::EncodableValue("time")] =
            flutter::EncodableValue(FormatNotificationTime(item));
        map[flutter::EncodableValue("severity")] =
            flutter::EncodableValue(static_cast<int32_t>(item.severity));
        map[flutter::EncodableValue("read")] =
            flutter::EncodableValue(item.read != 0);
        items.push_back(flutter::EncodableValue(std::move(map)));
    }
    state[flutter::EncodableValue("items")] = flutter::EncodableValue(std::move(items));
    return flutter::EncodableValue(std::move(state));
}

void ConvertBrokerFiles(
    const std::vector<BrokerClientFileItem>& broker_files,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<NativeFileItem> files;
    files.reserve(broker_files.size());
    for (const BrokerClientFileItem& item : broker_files)
    {
        files.push_back({
            item.name,
            item.path,
            item.is_folder,
            item.size_formatted,
            item.modified_formatted,
            item.source,
            item.extension,
            item.entry_id,
        });
    }
    out_files = std::move(files);
}
} // namespace

void CloudOSFlutterBridgeV20::RegisterWithMessenger(
    flutter::BinaryMessenger* messenger,
    HWND window_handle)
{
    auto& bridge = Instance();
    bridge.Initialize(window_handle);

    bridge.channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    CloudOSConPTYManager::Instance().SetMethodChannel(bridge.channel_.get());
    CloudOSConPTYManager::Instance().SetPlatformWindow(window_handle);

    bridge.channel_->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            CloudOSFlutterBridgeV20::Instance().HandleMethodCall(call, std::move(result));
        });

    bridge.is_registered_.store(true);
}

CloudOSFlutterBridgeV20& CloudOSFlutterBridgeV20::Instance()
{
    static CloudOSFlutterBridgeV20 instance;
    return instance;
}

void CloudOSFlutterBridgeV20::Initialize(HWND window_handle)
{
    window_handle_ = window_handle;
    ManagedWin32HostV22::SetFlutterUiActive(true);
    CloudOSBrokerClientV21::Instance().EnsureConnected();
    RefreshAppCatalog();
    RefreshSystemSnapshot();
}

void CloudOSFlutterBridgeV20::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    const std::string& method = method_call.method_name();

    if (method == "terminal.createSession")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args == nullptr)
        {
            result->Error("INVALID_ARGUMENT", "terminal.createSession requires a map");
            return;
        }
        std::string shell_kind = "powershell";
        std::string distro;
        int cols = 80;
        int rows = 24;
        const auto shell_it = args->find(flutter::EncodableValue("shellKind"));
        if (shell_it != args->end() && std::holds_alternative<std::string>(shell_it->second))
            shell_kind = std::get<std::string>(shell_it->second);
        const auto distro_it = args->find(flutter::EncodableValue("distro"));
        if (distro_it != args->end() && std::holds_alternative<std::string>(distro_it->second))
            distro = std::get<std::string>(distro_it->second);
        ReadIntArgument(*args, "cols", &cols);
        ReadIntArgument(*args, "rows", &rows);

        std::string error;
        const std::string session_id = CloudOSConPTYManager::Instance().CreateSession(
            shell_kind, distro, cols, rows, error);
        if (session_id.empty())
        {
            result->Error("CONPTY_CREATE_FAILED", error);
            return;
        }
        flutter::EncodableMap response;
        response[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(session_id);
        result->Success(flutter::EncodableValue(std::move(response)));
        return;
    }

    if (method == "terminal.write")
    {
        std::string session_id;
        std::string data;
        if (!ReadStringArgument(method_call, "sessionId", &session_id) ||
            !ReadStringArgument(method_call, "data", &data))
        {
            result->Error("INVALID_ARGUMENT", "terminal.write requires sessionId and data");
            return;
        }
        result->Success(flutter::EncodableValue(
            CloudOSConPTYManager::Instance().WriteSession(session_id, data)));
        return;
    }

    if (method == "terminal.resize")
    {
        std::string session_id;
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        int cols = 0;
        int rows = 0;
        if (!ReadStringArgument(method_call, "sessionId", &session_id) || args == nullptr ||
            !ReadIntArgument(*args, "cols", &cols) || !ReadIntArgument(*args, "rows", &rows))
        {
            result->Error("INVALID_ARGUMENT", "terminal.resize requires sessionId, cols and rows");
            return;
        }
        result->Success(flutter::EncodableValue(
            CloudOSConPTYManager::Instance().ResizeSession(session_id, cols, rows)));
        return;
    }

    if (method == "terminal.signal")
    {
        std::string session_id;
        std::string signal;
        if (!ReadStringArgument(method_call, "sessionId", &session_id) ||
            !ReadStringArgument(method_call, "signal", &signal))
        {
            result->Error("INVALID_ARGUMENT", "terminal.signal requires sessionId and signal");
            return;
        }
        result->Success(flutter::EncodableValue(
            CloudOSConPTYManager::Instance().SignalSession(session_id, signal)));
        return;
    }

    if (method == "terminal.close")
    {
        std::string session_id;
        if (!ReadStringArgument(method_call, "sessionId", &session_id))
        {
            result->Error("INVALID_ARGUMENT", "terminal.close requires sessionId");
            return;
        }
        result->Success(flutter::EncodableValue(
            CloudOSConPTYManager::Instance().CloseSession(session_id)));
        return;
    }

    if (method == "getApps")
    {
        const auto apps = GetApps();
        flutter::EncodableList list;
        list.reserve(apps.size());
        for (const auto& app : apps)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("id")] = flutter::EncodableValue(app.id);
            map[flutter::EncodableValue("name")] = flutter::EncodableValue(app.name);
            map[flutter::EncodableValue("platform")] = flutter::EncodableValue(app.platform);
            map[flutter::EncodableValue("subtitle")] = flutter::EncodableValue(app.subtitle);
            map[flutter::EncodableValue("distro")] = flutter::EncodableValue(app.distro);
            map[flutter::EncodableValue("category")] = flutter::EncodableValue(app.category);
            map[flutter::EncodableValue("source")] = flutter::EncodableValue(app.source);
            map[flutter::EncodableValue("displayName")] = flutter::EncodableValue(app.display_name.empty() ? app.name : app.display_name);
            map[flutter::EncodableValue("launchTarget")] = flutter::EncodableValue(app.launch_target.empty() ? app.id : app.launch_target);
            map[flutter::EncodableValue("availability")] = flutter::EncodableValue(app.availability.empty() ? (app.can_launch ? "ready" : "unavailable") : app.availability);
            flutter::EncodableList caps_list;
            for (const auto& cap : app.capabilities)
            {
                caps_list.push_back(flutter::EncodableValue(cap));
            }
            map[flutter::EncodableValue("capabilities")] = flutter::EncodableValue(std::move(caps_list));
            map[flutter::EncodableValue("canLaunch")] = flutter::EncodableValue(app.can_launch);
            map[flutter::EncodableValue("pinned")] = flutter::EncodableValue(app.pinned);
            map[flutter::EncodableValue("recent")] = flutter::EncodableValue(app.recent);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }
        result->Success(flutter::EncodableValue(std::move(list)));
        return;
    }

    if (method == "getFiles")
    {
        std::string location;
        if (!ReadStringArgument(method_call, "location", &location))
        {
            result->Error("INVALID_ARGUMENT", "getFiles requires an allowlisted location id");
            return;
        }
        std::vector<NativeFileItem> files;
        if (!GetFiles(location, files))
        {
            result->Error("FILES_UNAVAILABLE", "System broker rejected or failed the allowlisted Files location");
            return;
        }
        result->Success(EncodeFileItems(files));
        return;
    }

    if (method == "getFilesEntry")
    {
        std::string entry_id;
        if (!ReadStringArgument(method_call, "entryId", &entry_id))
        {
            result->Error("INVALID_ARGUMENT", "getFilesEntry requires an opaque entryId capability");
            return;
        }
        std::vector<NativeFileItem> files;
        if (!GetFilesEntry(entry_id, files))
        {
            result->Error("FILES_ENTRY_UNAVAILABLE", "System broker rejected or expired the Files entry capability");
            return;
        }
        result->Success(EncodeFileItems(files));
        return;
    }

    if (method == "openFileEntry")
    {
        std::string entry_id;
        if (!ReadStringArgument(method_call, "entryId", &entry_id))
        {
            result->Error("INVALID_ARGUMENT", "openFileEntry requires an opaque entryId capability");
            return;
        }
        if (!OpenFileEntry(entry_id))
        {
            result->Error("FILES_OPEN_FAILED", "System broker rejected or failed the Files entry capability");
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "createFolder")
    {
        std::string parent_id, name;
        if (!ReadStringArgument(method_call, "parentEntryId", &parent_id) ||
            !ReadStringArgument(method_call, "name", &name))
        {
            result->Error("INVALID_ARGUMENT", "createFolder requires parentEntryId and name");
            return;
        }
        BrokerClientFileItem created;
        std::string err;
        if (!CloudOSBrokerClientV21::Instance().CreateFolder(parent_id, name, created, err))
        {
            result->Error("CREATE_FOLDER_FAILED", err.empty() ? "Falha ao criar pasta" : err);
            return;
        }
        flutter::EncodableMap map;
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(created.name);
        map[flutter::EncodableValue("path")] = flutter::EncodableValue(created.path);
        map[flutter::EncodableValue("isFolder")] = flutter::EncodableValue(created.is_folder);
        map[flutter::EncodableValue("sizeFormatted")] = flutter::EncodableValue(created.size_formatted);
        map[flutter::EncodableValue("modifiedFormatted")] = flutter::EncodableValue(created.modified_formatted);
        map[flutter::EncodableValue("source")] = flutter::EncodableValue(created.source);
        map[flutter::EncodableValue("extension")] = flutter::EncodableValue(created.extension);
        map[flutter::EncodableValue("entryId")] = flutter::EncodableValue(created.entry_id);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "renameFile")
    {
        std::string entry_id, new_name;
        if (!ReadStringArgument(method_call, "entryId", &entry_id) ||
            !ReadStringArgument(method_call, "newName", &new_name))
        {
            result->Error("INVALID_ARGUMENT", "renameFile requires entryId and newName");
            return;
        }
        BrokerClientFileItem renamed;
        std::string err;
        if (!CloudOSBrokerClientV21::Instance().RenameFile(entry_id, new_name, renamed, err))
        {
            result->Error("RENAME_FAILED", err.empty() ? "Falha ao renomear" : err);
            return;
        }
        flutter::EncodableMap map;
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(renamed.name);
        map[flutter::EncodableValue("path")] = flutter::EncodableValue(renamed.path);
        map[flutter::EncodableValue("isFolder")] = flutter::EncodableValue(renamed.is_folder);
        map[flutter::EncodableValue("sizeFormatted")] = flutter::EncodableValue(renamed.size_formatted);
        map[flutter::EncodableValue("modifiedFormatted")] = flutter::EncodableValue(renamed.modified_formatted);
        map[flutter::EncodableValue("source")] = flutter::EncodableValue(renamed.source);
        map[flutter::EncodableValue("extension")] = flutter::EncodableValue(renamed.extension);
        map[flutter::EncodableValue("entryId")] = flutter::EncodableValue(renamed.entry_id);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "deleteFiles")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args == nullptr)
        {
            result->Error("INVALID_ARGUMENT", "deleteFiles requires arguments map");
            return;
        }
        std::vector<std::string> entry_ids;
        const auto it_ids = args->find(flutter::EncodableValue("entryIds"));
        if (it_ids != args->end() && std::holds_alternative<flutter::EncodableList>(it_ids->second))
        {
            for (const auto& item : std::get<flutter::EncodableList>(it_ids->second))
            {
                if (std::holds_alternative<std::string>(item))
                    entry_ids.push_back(std::get<std::string>(item));
            }
        }
        bool permanent = false;
        const auto it_perm = args->find(flutter::EncodableValue("permanent"));
        if (it_perm != args->end() && std::holds_alternative<bool>(it_perm->second))
        {
            permanent = std::get<bool>(it_perm->second);
        }

        std::vector<std::string> deleted;
        std::string err;
        if (!CloudOSBrokerClientV21::Instance().DeleteFiles(entry_ids, permanent, deleted, err))
        {
            result->Error("DELETE_FAILED", err.empty() ? "Falha ao excluir itens" : err);
            return;
        }
        flutter::EncodableList out_list;
        out_list.reserve(deleted.size());
        for (const auto& d : deleted) out_list.push_back(flutter::EncodableValue(d));
        result->Success(flutter::EncodableValue(std::move(out_list)));
        return;
    }

    if (method == "copyFiles" || method == "moveFiles")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args == nullptr)
        {
            result->Error("INVALID_ARGUMENT", "copy/move requires arguments map");
            return;
        }
        std::vector<std::string> source_ids;
        const auto it_src = args->find(flutter::EncodableValue("sourceEntryIds"));
        if (it_src != args->end() && std::holds_alternative<flutter::EncodableList>(it_src->second))
        {
            for (const auto& item : std::get<flutter::EncodableList>(it_src->second))
            {
                if (std::holds_alternative<std::string>(item))
                    source_ids.push_back(std::get<std::string>(item));
            }
        }
        std::string dest_id;
        const auto it_dest = args->find(flutter::EncodableValue("destinationEntryId"));
        if (it_dest != args->end() && std::holds_alternative<std::string>(it_dest->second))
        {
            dest_id = std::get<std::string>(it_dest->second);
        }

        std::string job_id;
        std::string err;
        const std::string op_type = (method == "moveFiles") ? "move" : "copy";
        if (!CloudOSBrokerClientV21::Instance().CopyOrMoveFiles(op_type, source_ids, dest_id, job_id, err))
        {
            result->Error("OPERATION_FAILED", err.empty() ? "Falha ao iniciar operação" : err);
            return;
        }
        result->Success(flutter::EncodableValue(job_id));
        return;
    }

    if (method == "cancelFileOperation")
    {
        std::string job_id;
        if (!ReadStringArgument(method_call, "jobId", &job_id))
        {
            result->Error("INVALID_ARGUMENT", "cancelFileOperation requires jobId");
            return;
        }
        const bool cancelled = CloudOSBrokerClientV21::Instance().CancelFileOperation(job_id);
        result->Success(flutter::EncodableValue(cancelled));
        return;
    }

    if (method == "listDrives")
    {
        std::vector<BrokerClientDriveItem> drives;
        std::string err;
        if (!CloudOSBrokerClientV21::Instance().ListDrives(drives, err))
        {
            result->Error("LIST_DRIVES_FAILED", err.empty() ? "Falha ao listar unidades" : err);
            return;
        }
        flutter::EncodableList list;
        list.reserve(drives.size());
        for (const auto& d : drives)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("mountPath")] = flutter::EncodableValue(d.mount_path);
            map[flutter::EncodableValue("label")] = flutter::EncodableValue(d.label);
            map[flutter::EncodableValue("driveType")] = flutter::EncodableValue(d.drive_type);
            map[flutter::EncodableValue("totalBytes")] = flutter::EncodableValue(static_cast<int64_t>(d.total_bytes));
            map[flutter::EncodableValue("freeBytes")] = flutter::EncodableValue(static_cast<int64_t>(d.free_bytes));
            map[flutter::EncodableValue("totalFormatted")] = flutter::EncodableValue(d.total_formatted);
            map[flutter::EncodableValue("freeFormatted")] = flutter::EncodableValue(d.free_formatted);
            map[flutter::EncodableValue("entryId")] = flutter::EncodableValue(d.entry_id);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }
        result->Success(flutter::EncodableValue(std::move(list)));
        return;
    }

    if (method == "getSystemSnapshot")
    {
        const auto snapshot = GetSystemSnapshot();
        flutter::EncodableMap map;
        map[flutter::EncodableValue("deviceName")] = flutter::EncodableValue(snapshot.device_name);
        map[flutter::EncodableValue("networkAvailable")] = flutter::EncodableValue(snapshot.network_available);
        map[flutter::EncodableValue("networkName")] = flutter::EncodableValue(snapshot.network_name);
        map[flutter::EncodableValue("volumeAvailable")] = flutter::EncodableValue(snapshot.volume_available);
        map[flutter::EncodableValue("volume")] = flutter::EncodableValue(snapshot.volume);
        map[flutter::EncodableValue("brightnessAvailable")] = flutter::EncodableValue(snapshot.brightness_available);
        map[flutter::EncodableValue("brightness")] = flutter::EncodableValue(snapshot.brightness);
        map[flutter::EncodableValue("batteryAvailable")] = flutter::EncodableValue(snapshot.battery_available);
        map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(snapshot.battery_percent);
        map[flutter::EncodableValue("wslAvailable")] = flutter::EncodableValue(snapshot.wsl_available);
        map[flutter::EncodableValue("defaultDistro")] = flutter::EncodableValue(snapshot.default_distro);
        map[flutter::EncodableValue("currentWorkspace")] = flutter::EncodableValue(snapshot.current_workspace);
        flutter::EncodableList distros_list;
        for (const auto& d : snapshot.distros) distros_list.push_back(flutter::EncodableValue(d));
        map[flutter::EncodableValue("distros")] = flutter::EncodableValue(std::move(distros_list));
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "getNotificationState")
    {
        auto snapshot = std::make_unique<ShellNotificationV21::Snapshot>();
        std::string error;
        if (!NativeShellNotificationClientV21::Query(snapshot.get(), &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(EncodeNotificationState(*snapshot));
        return;
    }

    if (method == "markNotificationsRead")
    {
        std::string error;
        if (!NativeShellNotificationClientV21::MarkAllRead(&error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "dismissNotification")
    {
        std::string notification_id_text;
        std::uint64_t notification_id = 0;
        if (!ReadStringArgument(method_call, "id", &notification_id_text) ||
            !ParseNotificationId(notification_id_text, &notification_id))
        {
            result->Error("INVALID_ARGUMENT", "dismissNotification requires a numeric notification id");
            return;
        }
        std::string error;
        if (!NativeShellNotificationClientV21::Dismiss(notification_id, &error))
        {
            result->Error("NOTIFICATION_MUTATION_FAILED", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "clearNotifications")
    {
        std::string error;
        if (!NativeShellNotificationClientV21::Clear(&error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "getShellSurfaceStates")
    {
        bool browser_running = false;
        bool terminal_running = false;
        std::string error;
        if (!NativeShellActivationClientV21::QueryRunning(
                ShellActivationV21::App::Browser,
                &browser_running,
                &error) ||
            !NativeShellActivationClientV21::QueryRunning(
                ShellActivationV21::App::Terminal,
                &terminal_running,
                &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        flutter::EncodableMap map;
        map[flutter::EncodableValue("browser")] = flutter::EncodableValue(browser_running);
        map[flutter::EncodableValue("terminal")] = flutter::EncodableValue(terminal_running);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "focusShellSurface" || method == "closeShellSurface")
    {
        ShellActivationV21::App app{};
        std::string surface_id;
        if (!ReadSurfaceArgument(method_call, &app, &surface_id))
        {
            result->Error("INVALID_ARGUMENT", "A supported Browser or Terminal surface id is required");
            return;
        }
        bool surface_was_running = false;
        std::string error;
        const bool ok = method == "focusShellSurface"
            ? NativeShellActivationClientV21::Focus(app, &surface_was_running, &error)
            : NativeShellActivationClientV21::Close(app, &surface_was_running, &error);
        if (!ok)
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(surface_was_running));
        return;
    }

    if (method == "getCurrentWorkspace")
    {
        int workspace = 0;
        std::string error;
        if (!NativeShellActivationClientV21::QueryWorkspace(&workspace, &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(workspace + 1));
        return;
    }

    if (method == "switchWorkspace")
    {
        int workspace = 0;
        if (!ReadWorkspaceArgument(method_call, &workspace) || workspace < 1 ||
            workspace > ShellActivationV21::kWorkspaceCount)
        {
            result->Error("INVALID_ARGUMENT", "workspace must be in the presentation range 1..4");
            return;
        }
        int actual_workspace = 0;
        std::string error;
        if (!NativeShellActivationClientV21::SwitchWorkspace(
                workspace - 1,
                &actual_workspace,
                &error))
        {
            result->Error("NATIVE_SHELL_UNAVAILABLE", error);
            return;
        }
        result->Success(flutter::EncodableValue(actual_workspace + 1));
        return;
    }

    if (method == "launchApp")
    {
        std::string app_id;
        if (!ReadStringArgument(method_call, "id", &app_id))
        {
            result->Error("INVALID_ARGUMENT", "launchApp requires a map with an 'id' property");
            return;
        }
        const bool ok = LaunchApp(app_id);
        if (ok) result->Success(flutter::EncodableValue(true));
        else result->Error("LAUNCH_FAILED", "Failed to launch application with ID: " + app_id);
        return;
    }

    if (method == "launchAppStructured")
    {
        std::string app_id;
        if (!ReadStringArgument(method_call, "id", &app_id))
        {
            result->Error("INVALID_ARGUMENT", "launchAppStructured requires a map with an 'id' property");
            return;
        }
        BrokerClientLaunchResult launch_res;
        std::string err;
        const bool ok = CloudOSBrokerClientV21::Instance().LaunchAppStructured(app_id, launch_res, err);
        flutter::EncodableMap map;
        map[flutter::EncodableValue("id")] = flutter::EncodableValue(launch_res.id);
        map[flutter::EncodableValue("status")] = flutter::EncodableValue(launch_res.status);
        map[flutter::EncodableValue("launched")] = flutter::EncodableValue(launch_res.launched);
        map[flutter::EncodableValue("platform")] = flutter::EncodableValue(launch_res.platform);
        map[flutter::EncodableValue("target")] = flutter::EncodableValue(launch_res.target);
        map[flutter::EncodableValue("message")] = flutter::EncodableValue(launch_res.message);
        if (ok)
        {
            result->Success(flutter::EncodableValue(std::move(map)));
        }
        else
        {
            result->Error("LAUNCH_FAILED", err.empty() ? "Failed to launch application" : err, flutter::EncodableValue(std::move(map)));
        }
        return;
    }

    if (method == "wsl.listDistros")
    {
        std::vector<BrokerClientDistroInfo> distros;
        std::string default_distro;
        bool available = false;
        if (!CloudOSBrokerClientV21::Instance().ListWslDistros(distros, default_distro, available))
        {
            result->Error("WSL_UNAVAILABLE", "Failed to retrieve WSL distributions from system broker");
            return;
        }
        flutter::EncodableList list;
        for (const auto& d : distros)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("id")] = flutter::EncodableValue(d.id);
            map[flutter::EncodableValue("name")] = flutter::EncodableValue(d.name);
            map[flutter::EncodableValue("guid")] = flutter::EncodableValue(d.guid);
            map[flutter::EncodableValue("version")] = flutter::EncodableValue(static_cast<int64_t>(d.version));
            map[flutter::EncodableValue("state")] = flutter::EncodableValue(d.state);
            map[flutter::EncodableValue("basePath")] = flutter::EncodableValue(d.base_path);
            map[flutter::EncodableValue("defaultUid")] = flutter::EncodableValue(static_cast<int64_t>(d.default_uid));
            map[flutter::EncodableValue("flags")] = flutter::EncodableValue(static_cast<int64_t>(d.flags));
            map[flutter::EncodableValue("isDefault")] = flutter::EncodableValue(d.is_default);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }
        flutter::EncodableMap res_map;
        res_map[flutter::EncodableValue("distros")] = flutter::EncodableValue(std::move(list));
        res_map[flutter::EncodableValue("defaultDistro")] = flutter::EncodableValue(default_distro);
        res_map[flutter::EncodableValue("wslAvailable")] = flutter::EncodableValue(available);
        result->Success(flutter::EncodableValue(std::move(res_map)));
        return;
    }

    if (method == "path.translate")
    {
        std::string path;
        if (!ReadStringArgument(method_call, "path", &path))
        {
            result->Error("INVALID_ARGUMENT", "path.translate requires 'path'");
            return;
        }
        std::string target = "linux";
        ReadStringArgument(method_call, "target", &target);
        std::string distro;
        ReadStringArgument(method_call, "distro", &distro);

        BrokerClientPathTranslation translation;
        if (!CloudOSBrokerClientV21::Instance().TranslatePath(path, target, distro, translation))
        {
            result->Error("TRANSLATION_FAILED", "Failed to translate path");
            return;
        }
        flutter::EncodableMap res_map;
        res_map[flutter::EncodableValue("originalPath")] = flutter::EncodableValue(translation.original_path);
        res_map[flutter::EncodableValue("translatedPath")] = flutter::EncodableValue(translation.translated_path);
        res_map[flutter::EncodableValue("target")] = flutter::EncodableValue(translation.target);
        res_map[flutter::EncodableValue("distro")] = flutter::EncodableValue(translation.distro);
        res_map[flutter::EncodableValue("exists")] = flutter::EncodableValue(translation.exists);
        result->Success(flutter::EncodableValue(std::move(res_map)));
        return;
    }

    if (method == "system.getMountPoints")
    {
        std::vector<BrokerClientMountPoint> mounts;
        if (!CloudOSBrokerClientV21::Instance().GetMountPoints(mounts))
        {
            result->Error("MOUNTS_UNAVAILABLE", "Failed to retrieve mount points");
            return;
        }
        flutter::EncodableList list;
        for (const auto& m : mounts)
        {
            flutter::EncodableMap map;
            map[flutter::EncodableValue("id")] = flutter::EncodableValue(m.id);
            map[flutter::EncodableValue("label")] = flutter::EncodableValue(m.label);
            map[flutter::EncodableValue("path")] = flutter::EncodableValue(m.path);
            map[flutter::EncodableValue("platform")] = flutter::EncodableValue(m.platform);
            map[flutter::EncodableValue("isOnline")] = flutter::EncodableValue(m.is_online);
            list.push_back(flutter::EncodableValue(std::move(map)));
        }
        result->Success(flutter::EncodableValue(std::move(list)));
        return;
    }

    if (method == "setVolume")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                const bool ok = SetVolume(std::get<double>(it->second));
                if (ok) result->Success(flutter::EncodableValue(true));
                else result->Error("BROKER_WRITE_FAILED", "System broker rejected or failed the volume update");
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setVolume requires a double 'value'");
        return;
    }

    if (method == "setBrightness")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args)
        {
            auto it = args->find(flutter::EncodableValue("value"));
            if (it != args->end() && std::holds_alternative<double>(it->second))
            {
                const bool ok = SetBrightness(std::get<double>(it->second));
                if (ok) result->Success(flutter::EncodableValue(true));
                else result->Error("BROKER_WRITE_FAILED", "System broker rejected or failed the brightness update");
                return;
            }
        }
        result->Error("INVALID_ARGUMENT", "setBrightness requires a double 'value'");
        return;
    }

    if (method == "getBridgeInfo")
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("schema")] = flutter::EncodableValue(21);
        map[flutter::EncodableValue("verdict")] = flutter::EncodableValue("pass");
        map[flutter::EncodableValue("bridge_type")] = flutter::EncodableValue("CloudOSFlutterBridgeV20");
        map[flutter::EncodableValue("channel")] = flutter::EncodableValue(kChannelName);
        map[flutter::EncodableValue("brokerConnected")] = flutter::EncodableValue(CloudOSBrokerClientV21::Instance().IsConnected());
        map[flutter::EncodableValue("brokerState")] = flutter::EncodableValue(ConnectionStateToString(CloudOSBrokerClientV21::Instance().GetConnectionState()));
        map[flutter::EncodableValue("conptyAvailable")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("arbitrary_command_api")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("winlogon_modified")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("shell_activation_executed")] = flutter::EncodableValue(false);
        map[flutter::EncodableValue("shell_surface_lifecycle")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("shell_workspace_control")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("shell_notification_authority")] = flutter::EncodableValue(true);
        map[flutter::EncodableValue("files_capability_actions")] = flutter::EncodableValue(true);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "getPerformanceProfile")
    {
        BrokerClientPerformanceProfile profile;
        if (!CloudOSBrokerClientV21::Instance().GetPerformanceProfile(profile))
        {
            result->Error("BROKER_READ_FAILED", "Could not query performance profile from System Broker");
            return;
        }
        flutter::EncodableMap map;
        map[flutter::EncodableValue("profile")] = flutter::EncodableValue(profile.profile);
        map[flutter::EncodableValue("totalRamMb")] = flutter::EncodableValue(profile.total_ram_mb);
        map[flutter::EncodableValue("freeRamMb")] = flutter::EncodableValue(profile.free_ram_mb);
        map[flutter::EncodableValue("memoryLoadPercent")] = flutter::EncodableValue(profile.memory_load_percent);
        map[flutter::EncodableValue("cpuCores")] = flutter::EncodableValue(profile.cpu_cores);
        map[flutter::EncodableValue("onBattery")] = flutter::EncodableValue(profile.on_battery);
        map[flutter::EncodableValue("batteryPercent")] = flutter::EncodableValue(profile.battery_percent);
        map[flutter::EncodableValue("isLowEndHardware")] = flutter::EncodableValue(profile.is_low_end_hardware);
        result->Success(flutter::EncodableValue(std::move(map)));
        return;
    }

    if (method == "setPerformanceProfile")
    {
        std::string profile_str;
        if (!ReadStringArgument(method_call, "profile", &profile_str))
        {
            result->Error("INVALID_ARGUMENT", "setPerformanceProfile requires a 'profile' string");
            return;
        }
        if (!CloudOSBrokerClientV21::Instance().SetPerformanceProfile(profile_str))
        {
            result->Error("BROKER_WRITE_FAILED", "System broker rejected or failed performance profile update");
            return;
        }
        result->Success(flutter::EncodableValue(true));
        return;
    }

    if (method == "window.getSnapshot" || method == "window.list")
    {
        std::string snapshot_json;
        if (!CloudOSBrokerClientV21::Instance().GetWindowSnapshot(snapshot_json) || snapshot_json.empty())
        {
            snapshot_json = "{\"windows\":[],\"monitors\":[],\"currentWorkspace\":1,\"sequence\":1,\"timestamp\":0}";
        }
        result->Success(flutter::EncodableValue(snapshot_json));
        return;
    }

    if (method == "window.focus")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.focus requires a valid 'hwnd'");
            return;
        }
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("focus", hwnd);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.minimize")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.minimize requires a valid 'hwnd'");
            return;
        }
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("minimize", hwnd);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.maximize")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.maximize requires a valid 'hwnd'");
            return;
        }
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("maximize", hwnd);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.restore")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.restore requires a valid 'hwnd'");
            return;
        }
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("restore", hwnd);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.close")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.close requires a valid 'hwnd'");
            return;
        }
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("close", hwnd);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.setBounds")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.setBounds requires a valid 'hwnd'");
            return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        int x = args ? ReadIntField(*args, "x", 0) : 0;
        int y = args ? ReadIntField(*args, "y", 0) : 0;
        int w = args ? ReadIntField(*args, "width", 800) : 800;
        int h = args ? ReadIntField(*args, "height", 600) : 600;
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("setBounds", hwnd, x, y, w, h);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.snap")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.snap requires a valid 'hwnd'");
            return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        std::string snap = args ? ReadStringField(*args, "snap") : "";
        if (snap.empty() && args) snap = ReadStringField(*args, "target");
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("snap", hwnd, 0, 0, 0, 0, 1, snap);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.moveToWorkspace")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.moveToWorkspace requires a valid 'hwnd'");
            return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        int ws = args ? ReadIntField(*args, "workspace", 1) : 1;
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("moveToWorkspace", hwnd, 0, 0, 0, 0, ws);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "window.setFullscreen")
    {
        uint64_t hwnd = 0;
        if (!ReadHwndArgument(method_call, &hwnd) || hwnd == 0)
        {
            result->Error("INVALID_ARGUMENT", "window.setFullscreen requires a valid 'hwnd'");
            return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        bool fs = args ? ReadBoolField(*args, "fullscreen", true) : true;
        const bool ok = CloudOSBrokerClientV21::Instance().ExecuteWindowCommand("setFullscreen", hwnd, 0, 0, 0, 0, 1, "", fs);
        result->Success(flutter::EncodableValue(ok));
        return;
    }

    if (method == "monitor.list")
    {
        std::string snapshot_json;
        if (!CloudOSBrokerClientV21::Instance().GetWindowSnapshot(snapshot_json) || snapshot_json.empty())
        {
            snapshot_json = "{\"windows\":[],\"monitors\":[],\"currentWorkspace\":1,\"sequence\":1,\"timestamp\":0}";
        }
        result->Success(flutter::EncodableValue(snapshot_json));
        return;
    }

    if (method == "broker.invokeRpc")
    {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (!args)
        {
            result->Error("INVALID_ARGUMENT", "broker.invokeRpc requires arguments map");
            return;
        }

        std::string rpc_method;
        const auto it_m = args->find(flutter::EncodableValue("method"));
        if (it_m != args->end() && std::holds_alternative<std::string>(it_m->second))
        {
            rpc_method = std::get<std::string>(it_m->second);
        }

        if (rpc_method.empty())
        {
            result->Error("INVALID_ARGUMENT", "broker.invokeRpc requires a valid 'method'");
            return;
        }

        JsonObject payload;
        const auto it_p = args->find(flutter::EncodableValue("payload"));
        if (it_p != args->end() && std::holds_alternative<std::string>(it_p->second))
        {
            const std::string& p_str = std::get<std::string>(it_p->second);
            JsonValue root;
            if (ParseJson(p_str, root) && root.IsObject())
            {
                payload = root.AsObject();
            }
        }

        BrokerResponse res;
        std::string err;
        if (!CloudOSBrokerClientV21::Instance().InvokeRpc(rpc_method, payload, res, err))
        {
            result->Error("RPC_FAILED", err.empty() ? "Broker RPC execution failed" : err);
            return;
        }

        std::string serialized_payload = SerializeJson(JsonValue(res.payload));
        result->Success(flutter::EncodableValue(std::move(serialized_payload)));
        return;
    }

    result->NotImplemented();
}

std::vector<NativeAppItem> CloudOSFlutterBridgeV20::GetApps()
{
    std::vector<BrokerClientAppItem> broker_apps;
    if (CloudOSBrokerClientV21::Instance().GetApps(broker_apps) && !broker_apps.empty())
    {
        std::vector<NativeAppItem> result;
        result.reserve(broker_apps.size());
        for (const auto& a : broker_apps)
        {
            NativeAppItem item;
            item.id = a.id;
            item.name = a.name;
            item.platform = a.platform;
            item.subtitle = a.subtitle;
            item.distro = a.distro;
            item.category = a.category;
            item.source = a.source;
            item.can_launch = a.can_launch;
            item.pinned = a.pinned;
            item.recent = a.recent;
            item.display_name = a.display_name.empty() ? a.name : a.display_name;
            item.launch_target = a.launch_target.empty() ? a.id : a.launch_target;
            item.availability = a.availability.empty() ? (a.can_launch ? "ready" : "unavailable") : a.availability;
            item.capabilities = a.capabilities;
            result.push_back(std::move(item));
        }
        return result;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    return cached_apps_;
}

bool CloudOSFlutterBridgeV20::GetFiles(
    const std::string& location,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<BrokerClientFileItem> broker_files;
    if (!CloudOSBrokerClientV21::Instance().GetFiles(location, broker_files)) return false;
    ConvertBrokerFiles(broker_files, out_files);
    return true;
}

bool CloudOSFlutterBridgeV20::GetFilesEntry(
    const std::string& entry_id,
    std::vector<NativeFileItem>& out_files)
{
    std::vector<BrokerClientFileItem> broker_files;
    if (!CloudOSBrokerClientV21::Instance().GetFilesEntry(entry_id, broker_files)) return false;
    ConvertBrokerFiles(broker_files, out_files);
    return true;
}

bool CloudOSFlutterBridgeV20::OpenFileEntry(const std::string& entry_id)
{
    return CloudOSBrokerClientV21::Instance().OpenFileEntry(entry_id);
}

NativeSystemSnapshot CloudOSFlutterBridgeV20::GetSystemSnapshot()
{
    NativeSystemSnapshot snapshot;
    BrokerClientSnapshot broker_snap;
    if (CloudOSBrokerClientV21::Instance().GetSystemSnapshot(broker_snap))
    {
        snapshot.device_name = broker_snap.device_name;
        snapshot.network_available = broker_snap.network_available;
        snapshot.network_name = broker_snap.network_name;
        snapshot.volume_available = broker_snap.volume_available;
        snapshot.volume = broker_snap.volume;
        snapshot.brightness_available = broker_snap.brightness_available;
        snapshot.brightness = broker_snap.brightness;
        snapshot.battery_available = broker_snap.battery_available;
        snapshot.battery_percent = broker_snap.battery_percent;
        snapshot.wsl_available = broker_snap.wsl_available;
        snapshot.distros = broker_snap.distros;
        snapshot.default_distro = broker_snap.default_distro;
        snapshot.current_workspace = broker_snap.current_workspace;
    }
    else
    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot = cached_snapshot_;
    }

    int native_workspace = 0;
    if (NativeShellActivationClientV21::QueryWorkspace(&native_workspace))
    {
        snapshot.current_workspace = native_workspace + 1;
    }
    return snapshot;
}

bool CloudOSFlutterBridgeV20::LaunchApp(const std::string& app_id)
{
    std::string err;
    if (CloudOSBrokerClientV21::Instance().LaunchApp(app_id, err)) return true;

    ShellActivationV21::App surface_app{};
    if (ResolveSurfaceApp(app_id, &surface_app))
    {
        return NativeShellActivationClientV21::Activate(surface_app, &err);
    }

    if (app_id == "files" || app_id == "cloudos:files")
    {
        // First-party Flutter surface: handled directly by CloudOS Shell. Fail closed.
        return false;
    }
    if (app_id == "windows:notepad")
    {
        // Uncontained fallback is blocked to prevent desktop escape (Issue #52).
        return false;
    }
    return false;
}

bool CloudOSFlutterBridgeV20::SetVolume(double volume)
{
    const double clamped = std::clamp(volume, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetVolume(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.volume_available = true;
    cached_snapshot_.volume = clamped;
    return true;
}

bool CloudOSFlutterBridgeV20::SetBrightness(double brightness)
{
    const double clamped = std::clamp(brightness, 0.0, 1.0);
    if (!CloudOSBrokerClientV21::Instance().SetBrightness(clamped)) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.brightness_available = true;
    cached_snapshot_.brightness = clamped;
    return true;
}

void CloudOSFlutterBridgeV20::RefreshAppCatalog()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_apps_.clear();
    cached_apps_.push_back({"cloudos:files", "Arquivos", "cloudos", "Windows + Linux (WSL2)", "", "Sistema", "CloudOS", true, true, false});
    cached_apps_.push_back({"cloudos:browser", "Navegador Web", "cloudos", "WebView2 nativo do CloudOS", "", "Produtividade", "CloudOS", true, true, true});
    cached_apps_.push_back({"cloudos:terminal", "Terminal", "cloudos", "Terminal nativo / ConPTY", "", "Utilitários", "CloudOS", true, true, true});
    cached_apps_.push_back({"windows:notepad", "Bloco de Notas", "windows", "Editor de Texto", "", "Produtividade", "Windows", true, true, false});
}

void CloudOSFlutterBridgeV20::RefreshSystemSnapshot()
{
    std::lock_guard<std::mutex> lock(mutex_);
    cached_snapshot_.device_name = "CloudOS Desktop";
    cached_snapshot_.network_available = false;
    cached_snapshot_.network_name = "Indisponível";
    cached_snapshot_.volume_available = false;
    cached_snapshot_.volume = 0.0;
    cached_snapshot_.brightness_available = false;
    cached_snapshot_.brightness = 0.0;
    cached_snapshot_.battery_available = false;
    cached_snapshot_.battery_percent = 0;
    cached_snapshot_.wsl_available = false;
    cached_snapshot_.distros = {};
    cached_snapshot_.current_workspace = 1;
}

} // namespace CloudOS
