#include "flutter_window.h"

#include <chrono>
#include <optional>
#include <sstream>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "mutsumi/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "beginPlaybackMode") {
          double aspect_ratio = 16.0 / 9.0;
          if (const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto ratio = arguments->find(flutter::EncodableValue("aspectRatio"));
            if (ratio != arguments->end()) {
              if (const auto* value = std::get_if<double>(&ratio->second)) {
                aspect_ratio = *value;
              }
            }
          }
          BeginPlaybackMode(aspect_ratio, std::move(result));
          return;
        }
        if (call.method_name() == "endPlaybackMode") {
          std::string token;
          if (const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto value = arguments->find(flutter::EncodableValue("token"));
            if (value != arguments->end()) {
              if (const auto* text = std::get_if<std::string>(&value->second)) {
                token = *text;
              }
            }
          }
          EndPlaybackMode(token, std::move(result));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_SIZING:
      if (playback_aspect_ratio_ && !IsZoomed(hwnd)) {
        ConstrainSizingRect(wparam, reinterpret_cast<RECT*>(lparam));
        return TRUE;
      }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::BeginPlaybackMode(
    double aspect_ratio,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (aspect_ratio <= 0) {
    result->Error("invalid_aspect_ratio", "Aspect ratio must be greater than zero");
    return;
  }
  if (!frame_before_playback_) {
    RECT frame;
    if (GetWindowRect(GetHandle(), &frame)) {
      frame_before_playback_ = frame;
    }
  }
  playback_aspect_ratio_ = aspect_ratio;
  std::ostringstream token;
  token << std::chrono::steady_clock::now().time_since_epoch().count();
  playback_token_ = token.str();
  if (!IsZoomed(GetHandle())) {
    ApplyPlaybackSize(aspect_ratio);
  }
  flutter::EncodableMap response;
  response[flutter::EncodableValue("status")] =
      flutter::EncodableValue("supported");
  response[flutter::EncodableValue("token")] =
      flutter::EncodableValue(playback_token_);
  result->Success(flutter::EncodableValue(response));
}

void FlutterWindow::EndPlaybackMode(
    const std::string& token,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (token != playback_token_) {
    result->Success();
    return;
  }
  playback_token_.clear();
  playback_aspect_ratio_.reset();
  if (frame_before_playback_ && !IsZoomed(GetHandle())) {
    const RECT frame = *frame_before_playback_;
    SetWindowPos(GetHandle(), nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  frame_before_playback_.reset();
  result->Success();
}

void FlutterWindow::ApplyPlaybackSize(double aspect_ratio) {
  const RECT client = GetClientArea();
  const LONG width = client.right - client.left;
  RECT frame = {0, 0, width, static_cast<LONG>(width / aspect_ratio)};
  const DWORD style = static_cast<DWORD>(GetWindowLongPtr(GetHandle(), GWL_STYLE));
  const DWORD ex_style = static_cast<DWORD>(GetWindowLongPtr(GetHandle(), GWL_EXSTYLE));
  const UINT dpi = GetDpiForWindow(GetHandle());
  AdjustWindowRectExForDpi(&frame, style, FALSE, ex_style, dpi);
  RECT current;
  GetWindowRect(GetHandle(), &current);
  SetWindowPos(GetHandle(), nullptr, current.left, current.top,
               frame.right - frame.left, frame.bottom - frame.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FlutterWindow::ConstrainSizingRect(WPARAM edge, RECT* rect) {
  if (!rect || !playback_aspect_ratio_) {
    return;
  }
  const DWORD style = static_cast<DWORD>(GetWindowLongPtr(GetHandle(), GWL_STYLE));
  const DWORD ex_style = static_cast<DWORD>(GetWindowLongPtr(GetHandle(), GWL_EXSTYLE));
  RECT decoration = {0, 0, 0, 0};
  AdjustWindowRectExForDpi(&decoration, style, FALSE, ex_style,
                           GetDpiForWindow(GetHandle()));
  const LONG horizontal = decoration.right - decoration.left;
  const LONG vertical = decoration.bottom - decoration.top;
  LONG client_width = rect->right - rect->left - horizontal;
  LONG client_height = rect->bottom - rect->top - vertical;
  const bool vertical_edge = edge == WMSZ_TOP || edge == WMSZ_BOTTOM;
  if (vertical_edge) {
    client_width = static_cast<LONG>(client_height * *playback_aspect_ratio_);
    rect->right = rect->left + client_width + horizontal;
  } else {
    client_height = static_cast<LONG>(client_width / *playback_aspect_ratio_);
    if (edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT) {
      rect->top = rect->bottom - client_height - vertical;
    } else {
      rect->bottom = rect->top + client_height + vertical;
    }
  }
}
