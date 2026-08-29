#include "native_taskbar_window.h"
namespace CloudOS {
CloudOSNativeTaskbarWindow::~CloudOSNativeTaskbarWindow() {}
bool CloudOSNativeTaskbarWindow::Create(HINSTANCE, CloudOSNativeWindowManager*) { return true; }
void CloudOSNativeTaskbarWindow::Destroy() {}
int CloudOSNativeTaskbarWindow::HeightPixels() const noexcept { return 0; }
void CloudOSNativeTaskbarWindow::UpdateLayout(const RECT&) {}
void CloudOSNativeTaskbarWindow::Redraw() {}
}
