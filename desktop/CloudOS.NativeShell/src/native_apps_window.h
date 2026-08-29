#pragma once
#include <Windows.h>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>
class CloudOSNativeAppsWindow final {
public:
 static void Open(HINSTANCE instance);
 static LRESULT CALLBACK WindowProcedure(HWND,UINT,WPARAM,LPARAM);
private:
 struct AppEntry final { std::wstring name; std::wstring path; };
 explicit CloudOSNativeAppsWindow(HINSTANCE instance); ~CloudOSNativeAppsWindow()=default;
 bool Create(); void Layout(); void LoadCatalog(); void EnumerateFolder(const std::wstring&,int); void ApplyFilter(); void LaunchSelection();
 static std::wstring ReadText(HWND); static bool ContainsInsensitive(std::wstring_view,std::wstring_view);
 LRESULT HandleMessage(UINT,WPARAM,LPARAM);
 HINSTANCE instance_{}; HWND window_{}; HWND search_edit_{}; HWND list_{}; HWND launch_button_{};
 std::vector<AppEntry> catalog_; std::vector<std::size_t> visible_indices_;
};
