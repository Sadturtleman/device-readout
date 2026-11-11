#include "viewport_test_host.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

Map WindowState(HWND window) {
  RECT client{};
  GetClientRect(window, &client);
  return {{Value("width"), Value(static_cast<int32_t>(client.right))},
          {Value("height"), Value(static_cast<int32_t>(client.bottom))},
          {Value("dpi"), Value(static_cast<int32_t>(GetDpiForWindow(window)))},
          {Value("visible"), Value(IsWindowVisible(window) != FALSE)},
          {Value("processId"), Value(static_cast<int64_t>(GetCurrentProcessId()))}};
}

BOOL CALLBACK CountMonitor(HMONITOR, HDC, LPRECT, LPARAM count) {
  ++*reinterpret_cast<int32_t*>(count);
  return TRUE;
}

Map DisplayState(HWND window) {
  const HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) return {};
  DEVMODEW mode{};
  mode.dmSize = sizeof(mode);
  if (!EnumDisplaySettingsW(info.szDevice, ENUM_CURRENT_SETTINGS, &mode)) return {};
  int32_t count = 0;
  if (!EnumDisplayMonitors(nullptr, nullptr, CountMonitor,
                           reinterpret_cast<LPARAM>(&count))) return {};
  return {{Value("width"), Value(static_cast<int32_t>(info.rcMonitor.right - info.rcMonitor.left))},
          {Value("height"), Value(static_cast<int32_t>(info.rcMonitor.bottom - info.rcMonitor.top))},
          {Value("rate"), Value(static_cast<int32_t>(mode.dmDisplayFrequency))},
          {Value("dpi"), Value(static_cast<int32_t>(GetDpiForWindow(window)))},
          {Value("count"), Value(count)}};
}
}  // namespace

void RegisterViewportTestHost(flutter::BinaryMessenger* messenger, HWND window) {
  flutter::MethodChannel<Value> channel(
      messenger, "device_readout.test/windows_viewport",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [window](const flutter::MethodCall<Value>& call,
               std::unique_ptr<flutter::MethodResult<Value>> result) {
        if (call.method_name() == "state") {
          result->Success(Value(WindowState(window)));
          return;
        }
        if (call.method_name() == "displayState") {
          result->Success(Value(DisplayState(window)));
          return;
        }
        if (call.method_name() == "notifyDisplays") {
          // Explicit test stimulus; no monitor settings or hardware are changed.
          SendMessage(window, WM_DISPLAYCHANGE, 0, 0);
          result->Success();
          return;
        }
        if (call.method_name() == "resize") {
          const auto* args = call.arguments() == nullptr
                                 ? nullptr
                                 : std::get_if<Map>(call.arguments());
          if (args == nullptr || args->count(Value("width")) != 1 ||
              args->count(Value("height")) != 1) {
            result->Error("InvalidArguments", "Expected width and height.");
            return;
          }
          const auto* width = std::get_if<int32_t>(&args->at(Value("width")));
          const auto* height = std::get_if<int32_t>(&args->at(Value("height")));
          if (width == nullptr || height == nullptr || *width < 100 ||
              *width > 2000 || *height < 100 || *height > 2000) {
            result->Error("InvalidArguments", "Dimensions outside test bounds.");
            return;
          }
          RECT rect{0, 0, *width, *height};
          if (!AdjustWindowRectExForDpi(
                  &rect, static_cast<DWORD>(GetWindowLongPtr(window, GWL_STYLE)),
                  FALSE, static_cast<DWORD>(GetWindowLongPtr(window, GWL_EXSTYLE)),
                  GetDpiForWindow(window)) ||
              !SetWindowPos(window, nullptr, 0, 0, rect.right - rect.left,
                            rect.bottom - rect.top,
                            SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) {
            result->Error("ResizeFailed", std::to_string(GetLastError()));
            return;
          }
          result->Success(Value(WindowState(window)));
          return;
        }
        if (call.method_name() == "finish") {
          result->Success();
          PostMessage(window, WM_CLOSE, 0, 0);
          return;
        }
        result->NotImplemented();
      });
}
