import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var frameBeforePlayback: NSRect?
  private var frameToRestoreAfterFullScreen: NSRect?
  private var playbackToken: String?
  private var fullScreenExitObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 800, height: 600))
    self.styleMask.insert(.resizable)
    self.contentMinSize = .zero
    self.contentMaxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    self.resizeIncrements = NSSize(width: 1, height: 1)
    self.standardWindowButton(.zoomButton)?.isEnabled = true
    self.fullScreenExitObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didExitFullScreenNotification,
      object: self,
      queue: .main
    ) { [weak self] _ in
      guard let self, let frame = self.frameToRestoreAfterFullScreen else {
        return
      }
      self.frameToRestoreAfterFullScreen = nil
      self.setFrame(frame, display: true, animate: true)
    }

    let windowChannel = FlutterMethodChannel(
      name: "mutsumi/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "window_unavailable",
          message: "Main window is unavailable",
          details: nil
        ))
        return
      }
      switch call.method {
      case "beginPlaybackMode":
        let arguments = call.arguments as? [String: Any]
        let aspectRatio = arguments?["aspectRatio"] as? Double ?? 16.0 / 9.0
        guard aspectRatio > 0 else {
          result(FlutterError(
            code: "invalid_aspect_ratio",
            message: "Aspect ratio must be greater than zero",
            details: nil
          ))
          return
        }
        if self.frameBeforePlayback == nil {
          self.frameBeforePlayback = self.frame
        }
        let size = self.contentView?.bounds.size ?? self.frame.size
        self.setContentSize(NSSize(width: size.width, height: size.width / aspectRatio))
        self.contentAspectRatio = NSSize(width: aspectRatio, height: 1)
        let token = UUID().uuidString
        self.playbackToken = token
        result(["status": "supported", "token": token])
      case "endPlaybackMode":
        let arguments = call.arguments as? [String: Any]
        guard let token = arguments?["token"] as? String,
              token == self.playbackToken else {
          result(nil)
          return
        }
        self.playbackToken = nil
        self.contentAspectRatio = .zero
        self.styleMask.insert(.resizable)
        self.contentMinSize = .zero
        self.contentMaxSize = NSSize(
          width: CGFloat.greatestFiniteMagnitude,
          height: CGFloat.greatestFiniteMagnitude
        )
        self.resizeIncrements = NSSize(width: 1, height: 1)
        self.standardWindowButton(.zoomButton)?.isEnabled = true
        if self.styleMask.contains(.fullScreen) {
          self.frameToRestoreAfterFullScreen = self.frameBeforePlayback
          self.frameBeforePlayback = nil
        } else if let frame = self.frameBeforePlayback {
          self.setFrame(frame, display: true, animate: true)
          self.frameBeforePlayback = nil
        }
        result(nil)
      case "setPlaybackAspectRatio":
        if self.frameBeforePlayback == nil {
          self.frameBeforePlayback = self.frame
        }
        let size = self.contentView?.bounds.size ?? self.frame.size
        self.setContentSize(NSSize(width: size.width, height: size.width * 9 / 16))
        self.contentAspectRatio = NSSize(width: 16, height: 9)
        result(nil)
      case "clearPlaybackAspectRatio":
        self.playbackToken = nil
        self.contentAspectRatio = .zero
        if let frame = self.frameBeforePlayback {
          self.setFrame(frame, display: true, animate: true)
          self.frameBeforePlayback = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  deinit {
    if let fullScreenExitObserver {
      NotificationCenter.default.removeObserver(fullScreenExitObserver)
    }
  }
}
