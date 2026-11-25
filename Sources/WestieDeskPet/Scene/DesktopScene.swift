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
    private var snapshotTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var isDraggingDog = false
    private var lastAppliedFPS: Int = 30

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
            companion.placeInitially(on: snap.platforms, sceneSize: size)
        }
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        tennis.layout(in: size)
    }

    public func switchToMode(_ target: AppInteractionMode) {
        guard mode != target else { return }
        mode = target
        switch target {
        case .tennis:
            isDraggingDog = false
            companion.rootNode.isHidden = true
            tennis.startMatch(in: size)
            applyPreferredFPS(60)
        case .companion:
            tennis.stopMatch()
            companion.rootNode.isHidden = false
            refreshWindowSnapshot()
            if let snap = latestSnapshot {
                companion.summonToFrontWindow(snapshot: snap)
            }
            applyPreferredFPS(30)
        }
    }

    public func summonDogToActiveWindow() {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.summonToFrontWindow(snapshot: snap)
        }
    }

    public func feedBoneTreat() {
        if mode == .tennis { return }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.dropBoneTreat(snapshot: snap)
            applyPreferredFPS(60)
        }
    }

    public func triggerDogTennisInvite() {
        if mode == .tennis { return }
        companion.triggerTennisInvite()
    }

    /// Used by `OverlayWindow` to dynamically toggle `ignoresMouseEvents` in Companion Mode!
    public func shouldCaptureMouse(at globalScreenPoint: CGPoint, windowFrame: CGRect) -> Bool {
        if mode == .tennis || isDraggingDog {
            return true
        }
        let localPoint = CGPoint(
            x: globalScreenPoint.x - windowFrame.minX,
            y: globalScreenPoint.y - windowFrame.minY
        )
        return companion.interactiveHitRect().contains(localPoint)
    }

    public func notifyGlobalHover(at globalScreenPoint: CGPoint, windowFrame: CGRect) {
        guard mode == .companion, !isDraggingDog else { return }
        let localPoint = CGPoint(
            x: globalScreenPoint.x - windowFrame.minX,
            y: globalScreenPoint.y - windowFrame.minY
        )
        if companion.interactiveHitRect().contains(localPoint) {
            companion.handleHoverStroke(at: localPoint)
            applyPreferredFPS(60)
        }
    }

    // MARK: - SpriteKit Update Loop

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
            snapshotTimer -= dt
            if snapshotTimer <= 0 {
                // Poll window positions at ~8 Hz: responsive to drags while practically 0% CPU!
                snapshotTimer = 0.125
                refreshWindowSnapshot()
            }
            if let snap = latestSnapshot {
                companion.update(dt: dt, snapshot: snap, sceneSize: size)
            }
            applyPreferredFPS(companion.isNeedingHighFPS ? 60 : 18)

        case .tennis:
            tennis.update(dt: dt)
            applyPreferredFPS(60)
        }
    }

    private func refreshWindowSnapshot() {
        guard let screen = view?.window?.screen ?? NSScreen.main else { return }
        latestSnapshot = windowTracker.captureSnapshot(for: screen)
    }

    private func applyPreferredFPS(_ fps: Int) {
        guard fps != lastAppliedFPS else { return }
        lastAppliedFPS = fps
        view?.preferredFramesPerSecond = fps
        onPreferredFPSChanged?(fps)
    }

    // MARK: - Mouse & Keyboard Events

    public override func mouseMoved(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else {
            companion.handleHoverStroke(at: pt)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseDown(scenePoint: pt)
        } else {
            if companion.handleMouseDown(at: pt) {
                if case .dragged = companion.state {
                    isDraggingDog = true
                    applyPreferredFPS(60)
                }
            }
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else if isDraggingDog {
            companion.handleMouseDragged(to: pt)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseUp(scenePoint: pt)
        } else if isDraggingDog {
            isDraggingDog = false
            companion.handleMouseUp(at: pt)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleRightMouseDown(scenePoint: pt)
        } else if companion.interactiveHitRect().contains(pt) {
            presentDogQuickMenu(with: event)
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

    private func presentDogQuickMenu(with event: NSEvent) {
        guard let view = self.view else { return }
        let menu = NSMenu(title: "西高地")

        let tennisItem = NSMenuItem(title: "🎾 开始打网球 (WASD + 鼠标)", action: #selector(ctxStartTennis), keyEquivalent: "")
        tennisItem.target = self
        menu.addItem(tennisItem)

        let treatItem = NSMenuItem(title: "🦴 喂一根骨头饼干", action: #selector(ctxFeedTreat), keyEquivalent: "")
        treatItem.target = self
        menu.addItem(treatItem)

        let sleepTitle = companion.forceQuietSleep ? "☀️ 叫醒小狗" : "💤 安静趴睡模式"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(ctxToggleSleep), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func ctxStartTennis() {
        switchToMode(.tennis)
    }

    @objc private func ctxFeedTreat() {
        feedBoneTreat()
    }

    @objc private func ctxToggleSleep() {
        companion.forceQuietSleep.toggle()
    }
}
