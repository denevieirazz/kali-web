#pragma once

#include <Windows.h>

#include <atomic>
#include <cwctype>
#include <functional>
#include <string>
#include <thread>
#include <vector>

namespace CloudOS
{
class CloudOSNativeFileOperationsWindow final
{
public:
    static void Open(HINSTANCE instance, const std::wstring& initial_destination = {});
    static void OpenWithSources(
        HINSTANCE instance,
        const std::vector<std::wstring>& sources,
        const std::wstring& initial_destination = {});

private:
    enum class OperationKind
    {
        Copy,
        Move,
        CreateZip,
        ExtractZip,
    };

    explicit CloudOSNativeFileOperationsWindow(
        HINSTANCE instance,
        std::wstring initial_destination);
    ~CloudOSNativeFileOperationsWindow();

    CloudOSNativeFileOperationsWindow(const CloudOSNativeFileOperationsWindow&) = delete;
    CloudOSNativeFileOperationsWindow& operator=(const CloudOSNativeFileOperationsWindow&) = delete;

    bool Create();
    void Layout();
    void RefreshSourceList();
    void AddFiles();
    void AddFolder();
    void RemoveSelection();
    void PickDestination();
    void StartOperation(OperationKind kind);
    void CancelOperation();
    void FinishOperation(bool success, HRESULT result);
    void SetRunning(bool running, bool marquee);
    std::wstring ChooseZipOutput();
    std::wstring ChooseExtractionFolder();

    void WorkerMain(
        OperationKind kind,
        std::vector<std::wstring> sources,
        std::wstring destination,
        std::wstring archive_path);

    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM w_param, LPARAM l_param);
    LRESULT HandleMessage(HWND window, UINT message, WPARAM w_param, LPARAM l_param);

    HINSTANCE instance_{};
    HWND window_{};
    HWND source_list_{};
    HWND destination_edit_{};
    HWND add_files_button_{};
    HWND add_folder_button_{};
    HWND remove_button_{};
    HWND destination_button_{};
    HWND copy_button_{};
    HWND move_button_{};
    HWND zip_button_{};
    HWND extract_button_{};
    HWND cancel_button_{};
    HWND progress_{};
    HWND status_{};
    HFONT font_{};

    std::vector<std::wstring> sources_;
    std::wstring destination_;
    std::thread worker_;
    std::atomic_bool cancel_requested_{false};
    bool running_{};
    bool self_delete_{};
};
} // namespace CloudOS
