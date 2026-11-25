import CoreGraphics
import Foundation

public struct RawWindowInfo: Sendable, Equatable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let ownerName: String
    public let layer: Int
    public let alpha: CGFloat
    /// Bounds already converted into bottom-left scene coordinates.
    public let frame: CGRect
    public let isFrontmostApp: Bool

    public init(
        windowID: UInt32,
        ownerPID: Int32,
        ownerName: String,
        layer: Int = 0,
        alpha: CGFloat = 1.0,
        frame: CGRect,
        isFrontmostApp: Bool = false
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.layer = layer
        self.alpha = alpha
        self.frame = frame
        self.isFrontmostApp = isFrontmostApp
    }
}

public struct WindowPlatform: Sendable, Equatable, Identifiable {
    public var id: String { "\(windowID)-\(Int(minX.rounded()))-\(Int(y.rounded()))" }
    public let windowID: UInt32
    public let ownerName: String
    public let minX: CGFloat
    public let maxX: CGFloat
    public let y: CGFloat
    public let windowMinX: CGFloat
    public let isDockFloor: Bool
    public let isFrontmost: Bool

    public var width: CGFloat { max(0, maxX - minX) }
    public var midX: CGFloat { (minX + maxX) * 0.5 }

    public func containsX(_ x: CGFloat, margin: CGFloat = 10) -> Bool {
        x >= (minX + margin) && x <= (maxX - margin)
    }

    public func clampedX(_ x: CGFloat, margin: CGFloat = 18) -> CGFloat {
        guard maxX - minX > margin * 2 else { return midX }
        return min(max(x, minX + margin), maxX - margin)
    }
}

public struct JumpArc: Sendable, Equatable {
    public let targetPlatform: WindowPlatform
    public let targetX: CGFloat
    public let initialVelocity: CGVector
    public let duration: TimeInterval
}

public enum PlatformPhysics {
    public static let gravity: CGFloat = 1180.0
    public static let minSegmentWidth: CGFloat = 76.0
    public static let headClearance: CGFloat = 38.0

    /// Extracts visible, non-occluded window top-edge platforms ordered high-to-low, plus the Dock floor fallback.
    public static func extractVisiblePlatforms(
        windowsFrontToBack: [RawWindowInfo],
        visibleScreenFrame: CGRect,
        excludedPID: Int32
    ) -> [WindowPlatform] {
        var occluders: [CGRect] = []
        var platforms: [WindowPlatform] = []

        let maxAllowedTopY = visibleScreenFrame.maxY - headClearance
        let minAllowedTopY = visibleScreenFrame.minY + 24

        for win in windowsFrontToBack {
            guard win.ownerPID != excludedPID,
                  win.layer == 0,
                  win.alpha >= 0.2,
                  win.frame.width >= 140,
                  win.frame.height >= 70
            else {
                continue
            }

            let clippedMinX = max(win.frame.minX, visibleScreenFrame.minX + 6)
            let clippedMaxX = min(win.frame.maxX, visibleScreenFrame.maxX - 6)
            let topY = win.frame.maxY

            if topY <= maxAllowedTopY,
               topY >= minAllowedTopY,
               clippedMaxX - clippedMinX >= minSegmentWidth
            {
                // Check which parts of [clippedMinX, clippedMaxX] at height (topY + 6) are NOT covered by front windows
                let probeY = topY + 6
                var intervals: [(CGFloat, CGFloat)] = [(clippedMinX + 8, clippedMaxX - 8)]

                for occ in occluders {
                    if probeY >= occ.minY && probeY <= occ.maxY + 18 {
                        intervals = subtractInterval(
                            from: intervals,
                            cutMin: occ.minX - 6,
                            cutMax: occ.maxX + 6
                        )
                        if intervals.isEmpty { break }
                    }
                }

                for (segMin, segMax) in intervals where (segMax - segMin) >= minSegmentWidth {
                    platforms.append(
                        WindowPlatform(
                            windowID: win.windowID,
                            ownerName: win.ownerName,
                            minX: segMin,
                            maxX: segMax,
                            y: topY,
                            windowMinX: win.frame.minX,
                            isDockFloor: false,
                            isFrontmost: win.isFrontmostApp
                        )
                    )
                }
            }

            // Every opaque normal window occludes windows behind it
            occluders.append(win.frame)
        }

        // Always append Dock / visible screen bottom as safe fallback floor
        let dockFloor = WindowPlatform(
            windowID: 0,
            ownerName: "Dock",
            minX: visibleScreenFrame.minX + 24,
            maxX: visibleScreenFrame.maxX - 24,
            y: max(visibleScreenFrame.minY, 4),
            windowMinX: visibleScreenFrame.minX,
            isDockFloor: true,
            isFrontmost: false
        )
        platforms.append(dockFloor)

        return platforms.sorted { lhs, rhs in
            if abs(lhs.y - rhs.y) > 0.5 {
                return lhs.y > rhs.y
            }
            return lhs.minX < rhs.minX
        }
    }

    public static func subtractInterval(
        from intervals: [(CGFloat, CGFloat)],
        cutMin: CGFloat,
        cutMax: CGFloat
    ) -> [(CGFloat, CGFloat)] {
        guard cutMax > cutMin else { return intervals }
        var result: [(CGFloat, CGFloat)] = []
        for (a, b) in intervals {
            if cutMax <= a || cutMin >= b {
                result.append((a, b))
            } else {
                if cutMin > a {
                    result.append((a, cutMin))
                }
                if cutMax < b {
                    result.append((cutMax, b))
                }
            }
        }
        return result
    }

    /// Finds a landing platform crossed during downward movement from `prevY` to `nextY`.
    public static func findLandingPlatform(
        x: CGFloat,
        prevY: CGFloat,
        nextY: CGFloat,
        platforms: [WindowPlatform]
    ) -> WindowPlatform? {
        guard nextY <= prevY + 2 else { return nil }
        let candidates = platforms.filter { plat in
            plat.containsX(x, margin: 8) &&
            plat.y <= prevY + 10 &&
            plat.y >= nextY - 6
        }
        return candidates.max(by: { $0.y < $1.y })
    }

    /// Computes a parabolic jump arc from `(startX, startY)` onto another window platform.
    public static func planCrossWindowJump(
        from currentPlatform: WindowPlatform,
        startX: CGFloat,
        startY: CGFloat,
        platforms: [WindowPlatform],
        preferFrontmost: Bool = true
    ) -> JumpArc? {
        let others = platforms.filter { candidate in
            candidate.id != currentPlatform.id &&
            candidate.windowID != currentPlatform.windowID &&
            candidate.width >= 90
        }
        guard !others.isEmpty else { return nil }

        struct ScoredTarget {
            let platform: WindowPlatform
            let targetX: CGFloat
            let score: CGFloat
        }

        var scored: [ScoredTarget] = []
        for plat in others {
            // Pick closest comfortable landing X on the target platform
            let tx = plat.clampedX(startX, margin: 28)
            let dx = tx - startX
            let dy = plat.y - startY
            let absDx = abs(dx)

            // Reachable jump envelope
            guard absDx <= 340, dy <= 190, dy >= -280 else { continue }
            // Avoid trivial tiny drops straight down unless jumping onto an actual window from Dock
            if absDx < 20 && abs(dy) < 18 { continue }

            var score: CGFloat = 380 - hypot(dx, dy)
            if !plat.isDockFloor { score += 90 }
            if preferFrontmost && plat.isFrontmost { score += 110 }
            scored.append(ScoredTarget(platform: plat, targetX: tx, score: score))
        }

        guard let best = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        let dx = best.targetX - startX
        let dy = best.platform.y - startY
        let distance = hypot(dx, dy)
        let duration = TimeInterval(min(max(distance / 420.0, 0.38), 0.72))
        let t = CGFloat(duration)
        let vx = dx / t
        // y(t) = y0 + vy*t - 0.5*g*t^2  =>  vy = (dy + 0.5*g*t^2) / t
        let vy = (dy + 0.5 * gravity * t * t) / t

        return JumpArc(
            targetPlatform: best.platform,
            targetX: best.targetX,
            initialVelocity: CGVector(dx: vx, dy: vy),
            duration: duration
        )
    }
}
