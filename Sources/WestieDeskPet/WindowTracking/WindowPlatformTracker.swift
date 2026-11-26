import AppKit
import CoreGraphics
import Foundation

public struct ActiveWorkspaceSnapshot: Sendable {
    public let platforms: [WindowPlatform]
    public let perchLayout: ActiveWindowPerchLayout
    public let windowsFrontToBack: [RawWindowInfo]
    public let windowFramesByID: [UInt32: CGRect]
    public let screenSize: CGSize
    public let visibleScreenFrame: CGRect
    public let frontmostAppName: String
    public let frontmostBundleID: String
    public let isMeetingActive: Bool
    public let isCodingActive: Bool
    public let secondsSinceLastKeyDown: TimeInterval

    public init(
        platforms: [WindowPlatform],
        perchLayout: ActiveWindowPerchLayout,
        windowsFrontToBack: [RawWindowInfo] = [],
        windowFramesByID: [UInt32: CGRect] = [:],
        screenSize: CGSize = CGSize(width: 1440, height: 900),
        visibleScreenFrame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 875),
        frontmostAppName: String,
        frontmostBundleID: String,
        isMeetingActive: Bool,
        isCodingActive: Bool,
        secondsSinceLastKeyDown: TimeInterval = 999
    ) {
        self.platforms = platforms
        self.perchLayout = perchLayout
        self.windowsFrontToBack = windowsFrontToBack
        self.windowFramesByID = windowFramesByID
        self.screenSize = screenSize
        self.visibleScreenFrame = visibleScreenFrame
        self.frontmostAppName = frontmostAppName
        self.frontmostBundleID = frontmostBundleID
        self.isMeetingActive = isMeetingActive
        self.isCodingActive = isCodingActive
        self.secondsSinceLastKeyDown = secondsSinceLastKeyDown
    }

    public func perchLayout(forWindowID windowID: UInt32) -> ActiveWindowPerchLayout? {
        if perchLayout.activeWindowID == windowID {
            return perchLayout
        }
        guard let frame = windowFramesByID[windowID] else { return nil }
        let ownerName = windowsFrontToBack.first(where: { $0.windowID == windowID })?.ownerName ?? "Window"
        return PlatformPhysics.computeSingleWindowPerchLayout(
            windowID: windowID,
            ownerName: ownerName,
            windowFrame: frame,
            screenSize: screenSize,
            visibleScreenFrame: visibleScreenFrame
        )
    }
}

@MainActor
public final class WindowPlatformTracker {
    private let ownPID: Int32

    private static let meetingKeywords: [String] = [
        "zoom", "teams", "facetime", "webex", "lark", "feishu", "tencentmeeting", "voov", "google meet"
    ]
    private static let codingKeywords: [String] = [
        "code", "cursor", "xcode", "iterm", "terminal", "warp", "ghostty", "zed", "intellij", "pycharm", "copilot"
    ]

    public init(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    public func captureSnapshot(for screen: NSScreen) -> ActiveWorkspaceSnapshot {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenFrame = screen.frame
        let localVisibleFrame = CGRect(
            x: screen.visibleFrame.minX - screenFrame.minX,
            y: screen.visibleFrame.minY - screenFrame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )

        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontPID = frontApp?.processIdentifier ?? -1
        let frontName = frontApp?.localizedName ?? ""
        let frontBundle = frontApp?.bundleIdentifier ?? ""

        let loweredContext = "\(frontName) \(frontBundle)".lowercased()
        let isMeeting = Self.meetingKeywords.contains { loweredContext.contains($0) }
        let isCoding = Self.codingKeywords.contains { loweredContext.contains($0) }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let rawList = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

        var parsedWindows: [RawWindowInfo] = []
        parsedWindows.reserveCapacity(rawList.count)

        for entry in rawList {
            guard let windowID = entry[kCGWindowNumber as String] as? UInt32,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
            else {
                continue
            }

            var cgBounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &cgBounds) else {
                continue
            }

            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            let alpha = (entry[kCGWindowAlpha as String] as? CGFloat) ?? 1.0
            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? "Window"

            // Convert Quartz top-left global coordinates -> AppKit bottom-left global -> screen-local scene coordinates
            let globalBottomY = primaryScreenHeight - (cgBounds.origin.y + cgBounds.size.height)
            let globalRect = CGRect(
                x: cgBounds.origin.x,
                y: globalBottomY,
                width: cgBounds.size.width,
                height: cgBounds.size.height
            )

            // Keep windows intersecting this target screen
            guard globalRect.intersects(screenFrame) else { continue }

            let localRect = CGRect(
                x: globalRect.minX - screenFrame.minX,
                y: globalRect.minY - screenFrame.minY,
                width: globalRect.width,
                height: globalRect.height
            )

            parsedWindows.append(
                RawWindowInfo(
                    windowID: windowID,
                    ownerPID: ownerPID,
                    ownerName: ownerName,
                    layer: layer,
                    alpha: alpha,
                    frame: localRect,
                    isFrontmostApp: ownerPID == frontPID
                )
            )
        }

        let platforms = PlatformPhysics.extractVisiblePlatforms(
            windowsFrontToBack: parsedWindows,
            visibleScreenFrame: localVisibleFrame,
            excludedPID: ownPID
        )

        let perchLayout = PlatformPhysics.computeActiveWindowPerchLayout(
            windowsFrontToBack: parsedWindows,
            screenSize: screenFrame.size,
            visibleScreenFrame: localVisibleFrame,
            excludedPID: ownPID
        )

        var framesByID: [UInt32: CGRect] = [:]
        framesByID.reserveCapacity(parsedWindows.count)
        for win in parsedWindows where win.ownerPID != ownPID && win.layer == 0 && win.alpha >= 0.2 {
            framesByID[win.windowID] = win.frame
        }

        let secsSinceKey = Self.querySecondsSinceLastKeyDown()

        return ActiveWorkspaceSnapshot(
            platforms: platforms,
            perchLayout: perchLayout,
            windowsFrontToBack: parsedWindows,
            windowFramesByID: framesByID,
            screenSize: screenFrame.size,
            visibleScreenFrame: localVisibleFrame,
            frontmostAppName: frontName,
            frontmostBundleID: frontBundle,
            isMeetingActive: isMeeting,
            isCodingActive: isCoding,
            secondsSinceLastKeyDown: secsSinceKey
        )
    }

    public static func querySecondsSinceLastKeyDown() -> TimeInterval {
        let secs = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        return secs.isFinite && secs >= 0 ? secs : 999.0
    }

    /// Ultra-lightweight O(1) single-window query (~10µs) via `.optionIncludingWindow`.
    /// Keeps Westie locked at 60/120Hz ProMotion while the user drags or resizes the active (or anchored) window!
    public func fastRefreshActiveWindow(
        in previous: ActiveWorkspaceSnapshot,
        for screen: NSScreen,
        trackedWindowID: UInt32 = 0
    ) -> ActiveWorkspaceSnapshot {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenFrame = screen.frame
        let localVisibleFrame = CGRect(
            x: screen.visibleFrame.minX - screenFrame.minX,
            y: screen.visibleFrame.minY - screenFrame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )

        var updatedLayout = previous.perchLayout
        var updatedFrames = previous.windowFramesByID
        var updatedWindows = previous.windowsFrontToBack
        var didChange = false

        func refreshWindowFrame(_ winID: UInt32) -> (frame: CGRect, ownerName: String)? {
            guard winID != 0,
                  let rawList = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(winID)) as? [[String: Any]],
                  let entry = rawList.first,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
            else {
                return nil
            }
            let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? true
            guard isOnScreen else { return nil }
            var cgBounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &cgBounds) else { return nil }
            let globalBottomY = primaryScreenHeight - (cgBounds.origin.y + cgBounds.size.height)
            let localRect = CGRect(
                x: cgBounds.origin.x - screenFrame.minX,
                y: globalBottomY - screenFrame.minY,
                width: cgBounds.size.width,
                height: cgBounds.size.height
            )
            let owner = (entry[kCGWindowOwnerName as String] as? String) ?? previous.frontmostAppName
            return (localRect, owner)
        }

        if let activeID = previous.perchLayout.activeWindowID, activeID != 0,
           let refreshed = refreshWindowFrame(activeID)
        {
            let oldFrame = previous.perchLayout.activeWindowFrame
            let moved = oldFrame.map {
                abs($0.origin.x - refreshed.frame.origin.x) >= 0.05
                    || abs($0.origin.y - refreshed.frame.origin.y) >= 0.05
                    || abs($0.size.width - refreshed.frame.size.width) >= 0.05
                    || abs($0.size.height - refreshed.frame.size.height) >= 0.05
            } ?? true

            if moved {
                didChange = true
                updatedFrames[activeID] = refreshed.frame
                updatedLayout = PlatformPhysics.computeSingleWindowPerchLayout(
                    windowID: activeID,
                    ownerName: refreshed.ownerName,
                    windowFrame: refreshed.frame,
                    screenSize: screenFrame.size,
                    visibleScreenFrame: localVisibleFrame
                )
                if let idx = updatedWindows.firstIndex(where: { $0.windowID == activeID }) {
                    let old = updatedWindows[idx]
                    updatedWindows[idx] = RawWindowInfo(
                        windowID: old.windowID,
                        ownerPID: old.ownerPID,
                        ownerName: old.ownerName,
                        layer: old.layer,
                        alpha: old.alpha,
                        frame: refreshed.frame,
                        isFrontmostApp: old.isFrontmostApp
                    )
                }
            }
        }

        // Also keep old anchored window refreshed during the 5s dwell delay so Westie never drifts!
        if trackedWindowID != 0 && trackedWindowID != previous.perchLayout.activeWindowID,
           let refreshed = refreshWindowFrame(trackedWindowID)
        {
            let oldFrame = previous.windowFramesByID[trackedWindowID]
            let moved = oldFrame.map {
                abs($0.origin.x - refreshed.frame.origin.x) >= 0.05
                    || abs($0.origin.y - refreshed.frame.origin.y) >= 0.05
                    || abs($0.size.width - refreshed.frame.size.width) >= 0.05
                    || abs($0.size.height - refreshed.frame.size.height) >= 0.05
            } ?? true
            if moved {
                didChange = true
                updatedFrames[trackedWindowID] = refreshed.frame
            }
        }

        let secsSinceKey = Self.querySecondsSinceLastKeyDown()
        if !didChange && abs(secsSinceKey - previous.secondsSinceLastKeyDown) < 0.2 {
            return previous
        }

        return ActiveWorkspaceSnapshot(
            platforms: previous.platforms,
            perchLayout: updatedLayout,
            windowsFrontToBack: updatedWindows,
            windowFramesByID: updatedFrames,
            screenSize: screenFrame.size,
            visibleScreenFrame: localVisibleFrame,
            frontmostAppName: previous.frontmostAppName,
            frontmostBundleID: previous.frontmostBundleID,
            isMeetingActive: previous.isMeetingActive,
            isCodingActive: previous.isCodingActive,
            secondsSinceLastKeyDown: secsSinceKey
        )
    }
}
