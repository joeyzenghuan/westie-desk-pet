import AppKit
import CoreGraphics
import OSLog
import SpriteKit

private let inputLogger = Logger(subsystem: "com.joeyzenghuan.westie-desk-pet", category: "input")

@MainActor
public final class InteractiveSKView: SKView {
    public var desiredCursor: NSCursor = .arrow {
        didSet {
            guard desiredCursor !== oldValue else { return }
            window?.invalidateCursorRects(for: self)
            desiredCursor.set()
        }
    }

    public var onRequestCompanionContextMenu: ((NSEvent) -> Void)?

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

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard let desktopScene = scene as? DesktopScene, desktopScene.mode == .companion else {
            return nil
        }
        desktopScene.companion.prepareForContextMenu()
        return desktopScene.buildDogContextMenu()
    }

    public override func mouseDown(with event: NSEvent) {
        if let desktopScene = scene as? DesktopScene,
           desktopScene.mode == .companion,
           event.modifierFlags.contains(.control)
        {
            onRequestCompanionContextMenu?(event)
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
            onRequestCompanionContextMenu?(event)
            return
        }
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
    public var onRightMouseDownEvent: ((NSEvent) -> Bool)?

    public override var canBecomeKey: Bool { allowKeyFocus }
    public override var canBecomeMain: Bool { false }

    public override func sendEvent(_ event: NSEvent) {
        let isContextTrigger = (event.type == .rightMouseDown)
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if isContextTrigger {
            inputLogger.notice("OverlayPanel.sendEvent contextTrigger type=\(event.type.rawValue, privacy: .public) loc=\(event.locationInWindow.x, privacy: .public),\(event.locationInWindow.y, privacy: .public)")
            if onRightMouseDownEvent?(event) == true {
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
public final class OverlayWindowController {
    public let panel: OverlayPanel
    public let skView: InteractiveSKView
    public let scene: DesktopScene

    private nonisolated(unsafe) var mousePollTimer: Timer?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private nonisolated(unsafe) var localMouseMonitor: Any?
    private var lastContextMenuPopTime: TimeInterval = 0
    private var wasHardwareRightButtonDown: Bool = false
    private var pendingHardwareRightClickOnDog: Bool = false
    private var hardwareRightClickStartTime: TimeInterval = 0

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
        scene.targetScreen = screen
        panel.contentView = skView
        skView.presentScene(scene)

        panel.onRightMouseDownEvent = { [weak self] event in
            guard let self, self.scene.mode == .companion else { return false }
            self.presentCompanionContextMenu(with: event, source: "panel.sendEvent")
            return true
        }

        skView.onRequestCompanionContextMenu = { [weak self] event in
            self?.presentCompanionContextMenu(with: event, source: "skView")
        }

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
        ) { [weak self] notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            let ownPID = ProcessInfo.processInfo.processIdentifier
            guard activatedPID != ownPID else { return }
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
        scene.targetScreen = screen
        let targetFPS = max(60, screen.maximumFramesPerSecond)
        if skView.preferredFramesPerSecond != targetFPS {
            skView.preferredFramesPerSecond = targetFPS
        }
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
            skView.frame = NSRect(origin: .zero, size: screen.frame.size)
            scene.size = screen.frame.size
        }
        panel.orderFrontRegardless()
    }

    private func handleActiveWorkspaceChanged() {
        realignToCurrentScreen()
        panel.orderFrontRegardless()
        scene.handleWorkspaceNotification()
        syncPointerState()
    }

    private var isContextMenuOpen: Bool = false

    public func presentCompanionContextMenu(with triggeringEvent: NSEvent? = nil, source: String = "unknown") {
        guard scene.mode == .companion, !isContextMenuOpen else {
            inputLogger.notice("presentCompanionContextMenu skipped source=\(source, privacy: .public) open=\(self.isContextMenuOpen, privacy: .public)")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastContextMenuPopTime > 0.22 else { return }
        lastContextMenuPopTime = now
        isContextMenuOpen = true
        pendingHardwareRightClickOnDog = false

        let screenMouse = NSEvent.mouseLocation
        inputLogger.notice("presentCompanionContextMenu OPEN source=\(source, privacy: .public) mouse=\(screenMouse.x, privacy: .public),\(screenMouse.y, privacy: .public) panelFrame=\(self.panel.frame.origin.x, privacy: .public),\(self.panel.frame.origin.y, privacy: .public),\(self.panel.frame.width, privacy: .public),\(self.panel.frame.height, privacy: .public)")

        scene.companion.prepareForContextMenu()
        let menu = scene.buildDogContextMenu()

        let t0 = ProcessInfo.processInfo.systemUptime
        if let triggeringEvent, triggeringEvent.window === panel {
            NSMenu.popUpContextMenu(menu, with: triggeringEvent, for: skView)
        } else {
            // Hardware release-edge or global monitor fallback: right button is already up or outside our window,
            // so screen-coordinate `popUp(positioning:at:in:nil)` pops cleanly on ANY monitor without needing focus!
            _ = menu.popUp(positioning: nil, at: screenMouse, in: nil)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        inputLogger.notice("presentCompanionContextMenu CLOSED source=\(source, privacy: .public) openDuration=\(elapsed, privacy: .public)s")

        isContextMenuOpen = false
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
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            let isRightUp = (event.type == .rightMouseUp)
            let isRightDown = (event.type == .rightMouseDown)
            Task { @MainActor in
                guard let self else { return }
                self.syncPointerState()
                if isRightDown {
                    let mouse = NSEvent.mouseLocation
                    let scenePt = self.scenePointForGlobalMouse(mouse)
                    let hr = self.scene.companion.interactiveHitRect()
                    let over = self.scene.isPointOverDogForContextMenu(scenePt)
                    inputLogger.notice("globalMonitor rightMouseDown overDog=\(over, privacy: .public) ignoresMouse=\(self.panel.ignoresMouseEvents, privacy: .public) mouse=(\(mouse.x, privacy: .public),\(mouse.y, privacy: .public)) scenePt=(\(scenePt.x, privacy: .public),\(scenePt.y, privacy: .public)) hitRect=(\(hr.minX, privacy: .public),\(hr.minY, privacy: .public),\(hr.width, privacy: .public),\(hr.height, privacy: .public)) zone=\(self.scene.companion.perchZone.rawValue, privacy: .public) panel=(\(self.panel.frame.minX, privacy: .public),\(self.panel.frame.minY, privacy: .public),\(self.panel.frame.width, privacy: .public),\(self.panel.frame.height, privacy: .public))")
                    if over {
                        self.pendingHardwareRightClickOnDog = true
                        self.hardwareRightClickStartTime = ProcessInfo.processInfo.systemUptime
                    }
                } else if isRightUp && self.pendingHardwareRightClickOnDog {
                    let scenePt = self.scenePointForGlobalMouse(NSEvent.mouseLocation)
                    if self.scene.isPointOverDogForContextMenu(scenePt) {
                        self.presentCompanionContextMenu(with: nil, source: "globalMonitor.rightUp")
                    }
                    self.pendingHardwareRightClickOnDog = false
                }
            }
        }

        // Note: Do NOT intercept `.rightMouseDown` here — let `InteractiveSKView.rightMouseDown` handle it cleanly
        // (calling NSMenu.popUp synchronously inside a local event monitor is dropped by AppKit!).
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
        if isContextMenuOpen {
            return
        }
        if scene.mode == .tennis {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            return
        }

        let globalMouse = NSEvent.mouseLocation
        let scenePt = scenePointForGlobalMouse(globalMouse)
        let shouldCapture = scene.updatePointerCaptureAndHover(atScenePoint: scenePt)
        if panel.ignoresMouseEvents == shouldCapture {
            panel.ignoresMouseEvents = !shouldCapture
            inputLogger.notice("ignoresMouseEvents -> \(!shouldCapture, privacy: .public) scenePt=\(scenePt.x, privacy: .public),\(scenePt.y, privacy: .public)")
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

        // Zero-permission 60Hz hardware right-button detector:
        // If AppKit fails to route `.rightMouseDown` to our `.nonactivatingPanel` for any reason,
        // catch the press while hovering Westie and pop the menu cleanly on button release!
        let isRightDown = ((NSEvent.pressedMouseButtons & (1 << 1)) != 0)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
        if isRightDown && !wasHardwareRightButtonDown {
            if shouldCapture || scene.isPointOverDogForContextMenu(scenePt) {
                pendingHardwareRightClickOnDog = true
                hardwareRightClickStartTime = ProcessInfo.processInfo.systemUptime
                inputLogger.notice("hwRightButton DOWN overDog=true scenePt=\(scenePt.x, privacy: .public),\(scenePt.y, privacy: .public)")
            }
        } else if !isRightDown && wasHardwareRightButtonDown {
            if pendingHardwareRightClickOnDog {
                let held = ProcessInfo.processInfo.systemUptime - hardwareRightClickStartTime
                pendingHardwareRightClickOnDog = false
                if held <= 0.8 && (shouldCapture || scene.isPointOverDogForContextMenu(scenePt)) {
                    presentCompanionContextMenu(with: nil, source: "hwRightButton.release")
                }
            }
        }
        wasHardwareRightButtonDown = isRightDown
    }
}
