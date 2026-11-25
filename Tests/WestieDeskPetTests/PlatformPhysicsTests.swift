#if canImport(Testing)
import CoreGraphics
import Testing
@testable import WestieDeskPetCore

@Suite("Window Platform Physics & Occlusion")
struct PlatformPhysicsTests {
    @Test("Front window occludes overlapping part of back window top edge")
    func occlusionSplitsOrTrimsBackWindow() {
        let screen = CGRect(x: 0, y: 60, width: 1440, height: 840)

        let frontWindow = RawWindowInfo(
            windowID: 101,
            ownerPID: 500,
            ownerName: "Code",
            frame: CGRect(x: 200, y: 300, width: 400, height: 420), // covers x: 200...600, y: 300...720
            isFrontmostApp: true
        )
        let backWindow = RawWindowInfo(
            windowID: 102,
            ownerPID: 501,
            ownerName: "Terminal",
            frame: CGRect(x: 400, y: 200, width: 500, height: 400), // topY = 600, x: 400...900 (400...600 occluded!)
            isFrontmostApp: false
        )
        let ownOverlay = RawWindowInfo(
            windowID: 999,
            ownerPID: 777,
            ownerName: "WestieDeskPet",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            isFrontmostApp: false
        )

        let platforms = PlatformPhysics.extractVisiblePlatforms(
            windowsFrontToBack: [ownOverlay, frontWindow, backWindow],
            visibleScreenFrame: screen,
            excludedPID: 777
        )

        // Own overlay must be excluded
        #expect(!platforms.contains(where: { $0.windowID == 999 }))

        // Front window top bar at y = 720 should be fully visible
        let frontPlat = platforms.first(where: { $0.windowID == 101 })
        #expect(frontPlat != nil)
        #expect(frontPlat?.y == 720)

        // Back window top bar at y = 600 should only expose the non-occluded right part (> 600)
        let backPlat = platforms.first(where: { $0.windowID == 102 })
        #expect(backPlat != nil)
        #expect((backPlat?.minX ?? 0) >= 600)
        #expect((backPlat?.maxX ?? 0) <= 900)

        // Dock floor fallback must always exist
        #expect(platforms.contains(where: { $0.isDockFloor }))
    }

    @Test("Cross-window jump planner finds reachable neighbor and prefers frontmost")
    func crossWindowJumpPlanning() {
        let startPlat = WindowPlatform(
            windowID: 1,
            ownerName: "Safari",
            minX: 100,
            maxX: 400,
            y: 500,
            windowMinX: 100,
            isDockFloor: false,
            isFrontmost: false
        )
        let frontTarget = WindowPlatform(
            windowID: 2,
            ownerName: "Xcode",
            minX: 480,
            maxX: 900,
            y: 580,
            windowMinX: 480,
            isDockFloor: false,
            isFrontmost: true
        )

        let arc = PlatformPhysics.planCrossWindowJump(
            from: startPlat,
            startX: 380,
            startY: 500,
            platforms: [frontTarget, startPlat]
        )

        #expect(arc != nil)
        #expect(arc?.targetPlatform.windowID == 2)
        #expect((arc?.initialVelocity.dx ?? 0) > 0)
        #expect((arc?.initialVelocity.dy ?? 0) > 0)
    }

    @Test("Meeting context puts Westie into calm sleep behavior")
    func meetingContextTriggersSleep() {
        let plat = WindowPlatform(
            windowID: 10,
            ownerName: "Teams",
            minX: 100,
            maxX: 600,
            y: 620,
            windowMinX: 100,
            isDockFloor: false,
            isFrontmost: true
        )
        let next = WestieBehaviorPlanner.chooseNextTopBehavior(
            currentX: 300,
            platform: plat,
            context: CompanionContext(isMeetingActive: true)
        )
        if case .sleeping = next {
            #expect(Bool(true))
        } else {
            Issue.record("Expected Westie to sleep during active meeting, got \(next)")
        }
    }
}
#endif
