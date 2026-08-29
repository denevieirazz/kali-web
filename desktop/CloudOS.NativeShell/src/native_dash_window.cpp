#include "native_dash_window.h"
namespace CloudOS {
CloudOSNativeDashWindow::~CloudOSNativeDashWindow() {}
bool CloudOSNativeDashWindow::Create(HINSTANCE, CloudOSNativeWindowManager*) { return true; }
void CloudOSNativeDashWindow::Destroy() {}
void CloudOSNativeDashWindow::UpdateLayout(const RECT&) {}
void CloudOSNativeDashWindow::Redraw() {}
}
