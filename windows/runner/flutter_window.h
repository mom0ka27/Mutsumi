#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void BeginPlaybackMode(double aspect_ratio,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void EndPlaybackMode(const std::string& token,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ApplyPlaybackSize(double aspect_ratio);
  void ConstrainSizingRect(WPARAM edge, RECT* rect);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  std::optional<RECT> frame_before_playback_;
  std::optional<double> playback_aspect_ratio_;
  std::string playback_token_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
