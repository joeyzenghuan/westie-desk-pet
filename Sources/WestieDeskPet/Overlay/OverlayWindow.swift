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

    public override func mouseDown(with event: NSEvent) {
        if let desktopScene = scene as? DesktopScene,
           desktopScene.mode == .companion,
           event.modifierFlags.contains(.control)
        {
            popCompanionContextMenu(with: event, desktopScene: desktopScene)
            return
        }
        super.mouseDown(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let desktopScene = scene as? DesktopScene, desktopScene.mode == .companion {
            popCompanionContextMenu(with: event, desktopScene: desktopScene)
            return
        }
        scene?.rightMouseDown(with: event)
    }

    private func popCompanionContextMenu(with event: NSEvent, desktopScene: DesktopScene) {
        let menu = desktopScene.buildDogContextMenu()
        let viewPoint = convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: self)
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
    private nonisolated(unsafe) var localMouseMonitor: Any?

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
        // `.statusBar` level stays visible across Full-Screen Spaces while remaining below NSMenu popups (level 101)
        panel.level = .statusBar
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
                self?.realignToCurrentScreen()
            }
        }

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleActiveWorkspaceChanged()
            }
        }

        wsCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.realignToCurrentScreen()
                self?.handleActiveWorkspaceChanged()
            }
        }
    }

    deinit {
        mousePollTimer?.invalidate()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func show() {
        panel.orderFrontRegardless()
        startDynamicHitTesting()
    }

    private func realignToCurrentScreen() {
        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
        guard let screen = activeScreen else { return }
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
            scene.size = screen.frame.size
        }
        panel.orderFrontRegardless()
    }

    private func handleActiveWorkspaceChanged() {
        panel.orderFrontRegardless()
        scene.handleWorkspaceNotification()
        syncPointerState()
    }

    private func applyInteractionMode(_ mode: AppInteractionMode) {
        switch mode {
        case .companion:
            panel.allowKeyFocus = false
            panel.resignKey()
            syncPointerState()

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
        // 60 Hz lightweight rect check eliminates any pass-through race before quick right-clicks!
        mousePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncPointerState()
            }
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncPointerState()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.syncPointerState()
            return event
        }
    }

    private func scenePointForGlobalMouse(_ globalPoint: CGPoint) -> CGPoint {
        let winPt = panel.convertPoint(fromScreen: globalPoint)
        let viewPt = skView.convert(winPt, from: nil)
        return scene.convertPoint(fromView: viewPt)
    }

    private func syncPointerState() {
        if scene.mode == .tennis {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            return
        }

        let scenePt = scenePointForGlobalMouse(NSEvent.mouseLocation)
        let shouldCapture = scene.updatePointerCaptureAndHover(atScenePoint: scenePt)
        if panel.ignoresMouseEvents == shouldCapture {
            panel.ignoresMouseEvents = !shouldCapture
        }
    }
}
