#include "cloudos_conpty_manager.h"

#include <algorithm>
#include <cstdlib>
#include <limits>
#include <sstream>
#include <system_error>

namespace CloudOS
{

namespace
{

std::wstring Utf8ToWide(const std::string& str)
{
    if (str.empty()) return {};
    const int size = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        str.data(),
        static_cast<int>(str.size()),
        nullptr,
        0);
    if (size <= 0) return {};
    std::wstring result(size, 0);
    MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        str.data(),
        static_cast<int>(str.size()),
        result.data(),
        size);
    return result;
}

// Implements the quoting rules consumed by CommandLineToArgvW/CreateProcessW.
std::wstring QuoteWindowsArgument(const std::wstring& argument)
{
    if (argument.empty()) return L"\"\"";
    if (argument.find_first_of(L" \t\n\v\"") == std::wstring::npos)
    {
        return argument;
    }

    std::wstring quoted = L"\"";
    size_t backslashes = 0;
    for (const wchar_t ch : argument)
    {
        if (ch == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (ch == L'\"')
        {
            quoted.append(backslashes * 2 + 1, L'\\');
            quoted.push_back(L'\"');
            backslashes = 0;
            continue;
        }
        quoted.append(backslashes, L'\\');
        backslashes = 0;
        quoted.push_back(ch);
    }
    quoted.append(backslashes * 2, L'\\');
    quoted.push_back(L'\"');
    return quoted;
}

bool IsExistingDirectory(const std::wstring& path)
{
    if (path.empty()) return false;
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

class ScopedAttributeList final
{
public:
    ~ScopedAttributeList()
    {
        if (list_) DeleteProcThreadAttributeList(list_);
        std::free(storage_);
    }

    ScopedAttributeList(const ScopedAttributeList&) = delete;
    ScopedAttributeList& operator=(const ScopedAttributeList&) = delete;

    ScopedAttributeList() = default;

    bool Initialize()
    {
        SIZE_T size = 0;
        InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
        storage_ = std::malloc(size);
        if (!storage_) return false;
        list_ = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage_);
        if (!InitializeProcThreadAttributeList(list_, 1, 0, &size))
        {
            list_ = nullptr;
            return false;
        }
        return true;
    }

    [[nodiscard]] LPPROC_THREAD_ATTRIBUTE_LIST get() const noexcept { return list_; }

private:
    void* storage_{nullptr};
    LPPROC_THREAD_ATTRIBUTE_LIST list_{nullptr};
};

size_t CompleteUtf8PrefixLength(const std::string& data)
{
    if (data.empty()) return 0;
    size_t index = data.size();
    size_t continuation_count = 0;
    while (index > 0 &&
           (static_cast<unsigned char>(data[index - 1]) & 0xC0U) == 0x80U &&
           continuation_count < 3)
    {
        --index;
        ++continuation_count;
    }
    if (index == data.size())
    {
        const unsigned char last = static_cast<unsigned char>(data.back());
        if ((last & 0x80U) == 0) return data.size();
        if ((last & 0xE0U) == 0xC0U ||
            (last & 0xF0U) == 0xE0U ||
            (last & 0xF8U) == 0xF0U)
        {
            return data.size() - 1;
        }
        return data.size();
    }
    if (index == 0) return 0;

    const size_t lead_index = index - 1;
    const unsigned char lead = static_cast<unsigned char>(data[lead_index]);
    size_t expected = 1;
    if ((lead & 0xE0U) == 0xC0U) expected = 2;
    else if ((lead & 0xF0U) == 0xE0U) expected = 3;
    else if ((lead & 0xF8U) == 0xF0U) expected = 4;
    else return data.size();

    return continuation_count + 1 < expected ? lead_index : data.size();
}

} // namespace

CloudOSConPTYManager& CloudOSConPTYManager::Instance()
{
    static CloudOSConPTYManager instance;
    return instance;
}

CloudOSConPTYManager::~CloudOSConPTYManager()
{
    ShutdownAll();
}

void CloudOSConPTYManager::SetMethodChannel(
    flutter::MethodChannel<flutter::EncodableValue>* channel)
{
    std::lock_guard<std::mutex> lock(mutex_);
    channel_ = channel;
}

void CloudOSConPTYManager::SetPlatformWindow(HWND window)
{
    std::lock_guard<std::mutex> lock(mutex_);
    platform_window_ = window;
}

void CloudOSConPTYManager::SetEventSinkForTesting(
    std::function<void(const std::string&, const std::string&, int, bool)> sink)
{
    std::lock_guard<std::mutex> lock(mutex_);
    test_event_sink_ = std::move(sink);
}

std::string CloudOSConPTYManager::CreateSession(
    const std::string& shell_kind,
    const std::string& distro,
    int cols,
    int rows,
    std::string& out_error,
    const std::string& working_directory)
{
    cols = std::clamp(cols, 1, static_cast<int>((std::numeric_limits<SHORT>::max)()));
    rows = std::clamp(rows, 1, static_cast<int>((std::numeric_limits<SHORT>::max)()));

    std::wstring wide_working_directory;
    if (!working_directory.empty())
    {
        wide_working_directory = Utf8ToWide(working_directory);
        if (wide_working_directory.empty())
        {
            out_error = "Terminal working directory is not valid UTF-8";
            return {};
        }
        if (wide_working_directory.size() >= 32760)
        {
            out_error = "Terminal working directory is too long";
            return {};
        }
    }

    HANDLE raw_pipe_in_reader = nullptr;
    HANDLE raw_pipe_in_writer = nullptr;
    HANDLE raw_pipe_out_reader = nullptr;
    HANDLE raw_pipe_out_writer = nullptr;

    if (!CreatePipe(&raw_pipe_in_reader, &raw_pipe_in_writer, nullptr, 0))
    {
        out_error = "CreatePipe(stdin) failed: " + std::to_string(GetLastError());
        return {};
    }
    UniqueWinHandle pipe_in_reader(raw_pipe_in_reader);
    UniqueWinHandle pipe_in_writer(raw_pipe_in_writer);

    if (!CreatePipe(&raw_pipe_out_reader, &raw_pipe_out_writer, nullptr, 0))
    {
        out_error = "CreatePipe(stdout) failed: " + std::to_string(GetLastError());
        return {};
    }
    UniqueWinHandle pipe_out_reader(raw_pipe_out_reader);
    UniqueWinHandle pipe_out_writer(raw_pipe_out_writer);

    HPCON raw_pseudo_console = nullptr;
    const COORD console_size{
        static_cast<SHORT>(cols),
        static_cast<SHORT>(rows)};
    const HRESULT create_result = CreatePseudoConsole(
        console_size,
        pipe_in_reader.get(),
        pipe_out_writer.get(),
        0,
        &raw_pseudo_console);

    // ConPTY retains the two server-side pipe handles after creation.
    pipe_in_reader.reset();
    pipe_out_writer.reset();

    if (FAILED(create_result))
    {
        std::ostringstream message;
        message << "CreatePseudoConsole failed with HRESULT 0x"
                << std::hex << static_cast<unsigned long>(create_result);
        out_error = message.str();
        return {};
    }
    UniquePseudoConsole pseudo_console(raw_pseudo_console);

    ScopedAttributeList attribute_list;
    if (!attribute_list.Initialize())
    {
        out_error = "InitializeProcThreadAttributeList failed: " +
                    std::to_string(GetLastError());
        return {};
    }
    if (!UpdateProcThreadAttribute(
            attribute_list.get(),
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            pseudo_console.get(),
            sizeof(HPCON),
            nullptr,
            nullptr))
    {
        out_error = "UpdateProcThreadAttribute failed: " +
                    std::to_string(GetLastError());
        return {};
    }

    std::wstring command_line;
    LPCWSTR process_current_directory = nullptr;
    if (shell_kind == "wsl")
    {
        command_line = L"wsl.exe";
        if (!distro.empty())
        {
            const std::wstring wide_distro = Utf8ToWide(distro);
            if (wide_distro.empty())
            {
                out_error = "WSL distribution name is not valid UTF-8";
                return {};
            }
            command_line += L" -d " + QuoteWindowsArgument(wide_distro);
        }
        if (!wide_working_directory.empty())
        {
            // wsl.exe performs the Windows/Linux path translation itself and
            // starts the selected distro directly in the requested directory.
            command_line += L" --cd " + QuoteWindowsArgument(wide_working_directory);
        }
    }
    else if (shell_kind == "cmd")
    {
        command_line = L"cmd.exe";
        if (!wide_working_directory.empty())
        {
            if (!IsExistingDirectory(wide_working_directory))
            {
                out_error = "Terminal working directory does not exist";
                return {};
            }
            process_current_directory = wide_working_directory.c_str();
        }
    }
    else if (shell_kind == "powershell")
    {
        command_line = L"powershell.exe -NoLogo -NoProfile";
        if (!wide_working_directory.empty())
        {
            if (!IsExistingDirectory(wide_working_directory))
            {
                out_error = "Terminal working directory does not exist";
                return {};
            }
            process_current_directory = wide_working_directory.c_str();
        }
    }
    else
    {
        out_error = "Unsupported shell kind: " + shell_kind;
        return {};
    }

    std::vector<wchar_t> command_buffer(command_line.begin(), command_line.end());
    command_buffer.push_back(L'\0');

    STARTUPINFOEXW startup_info{};
    startup_info.StartupInfo.cb = sizeof(startup_info);
    startup_info.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup_info.lpAttributeList = attribute_list.get();

    PROCESS_INFORMATION process_info{};
    if (!CreateProcessW(
            nullptr,
            command_buffer.data(),
            nullptr,
            nullptr,
            FALSE,
            EXTENDED_STARTUPINFO_PRESENT,
            nullptr,
            process_current_directory,
            &startup_info.StartupInfo,
            &process_info))
    {
        out_error = "CreateProcessW failed: " + std::to_string(GetLastError());
        return {};
    }

    UniqueWinHandle process(process_info.hProcess);
    UniqueWinHandle primary_thread(process_info.hThread);

    const uint64_t id_number = ++session_counter_;
    const std::string session_id =
        "pty_" + std::to_string(id_number) + "_" + shell_kind;

    auto session = std::make_shared<ConPTYSession>();
    session->session_id = session_id;
    session->shell_kind = shell_kind;
    session->distro = distro;
    session->working_directory = working_directory;
    session->cols = cols;
    session->rows = rows;
    session->pseudo_console = std::move(pseudo_console);
    session->process = std::move(process);
    session->primary_thread = std::move(primary_thread);
    session->pipe_in_writer = std::move(pipe_in_writer);
    session->pipe_out_reader = std::move(pipe_out_reader);
    session->process_id = process_info.dwProcessId;
    session->is_alive.store(true);

    {
        std::lock_guard<std::mutex> lock(mutex_);
        sessions_.emplace(session_id, session);
    }

    try
    {
        session->reader_thread = std::thread([this, session]() {
            ReaderLoop(session);
        });
    }
    catch (const std::system_error& error)
    {
        out_error = "Failed to create ConPTY reader thread: " +
                    std::string(error.what());
        CloseSession(session_id);
        return {};
    }

    return session_id;
}

void CloudOSConPTYManager::ReaderLoop(
    const std::shared_ptr<ConPTYSession>& session)
{
    constexpr DWORD kBufferSize = 8192;
    char buffer[kBufferSize];
    std::string utf8_pending;

    while (!session->closing.load())
    {
        DWORD bytes_read = 0;
        const BOOL success = ReadFile(
            session->pipe_out_reader.get(),
            buffer,
            kBufferSize,
            &bytes_read,
            nullptr);
        if (!success || bytes_read == 0) break;

        utf8_pending.append(buffer, bytes_read);
        const size_t complete_length = CompleteUtf8PrefixLength(utf8_pending);
        if (complete_length > 0)
        {
            NotifyData(session->session_id, utf8_pending.substr(0, complete_length));
            utf8_pending.erase(0, complete_length);
        }
    }

    if (!utf8_pending.empty() && !session->closing.load())
    {
        NotifyData(session->session_id, std::move(utf8_pending));
    }

    DWORD exit_code = 0;
    const HANDLE process = session->process.get();
    if (process && process != INVALID_HANDLE_VALUE)
    {
        WaitForSingleObject(process, INFINITE);
        GetExitCodeProcess(process, &exit_code);
    }
    session->is_alive.store(false);
    if (!session->closing.load())
    {
        NotifyExit(session->session_id, static_cast<int>(exit_code));
    }
}

void CloudOSConPTYManager::NotifyData(
    const std::string& session_id,
    std::string data)
{
    QueuePlatformEvent({
        PlatformEventKind::data,
        session_id,
        std::move(data),
        0});
}

void CloudOSConPTYManager::NotifyExit(
    const std::string& session_id,
    int exit_code)
{
    QueuePlatformEvent({
        PlatformEventKind::exit,
        session_id,
        {},
        exit_code});
}

void CloudOSConPTYManager::QueuePlatformEvent(PlatformEvent event)
{
    HWND window = nullptr;
    std::function<void(const std::string&, const std::string&, int, bool)> test_sink;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        window = platform_window_;
        test_sink = test_event_sink_;
    }
    if (test_sink)
    {
        test_sink(
            event.session_id,
            event.data,
            event.exit_code,
            event.kind == PlatformEventKind::exit);
    }
    if (!window) return;

    {
        std::lock_guard<std::mutex> lock(event_mutex_);
        pending_events_.push_back(std::move(event));
    }
    PostMessageW(window, kDispatchMessage, 0, 0);
}

void CloudOSConPTYManager::DrainPlatformEvents()
{
    std::deque<PlatformEvent> events;
    {
        std::lock_guard<std::mutex> lock(event_mutex_);
        events.swap(pending_events_);
    }

    flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        channel = channel_;
    }
    if (!channel) return;

    for (auto& event : events)
    {
        flutter::EncodableMap map;
        map[flutter::EncodableValue("sessionId")] =
            flutter::EncodableValue(event.session_id);
        if (event.kind == PlatformEventKind::data)
        {
            map[flutter::EncodableValue("data")] =
                flutter::EncodableValue(std::move(event.data));
            channel->InvokeMethod(
                "terminal.onData",
                std::make_unique<flutter::EncodableValue>(std::move(map)));
        }
        else
        {
            map[flutter::EncodableValue("exitCode")] =
                flutter::EncodableValue(event.exit_code);
            channel->InvokeMethod(
                "terminal.onExit",
                std::make_unique<flutter::EncodableValue>(std::move(map)));
        }
    }
}

bool CloudOSConPTYManager::WriteSession(
    const std::string& session_id,
    const std::string& input_data)
{
    std::shared_ptr<ConPTYSession> session;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = sessions_.find(session_id);
        if (it == sessions_.end()) return false;
        session = it->second;
    }

    UniqueWinHandle write_handle;
    {
        std::lock_guard<std::mutex> lock(session->io_mutex);
        if (session->closing.load() ||
            !session->is_alive.load() ||
            !session->pipe_in_writer.valid())
        {
            return false;
        }
        HANDLE duplicate = nullptr;
        if (!DuplicateHandle(
                GetCurrentProcess(),
                session->pipe_in_writer.get(),
                GetCurrentProcess(),
                &duplicate,
                0,
                FALSE,
                DUPLICATE_SAME_ACCESS))
        {
            return false;
        }
        write_handle.reset(duplicate);
    }

    DWORD bytes_written = 0;
    const BOOL success = WriteFile(
        write_handle.get(),
        input_data.data(),
        static_cast<DWORD>(input_data.size()),
        &bytes_written,
        nullptr);
    return success == TRUE && bytes_written == input_data.size();
}

bool CloudOSConPTYManager::ResizeSession(
    const std::string& session_id,
    int cols,
    int rows)
{
    std::shared_ptr<ConPTYSession> session;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = sessions_.find(session_id);
        if (it == sessions_.end()) return false;
        session = it->second;
    }

    cols = std::clamp(cols, 1, static_cast<int>((std::numeric_limits<SHORT>::max)()));
    rows = std::clamp(rows, 1, static_cast<int>((std::numeric_limits<SHORT>::max)()));

    std::lock_guard<std::mutex> lock(session->io_mutex);
    if (session->closing.load() ||
        !session->is_alive.load() ||
        !session->pseudo_console.valid())
    {
        return false;
    }
    const COORD size{static_cast<SHORT>(cols), static_cast<SHORT>(rows)};
    if (FAILED(ResizePseudoConsole(session->pseudo_console.get(), size)))
    {
        return false;
    }
    session->cols = cols;
    session->rows = rows;
    return true;
}

bool CloudOSConPTYManager::SignalSession(
    const std::string& session_id,
    const std::string& signal_type)
{
    if (signal_type == "SIGINT" || signal_type == "ctrl_c")
    {
        return WriteSession(session_id, "\x03");
    }
    if (signal_type == "EOF" || signal_type == "ctrl_d")
    {
        return WriteSession(session_id, "\x04");
    }
    // ConPTY's VT input stream does not expose a distinct Ctrl+Break signal.
    // Returning false is deliberate; Ctrl+Break must not be faked as Ctrl+C.
    if (signal_type == "SIGQUIT" || signal_type == "ctrl_break")
    {
        return false;
    }
    return false;
}

bool CloudOSConPTYManager::CloseSession(const std::string& session_id)
{
    std::shared_ptr<ConPTYSession> session;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = sessions_.find(session_id);
        if (it == sessions_.end()) return false;
        session = it->second;
    }

    if (session->closing.exchange(true)) return true;
    session->is_alive.store(false);

    // Closing input requests normal EOF before a forced termination fallback.
    {
        std::lock_guard<std::mutex> lock(session->io_mutex);
        session->pipe_in_writer.reset();
    }

    const HANDLE process = session->process.get();
    if (process && process != INVALID_HANDLE_VALUE)
    {
        if (WaitForSingleObject(process, 250) == WAIT_TIMEOUT)
        {
            TerminateProcess(process, 0);
        }
    }

    // Closing HPCON closes ConPTY's pipe ends. The reader remains alive to
    // drain/unblock the output side before it is joined.
    {
        std::lock_guard<std::mutex> lock(session->io_mutex);
        session->pseudo_console.reset();
    }

    if (session->reader_thread.joinable())
    {
        CancelSynchronousIo(
            reinterpret_cast<HANDLE>(session->reader_thread.native_handle()));
        session->reader_thread.join();
    }

    // No worker can access these handles after join.
    {
        std::lock_guard<std::mutex> lock(session->io_mutex);
        session->pipe_out_reader.reset();
        session->process.reset();
        session->primary_thread.reset();
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = sessions_.find(session_id);
        if (it != sessions_.end() && it->second == session)
        {
            sessions_.erase(it);
        }
    }
    return true;
}

std::vector<TerminalSessionInfo> CloudOSConPTYManager::ListSessions()
{
    std::vector<std::shared_ptr<ConPTYSession>> snapshot;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        snapshot.reserve(sessions_.size());
        for (const auto& [_, session] : sessions_)
        {
            snapshot.push_back(session);
        }
    }

    std::vector<TerminalSessionInfo> result;
    result.reserve(snapshot.size());
    for (const auto& session : snapshot)
    {
        std::lock_guard<std::mutex> lock(session->io_mutex);
        result.push_back({
            session->session_id,
            session->shell_kind,
            session->distro,
            session->working_directory,
            session->cols,
            session->rows,
            session->is_alive.load(),
            session->process_id});
    }
    return result;
}

void CloudOSConPTYManager::ShutdownAll()
{
    std::vector<std::string> session_ids;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        session_ids.reserve(sessions_.size());
        for (const auto& [session_id, _] : sessions_)
        {
            session_ids.push_back(session_id);
        }
    }
    for (const auto& session_id : session_ids)
    {
        CloseSession(session_id);
    }
}

} // namespace CloudOS
