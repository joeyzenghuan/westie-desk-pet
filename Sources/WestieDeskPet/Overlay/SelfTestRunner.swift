import CoreGraphics
import Foundation

public enum SelfTestRunner {
    @MainActor
    public static func runAll() -> Bool {
        var passed = 0
        var failed = 0

        func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
            if condition() {
                print("  ✅ \(label)")
                passed += 1
            } else {
                print("  ❌ FAILED: \(label)")
                failed += 1
            }
        }

        print("Running WestieDeskPet Self-Test Suite...")

        // 1. Bundled Sprite Assets check (all 22 pixel-art PNGs including v0.2 peek & loaf poses)
        let totalExpected = SpriteAssetKey.allCases.count
        let missingSprites = SpriteAssetKey.allCases.filter { !SpriteBank.shared.hasRealSprite(for: $0) }
        expect(missingSprites.isEmpty && totalExpected == 22, "All \(totalExpected) pixel-art PNG sprites resolve from bundle (missing: \(missingSprites.map(\.rawValue)))")

        // 2. Window Platform Occlusion & Dock Fallback
        let screen = CGRect(x: 0, y: 60, width: 1440, height: 840)
        let frontWin = RawWindowInfo(windowID: 101, ownerPID: 500, ownerName: "Code", frame: CGRect(x: 200, y: 300, width: 400, height: 420), isFrontmostApp: true)
        let backWin = RawWindowInfo(windowID: 102, ownerPID: 501, ownerName: "Terminal", frame: CGRect(x: 400, y: 200, width: 500, height: 400), isFrontmostApp: false)
        let selfWin = RawWindowInfo(windowID: 999, ownerPID: 777, ownerName: "WestieDeskPet", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isFrontmostApp: false)

        let platforms = PlatformPhysics.extractVisiblePlatforms(
            windowsFrontToBack: [selfWin, frontWin, backWin],
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        expect(!platforms.contains(where: { $0.windowID == 999 }), "Excludes own overlay window PID")
        expect(platforms.first(where: { $0.windowID == 101 })?.y == 720, "Extracts front window top bar at y=720")
        expect((platforms.first(where: { $0.windowID == 102 })?.minX ?? 0) >= 600, "Occludes overlapping left half of back window")
        expect(platforms.contains(where: { $0.isDockFloor }), "Always includes Dock floor fallback")

        // 3. Cross-window Jump Arc
        if let p1 = platforms.first(where: { $0.windowID == 102 }),
           let p2 = platforms.first(where: { $0.windowID == 101 })
        {
            let arc = PlatformPhysics.planCrossWindowJump(from: p1, startX: 650, startY: p1.y, platforms: [p2, p1])
            expect(arc?.targetPlatform.windowID == 101, "Jump planner targets reachable frontmost window")
        }

        // 4. 2.5D Tennis Shot Physics & Net Clearance
        var topspinBall = TennisPhysics.makeShot(
            from: (x: 20, y: -205, z: 24),
            hitter: .player,
            target: CGPoint(x: -85, y: 175),
            kind: .chargedTopspin,
            chargeRatio: 0.8
        )
        var bouncedInOpponentHalf = false
        for _ in 0..<240 {
            let res = TennisPhysics.stepBall(ball: &topspinBall, dt: 1.0 / 60.0)
            if res.bounced && topspinBall.y > 0 {
                bouncedInOpponentHalf = true
                break
            }
        }
        expect(topspinBall.hasCrossedNet && bouncedInOpponentHalf, "Charged topspin clears net and bounces in bounds")

        // 5. Drop-shot backspin braking
        var dropBall = TennisPhysics.makeShot(
            from: (x: 0, y: -120, z: 24),
            hitter: .player,
            target: CGPoint(x: 35, y: 55),
            kind: .dropShot,
            chargeRatio: 0.2
        )
        let preSpeed = hypot(dropBall.vx, dropBall.vy)
        var postSpeed = preSpeed
        for _ in 0..<180 {
            let res = TennisPhysics.stepBall(ball: &dropBall, dt: 1.0 / 60.0)
            if res.bounced {
                postSpeed = hypot(dropBall.vx, dropBall.vy)
                break
            }
        }
        expect(postSpeed < preSpeed * 0.65, "Backspin drop-shot brakes horizontal speed on bounce")

        // 6. Westie Tennis AI return
        var rallyBall = TennisPhysics.makeShot(
            from: (x: 0, y: -200, z: 24),
            hitter: .player,
            target: CGPoint(x: 35, y: 170),
            kind: .flatDrive,
            chargeRatio: 0.3
        )
        var aiDog = WestieOpponentState()
        var aiReturned = false
        for _ in 0..<240 {
            let dt: CGFloat = 1.0 / 60.0
            _ = TennisPhysics.stepBall(ball: &rallyBall, dt: dt)
            if WestieTennisAI.step(opponent: &aiDog, ball: &rallyBall, isBallLive: true, playerPosition: CGPoint(x: 0, y: -205), difficulty: .pro, dt: dt) {
                aiReturned = true
                break
            }
        }
        expect(aiReturned && rallyBall.lastHitter == .westie && rallyBall.vy < 0, "Westie AI predicts landing and returns ball across net")

        // 7. Active Window Perch Layout: Non-fullscreen window exposes BOTH Top-Edge & Right-Edge Peek!
        let normalLayout = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [selfWin, frontWin, backWin],
            screenSize: CGSize(width: 1440, height: 932),
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        expect(!normalLayout.isFullScreenMode, "Non-fullscreen active window is detected as windowed mode")
        expect(normalLayout.topPerch?.windowID == 101 && (normalLayout.topPerch?.minX ?? 0) >= 278, "Top perch avoids macOS traffic-light buttons on left")
        expect(normalLayout.windowRightPeek?.edgeX == 600, "Window right-edge peek anchors cleanly at activeWindow.maxX=600")

        // 8. Full-Screen Space Detection -> Screen Right-Edge Peek!
        let fullScreenWin = RawWindowInfo(windowID: 202, ownerPID: 600, ownerName: "Keynote", frame: CGRect(x: 0, y: 0, width: 1440, height: 932), isFrontmostApp: true)
        let fullScreenLayout = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [fullScreenWin],
            screenSize: CGSize(width: 1440, height: 932),
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 932),
            excludedPID: 777
        )
        expect(fullScreenLayout.isFullScreenMode && fullScreenLayout.screenRightPeek.edgeX == 1440, "Full-screen mode switches Westie to right edge of screen (x=1440)")

        // 9. Tennis Speed Presets & Context Menu Reliability
        expect(TennisGameSpeed.slow.simulationScale < TennisGameSpeed.standard.simulationScale, "Slow tennis speed scales down ball & AI simulation pace")
        expect(TennisGameSpeed.slow.faster() == .medium && TennisGameSpeed.medium.slower() == .slow, "Tennis speed +/- controls step cleanly between presets")
        let scene = DesktopScene(size: CGSize(width: 1440, height: 900))
        let ctxMenu = scene.buildDogContextMenu()
        expect(ctxMenu.items.count >= 8, "Right-click context menu constructs rich menu items reliably")

        // 10. v0.3 Silky Smoothness: DampedSpring, Tap-vs-Drag Zero-Jump, & O(1) Single-Window Layout
        var spring = DampedSpring(value: 0, target: 1.0, stiffness: 320, damping: 22)
        var peakVal: CGFloat = 0
        for _ in 0..<120 {
            spring.step(dt: 1.0 / 120.0)
            peakVal = max(peakVal, spring.value)
        }
        expect(peakVal > 1.01 && spring.isSettled && abs(spring.value - 1.0) < 0.002, "DampedSpring exhibits lively overshoot and settles cleanly to target")

        let fastLayout = PlatformPhysics.computeSingleWindowPerchLayout(
            windowID: 101,
            ownerName: "Code",
            windowFrame: CGRect(x: 260, y: 315, width: 400, height: 420),
            screenSize: CGSize(width: 1440, height: 932),
            visibleScreenFrame: screen
        )
        expect(fastLayout.topPerch?.y == 735 && fastLayout.windowRightPeek?.edgeX == 660, "O(1) single-window fast refresh tracks live window top & right edges")

        let companion = CompanionController()
        let dummySnap = ActiveWorkspaceSnapshot(
            platforms: platforms,
            perchLayout: normalLayout,
            frontmostAppName: "Code",
            frontmostBundleID: "com.microsoft.VSCode",
            isMeetingActive: false,
            isCodingActive: true
        )
        companion.placeInitially(snapshot: dummySnap, sceneSize: CGSize(width: 1440, height: 932))
        let initialDogPos = companion.position
        let clickPt = CGPoint(x: initialDogPos.x + 6, y: initialDogPos.y + 24)
        let didPress = companion.handleMouseDown(at: clickPt)
        let zeroJumpOnDown = (companion.position == initialDogPos && companion.state != .dragged)
        companion.handleMouseDragged(to: CGPoint(x: clickPt.x + 2, y: clickPt.y + 1)) // < 4pt micro-jitter
        let stillNotDragged = (companion.state != .dragged && companion.position == initialDogPos)
        companion.handleMouseUp(at: clickPt, snapshot: dummySnap, sceneSize: CGSize(width: 1440, height: 932))
        expect(didPress && zeroJumpOnDown && stillNotDragged && !companion.isPointerDownOnDog, "Clicking Westie (< 4pt movement) triggers tactile bounce with zero position jump")

        _ = companion.handleMouseDown(at: clickPt)
        companion.handleMouseDragged(to: CGPoint(x: clickPt.x + 18, y: clickPt.y + 12)) // >= 4pt intentional drag
        expect(companion.state == .dragged, "Dragging past 4pt threshold smoothly transitions Westie into scruff-carry")

        print("Self-test summary: \(passed) passed, \(failed) failed.")
        return failed == 0
    }
}
