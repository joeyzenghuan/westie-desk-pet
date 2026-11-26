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

        // 1. Bundled Sprite Assets check: 100% parity for BOTH Westie (43 sprites) and Golden Shaded Cat (39 pet sprites)!
        let totalExpected = SpriteAssetKey.allCases.count
        let missingWestie = SpriteAssetKey.allCases.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .westie) }
        expect(missingWestie.isEmpty && totalExpected == 43, "All \(totalExpected) Westie + shared PNG sprites resolve from bundle (missing: \(missingWestie.map(\.rawValue)))")
        let catPetKeys = SpriteAssetKey.allCases.filter(\.isPetSpecific)
        let missingCat = catPetKeys.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .goldenCat) }
        expect(missingCat.isEmpty && catPetKeys.count == 39, "All \(catPetKeys.count) Golden Shaded Cat sprites (incl. dried fish & eating) resolve with 100% parity (missing: \(missingCat.map { $0.resourceName(for: .goldenCat) }))")

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
        expect(
            ctxMenu.items.count >= 8 && ctxMenu.items.contains(where: { $0.title.contains("立即预览爬顶") }),
            "Right-click context menu constructs rich menu items including quick climb preview"
        )

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
        let initialHitRect = companion.interactiveHitRect()
        let clickPt = CGPoint(x: initialHitRect.midX, y: initialHitRect.midY)
        let didPress = companion.handleMouseDown(at: clickPt)
        let zeroJumpOnDown = (companion.position == initialDogPos && companion.state != .dragged)
        companion.handleMouseDragged(to: CGPoint(x: clickPt.x + 2, y: clickPt.y + 1)) // < 4pt micro-jitter
        let stillNotDragged = (companion.state != .dragged && companion.position == initialDogPos)
        companion.handleMouseUp(at: clickPt, snapshot: dummySnap, sceneSize: CGSize(width: 1440, height: 932))
        expect(didPress && zeroJumpOnDown && stillNotDragged && !companion.isPointerDownOnDog, "Clicking Westie (< 4pt movement) triggers tactile bounce with zero position jump")

        _ = companion.handleMouseDown(at: clickPt)
        companion.handleMouseDragged(to: CGPoint(x: clickPt.x + 18, y: clickPt.y + 12)) // >= 4pt intentional drag
        expect(companion.state == .dragged, "Dragging past 4pt threshold smoothly transitions Westie into scruff-carry")

        // 11. v0.4 Stealthy Window-Switch Dwell Debounce (5s), Overlap Tuck, Same-Y Shortest Path, Climb-to-Top, Typing Pause, & Shy Retreat
        let testSuiteName = "westie.selftest.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        defer { testDefaults.removePersistentDomain(forName: testSuiteName) }
        let testPrefs = CompanionPreferences(defaults: testDefaults)
        testPrefs.windowSwitchDelaySeconds = 5.0
        testPrefs.climbToTopEnabled = true
        testPrefs.climbToTopIntervalSeconds = 60.0
        testPrefs.greetingDurationSeconds = 10.0
        testPrefs.shyRetreatEnabled = true
        testPrefs.typingPauseEnabled = true
        testPrefs.climbPawsPeekEnabled = true
        testPrefs.perchPreference = .auto

        let winA = RawWindowInfo(windowID: 301, ownerPID: 500, ownerName: "BrowserA", frame: CGRect(x: 80, y: 200, width: 520, height: 520), isFrontmostApp: true)
        let winB = RawWindowInfo(windowID: 302, ownerPID: 501, ownerName: "EditorB", frame: CGRect(x: 680, y: 180, width: 520, height: 560), isFrontmostApp: false)
        let winBFront = RawWindowInfo(windowID: 302, ownerPID: 501, ownerName: "EditorB", frame: CGRect(x: 680, y: 180, width: 520, height: 560), isFrontmostApp: true)
        let winABack = RawWindowInfo(windowID: 301, ownerPID: 500, ownerName: "BrowserA", frame: CGRect(x: 80, y: 200, width: 520, height: 520), isFrontmostApp: false)
        let sceneSize = CGSize(width: 1440, height: 932)

        let layoutA = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [winA, winB],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        let snapA = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: layoutA,
            windowsFrontToBack: [winA, winB],
            windowFramesByID: [301: winA.frame, 302: winB.frame],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            frontmostAppName: "BrowserA",
            frontmostBundleID: "com.test.browserA",
            isMeetingActive: false,
            isCodingActive: false,
            secondsSinceLastKeyDown: 10.0
        )

        let layoutB = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [winBFront, winABack],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        let snapB = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: layoutB,
            windowsFrontToBack: [winBFront, winABack],
            windowFramesByID: [301: winABack.frame, 302: winBFront.frame],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            frontmostAppName: "EditorB",
            frontmostBundleID: "com.test.editorB",
            isMeetingActive: false,
            isCodingActive: true,
            secondsSinceLastKeyDown: 10.0
        )

        let defaultAutoDog = CompanionController(preferences: testPrefs, ownPID: 777)
        defaultAutoDog.placeInitially(snapshot: snapA, sceneSize: sceneSize)
        expect(
            defaultAutoDog.perchZone == .screenRightPeek && defaultAutoDog.trackedWindowID == 301,
            "Default mode rests quietly on screen right bezel (never intruding on active app's right border)"
        )

        // Default `.auto` mode: switching windows stays quietly on screen right bezel and resets climb timer!
        for _ in 0..<20 {
            defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
        }
        expect(
            defaultAutoDog.perchZone == .screenRightPeek && defaultAutoDog.trackedWindowID == 302,
            "Default screen-right mode updates tracked window quietly without jumping across apps"
        )

        // Optional `.rightPeek` ("跟随窗口右侧边") mode tests: 5s dwell debounce, stealth same-Y shortest path, & early overlap tuck!
        testPrefs.perchPreference = .rightPeek
        let v04Dog = CompanionController(preferences: testPrefs, ownPID: 777)
        v04Dog.placeInitially(snapshot: snapA, sceneSize: sceneSize)
        let startYOnA = v04Dog.position.y
        expect(v04Dog.perchZone == .windowRightPeek && v04Dog.trackedWindowID == 301, "Opt-in window-right mode starts peeking on active window A's right edge")

        // Switch to window B for 3.0s (< 5s): Westie MUST stay anchored on A!
        for _ in 0..<60 {
            v04Dog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
        }
        expect(v04Dog.trackedWindowID == 301 && v04Dog.pendingWindowSwitch?.targetWindowID == 302, "Window-switch dwell debounce keeps Westie on window A before 5s elapses")

        // Step another 2.2s (>= 5s total): Westie enters stealthTransition!
        var sawRetract = false
        var sawHidden = false
        var sawTentativePeek = false
        for _ in 0..<120 {
            v04Dog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .stealthTransition(let phase, _, _, _, _) = v04Dog.state {
                switch phase {
                case .retracting: sawRetract = true
                case .hiddenTraverse: sawHidden = true
                case .tentativePeek: sawTentativePeek = true
                case .settlingOut: break
                }
            }
        }
        expect(sawRetract && sawHidden && sawTentativePeek, "Stealthy transition plays retract -> hidden traverse -> tentative peek phases")
        expect(
            v04Dog.trackedWindowID == 302 && v04Dog.perchZone == .windowRightPeek && abs(v04Dog.position.y - startYOnA) < 1.5,
            "Westie emerges on window B's right border at the exact same Y height (shortest path)"
        )

        // Overlap early-tuck check (`tuck_early`): window C covers Westie's right edge on window B
        let winCOverlap = RawWindowInfo(windowID: 303, ownerPID: 502, ownerName: "OverlapC", frame: CGRect(x: 1120, y: 200, width: 300, height: 600), isFrontmostApp: true)
        let winBBack = RawWindowInfo(windowID: 302, ownerPID: 501, ownerName: "EditorB", frame: winBFront.frame, isFrontmostApp: false)
        let layoutC = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [winCOverlap, winBBack],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        let snapC = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: layoutC,
            windowsFrontToBack: [winCOverlap, winBBack],
            windowFramesByID: [302: winBBack.frame, 303: winCOverlap.frame],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            frontmostAppName: "OverlapC",
            frontmostBundleID: "com.test.overlapC",
            isMeetingActive: false,
            isCodingActive: false,
            secondsSinceLastKeyDown: 10.0
        )
        for _ in 0..<8 {
            v04Dog.update(dt: 0.05, snapshot: snapC, sceneSize: sceneSize)
        }
        let isTuckedEarly: Bool = {
            if case .tuckedWaiting = v04Dog.state { return true }
            return false
        }()
        expect(isTuckedEarly && v04Dog.interactiveHitRect() == .zero, "Overlapping foreground window triggers early tuck & disables hitbox during 5s wait")

        // Switch back to B before 5s -> cancels switch and re-emerges on B!
        for _ in 0..<30 {
            v04Dog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
        }
        expect(v04Dog.trackedWindowID == 302 && v04Dog.pendingWindowSwitch == nil, "Returning to window B before 5s cancels switch and re-emerges cleanly")

        // Switch back to default `.auto` screen-right mode to test 1-minute climb from screen right -> active window top bar!
        testPrefs.perchPreference = .auto
        let snapBTyping = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: layoutB,
            windowsFrontToBack: [winBFront, winABack],
            windowFramesByID: [301: winABack.frame, 302: winBFront.frame],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            frontmostAppName: "EditorB",
            frontmostBundleID: "com.test.editorB",
            isMeetingActive: false,
            isCodingActive: true,
            secondsSinceLastKeyDown: 0.4 // User actively typing!
        )
        for _ in 0..<1250 { // 62.5 seconds while actively typing
            defaultAutoDog.update(dt: 0.05, snapshot: snapBTyping, sceneSize: sceneSize)
        }
        expect(defaultAutoDog.perchZone == .screenRightPeek, "Typing-pause defers screen-right-to-top climb while user is actively typing")

        // User stops typing -> Westie stealth-climbs from screen right edge onto window B's top bar!
        var sawTopPeek3s = false
        var sawHopLeft = false
        var sawLookAround = false
        var sawWalkRight = false
        var sawSmileSit = false
        var sawPreYawnWait = false
        var sawYawn = false
        var sawSettlingToSleep = false
        var sawSleepingAfterYawn = false
        for _ in 0..<900 { // 45 seconds covering the full unhurried story arc with pauses!
            defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            switch defaultAutoDog.state {
            case .stealthTransition(let phase, _, let dest, _, _):
                if case .tentativePeek(_, let dur) = phase, dest.perchZone == .windowTop, dur >= 2.9 {
                    sawTopPeek3s = true
                }
            case .topStory(let step):
                switch step {
                case .hopLeft: sawHopLeft = true
                case .lookAroundPause: if sawHopLeft { sawLookAround = true }
                case .walkRight: if sawLookAround { sawWalkRight = true }
                case .smileSit: if sawWalkRight { sawSmileSit = true }
                case .preYawnWait: if sawSmileSit { sawPreYawnWait = true }
                case .postClimbPause, .postWalkPause, .flashStep: break
                }
            case .yawning:
                if sawPreYawnWait { sawYawn = true }
            case .settlingToSleep:
                if sawYawn { sawSettlingToSleep = true }
            case .sleeping:
                if sawSettlingToSleep {
                    sawSleepingAfterYawn = true
                }
            default:
                break
            }
            if sawSleepingAfterYawn { break }
        }
        expect(sawTopPeek3s && sawHopLeft && sawLookAround && sawWalkRight, "Story arc plays 3s head peek -> hop LEFT -> look around -> walk RIGHT")
        expect(sawSmileSit && sawPreYawnWait && sawYawn && sawSettlingToSleep && sawSleepingAfterYawn, "After walking right, Westie smiles & sways head -> pauses -> yawns -> drowsy -> sleeps")

        // Unified top-bar mouse interaction: hover does NOT wake sleeping dog or mutate state;
        // tapping cycles cleanly through user's enabled poses (default: sitSmile -> loafCalm -> bigHeadPeek)!
        let stateBeforeHover = defaultAutoDog.state
        defaultAutoDog.setHovering(true, pointerSpeed: 60.0, nearZone: true)
        defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
        let hoverPreservedSleep: Bool = {
            if case .sleeping = defaultAutoDog.state, case .sleeping = stateBeforeHover { return true }
            return false
        }()
        let tapPt = CGPoint(x: defaultAutoDog.position.x, y: defaultAutoDog.position.y + 20)
        _ = defaultAutoDog.handleMouseDown(at: tapPt)
        defaultAutoDog.handleMouseUp(at: tapPt, snapshot: snapB, sceneSize: sceneSize)
        let tap1Sit: Bool = {
            if case .sitCalm = defaultAutoDog.state { return true }
            return false
        }()
        _ = defaultAutoDog.handleMouseDown(at: tapPt)
        defaultAutoDog.handleMouseUp(at: tapPt, snapshot: snapB, sceneSize: sceneSize)
        let tap2Loaf: Bool = {
            if case .loafing = defaultAutoDog.state { return true }
            return false
        }()
        _ = defaultAutoDog.handleMouseDown(at: tapPt)
        defaultAutoDog.handleMouseUp(at: tapPt, snapshot: snapB, sceneSize: sceneSize)
        let tap3BigHead: Bool = {
            if case .chinRest = defaultAutoDog.state { return true }
            return false
        }()
        // Disable `.loafCalm` in user preferences -> next tap cycles bigHeadPeek -> sitSmile -> bigHeadPeek!
        testPrefs.setTopTapPose(.loafCalm, enabled: false)
        _ = defaultAutoDog.handleMouseDown(at: tapPt)
        defaultAutoDog.handleMouseUp(at: tapPt, snapshot: snapB, sceneSize: sceneSize)
        _ = defaultAutoDog.handleMouseDown(at: tapPt)
        defaultAutoDog.handleMouseUp(at: tapPt, snapshot: snapB, sceneSize: sceneSize)
        let skippedDisabledLoaf: Bool = {
            if case .chinRest = defaultAutoDog.state { return true }
            return false
        }()
        testPrefs.setTopTapPose(.loafCalm, enabled: true)
        expect(
            hoverPreservedSleep && tap1Sit && tap2Loaf && tap3BigHead && skippedDisabledLoaf,
            "Top-bar hover never disrupts pose/sleep; tapping cycles cleanly through user-enabled poses (sit -> loaf -> bigHeadPeek)"
        )

        // Shy retreat check: high-speed mouse sweep sets shyRetreatTimer and blocks hover-out
        v04Dog.setHovering(true, pointerSpeed: 820.0, nearZone: true)
        let retreatedOnFastSweep = (v04Dog.shyRetreatTimer > 0 && !v04Dog.isHoveringDog)
        v04Dog.setHovering(true, pointerSpeed: 120.0, nearZone: true)
        let hoveredOnCalmApproach = (v04Dog.shyRetreatTimer == 0 && v04Dog.isHoveringDog)
        expect(retreatedOnFastSweep && hoveredOnCalmApproach, "Fast mouse sweep triggers shy micro-retreat while calm approach invites interaction")

        // 12. v0.4.1 Regression Tests:
        // (a) Secondary monitor with zero menu bar (visibleScreenFrame == screenSize) is NOT misclassified as Full-Screen!
        let extScreenSize = CGSize(width: 2560, height: 1440)
        let extVisible = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let extWin = RawWindowInfo(windowID: 401, ownerPID: 505, ownerName: "Chrome", frame: CGRect(x: 200, y: 200, width: 1200, height: 900), isFrontmostApp: true)
        let extLayout = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [extWin],
            screenSize: extScreenSize,
            visibleScreenFrame: extVisible,
            excludedPID: 777
        )
        expect(!extLayout.isFullScreenMode && extLayout.topPerch != nil && extLayout.windowRightPeek != nil, "Secondary display without menu bar detects normal windowed top & right perches")

        // (b) `perchPreference == .rightPeek` with `climbToTopEnabled == true` (minimum 3s!) STILL climbs to top after 3s!
        testPrefs.perchPreference = .rightPeek
        testPrefs.climbToTopIntervalSeconds = 3.0
        expect(testPrefs.climbToTopIntervalSeconds == 3.0, "Climb-to-top interval supports 3-second minimum for fast testing")
        let rightPrefDog = CompanionController(preferences: testPrefs, ownPID: 777)
        rightPrefDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        var rightPrefClimbed = false
        for _ in 0..<200 { // 10 seconds (3s dwell + 0.6s retract + 0.3s hidden + 3s head peek + 0.7s climb)
            rightPrefDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if rightPrefDog.perchZone == .windowTop {
                rightPrefClimbed = true
                break
            }
        }
        expect(rightPrefClimbed, "perchPreference=.rightPeek honors 3s climbToTopEnabled setting")

        // (c) Tight right-peek hover trigger: distant cursor (65pt away) does NOT trigger; close cursor (18pt) hits cleanly!
        testPrefs.perchPreference = .auto
        testPrefs.dogScale = 1.0
        let hitTestDog = CompanionController(preferences: testPrefs, ownPID: 777)
        hitTestDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        let distantPt = CGPoint(x: hitTestDog.position.x - 65, y: hitTestDog.position.y)
        let closeHeadPt = CGPoint(x: hitTestDog.position.x - 18, y: hitTestDog.position.y + 6)
        expect(
            !hitTestDog.interactiveHitRect().contains(distantPt) && hitTestDog.interactiveHitRect().contains(closeHeadPt),
            "Right-peek trigger stays tight around Westie's visible head (no premature distant hover trigger)"
        )

        // (d) Dog scale preference clamps cleanly (0.60...1.60) and scales hitbox proportionally
        let baseHeight = hitTestDog.interactiveHitRect().height
        testPrefs.dogScale = 1.50
        let bigHeight = hitTestDog.interactiveHitRect().height
        testPrefs.dogScale = 0.20 // should clamp to 0.60
        let clampedMin = testPrefs.dogScale
        expect(abs(bigHeight / baseHeight - 1.50) < 0.05 && abs(clampedMin - 0.60) < 0.001, "Dog size scale clamps to 60%..160% and scales interactive hitbox proportionally")

        // (e) Maximizing / entering Full-Screen while Westie is on `windowTop`:
        // Westie MUST smoothly duck in-place at its current X (ZERO teleport to screenWidth!), then emerge on screen right edge!
        let fsDog = CompanionController(preferences: testPrefs, ownPID: 777)
        testPrefs.perchPreference = .windowTop
        fsDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        let xBeforeFullScreen = fsDog.position.x
        let fullScreenSnap = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: fullScreenLayout,
            windowsFrontToBack: [fullScreenWin],
            windowFramesByID: [202: fullScreenWin.frame],
            screenSize: sceneSize,
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 1440, height: 932),
            frontmostAppName: "Keynote",
            frontmostBundleID: "com.apple.iWork.Keynote",
            isMeetingActive: false,
            isCodingActive: false,
            secondsSinceLastKeyDown: 10.0
        )
        var teleportedDuringRetract = false
        for _ in 0..<60 {
            fsDog.update(dt: 0.05, snapshot: fullScreenSnap, sceneSize: sceneSize)
            if case .stealthTransition(let phase, _, _, _, _) = fsDog.state,
               case .retracting = phase,
               abs(fsDog.position.x - xBeforeFullScreen) > 1.0
            {
                teleportedDuringRetract = true
            }
        }
        expect(
            !teleportedDuringRetract && fsDog.perchZone == .screenRightPeek && fsDog.position.x == 1440,
            "Entering Full-Screen from windowTop ducks smoothly in-place (zero corner teleport) then emerges on screen right bezel"
        )

        // (f) v0.5 Golden Shaded Cat mode + 5-step "闪身步" (Flash-Step) dance routine verification!
        testPrefs.petSpecies = .goldenCat
        testPrefs.topClimbRoutine = .flashStep
        testPrefs.perchPreference = .auto
        let catDog = CompanionController(preferences: testPrefs, ownPID: 777)
        catDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        let targetTopX = snapB.perchLayout.topPerch?.midX ?? 900
        catDog.beginStealthClimbToTop(targetX: targetTopX, windowID: 302, climbToGreet: true, routineOverride: .flashStep)
        var sawStance = false
        var sawDodgeRight = false
        var sawStopMid = false
        var sawReadyLeft = false
        var sawDodgeLeft = false
        var sawFlashSleep = false
        for _ in 0..<700 { // 35 seconds covering climb + 2 rounds of 闪身步 + smile + yawn + sleep
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .flashStep(_, let beat)) = catDog.state {
                switch beat {
                case .stance: sawStance = true
                case .dodgeRight: if sawStance { sawDodgeRight = true }
                case .stopMid: if sawDodgeRight { sawStopMid = true }
                case .readyLeft: if sawStopMid { sawReadyLeft = true }
                case .dodgeLeft: if sawReadyLeft { sawDodgeLeft = true }
                case .finishStop: break
                }
            } else if case .sleeping = catDog.state, sawDodgeLeft {
                sawFlashSleep = true
                break
            }
        }
        expect(
            sawStance && sawDodgeRight && sawStopMid && sawReadyLeft && sawDodgeLeft && sawFlashSleep,
            "Golden Cat + 闪身步 plays full 5-beat dance (起势→往右闪→停→准备→再往左闪) then yawns to sleep"
        )

        // (g) Species-matched snack feeding & eating animation (`chasingTreat` -> `eatingTreat` -> `sitCalm`)
        catDog.dropBoneTreat(snapshot: snapB, sceneSize: sceneSize)
        var sawEatingTreat = false
        var finishedEatingToSit = false
        for _ in 0..<140 { // 7 seconds
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .eatingTreat = catDog.state {
                sawEatingTreat = true
            } else if case .sitCalm = catDog.state, sawEatingTreat {
                finishedEatingToSit = true
                break
            }
        }
        expect(
            sawEatingTreat && finishedEatingToSit && SpriteAssetKey.boneTreat.resourceName(for: .goldenCat) == "dried_fish_treat",
            "Golden Cat uses dried_fish_treat snack and plays full chase -> chewing eatingTreat -> happy sit animation"
        )

        print("Self-test summary: \(passed) passed, \(failed) failed.")
        return failed == 0
    }
}
