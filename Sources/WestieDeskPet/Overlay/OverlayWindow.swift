import AppKit
import SpriteKit

@MainActor
public final class InteractiveSKView: SKView {
    public var desiredCursor: NSCursor = .arrow {
        didSet {
            guard desiredCursor !== oldValue else { return }
            window?.invalidateCursorRects(for: self)
            desiredCursor.set()
        }
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: desiredCursor)
    }

    public override func cursorUpdate(with event: NSEvent) {
        desiredCursor.set()
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
        if let desktopScene = scene as? DesktopScene {
            let pt = event.location(in: desktopScene)
            desiredCursor = desktopScene.desiredCursor(atScenePoint: pt)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if let desktopScene = scene as? DesktopScene {
            let pt = event.location(in: desktopScene)
            desiredCursor = desktopScene.desiredCursor(atScenePoint: pt)
        }
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
        // Lock to native display refresh rate (120Hz ProMotion / 60Hz external) without runtime FPS-switch hitches!
        skView.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
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
            MainActor.assumeIsolated {
                self?.realignToCurrentScreen()
            }
        }

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleActiveWorkspaceChanged()
            }
        }

        wsCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
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
        let targetFPS = max(60, screen.maximumFramesPerSecond)
        if skView.preferredFramesPerSecond != targetFPS {
            skView.preferredFramesPerSecond = targetFPS
        }
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
            skView.desiredCursor = .arrow
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(skView)
        }
    }

    private func startDynamicHitTesting() {
        mousePollTimer?.invalidate()
        // Scheduled in `.common` RunLoop mode so pointer & cursor tracking stay silky even while dragging windows!
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncPointerState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mousePollTimer = timer

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncPointerState()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.syncPointerState()
            }
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
            if !shouldCapture {
                // Reset cursor once upon leaving Westie so underlying apps control their own cursors cleanly
                skView.desiredCursor = .arrow
                NSCursor.arrow.set()
            }
        }
        if shouldCapture {
            let nextCursor = scene.desiredCursor(atScenePoint: scenePt)
            if skView.desiredCursor !== nextCursor {
                skView.desiredCursor = nextCursor
            } else {
                nextCursor.set()
            }
        }
    }
}
