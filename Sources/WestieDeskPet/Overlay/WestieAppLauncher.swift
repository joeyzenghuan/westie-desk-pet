import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private let startInTennisMode: Bool

    public init(startInTennisMode: Bool = false) {
        self.startInTennisMode = startInTennisMode
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            NSApp.terminate(nil)
            return
        }

        let overlay = OverlayWindowController(screen: screen)
        overlay.show()
        self.overlayController = overlay
        self.menuBarController = MenuBarController(scene: overlay.scene)

        if startInTennisMode {
            overlay.scene.switchToMode(.tennis)
        }
    }
}

public enum WestieAppLauncher {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            let ok = SelfTestRunner.runAll()
            exit(ok ? 0 : 1)
        }

        // Accessory policy: lives cleanly in the Menu Bar with no Dock icon clutter!
        app.setActivationPolicy(.accessory)
        let startTennis = args.contains("--tennis")
        let delegate = AppDelegate(startInTennisMode: startTennis)
        app.delegate = delegate
        app.run()
    }
}
