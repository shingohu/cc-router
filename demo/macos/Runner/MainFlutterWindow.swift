import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let minimumContentSize = NSSize(width: 480, height: 640)
  private static let preferredContentSize = NSSize(width: 800, height: 800)

  private var screenChangeObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    updateWindowConstraints(preferInitialSize: true)

    screenChangeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification,
      object: self,
      queue: .main
    ) { [weak self] _ in
      self?.updateWindowConstraints(preferInitialSize: false)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  deinit {
    if let screenChangeObserver {
      NotificationCenter.default.removeObserver(screenChangeObserver)
    }
  }

  private func updateWindowConstraints(preferInitialSize: Bool) {
    guard let targetScreen = screen ?? NSScreen.main else {
      contentMinSize = Self.minimumContentSize
      return
    }

    let availableContentSize = contentRect(forFrameRect: targetScreen.visibleFrame).size
    let effectiveMinimum = NSSize(
      width: min(Self.minimumContentSize.width, availableContentSize.width),
      height: min(Self.minimumContentSize.height, availableContentSize.height)
    )
    contentMinSize = effectiveMinimum
    contentMaxSize = availableContentSize

    let currentContentSize = contentRect(forFrameRect: frame).size
    let requestedContentSize = preferInitialSize
      ? Self.preferredContentSize
      : currentContentSize
    let targetContentSize = NSSize(
      width: min(max(requestedContentSize.width, effectiveMinimum.width), availableContentSize.width),
      height: min(max(requestedContentSize.height, effectiveMinimum.height), availableContentSize.height)
    )

    var targetFrame = frameRect(
      forContentRect: NSRect(origin: .zero, size: targetContentSize)
    )
    targetFrame.origin = frame.origin
    targetFrame.origin.y = frame.maxY - targetFrame.height
    targetFrame = constrainFrameRect(targetFrame, to: targetScreen)
    setFrame(targetFrame, display: true)
  }
}
