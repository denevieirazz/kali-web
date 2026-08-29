#include "native_start_menu_window.h"
namespace CloudOS {
CloudOSNativeStartMenuWindow::~CloudOSNativeStartMenuWindow() {}
bool CloudOSNativeStartMenuWindow::Create(HINSTANCE, HWND) { return true; }
void CloudOSNativeStartMenuWindow::Destroy() {}
void CloudOSNativeStartMenuWindow::Show(int, int) {}
void CloudOSNativeStartMenuWindow::Hide() {}
void CloudOSNativeStartMenuWindow::Toggle(int, int) {}
bool CloudOSNativeStartMenuWindow::IsVisible() const { return false; }
}
