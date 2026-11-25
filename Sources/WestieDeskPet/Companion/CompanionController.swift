import AppKit
import SpriteKit

@MainActor
public final class CompanionController {
    public let rootNode = SKNode()

    private let cropNode = SKCropNode()
    private let cropMaskNode: SKSpriteNode
    private let dogSprite: SKSpriteNode
    private let shadowNode: SKShapeNode
    private let inviteBadgeNode: SKNode
    private var treatNode: SKSpriteNode?

    public private(set) var perchZone: PerchZone = .windowTop
    public private(set) var currentPlatform: WindowPlatform?
    public private(set) var currentRightAnchor: RightEdgeAnchor?
    public private(set) var state: CompanionBehaviorState = .idle(remaining: 4.0)

    public var perchPreference: PerchPreference = .auto {
        didSet {
            UserDefaults.standard.set(perchPreference.rawValue, forKey: "westie.companion.perchPreference")
        }
    }

    public var forceQuietSleep: Bool = false {
        didSet {
            if forceQuietSleep {
                if perchZone == .windowTop {
                    state = .sleeping(remaining: 35.0)
                }
            } else if case .sleeping = state {
                state = .loafing(remaining: 8.0)
            }
        }
    }

    public var onRequestStartTennis: (() -> Void)?

    private var position: CGPoint = CGPoint(x: 520, y: 420)
    private var facingDirection: CGFloat = 1.0
    private var walkAnimTimer: TimeInterval = 0
    private var walkFrameToggle: Bool = false
    private var breathPhase: CGFloat = 0
    private var hoverWavePhase: CGFloat = 0

    // Hover tracking (smooth, silent, non-intrusive)
    private var isHoveringDog: Bool = false
    private var peekHoverProgress: CGFloat = 0.0

    // Active window & edge offset tracking
    private var trackedWindowID: UInt32 = 0
    private var offsetFromWindowMinX: CGFloat = 240
    private var offsetFromWindowMaxY: CGFloat = 68
    private var screenRightCustomYRatio: CGFloat = 0.66
    private var zoneStayTimer: TimeInterval = 0

    // Focus timer -> gently hold tennis ball after 25 minutes of work
    private var focusAccumulator: TimeInterval = 0
    private let focusInviteInterval: TimeInterval = 25 * 60

    private let topDogSize = CGSize(width: 66, height: 66)
    private let peekDogSize = CGSize(width: 76, height: 76)

    public var isNeedingHighFPS: Bool {
        state.isHighFrameRateNeeded
            || treatNode != nil
            || isHoveringDog
            || (peekHoverProgress > 0.01 && peekHoverProgress < 0.99)
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: "westie.companion.perchPreference"),
           let pref = PerchPreference(rawValue: saved)
        {
            self.perchPreference = pref
        }

        shadowNode = SKShapeNode(ellipseOf: CGSize(width: 42, height: 9))
        shadowNode.fillColor = NSColor(calibratedWhite: 0.0, alpha: 0.20)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = 1

        cropMaskNode = SKSpriteNode(color: .white, size: CGSize(width: 4096, height: 4096))
        cropMaskNode.anchorPoint = CGPoint(x: 0.0, y: 0.5)

        dogSprite = SKSpriteNode(
            texture: SpriteBank.shared.texture(for: .westieIdle),
            color: .clear,
            size: topDogSize
        )
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        dogSprite.zPosition = 3

        inviteBadgeNode = CompanionController.buildInviteBadge()
        inviteBadgeNode.position = CGPoint(x: 0, y: 78)
        inviteBadgeNode.zPosition = 10
        inviteBadgeNode.isHidden = true

        rootNode.addChild(shadowNode)
        cropNode.zPosition = 3
        cropNode.addChild(dogSprite)
        rootNode.addChild(cropNode)
        rootNode.addChild(inviteBadgeNode)
    }

    private static func buildInviteBadge() -> SKNode {
        let container = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: 118, height: 28), cornerRadius: 9)
        bg.fillColor = NSColor(calibratedRed: 0.11, green: 0.38, blue: 0.24, alpha: 0.94)
        bg.strokeColor = NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.30, alpha: 0.95)
        bg.lineWidth = 1.5
        container.addChild(bg)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "🎾 来打网球!"
        label.fontSize = 12
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        container.addChild(label)
        return container
    }

    public func placeInitially(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        } else if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else if let top = layout.topPerch {
            let startX = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            landOnWindowTop(top, atX: startX)
        } else if let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        }
        syncVisuals(dt: 0)
    }

    /// Interactive hitbox in scene coordinates — padded generously around Westie without blocking window content!
    public func interactiveHitRect() -> CGRect {
        var rect: CGRect
        if case .dragged = state {
            rect = CGRect(x: position.x - 48, y: position.y - 20, width: 96, height: 96)
        } else {
            switch perchZone {
            case .windowTop:
                rect = CGRect(
                    x: position.x - 44,
                    y: position.y - 8,
                    width: 88,
                    height: 80
                )
            case .screenRightPeek:
                // Peeking leftward from right screen edge (`position.x == screenWidth`)
                rect = CGRect(
                    x: position.x - 58,
                    y: position.y - 46,
                    width: 62,
                    height: 92
                )
            case .windowRightPeek:
                // Peeking rightward from active window's right border (`position.x == windowMaxX`)
                // Starts at `position.x - 2` so we never block the window's inner scrollbar!
                rect = CGRect(
                    x: position.x - 2,
                    y: position.y - 46,
                    width: 58,
                    height: 92
                )
            }
        }

        if !inviteBadgeNode.isHidden {
            let badgePos = inviteBadgeNode.position
            let badgeRect = CGRect(
                x: badgePos.x - 66,
                y: badgePos.y - 20,
                width: 132,
                height: 40
            )
            rect = rect.union(badgeRect)
        }
        return rect
    }

    public func isPointOnInviteBadge(_ scenePoint: CGPoint) -> Bool {
        guard !inviteBadgeNode.isHidden else { return false }
        let badgePos = inviteBadgeNode.position
        let badgeRect = CGRect(
            x: badgePos.x - 66,
            y: badgePos.y - 20,
            width: 132,
            height: 40
        )
        return badgeRect.contains(scenePoint)
    }

    // MARK: - User & Menu Actions

    public func triggerTennisInvite() {
        state = .holdingTennisBall(remaining: 25.0)
    }

    public func summonToFrontWindow(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        treatNode?.removeFromParent()
        treatNode = nil

        if layout.isFullScreenMode {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            return
        }
        if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else if let top = layout.topPerch {
            let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            landOnWindowTop(top, atX: x)
            state = .sitCalm(remaining: 5.0)
        } else if let right = layout.windowRightPeek {
            trackedWindowID = layout.activeWindowID ?? 0
            snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY)
        } else {
            snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
        }
    }

    public func moveImmediatelyToZone(_ targetZone: PerchZone, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        switch targetZone {
        case .windowTop:
            if let top = layout.topPerch {
                let x = top.clampedX(top.minX + top.width * 0.62, margin: 22)
                beginSmoothGlide(to: CGPoint(x: x, y: top.y), targetZone: .windowTop, layout: layout)
            }
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                beginSmoothGlide(to: CGPoint(x: right.edgeX, y: right.defaultY), targetZone: .windowRightPeek, layout: layout)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }
        case .screenRightPeek:
            let y = layout.screenRightPeek.clampedY(sceneSize.height * screenRightCustomYRatio)
            beginSmoothGlide(to: CGPoint(x: layout.screenRightPeek.edgeX, y: y), targetZone: .screenRightPeek, layout: layout)
        }
    }

    public func dropBoneTreat(snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let layout = snapshot.perchLayout
        guard let top = layout.topPerch else {
            // In fullscreen / right-peek mode, give a quick happy peek wave without cluttering screen
            peekHoverProgress = 1.0
            return
        }

        if perchZone != .windowTop || trackedWindowID != layout.activeWindowID {
            let startX = top.clampedX(top.minX + top.width * 0.62, margin: 24)
            landOnWindowTop(top, atX: startX)
        }

        treatNode?.removeFromParent()
        let treatX: CGFloat
        if top.width > 140 {
            let candidate = (position.x < top.midX) ? min(top.maxX - 28, position.x + 110) : max(top.minX + 28, position.x - 110)
            treatX = top.clampedX(candidate, margin: 24)
        } else {
            treatX = top.midX
        }

        let node = SKSpriteNode(texture: SpriteBank.shared.texture(for: .boneTreat))
        node.size = CGSize(width: 26, height: 26)
        node.position = CGPoint(x: treatX, y: top.y + 13)
        node.zPosition = 2
        rootNode.addChild(node)
        node.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 10, duration: 0.11),
            SKAction.moveBy(x: 0, y: -10, duration: 0.13)
        ]))
        treatNode = node
        state = .chasingTreat(treatX: treatX)
    }

    /// Updates continuous hover state without intrusive hearts or shaking!
    public func setHovering(_ hovering: Bool) {
        guard isHoveringDog != hovering else { return }
        isHoveringDog = hovering
    }

    public func handleMouseDown(at scenePoint: CGPoint) -> Bool {
        if isPointOnInviteBadge(scenePoint) {
            onRequestStartTennis?()
            return true
        }
        if case .holdingTennisBall = state, interactiveHitRect().contains(scenePoint) {
            onRequestStartTennis?()
            return true
        }
        guard interactiveHitRect().contains(scenePoint) else { return false }
        state = .dragged
        treatNode?.removeFromParent()
        treatNode = nil
        position = CGPoint(x: scenePoint.x, y: scenePoint.y - 24)
        return true
    }

    public func handleMouseDragged(to scenePoint: CGPoint) {
        guard case .dragged = state else { return }
        let dx = scenePoint.x - position.x
        if abs(dx) > 1.5 {
            facingDirection = dx > 0 ? 1.0 : -1.0
        }
        position = CGPoint(x: scenePoint.x, y: scenePoint.y - 24)
    }

    public func handleMouseUp(at scenePoint: CGPoint, snapshot: ActiveWorkspaceSnapshot?, sceneSize: CGSize) {
        guard case .dragged = state else { return }
        guard let layout = snapshot?.perchLayout else {
            state = .idle(remaining: 5.0)
            return
        }

        // Snap cleanly to whichever valid perch is closest to where the user dropped Westie!
        if layout.isFullScreenMode {
            let anchor = layout.screenRightPeek
            let clampedY = anchor.clampedY(scenePoint.y)
            if sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(clampedY / sceneSize.height, 0.15), 0.88)
            }
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: clampedY), targetZone: .screenRightPeek, layout: layout)
            return
        }

        // Check distance to screen right edge, active window right edge, and active window top edge
        var candidates: [(dist: CGFloat, point: CGPoint, zone: PerchZone)] = []

        if let top = layout.topPerch {
            let targetX = top.clampedX(scenePoint.x, margin: 20)
            let pt = CGPoint(x: targetX, y: top.y)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowTop))
        }
        if let right = layout.windowRightPeek {
            let targetY = right.clampedY(scenePoint.y)
            let pt = CGPoint(x: right.edgeX, y: targetY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .windowRightPeek))
        }
        if scenePoint.x >= sceneSize.width - 72 {
            let anchor = layout.screenRightPeek
            let clampedY = anchor.clampedY(scenePoint.y)
            if sceneSize.height > 100 {
                screenRightCustomYRatio = min(max(clampedY / sceneSize.height, 0.15), 0.88)
            }
            let pt = CGPoint(x: anchor.edgeX, y: clampedY)
            candidates.append((hypot(scenePoint.x - pt.x, scenePoint.y - pt.y), pt, .screenRightPeek))
        }

        if let best = candidates.min(by: { $0.dist < $1.dist }) {
            if best.zone == .windowRightPeek, let winMaxY = layout.activeWindowFrame?.maxY {
                offsetFromWindowMaxY = max(42, winMaxY - best.point.y)
            }
            beginSmoothGlide(to: best.point, targetZone: best.zone, layout: layout)
        } else {
            let anchor = layout.screenRightPeek
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: anchor.defaultY), targetZone: .screenRightPeek, layout: layout)
        }
    }

    // MARK: - Frame Update

    public func update(dt: TimeInterval, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let clampedDt = min(max(dt, 0.001), 0.08)
        breathPhase += CGFloat(clampedDt) * 2.2
        zoneStayTimer += clampedDt

        // Smooth peek slide animation on hover (0 -> 1 in ~0.16s, 1 -> 0 in ~0.22s)
        let targetHover: CGFloat = isHoveringDog ? 1.0 : 0.0
        if peekHoverProgress < targetHover {
            peekHoverProgress = min(1.0, peekHoverProgress + CGFloat(clampedDt) * 6.2)
        } else if peekHoverProgress > targetHover {
            peekHoverProgress = max(0.0, peekHoverProgress - CGFloat(clampedDt) * 4.5)
        }
        if peekHoverProgress > 0.05 {
            hoverWavePhase += CGFloat(clampedDt)
        } else {
            hoverWavePhase = 0
        }

        if !snapshot.isMeetingActive && !forceQuietSleep {
            focusAccumulator += clampedDt
        }

        let layout = snapshot.perchLayout
        reconcileWithActiveWindow(layout: layout, sceneSize: sceneSize)

        let shouldInvite = focusAccumulator >= focusInviteInterval
        if shouldInvite {
            focusAccumulator = 0
        }
        let context = CompanionContext(
            isMeetingActive: snapshot.isMeetingActive,
            isCodingActive: snapshot.isCodingActive,
            forceQuietSleep: forceQuietSleep,
            shouldOfferTennisBreak: shouldInvite
        )

        stepState(dt: clampedDt, layout: layout, context: context, sceneSize: sceneSize)
        syncVisuals(dt: clampedDt)
    }

    // MARK: - Active Window & Fullscreen Perch Tracking

    private func reconcileWithActiveWindow(layout: ActiveWindowPerchLayout, sceneSize: CGSize) {
        if case .dragged = state { return }
        if case .gliding = state { return }

        // 1. Fullscreen Space or maximized window -> always peek from right edge of screen!
        if layout.isFullScreenMode {
            let anchor = layout.screenRightPeek
            let desiredY = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
            if perchZone != .screenRightPeek {
                treatNode?.removeFromParent()
                treatNode = nil
                beginSmoothGlide(
                    to: CGPoint(x: anchor.edgeX, y: desiredY),
                    targetZone: .screenRightPeek,
                    layout: layout
                )
            } else {
                currentRightAnchor = anchor
                position = CGPoint(x: anchor.edgeX, y: desiredY)
            }
            return
        }

        // 2. Non-fullscreen mode: did the user switch to a different active window (or exit fullscreen)?
        let activeID = layout.activeWindowID ?? 0
        let switchedWindow = (activeID != 0 && activeID != trackedWindowID)
        let returningFromFullScreen = (perchZone == .screenRightPeek && (layout.topPerch != nil || layout.windowRightPeek != nil))

        if switchedWindow || returningFromFullScreen {
            treatNode?.removeFromParent()
            treatNode = nil
            trackedWindowID = activeID
            transitionToActiveWindowPreferredSpot(layout: layout, sceneSize: sceneSize)
            return
        }

        // 3. Same active window: keep Westie locked smoothly to the window's top or right border as it moves/resizes!
        switch perchZone {
        case .windowTop:
            if let top = layout.topPerch {
                let desiredX = top.clampedX(top.windowMinX + offsetFromWindowMinX, margin: 18)
                position = CGPoint(x: desiredX, y: top.y)
                currentPlatform = top
                if let treat = treatNode {
                    treat.position.y = top.y + 13
                    treat.position.x = top.clampedX(treat.position.x, margin: 20)
                }
            } else if let right = layout.windowRightPeek {
                // Window moved up to touch menu bar -> smoothly move to its right border!
                treatNode?.removeFromParent()
                treatNode = nil
                beginSmoothGlide(
                    to: CGPoint(x: right.edgeX, y: right.defaultY),
                    targetZone: .windowRightPeek,
                    layout: layout
                )
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }

        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                let winMaxY = layout.activeWindowFrame?.maxY ?? right.maxY
                let desiredY = right.clampedY(winMaxY - offsetFromWindowMaxY)
                position = CGPoint(x: right.edgeX, y: desiredY)
                currentRightAnchor = right
            } else if let top = layout.topPerch {
                // Window moved flush to right edge of screen -> move onto its top border!
                let x = top.clampedX(top.minX + top.width * 0.65, margin: 20)
                beginSmoothGlide(to: CGPoint(x: x, y: top.y), targetZone: .windowTop, layout: layout)
            } else {
                snapToScreenRightPeek(layout.screenRightPeek, sceneSize: sceneSize)
            }

        case .screenRightPeek:
            let anchor = layout.screenRightPeek
            position = CGPoint(x: anchor.edgeX, y: anchor.clampedY(sceneSize.height * screenRightCustomYRatio))
            currentRightAnchor = anchor
        }
    }

    private func transitionToActiveWindowPreferredSpot(layout: ActiveWindowPerchLayout, sceneSize: CGSize) {
        if perchPreference == .rightPeek, let right = layout.windowRightPeek {
            beginSmoothGlide(to: CGPoint(x: right.edgeX, y: right.defaultY), targetZone: .windowRightPeek, layout: layout)
        } else if let top = layout.topPerch {
            // Land on upper-middle/right portion of active window's top edge (away from traffic lights)
            let preferredX = top.clampedX(top.minX + top.width * 0.62, margin: 22)
            beginSmoothGlide(to: CGPoint(x: preferredX, y: top.y), targetZone: .windowTop, layout: layout)
        } else if let right = layout.windowRightPeek {
            beginSmoothGlide(to: CGPoint(x: right.edgeX, y: right.defaultY), targetZone: .windowRightPeek, layout: layout)
        } else {
            let anchor = layout.screenRightPeek
            let desiredY = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
            beginSmoothGlide(to: CGPoint(x: anchor.edgeX, y: desiredY), targetZone: .screenRightPeek, layout: layout)
        }
    }

    private func beginSmoothGlide(to target: CGPoint, targetZone: PerchZone, layout: ActiveWindowPerchLayout) {
        let dist = hypot(target.x - position.x, target.y - position.y)
        trackedWindowID = layout.activeWindowID ?? trackedWindowID
        if dist < 14 {
            finishGlideArrival(at: target, targetZone: targetZone, layout: layout)
            return
        }
        facingDirection = (target.x >= position.x) ? 1.0 : -1.0
        let duration = min(max(TimeInterval(dist / 950.0), 0.18), 0.36)
        state = .gliding(elapsed: 0, duration: duration, from: position, to: target, targetZone: targetZone)
    }

    private func finishGlideArrival(at target: CGPoint, targetZone: PerchZone, layout: ActiveWindowPerchLayout) {
        zoneStayTimer = 0
        switch targetZone {
        case .windowTop:
            if let top = layout.topPerch {
                landOnWindowTop(top, atX: target.x)
            } else {
                perchZone = .windowTop
                position = target
                state = .idle(remaining: 5.0)
            }
        case .windowRightPeek:
            if let right = layout.windowRightPeek {
                snapToWindowRightPeek(right, windowMaxY: layout.activeWindowFrame?.maxY ?? right.maxY, customY: target.y)
            } else {
                perchZone = .windowRightPeek
                position = target
                state = .peekingRight(remaining: 20.0)
            }
        case .screenRightPeek:
            perchZone = .screenRightPeek
            currentPlatform = nil
            currentRightAnchor = layout.screenRightPeek
            position = CGPoint(x: layout.screenRightPeek.edgeX, y: layout.screenRightPeek.clampedY(target.y))
            state = .peekingRight(remaining: 25.0)
        }
    }

    private func landOnWindowTop(_ platform: WindowPlatform, atX rawX: CGFloat) {
        let x = platform.clampedX(rawX, margin: 18)
        perchZone = .windowTop
        currentPlatform = platform
        currentRightAnchor = nil
        trackedWindowID = platform.windowID
        offsetFromWindowMinX = x - platform.windowMinX
        position = CGPoint(x: x, y: platform.y)
        zoneStayTimer = 0
        if forceQuietSleep {
            state = .sleeping(remaining: 25.0)
        } else {
            state = .idle(remaining: 4.5)
        }
    }

    private func snapToWindowRightPeek(_ anchor: RightEdgeAnchor, windowMaxY: CGFloat, customY: CGFloat? = nil) {
        let y = anchor.clampedY(customY ?? anchor.defaultY)
        perchZone = .windowRightPeek
        currentPlatform = nil
        currentRightAnchor = anchor
        offsetFromWindowMaxY = max(42, windowMaxY - y)
        position = CGPoint(x: anchor.edgeX, y: y)
        zoneStayTimer = 0
        state = .peekingRight(remaining: Double.random(in: 18.0...28.0))
    }

    private func snapToScreenRightPeek(_ anchor: RightEdgeAnchor, sceneSize: CGSize) {
        let y = anchor.clampedY(sceneSize.height * screenRightCustomYRatio)
        perchZone = .screenRightPeek
        currentPlatform = nil
        currentRightAnchor = anchor
        position = CGPoint(x: anchor.edgeX, y: y)
        zoneStayTimer = 0
        state = .peekingRight(remaining: 30.0)
    }

    // MARK: - Calm Behavior State Machine

    private func stepState(
        dt: TimeInterval,
        layout: ActiveWindowPerchLayout,
        context: CompanionContext,
        sceneSize: CGSize
    ) {
        switch state {
        case .idle(let remaining),
             .sitCalm(let remaining),
             .loafing(let remaining),
             .chinRest(let remaining),
             .sleeping(let remaining):
            let next = remaining - dt
            if next <= 0 {
                if perchZone == .windowTop, let top = layout.topPerch {
                    // Occasionally visit the active window's right edge (`右侧`) when in `.auto` mode!
                    if perchPreference == .auto,
                       !context.forceQuietSleep,
                       !isHoveringDog,
                       zoneStayTimer >= 26.0,
                       let right = layout.windowRightPeek,
                       Double.random(in: 0...1) < 0.28
                    {
                        beginSmoothGlide(
                            to: CGPoint(x: right.edgeX, y: right.defaultY),
                            targetZone: .windowRightPeek,
                            layout: layout
                        )
                    } else {
                        state = WestieBehaviorPlanner.chooseNextTopBehavior(
                            currentX: position.x,
                            platform: top,
                            context: context
                        )
                    }
                } else {
                    state = .peekingRight(remaining: 22.0)
                }
            } else {
                switch state {
                case .idle: state = .idle(remaining: next)
                case .sitCalm: state = .sitCalm(remaining: next)
                case .loafing: state = .loafing(remaining: next)
                case .chinRest: state = .chinRest(remaining: next)
                case .sleeping: state = .sleeping(remaining: next)
                default: break
                }
            }

        case .peekingRight(let remaining):
            let next = remaining - dt
            if next <= 0 {
                // If non-fullscreen and `.auto` mode, occasionally climb back onto the active window's top edge!
                if perchZone == .windowRightPeek,
                   perchPreference == .auto,
                   !isHoveringDog,
                   let top = layout.topPerch
                {
                    let targetX = top.clampedX(top.maxX - min(96, top.width * 0.28), margin: 22)
                    beginSmoothGlide(to: CGPoint(x: targetX, y: top.y), targetZone: .windowTop, layout: layout)
                } else if context.shouldOfferTennisBreak {
                    state = .holdingTennisBall(remaining: 22.0)
                } else {
                    state = .peekingRight(remaining: Double.random(in: 18.0...28.0))
                }
            } else {
                state = .peekingRight(remaining: next)
            }

        case .holdingTennisBall(let remaining):
            let next = remaining - dt
            if next <= 0 {
                state = (perchZone == .windowTop) ? .idle(remaining: 5.0) : .peekingRight(remaining: 20.0)
            } else {
                state = .holdingTennisBall(remaining: next)
            }

        case .chasingTreat(let treatX):
            let dx = treatX - position.x
            if abs(dx) < 12 {
                treatNode?.removeFromParent()
                treatNode = nil
                state = .loafing(remaining: 8.0)
            } else if let top = currentPlatform {
                let dir: CGFloat = dx > 0 ? 1.0 : -1.0
                facingDirection = dir
                position.x = top.clampedX(position.x + dir * 115.0 * CGFloat(dt), margin: 18)
                offsetFromWindowMinX = position.x - top.windowMinX
            } else {
                treatNode?.removeFromParent()
                treatNode = nil
                state = .idle(remaining: 4.0)
            }

        case .walking(var dir, let remaining):
            guard perchZone == .windowTop, let top = currentPlatform else {
                state = .peekingRight(remaining: 20.0)
                return
            }
            // Pause calmly in place while cursor hovers over Westie so clicking/right-clicking is effortless
            if isHoveringDog {
                return
            }

            facingDirection = dir
            let walkSpeed: CGFloat = 38.0 // Gentle, unhurried stroll
            var nextX = position.x + dir * walkSpeed * CGFloat(dt)

            if nextX <= top.minX + 18 || nextX >= top.maxX - 18 {
                // If walking right up to the right corner in `.auto` mode, sometimes peek over the right edge!
                if nextX >= top.maxX - 18,
                   perchPreference == .auto,
                   zoneStayTimer >= 18.0,
                   let right = layout.windowRightPeek,
                   Double.random(in: 0...1) < 0.35
                {
                    beginSmoothGlide(
                        to: CGPoint(x: right.edgeX, y: right.defaultY),
                        targetZone: .windowRightPeek,
                        layout: layout
                    )
                    return
                }
                dir = -dir
                facingDirection = dir
                nextX = top.clampedX(nextX, margin: 18)
            }

            position.x = nextX
            offsetFromWindowMinX = position.x - top.windowMinX

            let nextRem = remaining - dt
            if nextRem <= 0 {
                state = WestieBehaviorPlanner.chooseNextTopBehavior(
                    currentX: position.x,
                    platform: top,
                    context: context
                )
            } else {
                state = .walking(direction: dir, remaining: nextRem)
            }

        case .gliding(let elapsed, let duration, let from, var to, let targetZone):
            // Keep target anchored to live window frame during the short glide
            switch targetZone {
            case .windowTop:
                if let top = layout.topPerch {
                    to = CGPoint(x: top.clampedX(to.x, margin: 18), y: top.y)
                }
            case .windowRightPeek:
                if let right = layout.windowRightPeek {
                    to = CGPoint(x: right.edgeX, y: right.clampedY(to.y))
                }
            case .screenRightPeek:
                to = CGPoint(x: layout.screenRightPeek.edgeX, y: layout.screenRightPeek.clampedY(to.y))
            }

            let t = elapsed + dt
            if t >= duration {
                finishGlideArrival(at: to, targetZone: targetZone, layout: layout)
            } else {
                let u = CGFloat(t / max(duration, 0.01))
                // Smooth cubic ease-out + subtle 18pt hop arc
                let eased = 1.0 - pow(1.0 - u, 3)
                let arcHop = sin(u * .pi) * 18.0
                position = CGPoint(
                    x: from.x + (to.x - from.x) * eased,
                    y: from.y + (to.y - from.y) * eased + arcHop
                )
                state = .gliding(elapsed: t, duration: duration, from: from, to: to, targetZone: targetZone)
            }

        case .dragged:
            break
        }
    }

    // MARK: - Visual Sync

    private func syncVisuals(dt: TimeInterval) {
        let bank = SpriteBank.shared

        // 1. Handle Dragged & Gliding poses cleanly (unmasked)
        if case .dragged = state {
            cropNode.maskNode = nil
            dogSprite.size = topDogSize
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            dogSprite.texture = bank.texture(for: .westieDangling)
            dogSprite.position = position
            dogSprite.xScale = facingDirection >= 0 ? 1.0 : -1.0
            dogSprite.yScale = 1.0
            dogSprite.zRotation = sin(breathPhase * 2.0) * 0.06
            shadowNode.isHidden = true
            inviteBadgeNode.isHidden = true
            return
        }

        if case .gliding = state {
            cropNode.maskNode = nil
            dogSprite.size = topDogSize
            dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            dogSprite.texture = bank.texture(for: .westieWalk1)
            dogSprite.position = position
            dogSprite.xScale = facingDirection >= 0 ? 1.0 : -1.0
            dogSprite.yScale = 1.0
            dogSprite.zRotation = 0
            shadowNode.isHidden = true
            inviteBadgeNode.isHidden = true
            return
        }

        // 2. Right-Edge Peeking Modes (Fullscreen Screen-Right OR Non-Fullscreen Window-Right)
        if perchZone == .screenRightPeek || perchZone == .windowRightPeek {
            let easeOut = 1.0 - pow(1.0 - peekHoverProgress, 3)
            let isHoveredPose = peekHoverProgress >= 0.38

            dogSprite.size = peekDogSize
            dogSprite.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            dogSprite.texture = bank.texture(for: isHoveredPose ? .westiePeekHover : .westiePeekCalm)
            dogSprite.yScale = 1.0

            // Subtle friendly ear/paw tilt ONLY while hovered — completely still otherwise!
            let subtleHoverTilt: CGFloat = (peekHoverProgress > 0.05)
                ? sin(hoverWavePhase * 5.2) * 0.038 * easeOut
                : 0.0

            if perchZone == .screenRightPeek {
                // Monitor right bezel clips x > screenWidth naturally; peek LEFTWARD (`xScale = +1`)
                cropNode.maskNode = nil
                let tuckInward: CGFloat = 11.0 * (1.0 - easeOut) // +11pt tucked when calm -> 0pt full peek on hover!
                dogSprite.xScale = 1.0
                dogSprite.position = CGPoint(x: position.x + tuckInward, y: position.y)
                dogSprite.zRotation = subtleHoverTilt
                inviteBadgeNode.position = CGPoint(x: position.x - 68, y: position.y + 46)
            } else {
                // Window right border: mask `x >= position.x` so ZERO pixels overlap inside the active window!
                cropMaskNode.position = CGPoint(x: position.x, y: position.y)
                cropNode.maskNode = cropMaskNode
                let tuckBehindWindow: CGFloat = 10.0 * (1.0 - easeOut) // -10pt behind border when calm -> 0pt on hover!
                dogSprite.xScale = -1.0 // Mirrored to peek RIGHTWARD out from behind the active window!
                dogSprite.position = CGPoint(x: position.x - tuckBehindWindow, y: position.y)
                dogSprite.zRotation = -subtleHoverTilt
                inviteBadgeNode.position = CGPoint(x: position.x + 64, y: position.y + 46)
            }

            shadowNode.isHidden = true
            if case .holdingTennisBall = state {
                inviteBadgeNode.isHidden = false
            } else {
                inviteBadgeNode.isHidden = true
            }
            return
        }

        // 3. Active Window Top-Edge Mode (`正上方` — calm, zero shaking, zero heart popups)
        cropNode.maskNode = nil
        dogSprite.size = topDogSize
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        dogSprite.yScale = 1.0

        var bobY: CGFloat = 0
        if isHoveringDog, state.isGrounded, case .walking = state {
            // Calmly pause & rest chin when user hovers cursor over Westie on the top bar
            dogSprite.texture = bank.texture(for: .westieChinLedge)
        } else {
            switch state {
            case .idle:
                dogSprite.texture = bank.texture(for: isHoveringDog ? .westieChinLedge : .westieIdle)
            case .sitCalm:
                dogSprite.texture = bank.texture(for: .westieSitTilt)
            case .loafing:
                dogSprite.texture = bank.texture(for: .westieLoafCalm)
            case .chinRest:
                dogSprite.texture = bank.texture(for: .westieChinLedge)
            case .sleeping:
                dogSprite.texture = bank.texture(for: .westieSleep)
            case .holdingTennisBall:
                dogSprite.texture = bank.texture(for: .westieHoldingBall)
            case .walking, .chasingTreat:
                walkAnimTimer += dt
                let interval: TimeInterval = ( { if case .chasingTreat = state { return 0.12 } else { return 0.22 } }() )
                if walkAnimTimer >= interval {
                    walkAnimTimer = 0
                    walkFrameToggle.toggle()
                }
                dogSprite.texture = bank.texture(for: walkFrameToggle ? .westieWalk1 : .westieWalk2)
                bobY = abs(sin(breathPhase * 2.0)) * 1.1
            case .peekingRight, .gliding, .dragged:
                dogSprite.texture = bank.texture(for: .westieIdle)
            }
        }

        dogSprite.position = CGPoint(x: position.x, y: position.y + bobY)
        dogSprite.xScale = facingDirection >= 0 ? 1.0 : -1.0
        dogSprite.zRotation = 0 // Zero head-shaking wobble on top bar!

        shadowNode.position = CGPoint(x: position.x, y: (currentPlatform?.y ?? position.y) + 1)
        shadowNode.isHidden = false

        if case .holdingTennisBall = state {
            inviteBadgeNode.isHidden = false
            inviteBadgeNode.position = CGPoint(x: position.x, y: position.y + 80)
        } else {
            inviteBadgeNode.isHidden = true
        }
    }
}
