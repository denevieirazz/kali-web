#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "cloudos_flutter_bridge_v20.h"
#include "cloudos_broker_event_client_v23.h"
#include "cloudos_conpty_manager.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());

  CloudOS::CloudOSFlutterBridgeV20::RegisterWithMessenger(
      flutter_controller_->engine()->messenger(),
      GetHandle());

  // The dedicated EventBus channel is registered now, but its named-pipe
  // worker starts only after Dart installs its handler and invokes `start`.
  CloudOS::CloudOSBrokerEventClientV23::Instance().Initialize(
      flutter_controller_->engine()->messenger(),
      GetHandle());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  CloudOS::CloudOSBrokerEventClientV23::Instance().Shutdown();
  CloudOS::CloudOSConPTYManager::Instance().ShutdownAll();
  CloudOS::CloudOSConPTYManager::Instance().SetMethodChannel(nullptr);
  CloudOS::CloudOSConPTYManager::Instance().SetPlatformWindow(nullptr);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == CloudOS::CloudOSConPTYManager::kDispatchMessage) {
    CloudOS::CloudOSConPTYManager::Instance().DrainPlatformEvents();
    return 0;
  }

  if (message == CloudOS::CloudOSBrokerEventClientV23::kDispatchMessage) {
    CloudOS::CloudOSBrokerEventClientV23::Instance().DrainPlatformEvents();
    return 0;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
