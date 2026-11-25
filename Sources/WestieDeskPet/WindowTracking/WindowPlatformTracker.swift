import AppKit
import CoreGraphics
import Foundation

public struct ActiveWorkspaceSnapshot: Sendable {
    public let platforms: [WindowPlatform]
    public let perchLayout: ActiveWindowPerchLayout
    public let frontmostAppName: String
    public let frontmostBundleID: String
    public let isMeetingActive: Bool
    public let isCodingActive: Bool
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

        return ActiveWorkspaceSnapshot(
            platforms: platforms,
            perchLayout: perchLayout,
            frontmostAppName: frontName,
            frontmostBundleID: frontBundle,
            isMeetingActive: isMeeting,
            isCodingActive: isCoding
        )
    }

    /// Ultra-lightweight O(1) single-window query (~10µs) via `.optionIncludingWindow`.
    /// Keeps Westie locked at 60/120Hz ProMotion while the user drags or resizes the active window!
    public func fastRefreshActiveWindow(
        in previous: ActiveWorkspaceSnapshot,
        for screen: NSScreen
    ) -> ActiveWorkspaceSnapshot {
        guard let activeID = previous.perchLayout.activeWindowID, activeID != 0 else {
            return previous
        }

        guard let rawList = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(activeID)) as? [[String: Any]],
              let entry = rawList.first,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
        else {
            return previous
        }

        let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? true
        if !isOnScreen {
            return previous
        }

        var cgBounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDict, &cgBounds) else {
            return previous
        }

        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenFrame = screen.frame
        let globalBottomY = primaryScreenHeight - (cgBounds.origin.y + cgBounds.size.height)
        let localRect = CGRect(
            x: cgBounds.origin.x - screenFrame.minX,
            y: globalBottomY - screenFrame.minY,
            width: cgBounds.size.width,
            height: cgBounds.size.height
        )

        if let oldFrame = previous.perchLayout.activeWindowFrame,
           abs(oldFrame.origin.x - localRect.origin.x) < 0.05,
           abs(oldFrame.origin.y - localRect.origin.y) < 0.05,
           abs(oldFrame.size.width - localRect.size.width) < 0.05,
           abs(oldFrame.size.height - localRect.size.height) < 0.05
        {
            return previous
        }

        let localVisibleFrame = CGRect(
            x: screen.visibleFrame.minX - screenFrame.minX,
            y: screen.visibleFrame.minY - screenFrame.minY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
        let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? previous.frontmostAppName
        let updatedLayout = PlatformPhysics.computeSingleWindowPerchLayout(
            windowID: activeID,
            ownerName: ownerName,
            windowFrame: localRect,
            screenSize: screenFrame.size,
            visibleScreenFrame: localVisibleFrame
        )

        return ActiveWorkspaceSnapshot(
            platforms: previous.platforms,
            perchLayout: updatedLayout,
            frontmostAppName: previous.frontmostAppName,
            frontmostBundleID: previous.frontmostBundleID,
            isMeetingActive: previous.isMeetingActive,
            isCodingActive: previous.isCodingActive
        )
    }
}
