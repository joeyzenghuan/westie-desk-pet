import AppKit
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

        // 1. Bundled Sprite Assets check: 100% parity for Westie (72), Golden Cat (68), & Labrador (67 + shared)!
        let totalExpected = SpriteAssetKey.allCases.count
        let missingWestie = SpriteAssetKey.allCases.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .westie) }
        expect(missingWestie.isEmpty && totalExpected == 72, "All \(totalExpected) Westie + shared PNG sprites resolve from bundle (missing: \(missingWestie.map(\.rawValue)))")
        let catPetKeys = SpriteAssetKey.allCases.filter(\.isPetSpecific)
        let missingCat = catPetKeys.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .goldenCat) }
        expect(missingCat.isEmpty && catPetKeys.count == 68, "All \(catPetKeys.count) Golden Shaded Cat sprites (100% parity across all effects) resolve from bundle (missing: \(missingCat.map { $0.resourceName(for: .goldenCat) }))")
        let missingLab = SpriteAssetKey.allCases.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .labrador) }
        expect(missingLab.isEmpty, "All \(totalExpected) Cream-Yellow Labrador sprites (100% parity across all effects & tennis) resolve from bundle (missing: \(missingLab.map { $0.resourceName(for: .labrador) }))")
        let missingChinchilla = SpriteAssetKey.allCases.filter { !SpriteBank.shared.hasRealSprite(for: $0, species: .chinchilla) }
        expect(missingChinchilla.isEmpty, "All \(totalExpected) Silver Chinchilla Persian cat sprites (100% parity across all effects & tennis) resolve from bundle (missing: \(missingChinchilla.map { $0.resourceName(for: .chinchilla) }))")

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
        let topTitles = ctxMenu.items.map(\.title)
        let idxPeek = topTitles.firstIndex(where: { $0 == "👀 探头张望" })
        let idxSleepEffect = topTitles.firstIndex(where: { $0 == "😴 打哈欠睡觉" })
        let idxFeed = topTitles.firstIndex(where: { $0.contains("喂") })
        let idxQuiet = topTitles.firstIndex(where: { $0.contains("趴睡") })
        let idxTennis = topTitles.firstIndex(where: { $0.contains("开始打网球") })
        let idxSpeed = topTitles.firstIndex(where: { $0.contains("网球球速") })
        let idxMoveRight = topTitles.firstIndex(where: { $0 == "👀 移到屏幕右侧边" })
        let idxSpecies = topTitles.firstIndex(where: { $0.contains("切换宠物") })
        let hasSeparatorBeforeSpecies = (idxMoveRight != nil && idxSpecies != nil && idxSpecies! == idxMoveRight! + 2 && ctxMenu.items[idxMoveRight! + 1].isSeparatorItem)
        let settingsMenu = ctxMenu.items.first(where: { $0.title.contains("设置") && $0.submenu != nil })?.submenu
        expect(
            idxPeek == 0
                && topTitles.contains("🐾 跳走巡逻")
                && topTitles.contains("🐻 狗熊哆嗦毛")
                && topTitles.contains("⚽ 浪子踢球")
                && topTitles.contains("🥺 歪头杀")
                && topTitles.contains("🌀 翻肚皮打滚")
                && idxSleepEffect != nil && idxFeed != nil && idxQuiet != nil
                && idxFeed! > idxSleepEffect! && idxQuiet! == idxFeed! + 1
                && idxTennis != nil && idxSpeed != nil && idxSpeed! == idxTennis! + 1
                && hasSeparatorBeforeSpecies
                && settingsMenu != nil && settingsMenu!.items.contains(where: { $0.title.contains("爬顶等待") }),
            "Right-click menu places clean effect labels on Level 1, snack/sleep next, tennis+speed together, species standalone, settings in Level-2"
        )
        let routingPanel = OverlayPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        var remappedTypes: [NSEvent.EventType] = []
        routingPanel.onRemappedSecondaryClickEvent = { event in
            remappedTypes.append(event.type)
            return true
        }
        func syntheticLeftClick(buttonNumber: Int64) -> [NSEvent] {
            [CGEventType.leftMouseDown, .leftMouseUp].compactMap { type in
                let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 50, y: 50), mouseButton: .left)
                // CGEvent normalizes left-type events to button 0, so stamp the remapped button explicitly
                cg?.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
                return cg.flatMap { NSEvent(cgEvent: $0) }
            }
        }
        syntheticLeftClick(buttonNumber: 0).forEach { routingPanel.sendEvent($0) }
        syntheticLeftClick(buttonNumber: 1).forEach { routingPanel.sendEvent($0) }
        expect(
            remappedTypes == [.leftMouseDown, .leftMouseUp],
            "Right button re-posted as leftMouseDown/Up (buttonNumber 1) routes to context menu; plain left taps don't"
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
        expect(
            testPrefs.perchPreference == .auto
                && testPrefs.windowSwitchDelaySeconds == 15.0
                && testPrefs.climbToTopIntervalSeconds == 300.0
                && testPrefs.topEffectIntervalSeconds == 900.0
                && abs(testPrefs.dogScale - 1.50) < 0.001,
            "Fresh default preferences match v1.0 release defaults (screen-right, 15s switch, 5m climb, 15m effect, 150% scale)"
        )
        testPrefs.windowSwitchDelaySeconds = 5.0
        testPrefs.climbToTopEnabled = true
        testPrefs.climbToTopIntervalSeconds = 60.0
        testPrefs.topEffectsEnabled = true
        testPrefs.topEffectIntervalSeconds = 12.0
        testPrefs.enabledTopEffects = Set(TopBarEffect.allCases)
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

        // User stops typing -> Westie stealth-climbs from screen right edge onto window B's top bar,
        // looks left & right, and stays seamlessly in initial head-on-ledge forward pose (`.chinRest`)!
        var sawTopPeek3s = false
        var landedInInitialChinRest = false
        for _ in 0..<120 { // 6 seconds covering retract -> hidden -> 3s left/right peek -> resting forward pose
            defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .stealthTransition(let phase, _, let dest, _, _) = defaultAutoDog.state,
               case .tentativePeek(_, let dur) = phase, dest.perchZone == .windowTop, dur >= 2.9
            {
                sawTopPeek3s = true
            }
            if defaultAutoDog.perchZone == .windowTop, case .chinRest = defaultAutoDog.state {
                landedInInitialChinRest = true
                break
            }
        }
        expect(
            sawTopPeek3s && landedInInitialChinRest,
            "Default climb to top bar peeks left/right then stays in head-on-ledge forward resting pose (.chinRest)"
        )

        // Independent Effect 1: `.patrol` (hop left + look around + walk right -> smile sit -> calm sit, NO auto yawn/sleep!)
        defaultAutoDog.triggerTopBarEffect(.patrol, snapshot: snapB, sceneSize: sceneSize)
        var sawRisingFromPeek = false
        var sawHopLeft = false
        var sawLookAround = false
        var sawWalkRight = false
        var sawSmileSit = false
        var patrolEndedInCalmSit = false
        var patrolTriggeredYawn = false
        for _ in 0..<420 { // 21s
            defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            switch defaultAutoDog.state {
            case .topStory(let step):
                switch step {
                case .risingToFullBody: sawRisingFromPeek = true
                case .hopLeft: sawHopLeft = true
                case .lookAroundPause: if sawHopLeft { sawLookAround = true }
                case .walkRight: if sawLookAround { sawWalkRight = true }
                case .smileSit: if sawWalkRight { sawSmileSit = true }
                case .postClimbPause, .postWalkPause, .flashStep, .bearShake, .wandererKick, .headTilt, .bellyRoll: break
                }
            case .yawning:
                patrolTriggeredYawn = true
            case .sitCalm:
                if sawSmileSit { patrolEndedInCalmSit = true }
            default:
                break
            }
            if patrolEndedInCalmSit { break }
        }
        expect(
            sawRisingFromPeek && sawHopLeft && sawLookAround && sawWalkRight && sawSmileSit && patrolEndedInCalmSit && !patrolTriggeredYawn,
            "Independent Patrol effect rises from peek -> hop LEFT -> look around -> walk RIGHT -> smile -> calm sit (decoupled from sleep)"
        )

        // Independent Effect 3: `.yawnSleep` (yawn -> drowsy -> sleep)
        defaultAutoDog.triggerTopBarEffect(.yawnSleep, snapshot: snapB, sceneSize: sceneSize)
        var sawYawn = false
        var sawSettlingToSleep = false
        var sawSleepingAfterYawn = false
        for _ in 0..<240 { // 12s
            defaultAutoDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            switch defaultAutoDog.state {
            case .yawning: sawYawn = true
            case .settlingToSleep: if sawYawn { sawSettlingToSleep = true }
            case .sleeping: if sawSettlingToSleep { sawSleepingAfterYawn = true }
            default: break
            }
            if sawSleepingAfterYawn { break }
        }
        expect(
            sawYawn && sawSettlingToSleep && sawSleepingAfterYawn,
            "Independent Yawn & Sleep effect plays yawn -> drowsy -> sleep cleanly on demand"
        )

        // Periodic auto-effect trigger: resting in initial `.chinRest` for `topEffectIntervalSeconds` auto-plays an enabled effect!
        testPrefs.topEffectsEnabled = true
        testPrefs.topEffectIntervalSeconds = 5.0
        testPrefs.enabledTopEffects = [.flashStep]
        let autoEffectDog = CompanionController(preferences: testPrefs, ownPID: 777)
        autoEffectDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        autoEffectDog.moveImmediatelyToZone(.windowTop, snapshot: snapB, sceneSize: sceneSize)
        var periodicEffectFired = false
        for _ in 0..<240 { // 12s (3s initial peek + 5s wait + rise + flashStep)
            autoEffectDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .flashStep) = autoEffectDog.state {
                periodicEffectFired = true
                break
            }
        }
        testPrefs.topEffectIntervalSeconds = 3600.0
        let supportsOneHour = (testPrefs.topEffectIntervalSeconds == 3600.0
            && CompanionPreferences.formatDuration(900) == "15 分钟"
            && CompanionPreferences.formatDuration(1800) == "30 分钟"
            && CompanionPreferences.formatDuration(3600) == "1 小时")
        testPrefs.topEffectIntervalSeconds = 5.0
        expect(supportsOneHour, "Top-bar effect interval supports 15min / 30min / 1 hour presets and formatting")
        expect(
            periodicEffectFired,
            "Periodic topEffectIntervalSeconds automatically triggers an enabled top-bar effect from resting initial pose"
        )
        testPrefs.enabledTopEffects = Set(TopBarEffect.allCases)

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

        // (b) `perchPreference == .rightPeek` with `climbToTopEnabled == true` (3s..3600s!) STILL climbs to top after 3s!
        testPrefs.perchPreference = .rightPeek
        testPrefs.climbToTopIntervalSeconds = 3600.0
        let climbSupports1Hour = (testPrefs.climbToTopIntervalSeconds == 3600.0
            && CompanionPreferences.formatDuration(2700) == "45 分钟")
        testPrefs.climbToTopIntervalSeconds = 3.0
        expect(testPrefs.climbToTopIntervalSeconds == 3.0 && climbSupports1Hour, "Climb-to-top interval supports 3s minimum up to 60min (1 hour)")
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

        // (f) v0.5.2 Golden Shaded Cat + independent 8-frame "闪身步" (counter-lean split + pinned-foot flat glide + deadpan freeze)!
        testPrefs.petSpecies = .goldenCat
        testPrefs.perchPreference = .auto
        let catDog = CompanionController(preferences: testPrefs, ownPID: 777)
        catDog.placeInitially(snapshot: snapB, sceneSize: sceneSize)
        catDog.triggerTopBarEffect(.flashStep, snapshot: snapB, sceneSize: sceneSize)
        var sawSplitL = false
        var sawGlideL = false
        var sawSnapL = false
        var sawFreezeL = false
        var sawSplitR = false
        var sawGlideR = false
        var sawSnapR = false
        var sawFlashDone = false
        for _ in 0..<500 { // 25 seconds covering climb + 2 rounds of 8-frame 闪身步 + proud smile -> calm sit
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .flashStep(_, _, _, let beat)) = catDog.state {
                switch beat {
                case .splitFeintLeft: sawSplitL = true
                case .glideWideLeft: if sawSplitL { sawGlideL = true }
                case .snapCloseLeft: if sawGlideL { sawSnapL = true }
                case .statueFreezeLeft: if sawSnapL { sawFreezeL = true }
                case .splitFeintRight: if sawFreezeL { sawSplitR = true }
                case .glideWideRight: if sawSplitR { sawGlideR = true }
                case .snapCloseRight: if sawGlideR { sawSnapR = true }
                case .holdStart, .popLeft, .popRight, .statueFinish: break
                }
            } else if case .sitCalm = catDog.state, sawSnapR {
                sawFlashDone = true
                break
            }
        }
        expect(
            sawSplitL && sawGlideL && sawSnapL && sawFreezeL && sawSplitR && sawGlideR && sawSnapR && sawFlashDone,
            "Golden Cat + independent 8-frame 闪身步 plays full authentic split-feint -> pinned-foot glide -> snap -> freeze L/R -> calm sit"
        )

        // (f2) All 4 new independent effects end-to-end: 狗熊哆嗦毛, 浪子踢球, 歪头杀, & 窗顶打滚 (right -> left -> right)!
        catDog.triggerTopBarEffect(.bearShake, snapshot: snapB, sceneSize: sceneSize)
        var sawBear7 = false
        var bearDone = false
        for _ in 0..<260 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .bearShake(_, _, let idx, _)) = catDog.state, idx == 7 { sawBear7 = true }
            else if case .sitCalm = catDog.state, sawBear7 { bearDone = true; break }
        }
        catDog.triggerTopBarEffect(.wandererKick, snapshot: snapB, sceneSize: sceneSize)
        var sawKickMirror = false
        var kickDone = false
        for _ in 0..<260 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .wandererKick(_, let mirror, let idx, _)) = catDog.state, mirror < 0, idx == 4 { sawKickMirror = true }
            else if case .sitCalm = catDog.state, sawKickMirror { kickDone = true; break }
        }
        catDog.triggerTopBarEffect(.headTilt, snapshot: snapB, sceneSize: sceneSize)
        var sawHeroTilt = false
        var tiltDone = false
        for _ in 0..<180 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .headTilt(let idx, _)) = catDog.state, idx == 10 { sawHeroTilt = true }
            else if case .sitCalm = catDog.state, sawHeroTilt { tiltDone = true; break }
        }
        catDog.triggerTopBarEffect(.windowRoll, snapshot: snapB, sceneSize: sceneSize)
        var reachedBellyWaitSideA = false
        for _ in 0..<20 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .bellyRoll(phase: .waitingBellyUp, sideSign: let side)) = catDog.state, side > 0 {
                reachedBellyWaitSideA = true
                break
            }
        }
        // Wait 6s (< 10s), then click pet -> MUST flip smoothly to opposite side (`sideSign < 0`) and reset 10s timer!
        for _ in 0..<120 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
        }
        let bellyClickPt = CGPoint(x: catDog.position.x, y: catDog.position.y + 20)
        _ = catDog.handleMouseDown(at: bellyClickPt)
        catDog.handleMouseUp(at: bellyClickPt, snapshot: snapB, sceneSize: sceneSize)
        var sawRollingOver = false
        var flippedToSideB = false
        for _ in 0..<40 {
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .topStory(step: .bellyRoll(let phase, let side)) = catDog.state {
                if case .rollingOver = phase { sawRollingOver = true }
                if case .waitingBellyUp = phase, side < 0 { flippedToSideB = true; break }
            }
        }
        // Wait > 10s with NO click -> stands back up into calm `.sitCalm` and ends the round!
        var bellyEndedAfter10s = false
        for _ in 0..<230 { // 11.5s
            catDog.update(dt: 0.05, snapshot: snapB, sceneSize: sceneSize)
            if case .sitCalm = catDog.state {
                bellyEndedAfter10s = true
                break
            }
        }
        expect(
            sawBear7 && bearDone && sawKickMirror && kickDone && sawHeroTilt && tiltDone
                && reachedBellyWaitSideA && sawRollingOver && flippedToSideB && bellyEndedAfter10s,
            "All 4 new effects (狗熊哆嗦毛, 浪子踢球 L/R, 歪头杀, interactive 10s 翻肚皮打滚 click-to-flip) play end-to-end cleanly"
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

        // (h) Deadlock regression: perched on `windowTop`, old window loses top headroom while a new front window
        // touches screen right bezel -> MUST NOT get stuck in `.tuckedWaiting` / `hitRect == .zero` on `.screenRightPeek`!
        let dlPrefs = CompanionPreferences(defaults: testDefaults)
        dlPrefs.perchPreference = .auto
        dlPrefs.windowSwitchDelaySeconds = 5.0
        let dlDog = CompanionController(preferences: dlPrefs, ownPID: 777)
        dlDog.placeInitially(snapshot: snapA, sceneSize: sceneSize)
        dlDog.moveImmediatelyToZone(.windowTop, snapshot: snapA, sceneSize: sceneSize)
        for _ in 0..<110 {
            dlDog.update(dt: 0.05, snapshot: snapA, sceneSize: sceneSize)
        }
        // Old window 301 is pushed flush to menu bar (no topPerch!), while new front window 304 touches screen right edge
        let winAFlushTop = RawWindowInfo(windowID: 301, ownerPID: 500, ownerName: "BrowserA", frame: CGRect(x: 80, y: 120, width: 600, height: 780), isFrontmostApp: false)
        let winDRightFlush = RawWindowInfo(windowID: 304, ownerPID: 509, ownerName: "RightApp", frame: CGRect(x: 700, y: 100, width: 740, height: 740), isFrontmostApp: true)
        let layoutD = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: [winDRightFlush, winAFlushTop],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            excludedPID: 777
        )
        let snapD = ActiveWorkspaceSnapshot(
            platforms: [],
            perchLayout: layoutD,
            windowsFrontToBack: [winDRightFlush, winAFlushTop],
            windowFramesByID: [301: winAFlushTop.frame, 304: winDRightFlush.frame],
            screenSize: sceneSize,
            visibleScreenFrame: screen,
            frontmostAppName: "RightApp",
            frontmostBundleID: "com.test.rightapp",
            isMeetingActive: false,
            isCodingActive: false,
            secondsSinceLastKeyDown: 10.0
        )
        for _ in 0..<25 {
            dlDog.update(dt: 0.05, snapshot: snapD, sceneSize: sceneSize)
        }
        let stuckInTucked: Bool = {
            if case .tuckedWaiting = dlDog.state { return true }
            return false
        }()
        expect(
            dlDog.perchZone == .screenRightPeek && !stuckInTucked && dlDog.interactiveHitRect() != .zero,
            "Fallback from windowTop to screenRightPeek while occluded never deadlocks in hidden tuckedWaiting state"
        )

        print("Self-test summary: \(passed) passed, \(failed) failed.")
        return failed == 0
    }
}
