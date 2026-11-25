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

/// Describes where Westie can perch relative to the user's current active window or full-screen display.
public struct ActiveWindowPerchLayout: Sendable, Equatable {
    public let activeWindowID: UInt32?
    public let activeWindowFrame: CGRect?
    public let isFullScreenMode: Bool
    /// Top-edge perch interval `(minX, maxX, y)` above the active window (`正上方`), avoiding left traffic lights.
    public let topPerch: WindowPlatform?
    /// Right-edge peek anchor `(edgeX, minY, maxY, defaultY)` on the right border of the active window (`右侧`).
    public let windowRightPeek: RightEdgeAnchor?
    /// Screen right-bezel peek anchor `(edgeX, minY, maxY, defaultY)` used in Full-Screen mode (`屏幕右边探头`).
    public let screenRightPeek: RightEdgeAnchor

    public init(
        activeWindowID: UInt32?,
        activeWindowFrame: CGRect?,
        isFullScreenMode: Bool,
        topPerch: WindowPlatform?,
        windowRightPeek: RightEdgeAnchor?,
        screenRightPeek: RightEdgeAnchor
    ) {
        self.activeWindowID = activeWindowID
        self.activeWindowFrame = activeWindowFrame
        self.isFullScreenMode = isFullScreenMode
        self.topPerch = topPerch
        self.windowRightPeek = windowRightPeek
        self.screenRightPeek = screenRightPeek
    }
}

public struct RightEdgeAnchor: Sendable, Equatable {
    public let edgeX: CGFloat
    public let minY: CGFloat
    public let maxY: CGFloat
    public let defaultY: CGFloat

    public init(edgeX: CGFloat, minY: CGFloat, maxY: CGFloat, defaultY: CGFloat) {
        self.edgeX = edgeX
        self.minY = minY
        self.maxY = maxY
        self.defaultY = defaultY
    }

    public func clampedY(_ y: CGFloat) -> CGFloat {
        guard maxY > minY else { return defaultY }
        return min(max(y, minY), maxY)
    }
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

    /// Computes the active-window companionship layout for a single already-known frontmost window frame in O(1).
    /// Used by the 60/120Hz fast-path tracker while the user drags or resizes the active window!
    public static func computeSingleWindowPerchLayout(
        windowID: UInt32,
        ownerName: String,
        windowFrame: CGRect,
        screenSize: CGSize,
        visibleScreenFrame: CGRect
    ) -> ActiveWindowPerchLayout {
        let raw = RawWindowInfo(
            windowID: windowID,
            ownerPID: 0,
            ownerName: ownerName,
            layer: 0,
            alpha: 1.0,
            frame: windowFrame,
            isFrontmostApp: true
        )
        return computeActiveWindowPerchLayout(
            windowsFrontToBack: [raw],
            screenSize: screenSize,
            visibleScreenFrame: visibleScreenFrame,
            excludedPID: -1
        )
    }

    /// Computes the active-window companionship layout:
    /// - Full-screen Space or maximized window -> `screenRightPeek` (peeking inward from right screen edge)
    /// - Normal active window -> `topPerch` (`正上方`, right of traffic lights) and/or `windowRightPeek` (`右侧` upper-right border)
    public static func computeActiveWindowPerchLayout(
        windowsFrontToBack: [RawWindowInfo],
        screenSize: CGSize,
        visibleScreenFrame: CGRect,
        excludedPID: Int32
    ) -> ActiveWindowPerchLayout {
        let screenRight = RightEdgeAnchor(
            edgeX: screenSize.width,
            minY: max(visibleScreenFrame.minY + 90, 110),
            maxY: max(visibleScreenFrame.minY + 120, screenSize.height - 90),
            defaultY: min(max(screenSize.height * 0.66, 160), screenSize.height - 110)
        )

        let standardWindows = windowsFrontToBack.filter { win in
            win.ownerPID != excludedPID &&
            win.layer == 0 &&
            win.alpha >= 0.2 &&
            win.frame.width >= 200 &&
            win.frame.height >= 120
        }

        // Native macOS Full-Screen Space hides the menu bar so visibleScreenFrame approaches screenSize
        let isNativeFullScreenSpace = visibleScreenFrame.height >= screenSize.height - 4

        guard let activeWin = standardWindows.first(where: { $0.isFrontmostApp }) ?? standardWindows.first else {
            return ActiveWindowPerchLayout(
                activeWindowID: nil,
                activeWindowFrame: nil,
                isFullScreenMode: true,
                topPerch: nil,
                windowRightPeek: nil,
                screenRightPeek: screenRight
            )
        }

        let f = activeWin.frame
        let topHeadroom = visibleScreenFrame.maxY - f.maxY
        let rightHeadroom = screenSize.width - f.maxX

        let coversScreen = (f.width >= screenSize.width - 24 && f.height >= visibleScreenFrame.height - 24)
        let hasNeitherTopNorRightRoom = (topHeadroom < 26 && rightHeadroom < 36)

        if isNativeFullScreenSpace || coversScreen || hasNeitherTopNorRightRoom {
            return ActiveWindowPerchLayout(
                activeWindowID: activeWin.windowID,
                activeWindowFrame: f,
                isFullScreenMode: true,
                topPerch: nil,
                windowRightPeek: nil,
                screenRightPeek: screenRight
            )
        }

        // 1. Top-edge perch (`正上方` — avoid leftmost 78pt where macOS red/yellow/green window buttons live!)
        var topPlatform: WindowPlatform? = nil
        if topHeadroom >= 26 {
            let safeMinX = max(f.minX + 78, visibleScreenFrame.minX + 20)
            let safeMaxX = min(f.maxX - 20, screenSize.width - 24)
            if safeMaxX - safeMinX >= 70 {
                topPlatform = WindowPlatform(
                    windowID: activeWin.windowID,
                    ownerName: activeWin.ownerName,
                    minX: safeMinX,
                    maxX: safeMaxX,
                    y: f.maxY,
                    windowMinX: f.minX,
                    isDockFloor: false,
                    isFrontmost: true
                )
            }
        }

        // 2. Window right-edge peek (`右侧` — upper-right vertical border of active window, just like user's screenshot!)
        var rightPeek: RightEdgeAnchor? = nil
        if rightHeadroom >= 36 && f.maxX >= 120 {
            let maxY = min(f.maxY - 42, visibleScreenFrame.maxY - 44)
            let minY = max(f.minY + 56, min(maxY - 8, f.maxY - 220))
            if maxY >= minY {
                let defaultY = max(minY, min(maxY, f.maxY - 68))
                rightPeek = RightEdgeAnchor(
                    edgeX: f.maxX,
                    minY: minY,
                    maxY: maxY,
                    defaultY: defaultY
                )
            }
        }

        // If somehow neither fit (e.g., narrow edge case), fall back to screen-right peek
        let fallbackFullScreen = (topPlatform == nil && rightPeek == nil)
        return ActiveWindowPerchLayout(
            activeWindowID: activeWin.windowID,
            activeWindowFrame: f,
            isFullScreenMode: fallbackFullScreen,
            topPerch: topPlatform,
            windowRightPeek: rightPeek,
            screenRightPeek: screenRight
        )
    }
}
