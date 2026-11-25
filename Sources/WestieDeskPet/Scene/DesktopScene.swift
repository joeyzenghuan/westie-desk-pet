import AppKit
import SpriteKit

public enum AppInteractionMode: Equatable, Sendable {
    case companion
    case tennis
}

@MainActor
public final class DesktopScene: SKScene {
    public let companion = CompanionController()
    public let tennis = TennisMatchController()

    public private(set) var mode: AppInteractionMode = .companion {
        didSet {
            onModeChanged?(mode)
        }
    }

    public var onModeChanged: ((AppInteractionMode) -> Void)?
    public var onPreferredFPSChanged: ((Int) -> Void)?

    private let windowTracker = WindowPlatformTracker()
    private var latestSnapshot: ActiveWorkspaceSnapshot?
    private var fullSnapshotTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0

    public override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill

        addChild(companion.rootNode)
        addChild(tennis.rootNode)

        companion.onRequestStartTennis = { [weak self] in
            self?.switchToMode(.tennis)
        }
        tennis.onRequestExitTennis = { [weak self] in
            self?.switchToMode(.companion)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.placeInitially(snapshot: snap, sceneSize: size)
        }
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        tennis.layout(in: size)
        refreshWindowSnapshot()
    }

    public func handleWorkspaceNotification() {
        guard mode == .companion else { return }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.update(dt: 1.0 / 60.0, snapshot: snap, sceneSize: size)
        }
    }

    public func switchToMode(_ target: AppInteractionMode) {
        guard mode != target else { return }
        mode = target
        switch target {
        case .tennis:
            companion.setHovering(false)
            companion.rootNode.isHidden = true
            tennis.startMatch(in: size)
        case .companion:
            tennis.stopMatch()
            companion.rootNode.isHidden = false
            refreshWindowSnapshot()
            if let snap = latestSnapshot {
                companion.summonToFrontWindow(snapshot: snap, sceneSize: size)
            }
        }
    }

    public func summonDogToActiveWindow() {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.summonToFrontWindow(snapshot: snap, sceneSize: size)
        }
    }

    public func moveDogToZone(_ zone: PerchZone) {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.moveImmediatelyToZone(zone, snapshot: snap, sceneSize: size)
        }
    }

    public func feedBoneTreat() {
        if mode == .tennis { return }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.dropBoneTreat(snapshot: snap, sceneSize: size)
        }
    }

    public func triggerDogTennisInvite() {
        if mode == .tennis { return }
        companion.triggerTennisInvite()
    }

    public var isActivelyInteractingWithDog: Bool {
        if companion.isPointerDownOnDog { return true }
        if case .dragged = companion.state { return true }
        return false
    }

    /// Updates continuous hover & returns whether `OverlayWindow` should capture mouse events at `scenePoint`.
    public func updatePointerCaptureAndHover(atScenePoint scenePoint: CGPoint) -> Bool {
        if mode == .tennis || isActivelyInteractingWithDog {
            return true
        }
        // Extra 6pt outer cushion ensures fast clicks/right-clicks never miss!
        let captureRect = companion.interactiveHitRect().insetBy(dx: -6, dy: -6)
        let inside = captureRect.contains(scenePoint)
        companion.setHovering(inside)
        return inside
    }

    /// Native macOS cursor matching current hover/grab state.
    public func desiredCursor(atScenePoint scenePoint: CGPoint) -> NSCursor {
        if mode == .tennis {
            return .arrow
        }
        if isActivelyInteractingWithDog {
            return .closedHand
        }
        if companion.isPointOnInviteBadge(scenePoint) {
            return .pointingHand
        }
        if companion.isHoveringDog {
            return .openHand
        }
        return .arrow
    }

    // MARK: - SpriteKit Update Loop (60Hz / 120Hz ProMotion Locked)

    public override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(max(currentTime - lastUpdateTime, 0.001), 0.1)
        }
        lastUpdateTime = currentTime

        switch mode {
        case .companion:
            fullSnapshotTimer -= dt
            if fullSnapshotTimer <= 0 || latestSnapshot == nil {
                // Full frontmost window discovery (~6 Hz)
                fullSnapshotTimer = 0.16
                refreshWindowSnapshot()
            } else {
                // O(1) single-window query every frame (60/120Hz) for zero-lag window drag follow!
                fastRefreshCurrentActiveWindow()
            }
            if let snap = latestSnapshot {
                companion.update(dt: dt, snapshot: snap, sceneSize: size)
            }

        case .tennis:
            tennis.update(dt: dt)
        }
    }

    private func refreshWindowSnapshot() {
        guard let screen = view?.window?.screen ?? NSScreen.main else { return }
        latestSnapshot = windowTracker.captureSnapshot(for: screen)
    }

    private func fastRefreshCurrentActiveWindow() {
        guard let prev = latestSnapshot,
              let screen = view?.window?.screen ?? NSScreen.main
        else { return }
        latestSnapshot = windowTracker.fastRefreshActiveWindow(in: prev, for: screen)
    }

    // MARK: - Mouse & Keyboard Events

    public override func mouseMoved(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else {
            companion.setHovering(companion.interactiveHitRect().insetBy(dx: -6, dy: -6).contains(pt))
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseDown(scenePoint: pt)
        } else {
            _ = companion.handleMouseDown(at: pt)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else if isActivelyInteractingWithDog {
            companion.handleMouseDragged(to: pt)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseUp(scenePoint: pt)
        } else if isActivelyInteractingWithDog {
            refreshWindowSnapshot()
            companion.handleMouseUp(at: pt, snapshot: latestSnapshot, sceneSize: size)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleRightMouseDown(scenePoint: pt)
        } else if let view = self.view {
            let menu = buildDogContextMenu()
            let viewPt = view.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: viewPt, in: view)
        }
    }

    public override func keyDown(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleKeyDown(event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleKeyUp(event)
        }
    }

    // MARK: - Rich Context Menu on Westie

    public func buildDogContextMenu() -> NSMenu {
        let menu = NSMenu(title: "西高地")

        let tennisItem = NSMenuItem(title: "🎾 开始打网球 (WASD + 鼠标)", action: #selector(ctxStartTennis), keyEquivalent: "")
        tennisItem.target = self
        menu.addItem(tennisItem)

        menu.addItem(.separator())

        let moveTopItem = NSMenuItem(title: "📍 移到当前窗口正上方", action: #selector(ctxMoveWindowTop), keyEquivalent: "")
        moveTopItem.target = self
        menu.addItem(moveTopItem)

        let moveRightItem = NSMenuItem(title: "👀 移到右侧探头", action: #selector(ctxMoveRightPeek), keyEquivalent: "")
        moveRightItem.target = self
        menu.addItem(moveRightItem)

        let prefSubmenu = NSMenu(title: "位置偏好")
        for pref in PerchPreference.allCases {
            let item = NSMenuItem(title: pref.rawValue, action: #selector(ctxSelectPerchPreference(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pref.rawValue
            item.state = (companion.perchPreference == pref) ? .on : .off
            prefSubmenu.addItem(item)
        }
        let prefParent = NSMenuItem(title: "🧭 陪伴位置偏好", action: nil, keyEquivalent: "")
        prefParent.submenu = prefSubmenu
        menu.addItem(prefParent)

        menu.addItem(.separator())

        let speedSubmenu = NSMenu(title: "网球球速")
        for spd in TennisGameSpeed.allCases {
            let suffix = (spd == .slow) ? " (默认)" : ""
            let item = NSMenuItem(title: "\(spd.displayName)\(suffix)", action: #selector(ctxSelectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spd.rawValue
            item.state = (tennis.gameSpeed == spd) ? .on : .off
            speedSubmenu.addItem(item)
        }
        let speedParent = NSMenuItem(title: "⏱ 网球球速: \(tennis.gameSpeed.rawValue)", action: nil, keyEquivalent: "")
        speedParent.submenu = speedSubmenu
        menu.addItem(speedParent)

        menu.addItem(.separator())

        let treatItem = NSMenuItem(title: "🦴 喂一根骨头饼干", action: #selector(ctxFeedTreat), keyEquivalent: "")
        treatItem.target = self
        menu.addItem(treatItem)

        let sleepTitle = companion.forceQuietSleep ? "☀️ 取消固定趴睡" : "💤 安静趴睡模式"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(ctxToggleSleep), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Westie Desk Pet", action: #selector(ctxQuitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func ctxStartTennis() {
        switchToMode(.tennis)
    }

    @objc private func ctxMoveWindowTop() {
        companion.perchPreference = .auto
        moveDogToZone(.windowTop)
    }

    @objc private func ctxMoveRightPeek() {
        refreshWindowSnapshot()
        if latestSnapshot?.perchLayout.isFullScreenMode == true {
            moveDogToZone(.screenRightPeek)
        } else {
            moveDogToZone(.windowRightPeek)
        }
    }

    @objc private func ctxSelectPerchPreference(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pref = PerchPreference(rawValue: raw)
        else { return }
        companion.perchPreference = pref
        summonDogToActiveWindow()
    }

    @objc private func ctxSelectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let spd = TennisGameSpeed(rawValue: raw)
        else { return }
        tennis.gameSpeed = spd
    }

    @objc private func ctxFeedTreat() {
        feedBoneTreat()
    }

    @objc private func ctxToggleSleep() {
        companion.forceQuietSleep.toggle()
    }

    @objc private func ctxQuitApp() {
        NSApp.terminate(nil)
    }
}
