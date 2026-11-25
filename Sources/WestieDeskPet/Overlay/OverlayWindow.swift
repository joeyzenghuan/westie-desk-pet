import AppKit
import SpriteKit

@MainActor
public final class InteractiveSKView: SKView {
    public override var acceptsFirstResponder: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseMoved(with event: NSEvent) {
        scene?.mouseMoved(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        scene?.rightMouseDown(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        // Forward directly to scene without calling super to prevent macOS system beep!
        scene?.keyDown(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        scene?.keyUp(with: event)
    }
}

@MainActor
public final class OverlayPanel: NSPanel {
    public var allowKeyFocus: Bool = false

    public override var canBecomeKey: Bool { allowKeyFocus }
    public override var canBecomeMain: Bool { false }
}

@MainActor
public final class OverlayWindowController {
    public let panel: OverlayPanel
    public let skView: InteractiveSKView
    public let scene: DesktopScene

    private nonisolated(unsafe) var mousePollTimer: Timer?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private var lastMouseLoc: CGPoint = .zero

    public init(screen: NSScreen) {
        let frame = screen.frame

        panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false

        skView = InteractiveSKView(frame: NSRect(origin: .zero, size: frame.size))
        skView.allowsTransparency = true
        skView.preferredFramesPerSecond = 24
        skView.ignoresSiblingOrder = true
        skView.autoresizingMask = [.width, .height]

        scene = DesktopScene(size: frame.size)
        panel.contentView = skView
        skView.presentScene(scene)

        scene.onModeChanged = { [weak self] mode in
            self?.applyInteractionMode(mode)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.realignToMainScreen()
            }
        }
    }

    deinit {
        mousePollTimer?.invalidate()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func show() {
        panel.orderFrontRegardless()
        startDynamicHitTesting()
    }

    private func realignToMainScreen() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(screen.frame, display: true)
        scene.size = screen.frame.size
    }

    private func applyInteractionMode(_ mode: AppInteractionMode) {
        switch mode {
        case .companion:
            panel.allowKeyFocus = false
            panel.resignKey()
            updateMousePassThrough()

        case .tennis:
            panel.allowKeyFocus = true
            panel.ignoresMouseEvents = false
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(skView)
        }
    }

    private func startDynamicHitTesting() {
        mousePollTimer?.invalidate()
        mousePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMousePassThrough()
            }
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalMouseMove()
            }
        }
    }

    private func handleGlobalMouseMove() {
        let loc = NSEvent.mouseLocation
        guard hypot(loc.x - lastMouseLoc.x, loc.y - lastMouseLoc.y) > 2.0 else { return }
        lastMouseLoc = loc
        updateMousePassThrough()
        scene.notifyGlobalHover(at: loc, windowFrame: panel.frame)
    }

    private func updateMousePassThrough() {
        if scene.mode == .tennis {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            return
        }
        let loc = NSEvent.mouseLocation
        let shouldCapture = scene.shouldCaptureMouse(at: loc, windowFrame: panel.frame)
        if panel.ignoresMouseEvents == shouldCapture {
            panel.ignoresMouseEvents = !shouldCapture
        }
    }
}
