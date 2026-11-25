import AppKit
import SpriteKit

@MainActor
public final class CompanionController {
    public let rootNode = SKNode()

    private let dogSprite: SKSpriteNode
    private let shadowNode: SKShapeNode
    private let inviteBadgeNode: SKNode
    private var treatNode: SKSpriteNode?

    public private(set) var currentPlatform: WindowPlatform?
    public private(set) var state: CompanionBehaviorState = .idle(remaining: 3.0)
    public var forceQuietSleep: Bool = false {
        didSet {
            if forceQuietSleep {
                state = .sleeping(remaining: 30.0)
            } else if case .sleeping = state {
                state = .sitHeadTilt(remaining: 3.5)
            }
        }
    }

    public var onRequestStartTennis: (() -> Void)?

    private var position: CGPoint = CGPoint(x: 420, y: 120)
    private var facingDirection: CGFloat = 1.0
    private var walkAnimTimer: TimeInterval = 0
    private var walkFrameToggle: Bool = false
    private var breathPhase: CGFloat = 0
    private var zzzSpawnTimer: TimeInterval = 0
    private var heartCooldown: TimeInterval = 0

    // Window movement tracking
    private var trackedWindowID: UInt32 = 0
    private var offsetFromWindowMinX: CGFloat = 0

    // Focus timer -> invite user to play tennis after 25 minutes (or manual summon)
    private var focusAccumulator: TimeInterval = 0
    private let focusInviteInterval: TimeInterval = 25 * 60

    private let dogDisplaySize = CGSize(width: 68, height: 68)

    public var isNeedingHighFPS: Bool {
        state.isHighFrameRateNeeded || treatNode != nil
    }

    public init() {
        shadowNode = SKShapeNode(ellipseOf: CGSize(width: 44, height: 11))
        shadowNode.fillColor = NSColor(calibratedWhite: 0.0, alpha: 0.24)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = 1

        dogSprite = SKSpriteNode(
            texture: SpriteBank.shared.texture(for: .westieIdle),
            color: .clear,
            size: dogDisplaySize
        )
        dogSprite.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        dogSprite.zPosition = 3

        inviteBadgeNode = CompanionController.buildInviteBadge()
        inviteBadgeNode.position = CGPoint(x: 0, y: 78)
        inviteBadgeNode.zPosition = 10
        inviteBadgeNode.isHidden = true

        rootNode.addChild(shadowNode)
        rootNode.addChild(dogSprite)
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

    public func placeInitially(on platforms: [WindowPlatform], sceneSize: CGSize) {
        let preferred = platforms.first(where: { !$0.isDockFloor && $0.isFrontmost })
            ?? platforms.first(where: { !$0.isDockFloor })
            ?? platforms.last
        if let plat = preferred {
            land(on: plat, atX: plat.midX)
        } else {
            position = CGPoint(x: sceneSize.width * 0.5, y: 80)
        }
        syncVisuals(dt: 0)
    }

    /// Interactive hitbox in scene coordinates (includes Westie + tennis invite badge when visible).
    public func interactiveHitRect() -> CGRect {
        var rect = CGRect(
            x: position.x - 40,
            y: position.y - 6,
            width: 80,
            height: 78
        )
        if !inviteBadgeNode.isHidden {
            let badgeRect = CGRect(
                x: position.x - 64,
                y: position.y + 60,
                width: 128,
                height: 36
            )
            rect = rect.union(badgeRect)
        }
        return rect
    }

    public func isPointOnInviteBadge(_ scenePoint: CGPoint) -> Bool {
        guard !inviteBadgeNode.isHidden else { return false }
        let badgeRect = CGRect(
            x: position.x - 64,
            y: position.y + 60,
            width: 128,
            height: 36
        )
        return badgeRect.contains(scenePoint)
    }

    // MARK: - User & Menu Actions

    public func triggerTennisInvite() {
        state = .holdingTennisBall(remaining: 25.0)
        spawnFloatingEmoji("🎾", color: .systemGreen)
    }

    public func summonToFrontWindow(snapshot: ActiveWorkspaceSnapshot) {
        if let target = snapshot.platforms.first(where: { !$0.isDockFloor && $0.isFrontmost })
            ?? snapshot.platforms.first(where: { !$0.isDockFloor })
        {
            land(on: target, atX: target.midX)
            state = .sitHeadTilt(remaining: 4.5)
            playBounceSquash()
            spawnFloatingEmoji("🐾", color: .white)
        }
    }

    public func dropBoneTreat(snapshot: ActiveWorkspaceSnapshot) {
        let plat = currentPlatform
            ?? snapshot.platforms.first(where: { !$0.isDockFloor })
            ?? snapshot.platforms.last
        guard let plat else { return }

        treatNode?.removeFromParent()
        let treatX: CGFloat
        if plat.width > 140 {
            let candidate = (position.x < plat.midX) ? min(plat.maxX - 28, position.x + 110) : max(plat.minX + 28, position.x - 110)
            treatX = plat.clampedX(candidate, margin: 24)
        } else {
            treatX = plat.midX
        }

        let node = SKSpriteNode(texture: SpriteBank.shared.texture(for: .boneTreat))
        node.size = CGSize(width: 28, height: 28)
        node.position = CGPoint(x: treatX, y: plat.y + 14)
        node.zPosition = 2
        rootNode.addChild(node)
        node.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 12, duration: 0.12),
            SKAction.moveBy(x: 0, y: -12, duration: 0.15)
        ]))
        treatNode = node

        if currentPlatform?.windowID != plat.windowID {
            land(on: plat, atX: position.x)
        }
        state = .chasingTreat(treatX: treatX)
    }

    public func handleHoverStroke(at point: CGPoint) {
        guard state.isGrounded else { return }
        if case .holdingTennisBall = state { return }
        if heartCooldown <= 0 {
            heartCooldown = 0.65
            spawnFloatingEmoji("♥", color: NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.52, alpha: 1.0))
            if case .sleeping = state {
                // Soft purr/twitch in sleep without rude wake
                return
            }
            state = .petted(remaining: 2.2)
        }
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
        currentPlatform = nil
        trackedWindowID = 0
        position = CGPoint(x: scenePoint.x, y: scenePoint.y - 34)
        return true
    }

    public func handleMouseDragged(to scenePoint: CGPoint) {
        guard case .dragged = state else { return }
        let dx = scenePoint.x - position.x
        if abs(dx) > 1.5 {
            facingDirection = dx > 0 ? 1.0 : -1.0
        }
        position = CGPoint(x: scenePoint.x, y: scenePoint.y - 34)
    }

    public func handleMouseUp(at scenePoint: CGPoint) {
        guard case .dragged = state else { return }
        state = .falling(velocity: CGVector(dx: 0, dy: 0))
    }

    // MARK: - Frame Update

    public func update(dt: TimeInterval, snapshot: ActiveWorkspaceSnapshot, sceneSize: CGSize) {
        let clampedDt = min(max(dt, 0.001), 0.08)
        heartCooldown = max(0, heartCooldown - clampedDt)
        breathPhase += CGFloat(clampedDt) * 3.2

        if !snapshot.isMeetingActive && !forceQuietSleep {
            focusAccumulator += clampedDt
        }

        // 1. Reconcile grounded platform with live window movements / closures
        if state.isGrounded {
            reconcileStandingPlatform(platforms: snapshot.platforms)
        }

        // 2. Step behavior state machine
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

        stepState(dt: clampedDt, platforms: snapshot.platforms, context: context, sceneSize: sceneSize)
        syncVisuals(dt: clampedDt)
    }

    private func reconcileStandingPlatform(platforms: [WindowPlatform]) {
        guard trackedWindowID != 0 || currentPlatform != nil else {
            state = .falling(velocity: .zero)
            return
        }

        // Try matching same windowID
        if let prevPlat = currentPlatform {
            let matchingSegments = platforms.filter { $0.windowID == prevPlat.windowID }
            if let firstSeg = matchingSegments.first {
                // Follow dragged window horizontally + vertically!
                let desiredX = firstSeg.windowMinX + offsetFromWindowMinX
                if let containingSeg = matchingSegments.first(where: { $0.containsX(desiredX, margin: 8) }) {
                    let deltaMove = hypot(desiredX - position.x, containingSeg.y - position.y)
                    position.x = desiredX
                    position.y = containingSeg.y
                    currentPlatform = containingSeg
                    if deltaMove > 22 {
                        // Window was shaken rapidly -> cute sit stabilization
                        if case .walking = state {
                            state = .sitHeadTilt(remaining: 2.0)
                        }
                    }
                    return
                }
            }
        }

        // Window closed, minimized, or covered at Westie's X -> start falling!
        currentPlatform = nil
        trackedWindowID = 0
        treatNode?.removeFromParent()
        treatNode = nil
        state = .falling(velocity: CGVector(dx: 0, dy: 25))
    }

    private func stepState(
        dt: TimeInterval,
        platforms: [WindowPlatform],
        context: CompanionContext,
        sceneSize: CGSize
    ) {
        switch state {
        case .idle(let remaining):
            let next = remaining - dt
            if next <= 0, let plat = currentPlatform {
                transitionFromGrounded(on: plat, platforms: platforms, context: context)
            } else {
                state = .idle(remaining: next)
            }

        case .sitHeadTilt(let remaining):
            let next = remaining - dt
            if next <= 0, let plat = currentPlatform {
                transitionFromGrounded(on: plat, platforms: platforms, context: context)
            } else {
                state = .sitHeadTilt(remaining: next)
            }

        case .sleeping(let remaining):
            zzzSpawnTimer -= dt
            if zzzSpawnTimer <= 0 {
                zzzSpawnTimer = 2.1
                spawnFloatingEmoji("z", color: NSColor(calibratedRed: 0.72, green: 0.86, blue: 1.0, alpha: 0.9))
            }
            let next = remaining - dt
            if next <= 0, let plat = currentPlatform {
                transitionFromGrounded(on: plat, platforms: platforms, context: context)
            } else {
                state = .sleeping(remaining: next)
            }

        case .petted(let remaining):
            let next = remaining - dt
            if next <= 0 {
                state = .sitHeadTilt(remaining: 3.2)
            } else {
                state = .petted(remaining: next)
            }

        case .holdingTennisBall(let remaining):
            let next = remaining - dt
            if next <= 0 {
                state = .idle(remaining: 4.0)
            } else {
                state = .holdingTennisBall(remaining: next)
            }

        case .chasingTreat(let treatX):
            let dx = treatX - position.x
            if abs(dx) < 12 {
                treatNode?.removeFromParent()
                treatNode = nil
                spawnFloatingEmoji("🦴♥", color: .systemYellow)
                playBounceSquash()
                state = .petted(remaining: 2.5)
            } else if let plat = currentPlatform {
                let dir: CGFloat = dx > 0 ? 1.0 : -1.0
                facingDirection = dir
                position.x = plat.clampedX(position.x + dir * 135.0 * CGFloat(dt), margin: 16)
                offsetFromWindowMinX = position.x - plat.windowMinX
            } else {
                treatNode?.removeFromParent()
                treatNode = nil
                state = .falling(velocity: .zero)
            }

        case .walking(var dir, let remaining):
            guard let plat = currentPlatform else {
                state = .falling(velocity: .zero)
                return
            }
            facingDirection = dir
            let walkSpeed: CGFloat = 58.0
            var nextX = position.x + dir * walkSpeed * CGFloat(dt)

            // Edge of window top bar: consider leaping to neighboring window or turning around!
            if nextX <= plat.minX + 20 || nextX >= plat.maxX - 20 {
                if Double.random(in: 0...1) < 0.42,
                   let arc = PlatformPhysics.planCrossWindowJump(
                       from: plat,
                       startX: position.x,
                       startY: position.y,
                       platforms: platforms
                   )
                {
                    facingDirection = (arc.targetX >= position.x) ? 1.0 : -1.0
                    currentPlatform = nil
                    trackedWindowID = 0
                    state = .jumping(
                        elapsed: 0,
                        duration: arc.duration,
                        start: position,
                        velocity: arc.initialVelocity
                    )
                    return
                }
                dir = -dir
                facingDirection = dir
                nextX = plat.clampedX(nextX, margin: 20)
            }

            position.x = nextX
            offsetFromWindowMinX = position.x - plat.windowMinX

            let nextRem = remaining - dt
            if nextRem <= 0 {
                transitionFromGrounded(on: plat, platforms: platforms, context: context)
            } else {
                state = .walking(direction: dir, remaining: nextRem)
            }

        case .jumping(let elapsed, let duration, let start, let velocity):
            let t = elapsed + dt
            let tf = CGFloat(t)
            let prevY = position.y
            let nextX = min(max(start.x + velocity.dx * tf, 24), sceneSize.width - 24)
            let nextY = start.y + velocity.dy * tf - 0.5 * PlatformPhysics.gravity * tf * tf

            if t >= duration * 0.65,
               let landed = PlatformPhysics.findLandingPlatform(x: nextX, prevY: prevY, nextY: nextY, platforms: platforms)
            {
                land(on: landed, atX: nextX)
                playBounceSquash()
                state = .idle(remaining: 2.8)
            } else if t >= duration + 0.15 {
                let vyNow = velocity.dy - PlatformPhysics.gravity * tf
                position = CGPoint(x: nextX, y: nextY)
                state = .falling(velocity: CGVector(dx: velocity.dx * 0.4, dy: vyNow))
            } else {
                position = CGPoint(x: nextX, y: nextY)
                state = .jumping(elapsed: t, duration: duration, start: start, velocity: velocity)
            }

        case .falling(var vel):
            let prevY = position.y
            vel.dy -= PlatformPhysics.gravity * CGFloat(dt)
            let nextX = min(max(position.x + vel.dx * CGFloat(dt), 24), sceneSize.width - 24)
            let nextY = position.y + vel.dy * CGFloat(dt)

            if let landed = PlatformPhysics.findLandingPlatform(x: nextX, prevY: prevY, nextY: nextY, platforms: platforms) {
                land(on: landed, atX: nextX)
                playBounceSquash()
                state = .sitHeadTilt(remaining: 2.6)
            } else if nextY <= 6 {
                if let floor = platforms.last {
                    land(on: floor, atX: nextX)
                } else {
                    position = CGPoint(x: nextX, y: 12)
                }
                playBounceSquash()
                state = .idle(remaining: 3.0)
            } else {
                position = CGPoint(x: nextX, y: nextY)
                state = .falling(velocity: vel)
            }

        case .dragged:
            break
        }
    }

    private func transitionFromGrounded(
        on plat: WindowPlatform,
        platforms: [WindowPlatform],
        context: CompanionContext
    ) {
        // Occasionally jump onto the frontmost active window if Westie is on Dock or an older window!
        if !context.forceQuietSleep && !context.isMeetingActive && !plat.isFrontmost && Double.random(in: 0...1) < 0.30,
           let arc = PlatformPhysics.planCrossWindowJump(
               from: plat,
               startX: position.x,
               startY: position.y,
               platforms: platforms,
               preferFrontmost: true
           )
        {
            facingDirection = (arc.targetX >= position.x) ? 1.0 : -1.0
            currentPlatform = nil
            trackedWindowID = 0
            state = .jumping(
                elapsed: 0,
                duration: arc.duration,
                start: position,
                velocity: arc.initialVelocity
            )
            return
        }

        state = WestieBehaviorPlanner.chooseNextBehavior(
            currentX: position.x,
            platform: plat,
            context: context
        )
    }

    private func land(on platform: WindowPlatform, atX rawX: CGFloat) {
        let x = platform.clampedX(rawX, margin: 18)
        position = CGPoint(x: x, y: platform.y)
        currentPlatform = platform
        trackedWindowID = platform.windowID
        offsetFromWindowMinX = x - platform.windowMinX
    }

    private func syncVisuals(dt: TimeInterval) {
        let bank = SpriteBank.shared
        var bobY: CGFloat = 0
        var tiltAngle: CGFloat = 0

        switch state {
        case .idle:
            dogSprite.texture = bank.texture(for: .westieIdle)
            bobY = sin(breathPhase) * 1.2

        case .walking, .chasingTreat:
            walkAnimTimer += dt
            let interval = ( { if case .chasingTreat = state { return 0.11 } else { return 0.19 } }() )
            if walkAnimTimer >= interval {
                walkAnimTimer = 0
                walkFrameToggle.toggle()
            }
            dogSprite.texture = bank.texture(for: walkFrameToggle ? .westieWalk1 : .westieWalk2)
            bobY = abs(sin(breathPhase * 2.4)) * 2.2

        case .sitHeadTilt:
            dogSprite.texture = bank.texture(for: .westieSitTilt)
            tiltAngle = sin(breathPhase * 0.8) * 0.05

        case .sleeping:
            dogSprite.texture = bank.texture(for: .westieSleep)
            bobY = sin(breathPhase * 0.6) * 0.6

        case .petted:
            dogSprite.texture = bank.texture(for: .westieSitTilt)
            tiltAngle = sin(breathPhase * 4.5) * 0.09
            bobY = abs(sin(breathPhase * 3.5)) * 2.5

        case .holdingTennisBall:
            dogSprite.texture = bank.texture(for: .westieHoldingBall)
            bobY = abs(sin(breathPhase * 2.2)) * 2.0

        case .jumping:
            dogSprite.texture = bank.texture(for: .westieWalk1)
            tiltAngle = facingDirection * 0.14

        case .falling:
            dogSprite.texture = bank.texture(for: .westieWalk2)
            tiltAngle = -facingDirection * 0.18

        case .dragged:
            dogSprite.texture = bank.texture(for: .westieDangling)
            tiltAngle = sin(breathPhase * 3.2) * 0.12
        }

        dogSprite.position = CGPoint(x: position.x, y: position.y + bobY)
        let absScaleX = max(0.5, abs(dogSprite.xScale))
        dogSprite.xScale = facingDirection >= 0 ? absScaleX : -absScaleX
        dogSprite.zRotation = tiltAngle

        shadowNode.position = CGPoint(x: position.x, y: (currentPlatform?.y ?? position.y) + 2)
        shadowNode.isHidden = !state.isGrounded

        if case .holdingTennisBall = state {
            inviteBadgeNode.isHidden = false
            inviteBadgeNode.position = CGPoint(x: position.x, y: position.y + 82 + sin(breathPhase * 2.0) * 3.0)
        } else {
            inviteBadgeNode.isHidden = true
        }
    }

    private func playBounceSquash() {
        dogSprite.removeAction(forKey: "squash")
        let signX: CGFloat = facingDirection >= 0 ? 1.0 : -1.0
        let squash = SKAction.sequence([
            SKAction.scaleX(to: signX * 1.16, y: 0.84, duration: 0.07),
            SKAction.scaleX(to: signX * 0.95, y: 1.06, duration: 0.08),
            SKAction.scaleX(to: signX * 1.0, y: 1.0, duration: 0.08)
        ])
        dogSprite.run(squash, withKey: "squash")
    }

    private func spawnFloatingEmoji(_ text: String, color: NSColor) {
        let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
        lbl.text = text
        lbl.fontSize = 15
        lbl.fontColor = color
        lbl.position = CGPoint(x: position.x + CGFloat.random(in: -12...12), y: position.y + 62)
        lbl.zPosition = 12
        rootNode.addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: CGFloat.random(in: -10...10), y: 34, duration: 0.95),
                SKAction.fadeOut(withDuration: 0.95)
            ]),
            SKAction.removeFromParent()
        ]))
    }
}
