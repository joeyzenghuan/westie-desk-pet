import AppKit
import SpriteKit

@MainActor
public final class TennisMatchController {
    public let rootNode = SKNode()

    public var onRequestExitTennis: (() -> Void)?
    public var onGameSpeedChanged: ((TennisGameSpeed) -> Void)?

    public var difficulty: TennisDifficulty = .casual {
        didSet {
            updateDifficultyButtonLabel()
            updateScoreboardText()
        }
    }

    public var gameSpeed: TennisGameSpeed = {
        if let raw = UserDefaults.standard.string(forKey: "westie.tennis.speed"),
           let saved = TennisGameSpeed(rawValue: raw)
        {
            return saved
        }
        return .slow // Default slower rally pace as requested!
    }() {
        didSet {
            UserDefaults.standard.set(gameSpeed.rawValue, forKey: "westie.tennis.speed")
            updateSpeedButtonLabel()
            onGameSpeedChanged?(gameSpeed)
        }
    }

    private let courtOriginNode = SKNode()
    private let playerSprite: SKSpriteNode
    private let playerShadow: SKShapeNode
    private let chargeRing: SKShapeNode
    private let westieSprite: SKSpriteNode
    private let westieShadow: SKShapeNode
    private let ballSprite: SKSpriteNode
    private let ballShadow: SKShapeNode
    private let aimReticle: SKNode

    // HUD Nodes
    private let scoreLabel: SKLabelNode
    private let bannerLabel: SKLabelNode
    private let hintLabel: SKLabelNode
    private let exitButtonNode: SKNode
    private let difficultyButtonNode: SKNode
    private let speedButtonNode: SKNode

    // Match State
    private let targetPointsToWin = 5
    private var playerScore = 0
    private var westieScore = 0
    private var rallyHits = 0
    private var server: CourtSide = .player
    private var isAwaitingServe = true
    private var isMatchOver = false
    private var pointPauseTimer: TimeInterval = 0

    // Player & Ball Physics State
    private var playerPos = CGPoint(x: 0, y: -205)
    private var heldKeys: Set<UInt16> = []
    private var dashTimer: TimeInterval = 0
    private var dashDirection = CGVector.zero
    private var dashCooldown: TimeInterval = 0
    private var lastKeyDownTime: [UInt16: TimeInterval] = [:]
    private var playerSwingVisualTimer: TimeInterval = 0
    private var runAnimTimer: TimeInterval = 0
    private var runFrameToggle = false

    // Mouse Aim & Charge
    private var aimCourtPoint = CGPoint(x: 40, y: 165)
    private var isChargingLeftClick = false
    private var chargeStartTime: TimeInterval = 0
    private var currentChargeRatio: CGFloat = 0

    private var opponent = WestieOpponentState()
    private var ball = TennisBallState()

    // Hardware keycodes (works even when Chinese Pinyin IME is active!)
    private static let keyW: UInt16 = 13
    private static let keyA: UInt16 = 0
    private static let keyS: UInt16 = 1
    private static let keyD: UInt16 = 2
    private static let keySpace: UInt16 = 49
    private static let keyR: UInt16 = 15
    private static let keyEsc: UInt16 = 53
    private static let keyMinus: UInt16 = 27
    private static let keyEqual: UInt16 = 24
    private static let keyLeftBracket: UInt16 = 33
    private static let keyRightBracket: UInt16 = 30
    // Arrow keys as bonus convenience
    private static let keyUp: UInt16 = 126
    private static let keyLeft: UInt16 = 123
    private static let keyDown: UInt16 = 125
    private static let keyRight: UInt16 = 124

    private var currentPetSpecies: PetSpecies {
        CompanionPreferences.shared.petSpecies
    }

    private var currentPetLabel: String {
        switch currentPetSpecies {
        case .westie: return "🐶 西高地"
        case .goldenCat: return "🐱 金渐层"
        case .labrador: return "🐕 拉布拉多"
        case .chinchilla: return "🐈 金吉拉"
        }
    }

    public init() {
        rootNode.zPosition = 20
        rootNode.isHidden = true

        // Shadows
        playerShadow = SKShapeNode(ellipseOf: CGSize(width: 36, height: 11))
        playerShadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.30)
        playerShadow.strokeColor = .clear
        playerShadow.zPosition = 2

        westieShadow = SKShapeNode(ellipseOf: CGSize(width: 36, height: 11))
        westieShadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.30)
        westieShadow.strokeColor = .clear
        westieShadow.zPosition = 2

        ballShadow = SKShapeNode(ellipseOf: CGSize(width: 16, height: 7))
        ballShadow.fillColor = NSColor(calibratedWhite: 0, alpha: 0.36)
        ballShadow.strokeColor = .clear
        ballShadow.zPosition = 2

        // Charge Ring under player
        chargeRing = SKShapeNode(circleOfRadius: 24)
        chargeRing.strokeColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.22, alpha: 0.95)
        chargeRing.fillColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.22, alpha: 0.14)
        chargeRing.lineWidth = 2.5
        chargeRing.isHidden = true
        chargeRing.zPosition = 2.5

        // Sprites
        let bank = SpriteBank.shared
        playerSprite = SKSpriteNode(texture: bank.texture(for: .playerReady))
        playerSprite.size = CGSize(width: 62, height: 62)
        playerSprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        playerSprite.zPosition = 6

        westieSprite = SKSpriteNode(texture: bank.texture(for: .westieTennisReady))
        westieSprite.size = CGSize(width: 64, height: 64)
        westieSprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        westieSprite.zPosition = 4

        ballSprite = SKSpriteNode(texture: bank.texture(for: .tennisBall))
        ballSprite.size = CGSize(width: 20, height: 20)
        ballSprite.zPosition = 7

        aimReticle = Self.buildAimReticle()
        aimReticle.zPosition = 3

        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        scoreLabel.fontSize = 15
        scoreLabel.fontColor = .white
        scoreLabel.zPosition = 12

        bannerLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        bannerLabel.fontSize = 20
        bannerLabel.fontColor = NSColor(calibratedRed: 0.95, green: 1.0, blue: 0.55, alpha: 1.0)
        bannerLabel.zPosition = 15

        hintLabel = SKLabelNode(fontNamed: "Menlo")
        hintLabel.fontSize = 11.2
        hintLabel.fontColor = NSColor(calibratedWhite: 0.94, alpha: 0.92)
        hintLabel.text = "WASD 移动(双击冲刺) · 鼠标瞄准 · 左键击球/长按上旋 · 右键小球/高吊 · [-/+] 调球速 · R 重开 · ESC 收起"
        hintLabel.zPosition = 12

        exitButtonNode = Self.buildPillButton(title: "✕ 收起球场 (ESC)", width: 136, fill: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 0.92))
        exitButtonNode.zPosition = 14

        difficultyButtonNode = Self.buildPillButton(title: "🐾 难度: 休闲小狗", width: 142, fill: NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.28, alpha: 0.92))
        difficultyButtonNode.zPosition = 14

        speedButtonNode = Self.buildPillButton(title: "球速: \(gameSpeed.displayName)", width: 146, fill: NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.48, alpha: 0.92))
        speedButtonNode.zPosition = 14

        rootNode.addChild(courtOriginNode)
        Self.populateCourtGeometry(into: courtOriginNode)

        courtOriginNode.addChild(aimReticle)
        courtOriginNode.addChild(playerShadow)
        courtOriginNode.addChild(chargeRing)
        courtOriginNode.addChild(westieShadow)
        courtOriginNode.addChild(ballShadow)
        courtOriginNode.addChild(westieSprite)
        courtOriginNode.addChild(ballSprite)
        courtOriginNode.addChild(playerSprite)
        courtOriginNode.addChild(scoreLabel)
        courtOriginNode.addChild(bannerLabel)
        courtOriginNode.addChild(hintLabel)
        courtOriginNode.addChild(exitButtonNode)
        courtOriginNode.addChild(difficultyButtonNode)
        courtOriginNode.addChild(speedButtonNode)

        scoreLabel.position = CGPoint(x: 0, y: TennisCourtMetrics.apronMaxY + 14)
        bannerLabel.position = CGPoint(x: 0, y: 42)
        hintLabel.position = CGPoint(x: 0, y: -TennisCourtMetrics.apronMaxY - 24)
        difficultyButtonNode.position = CGPoint(x: -158, y: TennisCourtMetrics.apronMaxY + 48)
        speedButtonNode.position = CGPoint(x: 0, y: TennisCourtMetrics.apronMaxY + 48)
        exitButtonNode.position = CGPoint(x: 158, y: TennisCourtMetrics.apronMaxY + 48)
    }

    // MARK: - Lifecycle

    public func startMatch(in sceneSize: CGSize) {
        layout(in: sceneSize)
        playerScore = 0
        westieScore = 0
        server = .player
        isMatchOver = false
        heldKeys.removeAll()
        isChargingLeftClick = false
        currentChargeRatio = 0
        updateDifficultyButtonLabel()
        resetForNextPoint(announcement: "🎾 抢 5 分对决开始！点击左键或按空格发球")
        rootNode.isHidden = false
        rootNode.alpha = 0
        rootNode.setScale(0.94)
        rootNode.run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.18),
            SKAction.scale(to: 1.0, duration: 0.18)
        ]))
    }

    public func stopMatch() {
        heldKeys.removeAll()
        isChargingLeftClick = false
        rootNode.isHidden = true
    }

    public func layout(in sceneSize: CGSize) {
        courtOriginNode.position = CGPoint(x: sceneSize.width * 0.5, y: sceneSize.height * 0.5)
    }

    private func resetForNextPoint(announcement: String) {
        isAwaitingServe = true
        rallyHits = 0
        isChargingLeftClick = false
        currentChargeRatio = 0
        chargeRing.isHidden = true

        playerPos = CGPoint(x: (server == .player) ? 48 : -48, y: -212)
        opponent = WestieOpponentState()
        opponent.x = (server == .westie) ? -48 : 48
        opponent.y = 205

        if server == .player {
            ball = TennisBallState(x: playerPos.x + 14, y: playerPos.y + 12, z: 22, lastHitter: .player)
        } else {
            ball = TennisBallState(x: opponent.x, y: opponent.y - 12, z: 22, lastHitter: .westie)
            pointPauseTimer = 0.85 // Westie serves automatically after brief pause!
        }

        bannerLabel.text = announcement
        bannerLabel.alpha = 1.0
        updateScoreboardText()
        syncVisuals()
    }

    // MARK: - Input Handling (WASD + Mouse)

    public func handleKeyDown(_ event: NSEvent) {
        let code = event.keyCode
        if code == Self.keyEsc {
            onRequestExitTennis?()
            return
        }
        if code == Self.keyR {
            if let scene = rootNode.scene {
                startMatch(in: scene.size)
            }
            return
        }
        if code == Self.keyMinus || code == Self.keyLeftBracket {
            let next = gameSpeed.slower()
            gameSpeed = next
            spawnCourtPopText("球速: \(next.displayName)", at: CGPoint(x: 0, y: 95), color: .cyan)
            return
        }
        if code == Self.keyEqual || code == Self.keyRightBracket {
            let next = gameSpeed.faster()
            gameSpeed = next
            spawnCourtPopText("球速: \(next.displayName)", at: CGPoint(x: 0, y: 95), color: .cyan)
            return
        }

        if code == Self.keySpace {
            if isMatchOver, let scene = rootNode.scene {
                startMatch(in: scene.size)
                return
            }
            if isAwaitingServe && server == .player {
                performPlayerServe(chargeRatio: 0.35)
                return
            }
            triggerDashFromHeldKeys()
            return
        }

        // Detect double-tap WASD for quick dash!
        if !event.isARepeat, [Self.keyW, Self.keyA, Self.keyS, Self.keyD].contains(code) {
            let now = ProcessInfo.processInfo.systemUptime
            if let prev = lastKeyDownTime[code], (now - prev) < 0.26, dashCooldown <= 0 {
                heldKeys.insert(code)
                triggerDashFromHeldKeys()
                lastKeyDownTime[code] = 0
                return
            }
            lastKeyDownTime[code] = now
        }

        heldKeys.insert(code)
    }

    public func handleKeyUp(_ event: NSEvent) {
        heldKeys.remove(event.keyCode)
    }

    public func handleMouseMoved(scenePoint: CGPoint) {
        let local = rootNode.convert(scenePoint, to: courtOriginNode)
        let clampedX = min(max(local.x, -TennisCourtMetrics.halfWidth + 6), TennisCourtMetrics.halfWidth - 6)
        let clampedY = min(max(local.y, 34), TennisCourtMetrics.halfLength - 8)
        aimCourtPoint = CGPoint(x: clampedX, y: clampedY)
        aimReticle.position = aimCourtPoint
    }

    public func handleLeftMouseDown(scenePoint: CGPoint) {
        let local = rootNode.convert(scenePoint, to: courtOriginNode)

        // Check HUD buttons first
        if exitButtonNode.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(local) {
            onRequestExitTennis?()
            return
        }
        if difficultyButtonNode.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(local) {
            difficulty = (difficulty == .casual) ? .pro : .casual
            return
        }
        if speedButtonNode.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(local) {
            gameSpeed = gameSpeed.next()
            spawnCourtPopText("球速切换: \(gameSpeed.displayName)", at: CGPoint(x: 0, y: 95), color: .cyan)
            return
        }

        if isMatchOver, let scene = rootNode.scene {
            startMatch(in: scene.size)
            return
        }

        handleMouseMoved(scenePoint: scenePoint)

        if isAwaitingServe && server == .player {
            isChargingLeftClick = true
            chargeStartTime = ProcessInfo.processInfo.systemUptime
            return
        }

        // If ball is already right in the strike zone, swing immediately for snappy feel!
        if canPlayerStrikeBallNow() {
            executePlayerHit(kind: .flatDrive, charge: 0.25)
        } else {
            // Start charging topspin while approaching the ball!
            isChargingLeftClick = true
            chargeStartTime = ProcessInfo.processInfo.systemUptime
        }
    }

    public func handleLeftMouseUp(scenePoint: CGPoint) {
        handleMouseMoved(scenePoint: scenePoint)
        guard isChargingLeftClick else { return }
        let ratio = computeChargeRatio()
        isChargingLeftClick = false
        chargeRing.isHidden = true

        if isAwaitingServe && server == .player {
            performPlayerServe(chargeRatio: ratio)
            return
        }

        if canPlayerStrikeBallNow() {
            let kind: TennisShotKind = (ratio >= 0.42) ? .chargedTopspin : .flatDrive
            executePlayerHit(kind: kind, charge: ratio)
        } else {
            // Whiff swing animation
            playerSwingVisualTimer = 0.20
        }
        currentChargeRatio = 0
    }

    public func handleRightMouseDown(scenePoint: CGPoint) {
        if isMatchOver { return }
        handleMouseMoved(scenePoint: scenePoint)
        isChargingLeftClick = false
        chargeRing.isHidden = true

        if isAwaitingServe && server == .player {
            performPlayerServe(chargeRatio: 0.15)
            return
        }

        if canPlayerStrikeBallNow() {
            // Aimed near net -> cheeky Drop Shot; aimed deep -> High Lob over Westie!
            let kind: TennisShotKind = (aimCourtPoint.y < 118) ? .dropShot : .highLob
            executePlayerHit(kind: kind, charge: 0.3)
        } else {
            playerSwingVisualTimer = 0.20
        }
    }

    // MARK: - Update Loop (60+ FPS)

    public func update(dt: TimeInterval) {
        guard !rootNode.isHidden else { return }
        let clampedDt = CGFloat(min(max(dt, 0.001), 0.05))

        dashTimer = max(0, dashTimer - TimeInterval(clampedDt))
        dashCooldown = max(0, dashCooldown - TimeInterval(clampedDt))
        playerSwingVisualTimer = max(0, playerSwingVisualTimer - TimeInterval(clampedDt))

        // Update charge indicator
        if isChargingLeftClick {
            currentChargeRatio = computeChargeRatio()
            chargeRing.isHidden = false
            chargeRing.setScale(0.75 + currentChargeRatio * 0.55)
        } else {
            chargeRing.isHidden = true
        }

        // 1. Move human player via WASD (responsive even in slow-ball mode!)
        stepPlayerMovement(dt: clampedDt * gameSpeed.playerMoveScale)

        // 2. Handle serve waiting / between-point pause
        if isMatchOver {
            syncVisuals()
            return
        }

        if pointPauseTimer > 0 {
            pointPauseTimer -= TimeInterval(clampedDt)
            if pointPauseTimer <= 0 {
                if isAwaitingServe && server == .westie {
                    performWestieServe()
                }
            }
            syncVisuals()
            return
        }

        if isAwaitingServe {
            if server == .player {
                ball.x = playerPos.x + 14
                ball.y = playerPos.y + 12
                ball.z = 22
            }
            syncVisuals()
            return
        }

        // Auto-release charged shot if player is holding LMB and ball enters sweet-spot!
        if isChargingLeftClick && canPlayerStrikeBallSweetSpot() {
            let ratio = computeChargeRatio()
            isChargingLeftClick = false
            chargeRing.isHidden = true
            let kind: TennisShotKind = (ratio >= 0.42) ? .chargedTopspin : .flatDrive
            executePlayerHit(kind: kind, charge: ratio)
            currentChargeRatio = 0
        }

        let simDt = clampedDt * gameSpeed.simulationScale

        // 3. Step 2.5D Ball Physics (scaled cleanly by `gameSpeed`)
        let stepResult = TennisPhysics.stepBall(ball: &ball, dt: simDt)
        if stepResult.bounced {
            spawnCourtBounceMark(at: CGPoint(x: ball.x, y: ball.y))
        }
        if stepResult.hitNet {
            spawnCourtPopText("NET!", at: CGPoint(x: ball.x, y: 0), color: .systemOrange)
        }

        if case .pointWon(let winner, let reason) = stepResult.outcome {
            awardPoint(to: winner, reason: reason)
            syncVisuals()
            return
        }

        // 4. Step Westie AI Opponent
        let westieHit = WestieTennisAI.step(
            opponent: &opponent,
            ball: &ball,
            isBallLive: !isAwaitingServe,
            playerPosition: playerPos,
            difficulty: difficulty,
            dt: simDt
        )
        if westieHit {
            rallyHits += 1
            spawnHitSpark(at: CGPoint(x: opponent.x, y: opponent.y + 16), color: .white)
            updateScoreboardText()
        }

        syncVisuals()
    }

    // MARK: - Mechanics Helpers

    private func stepPlayerMovement(dt: CGFloat) {
        var moveX: CGFloat = 0
        var moveY: CGFloat = 0
        if heldKeys.contains(Self.keyW) || heldKeys.contains(Self.keyUp) { moveY += 1 }
        if heldKeys.contains(Self.keyS) || heldKeys.contains(Self.keyDown) { moveY -= 1 }
        if heldKeys.contains(Self.keyA) || heldKeys.contains(Self.keyLeft) { moveX -= 1 }
        if heldKeys.contains(Self.keyD) || heldKeys.contains(Self.keyRight) { moveX += 1 }

        if dashTimer > 0 {
            playerPos.x += dashDirection.dx * 420.0 * dt
            playerPos.y += dashDirection.dy * 420.0 * dt
        } else if moveX != 0 || moveY != 0 {
            let len = hypot(moveX, moveY)
            let chargeSlowdown: CGFloat = isChargingLeftClick ? 0.76 : 1.0
            let speed: CGFloat = 235.0 * chargeSlowdown
            playerPos.x += (moveX / len) * speed * dt
            playerPos.y += (moveY / len) * speed * dt

            runAnimTimer += TimeInterval(dt)
            if runAnimTimer >= 0.13 {
                runAnimTimer = 0
                runFrameToggle.toggle()
            }
        } else {
            runFrameToggle = false
        }

        playerPos.x = min(max(playerPos.x, -TennisCourtMetrics.apronMaxX + 20), TennisCourtMetrics.apronMaxX - 20)
        playerPos.y = min(max(playerPos.y, -TennisCourtMetrics.apronMaxY + 18), -28)
    }

    private func triggerDashFromHeldKeys() {
        guard dashCooldown <= 0 else { return }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if heldKeys.contains(Self.keyW) || heldKeys.contains(Self.keyUp) { dy += 1 }
        if heldKeys.contains(Self.keyS) || heldKeys.contains(Self.keyDown) { dy -= 1 }
        if heldKeys.contains(Self.keyA) || heldKeys.contains(Self.keyLeft) { dx -= 1 }
        if heldKeys.contains(Self.keyD) || heldKeys.contains(Self.keyRight) { dx += 1 }
        let len = hypot(dx, dy)
        guard len > 0.01 else { return }
        dashDirection = CGVector(dx: dx / len, dy: dy / len)
        dashTimer = 0.16
        dashCooldown = 0.52
        spawnCourtPopText("💨", at: playerPos, color: .white)
    }

    private func computeChargeRatio() -> CGFloat {
        let elapsed = ProcessInfo.processInfo.systemUptime - chargeStartTime
        return CGFloat(min(max(elapsed / 0.72, 0.0), 1.0))
    }

    private func canPlayerStrikeBallNow() -> Bool {
        guard !isAwaitingServe, ball.lastHitter == .westie, ball.y <= 10, ball.z <= 64 else {
            return false
        }
        let dist = hypot(ball.x - playerPos.x, ball.y - playerPos.y)
        return dist <= 58.0
    }

    private func canPlayerStrikeBallSweetSpot() -> Bool {
        guard !isAwaitingServe, ball.lastHitter == .westie, ball.y <= 4, ball.z <= 48 else {
            return false
        }
        let dist = hypot(ball.x - playerPos.x, ball.y - playerPos.y)
        return dist <= 40.0
    }

    private func performPlayerServe(chargeRatio: CGFloat) {
        isAwaitingServe = false
        bannerLabel.run(SKAction.fadeOut(withDuration: 0.25))
        playerSwingVisualTimer = 0.24
        ball = TennisPhysics.makeShot(
            from: (playerPos.x + 12, playerPos.y + 14, 28),
            hitter: .player,
            target: aimCourtPoint,
            kind: .serve,
            chargeRatio: chargeRatio
        )
        rallyHits = 1
        spawnHitSpark(at: CGPoint(x: playerPos.x + 12, y: playerPos.y + 24), color: .systemYellow)
        updateScoreboardText()
    }

    private func performWestieServe() {
        isAwaitingServe = false
        bannerLabel.run(SKAction.fadeOut(withDuration: 0.25))
        opponent.swingCooldown = 0.35
        let aimX: CGFloat = (opponent.x < 0) ? CGFloat.random(in: 25...120) : CGFloat.random(in: -120 ... -25)
        ball = TennisPhysics.makeShot(
            from: (opponent.x, opponent.y - 10, 24),
            hitter: .westie,
            target: CGPoint(x: aimX, y: -175),
            kind: .serve,
            chargeRatio: (difficulty == .pro) ? 0.55 : 0.20
        )
        rallyHits = 1
        let serveCry = currentPetSpecies.isCat ? "喵! 🎾" : "汪! 🎾"
        spawnCourtPopText(serveCry, at: CGPoint(x: opponent.x, y: opponent.y + 42), color: .white)
        updateScoreboardText()
    }

    private func executePlayerHit(kind: TennisShotKind, charge: CGFloat) {
        playerSwingVisualTimer = 0.24
        ball = TennisPhysics.makeShot(
            from: (ball.x, max(ball.y, playerPos.y + 6), max(ball.z, 18)),
            hitter: .player,
            target: aimCourtPoint,
            kind: kind,
            chargeRatio: charge
        )
        rallyHits += 1

        let labelText: String? = switch kind {
        case .chargedTopspin: "🔥 强力上旋!"
        case .dropShot: "🪶 网前小球!"
        case .highLob: "🌈 高吊球!"
        default: nil
        }
        if let labelText {
            spawnCourtPopText(labelText, at: CGPoint(x: playerPos.x, y: playerPos.y + 58), color: .systemYellow)
        }
        spawnHitSpark(at: CGPoint(x: ball.x, y: ball.y + ball.z * 0.8), color: .systemGreen)
        updateScoreboardText()
    }

    private func awardPoint(to winner: CourtSide, reason: String) {
        if winner == .player {
            playerScore += 1
        } else {
            westieScore += 1
            opponent.celebrateTimer = 1.2
        }
        updateScoreboardText()

        if playerScore >= targetPointsToWin || westieScore >= targetPointsToWin {
            isMatchOver = true
            isAwaitingServe = true
            if playerScore > westieScore {
                bannerLabel.text = "🏆 你赢啦 (\(playerScore) : \(westieScore))！左键/R 再来一局 · ESC 回桌面"
            } else {
                let winText: String
                switch currentPetSpecies {
                case .goldenCat:
                    winText = "🐱 金渐层获胜 (\(westieScore) : \(playerScore)) 喵呜！左键/R 再战 · ESC 回桌面"
                case .chinchilla:
                    winText = "🐈 金吉拉获胜 (\(westieScore) : \(playerScore)) 喵呜！左键/R 再战 · ESC 回桌面"
                case .labrador:
                    winText = "🐕 拉布拉多获胜 (\(westieScore) : \(playerScore)) 汪汪！左键/R 再战 · ESC 回桌面"
                case .westie:
                    winText = "🐶 西高地获胜 (\(westieScore) : \(playerScore)) 汪汪！左键/R 再战 · ESC 回桌面"
                }
                bannerLabel.text = winText
            }
            bannerLabel.alpha = 1.0
            return
        }

        server = server.opposite
        let petShort = currentPetSpecies.shortName
        let scorerName = (winner == .player) ? "你得分" : "\(petShort)得分"
        let nextServeHint = (server == .player) ? "轮到你发球(左键/空格)" : "\(petShort)准备发球..."
        resetForNextPoint(announcement: "\(reason) → \(scorerName)! \(nextServeHint)")
        if server == .westie {
            pointPauseTimer = 1.15
        }
    }

    // MARK: - Visual Sync & Court Drawing

    private func syncVisuals() {
        let bank = SpriteBank.shared

        // Player sprite
        if playerSwingVisualTimer > 0 {
            playerSprite.texture = bank.texture(for: .playerSwing)
        } else if runFrameToggle {
            playerSprite.texture = bank.texture(for: .playerRun)
        } else {
            playerSprite.texture = bank.texture(for: .playerReady)
        }
        playerSprite.position = playerPos
        playerShadow.position = CGPoint(x: playerPos.x, y: playerPos.y + 3)
        chargeRing.position = CGPoint(x: playerPos.x, y: playerPos.y + 6)

        // Pet opponent sprite (Westie OR Golden Shaded Cat!)
        let sp = currentPetSpecies
        if opponent.celebrateTimer > 0 || (isMatchOver && westieScore > playerScore) {
            westieSprite.texture = bank.texture(for: .westieVictory, species: sp)
            westieSprite.xScale = abs(westieSprite.xScale)
        } else if opponent.diveTimer > 0 {
            westieSprite.texture = bank.texture(for: .westieTennisDive, species: sp)
            westieSprite.xScale = (opponent.facingDirection < 0) ? -abs(westieSprite.xScale) : abs(westieSprite.xScale)
        } else if opponent.swingCooldown > 0.20 {
            westieSprite.texture = bank.texture(for: .westieTennisSwing, species: sp)
            westieSprite.xScale = abs(westieSprite.xScale)
        } else if !isAwaitingServe && ball.lastHitter == .player && abs(opponent.lastStepDX) > 0.4 {
            westieSprite.texture = bank.texture(for: .westieTennisRun, species: sp)
            westieSprite.xScale = (opponent.facingDirection < 0) ? -abs(westieSprite.xScale) : abs(westieSprite.xScale)
        } else {
            westieSprite.texture = bank.texture(for: .westieTennisReady, species: sp)
            westieSprite.xScale = abs(westieSprite.xScale)
        }
        westieSprite.position = CGPoint(x: opponent.x, y: opponent.y)
        westieShadow.position = CGPoint(x: opponent.x, y: opponent.y + 3)

        // 2.5D Ball + ground shadow
        ballShadow.position = CGPoint(x: ball.x, y: ball.y)
        let shadowScale = max(0.45, 1.0 - ball.z / 160.0)
        ballShadow.setScale(shadowScale)

        ballSprite.position = CGPoint(x: ball.x, y: ball.y + ball.z * 0.85)
        let ballScale = 1.0 + min(ball.z / 220.0, 0.42)
        ballSprite.setScale(ballScale)
    }

    public func refreshPetSpeciesUI() {
        updateDifficultyButtonLabel()
        updateScoreboardText()
    }

    private func updateScoreboardText() {
        let petText: String
        switch currentPetSpecies {
        case .westie: petText = "西高地 🐶"
        case .goldenCat: petText = "金渐层 🐱"
        case .labrador: petText = "拉布拉多 🐕"
        case .chinchilla: petText = "金吉拉 🐈"
        }
        scoreLabel.text = "🧑 你  \(playerScore)  :  \(westieScore)  \(petText)   |   回合 \(rallyHits)"
    }

    private func updateDifficultyButtonLabel() {
        if let lbl = difficultyButtonNode.childNode(withName: "pillLabel") as? SKLabelNode {
            lbl.text = "🐾 难度: \(difficulty.displayName(for: currentPetSpecies))"
        }
    }

    private func updateSpeedButtonLabel() {
        if let lbl = speedButtonNode.childNode(withName: "pillLabel") as? SKLabelNode {
            lbl.text = "球速: \(gameSpeed.displayName)"
        }
    }

    private func spawnCourtBounceMark(at pt: CGPoint) {
        let ring = SKShapeNode(ellipseOf: CGSize(width: 14, height: 7))
        ring.position = pt
        ring.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.65)
        ring.fillColor = .clear
        ring.lineWidth = 1.2
        ring.zPosition = 1.8
        courtOriginNode.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.6, duration: 0.35),
                SKAction.fadeOut(withDuration: 0.35)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func spawnHitSpark(at pt: CGPoint, color: NSColor) {
        let burst = SKShapeNode(circleOfRadius: 9)
        burst.position = pt
        burst.strokeColor = color
        burst.fillColor = color.withAlphaComponent(0.35)
        burst.lineWidth = 2
        burst.zPosition = 9
        courtOriginNode.addChild(burst)
        burst.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.1, duration: 0.16),
                SKAction.fadeOut(withDuration: 0.16)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func spawnCourtPopText(_ text: String, at pt: CGPoint, color: NSColor) {
        let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
        lbl.text = text
        lbl.fontSize = 13
        lbl.fontColor = color
        lbl.position = pt
        lbl.zPosition = 14
        courtOriginNode.addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 24, duration: 0.7),
                SKAction.fadeOut(withDuration: 0.7)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Static Geometry Builders

    private static func buildAimReticle() -> SKNode {
        let node = SKNode()
        let outer = SKShapeNode(circleOfRadius: 12)
        outer.strokeColor = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.35, alpha: 0.85)
        outer.lineWidth = 1.6
        outer.fillColor = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.35, alpha: 0.12)
        node.addChild(outer)

        let dot = SKShapeNode(circleOfRadius: 2.5)
        dot.fillColor = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.45, alpha: 0.95)
        dot.strokeColor = .clear
        node.addChild(dot)
        return node
    }

    private static func buildPillButton(title: String, width: CGFloat, fill: NSColor) -> SKNode {
        let node = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: 26), cornerRadius: 8)
        bg.fillColor = fill
        bg.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.35)
        bg.lineWidth = 1.2
        node.addChild(bg)

        let lbl = SKLabelNode(fontNamed: "Menlo-Bold")
        lbl.name = "pillLabel"
        lbl.text = title
        lbl.fontSize = 11.5
        lbl.fontColor = .white
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        node.addChild(lbl)
        return node
    }

    private static func populateCourtGeometry(into parent: SKNode) {
        let apronW = TennisCourtMetrics.apronMaxX * 2
        let apronH = TennisCourtMetrics.apronMaxY * 2

        // Semi-transparent stadium apron (lets user still see their desktop lightly behind!)
        let apron = SKShapeNode(rectOf: CGSize(width: apronW + 36, height: apronH + 84), cornerRadius: 18)
        apron.fillColor = NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.13, alpha: 0.84)
        apron.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.25)
        apron.lineWidth = 2.0
        apron.zPosition = 0
        parent.addChild(apron)

        // Classic Wimbledon / Australian hard-grass inner court surface
        let courtW = TennisCourtMetrics.halfWidth * 2
        let courtH = TennisCourtMetrics.halfLength * 2
        let surface = SKShapeNode(rectOf: CGSize(width: courtW, height: courtH))
        surface.fillColor = NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.32, alpha: 0.93)
        surface.strokeColor = .white
        surface.lineWidth = 2.5
        surface.zPosition = 1
        parent.addChild(surface)

        // Service boxes & center service line
        let linesPath = CGMutablePath()
        let serviceY: CGFloat = 118
        // Top & bottom service lines
        linesPath.move(to: CGPoint(x: -TennisCourtMetrics.halfWidth, y: serviceY))
        linesPath.addLine(to: CGPoint(x: TennisCourtMetrics.halfWidth, y: serviceY))
        linesPath.move(to: CGPoint(x: -TennisCourtMetrics.halfWidth, y: -serviceY))
        linesPath.addLine(to: CGPoint(x: TennisCourtMetrics.halfWidth, y: -serviceY))
        // Center service line
        linesPath.move(to: CGPoint(x: 0, y: -serviceY))
        linesPath.addLine(to: CGPoint(x: 0, y: serviceY))
        // Baseline center marks
        linesPath.move(to: CGPoint(x: 0, y: -TennisCourtMetrics.halfLength))
        linesPath.addLine(to: CGPoint(x: 0, y: -TennisCourtMetrics.halfLength + 10))
        linesPath.move(to: CGPoint(x: 0, y: TennisCourtMetrics.halfLength))
        linesPath.addLine(to: CGPoint(x: 0, y: TennisCourtMetrics.halfLength - 10))

        let serviceLines = SKShapeNode(path: linesPath)
        serviceLines.strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.88)
        serviceLines.lineWidth = 2.0
        serviceLines.zPosition = 1.2
        parent.addChild(serviceLines)

        // 2.5D Net with posts + white top tape
        let netMesh = SKShapeNode(rect: CGRect(
            x: -TennisCourtMetrics.halfWidth - 16,
            y: 0,
            width: courtW + 32,
            height: TennisCourtMetrics.netHeight * 0.82
        ))
        netMesh.fillColor = NSColor(calibratedWhite: 0.10, alpha: 0.48)
        netMesh.strokeColor = NSColor(calibratedWhite: 0.95, alpha: 0.95)
        netMesh.lineWidth = 2.2
        netMesh.zPosition = 5
        parent.addChild(netMesh)

        for postX in [-TennisCourtMetrics.halfWidth - 16, TennisCourtMetrics.halfWidth + 16] {
            let post = SKShapeNode(rectOf: CGSize(width: 5, height: 24), cornerRadius: 2)
            post.position = CGPoint(x: postX, y: 11)
            post.fillColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
            post.strokeColor = .darkGray
            post.zPosition = 5.2
            parent.addChild(post)
        }
    }
}
