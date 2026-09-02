cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(BINARY_NAME "cloudos_flutter_shell")

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "cloudos_flutter_bridge_v20.cpp"
  "cloudos_broker_client_v21.cpp"
  "cloudos_broker_event_client_v23.cpp"
  "cloudos_conpty_manager.cpp"
  "cloudos_system_metrics_native.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "_HAS_EXCEPTIONS=0")
target_compile_definitions(${BINARY_NAME} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
target_compile_definitions(${BINARY_NAME} PRIVATE "UNICODE" "_UNICODE")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE dwmapi.lib shlwapi.lib shell32.lib ole32.lib uuid.lib advapi32.lib psapi.lib iphlpapi.lib)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_executable(cloudos_conpty_probe EXCLUDE_FROM_ALL
  "cloudos_conpty_probe.cpp"
  "cloudos_conpty_manager.cpp"
)
apply_standard_settings(cloudos_conpty_probe)
target_compile_definitions(cloudos_conpty_probe PRIVATE "_HAS_EXCEPTIONS=0" "UNICODE" "_UNICODE")
target_link_libraries(cloudos_conpty_probe PRIVATE flutter flutter_wrapper_app psapi.lib)
target_include_directories(cloudos_conpty_probe PRIVATE "${CMAKE_SOURCE_DIR}")
