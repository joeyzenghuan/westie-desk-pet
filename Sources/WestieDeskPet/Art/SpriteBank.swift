import AppKit
import SpriteKit

public enum SpriteAssetKey: String, CaseIterable, Sendable {
    // Westie Companion
    case westieIdle = "westie_idle"
    case westieWalk1 = "westie_walk_1"
    case westieWalk2 = "westie_walk_2"
    case westieSitTilt = "westie_sit_tilt"
    case westieSleep = "westie_sleep"
    case westieDangling = "westie_dangling"
    case westiePeekCalm = "westie_peek_calm"
    case westiePeekHover = "westie_peek_hover"
    case westieLoafCalm = "westie_loaf_calm"
    case westieChinLedge = "westie_chin_ledge"

    // Westie Tennis & Special
    case westieHoldingBall = "westie_holding_ball"
    case westieTennisReady = "westie_tennis_ready"
    case westieTennisRun = "westie_tennis_run"
    case westieTennisSwing = "westie_tennis_swing"
    case westieTennisDive = "westie_tennis_dive"
    case westieVictory = "westie_victory"

    // Human Player & Props
    case playerReady = "player_ready"
    case playerRun = "player_run"
    case playerSwing = "player_swing"
    case tennisBall = "tennis_ball"
    case boneTreat = "bone_treat"
    case badgeIcon = "badge_icon"
}

@MainActor
public final class SpriteBank {
    public static let shared = SpriteBank()

    private var cache: [SpriteAssetKey: SKTexture] = [:]

    private init() {}

    public func texture(for key: SpriteAssetKey) -> SKTexture {
        if let existing = cache[key] {
            return existing
        }
        let loaded = loadFromBundle(key: key) ?? makeProceduralFallback(for: key)
        loaded.filteringMode = .nearest
        cache[key] = loaded
        return loaded
    }

    public func nsImage(for key: SpriteAssetKey) -> NSImage? {
        if let url = locateSpriteURL(named: key.rawValue),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }

    public func hasRealSprite(for key: SpriteAssetKey) -> Bool {
        locateSpriteURL(named: key.rawValue) != nil
    }

    private func locateSpriteURL(named name: String) -> URL? {
        // 1. Check standalone .app bundle Contents/Resources/Sprites FIRST (portable & codesign-clean!)
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Sprites") {
            return url
        }
        // 2. Check SwiftPM resource bundle in Contents/Resources/ if present
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("WestieDeskPet_WestieDeskPetCore.bundle"),
           let spmBundle = Bundle(url: resURL),
           let url = spmBundle.url(forResource: name, withExtension: "png", subdirectory: "Sprites")
        {
            return url
        }
        // 3. Fallback to SwiftPM Bundle.module during `swift run` development
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites") {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png") {
            return url
        }
        return nil
    }

    private func loadFromBundle(key: SpriteAssetKey) -> SKTexture? {
        guard let url = locateSpriteURL(named: key.rawValue),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        return SKTexture(image: image)
    }

    /// Crisp pixel-art fallback so tests and headless environments never fail if PNGs aren't unpacked yet.
    private func makeProceduralFallback(for key: SpriteAssetKey) -> SKTexture {
        let size = NSSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none

        switch key {
        case .tennisBall:
            NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.22, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: 16, height: 16)).fill()
            NSColor.white.setStroke()
            let arc = NSBezierPath()
            arc.move(to: NSPoint(x: 10, y: 12))
            arc.curve(to: NSPoint(x: 22, y: 20), controlPoint1: NSPoint(x: 15, y: 18), controlPoint2: NSPoint(x: 17, y: 14))
            arc.lineWidth = 2
            arc.stroke()

        case .boneTreat:
            NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
            NSRect(x: 9, y: 13, width: 14, height: 6).fill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 11, width: 6, height: 10)).fill()
            NSBezierPath(ovalIn: NSRect(x: 21, y: 11, width: 6, height: 10)).fill()

        case .playerReady, .playerRun, .playerSwing:
            // Green tennis shirt + white cap pixel character
            NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.36, alpha: 1.0).setFill()
            NSRect(x: 10, y: 8, width: 12, height: 11).fill()
            NSColor.white.setFill()
            NSRect(x: 10, y: 4, width: 5, height: 4).fill()
            NSRect(x: 17, y: 4, width: 5, height: 4).fill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 18, width: 12, height: 11)).fill()

        default:
            // Cute pixel white Westie silhouette with pointy ears, sky-blue collar & black nose
            NSColor.white.setFill()
            NSRect(x: 7, y: 6, width: 15, height: 11).fill()     // body
            NSRect(x: 16, y: 15, width: 11, height: 10).fill()   // head
            NSRect(x: 17, y: 25, width: 3, height: 4).fill()     // left ear
            NSRect(x: 23, y: 25, width: 3, height: 4).fill()     // right ear
            NSRect(x: 4, y: 13, width: 3, height: 6).fill()      // perky tail
            NSRect(x: 8, y: 2, width: 3, height: 4).fill()       // back leg
            NSRect(x: 18, y: 2, width: 3, height: 4).fill()      // front leg
            NSColor(calibratedRed: 0.25, green: 0.68, blue: 0.95, alpha: 1.0).setFill()
            NSRect(x: 16, y: 14, width: 9, height: 2).fill()     // collar
            NSColor.black.setFill()
            NSRect(x: 21, y: 20, width: 2, height: 2).fill()     // eye
            NSRect(x: 26, y: 18, width: 2, height: 2).fill()     // nose
        }

        img.unlockFocus()
        return SKTexture(image: img)
    }
}
