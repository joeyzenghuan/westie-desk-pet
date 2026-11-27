import AppKit
import ImageIO
import SpriteKit

public enum SpriteAssetKey: String, CaseIterable, Sendable {
    // Westie Companion
    case westieIdle = "westie_idle"
    case westieWalk1 = "westie_walk_1"
    case westieWalk2 = "westie_walk_2"
    case westieWalk3 = "westie_walk_3"
    case westieWalk4 = "westie_walk_4"
    case westieSitTilt = "westie_sit_tilt"
    case westieSleep = "westie_sleep"
    case westieDangling = "westie_dangling"
    case westiePeekCalm = "westie_peek_calm"
    case westiePeekHover = "westie_peek_hover"
    case westieLoafCalm = "westie_loaf_calm"
    case westieChinLedge = "westie_chin_ledge"

    // Westie v0.4.2 Climb, Look-Around, Yawn & Drowsy Transition Frames
    case westieTopPeekCenter = "westie_top_peek_center"
    case westieTopPeekLeft = "westie_top_peek_left"
    case westieTopPeekRight = "westie_top_peek_right"
    case westieClimbUp = "westie_climb_up"
    case westieYawn = "westie_yawn"
    case westieDrowsy = "westie_drowsy"

    // Westie v0.4.3 Bouncy Hop Cycle & Stationary-Body Head-Turn Frames
    case westieHopCrouch = "westie_hop_crouch"
    case westieHopAir = "westie_hop_air"
    case westieHopLand = "westie_hop_land"
    case westieLookLeftHeadLeft = "westie_look_left_head_left"
    case westieLookLeftHeadCenter = "westie_look_left_head_center"
    case westieLookLeftHeadRight = "westie_look_left_head_right"

    // v0.5.2 Authentic 8-Frame Bipedal Flash-Step ("闪身步": F56/F60/F66/F70/F73/F102/F107/F110, 192x128 height-locked)
    case westieFlashStep1 = "westie_flash_step_1"
    case westieFlashStep2 = "westie_flash_step_2"
    case westieFlashStep3 = "westie_flash_step_3"
    case westieFlashStep4 = "westie_flash_step_4"
    case westieFlashStep5 = "westie_flash_step_5"
    case westieFlashStep6 = "westie_flash_step_6"
    case westieFlashStep7 = "westie_flash_step_7"
    case westieFlashStep8 = "westie_flash_step_8"

    // v0.5.3 8-Frame "狗熊哆嗦毛" (Bear Fur Shake dance, 192x128 height-locked)
    case westieBearShake1 = "westie_bear_shake_1"
    case westieBearShake2 = "westie_bear_shake_2"
    case westieBearShake3 = "westie_bear_shake_3"
    case westieBearShake4 = "westie_bear_shake_4"
    case westieBearShake5 = "westie_bear_shake_5"
    case westieBearShake6 = "westie_bear_shake_6"
    case westieBearShake7 = "westie_bear_shake_7"
    case westieBearShake8 = "westie_bear_shake_8"

    // v0.5.3 6-Frame "浪子踢球" (Wanderer Ball Kick folk dance, 192x128 height-locked)
    case westieWandererKick1 = "westie_wanderer_kick_1"
    case westieWandererKick2 = "westie_wanderer_kick_2"
    case westieWandererKick3 = "westie_wanderer_kick_3"
    case westieWandererKick4 = "westie_wanderer_kick_4"
    case westieWandererKick5 = "westie_wanderer_kick_5"
    case westieWandererKick6 = "westie_wanderer_kick_6"

    // v0.5.4 6-Frame Interactive "翻肚皮打滚" (pose-locked to 打滚.mp4, 128x128)
    case westieBellyRoll1 = "westie_belly_roll_1"
    case westieBellyRoll2 = "westie_belly_roll_2"
    case westieBellyRoll3 = "westie_belly_roll_3"
    case westieBellyRoll4 = "westie_belly_roll_4"
    case westieBellyRoll5 = "westie_belly_roll_5"
    case westieBellyRoll6 = "westie_belly_roll_6"

    // v0.5.3 6-Frame "歪头杀" (Head-Tilt Kill stationary front-facing sit, 128x128)
    case westieHeadTilt1 = "westie_head_tilt_1"
    case westieHeadTilt2 = "westie_head_tilt_2"
    case westieHeadTilt3 = "westie_head_tilt_3"
    case westieHeadTilt4 = "westie_head_tilt_4"
    case westieHeadTilt5 = "westie_head_tilt_5"
    case westieHeadTilt6 = "westie_head_tilt_6"

    // v0.5.1 Snack Chewing Animation (Westie chewing bone / Golden Cat chewing dried fish)
    case westieEat1 = "westie_eat_1"
    case westieEat2 = "westie_eat_2"

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
    public func resourceName(for species: PetSpecies) -> String {
        switch species {
        case .westie:
            return rawValue
        case .goldenCat:
            if rawValue.hasPrefix("westie_") {
                return "cat_" + rawValue.dropFirst("westie_".count)
            }
            if self == .badgeIcon {
                return "cat_badge_icon"
            }
            if self == .boneTreat {
                return "dried_fish_treat"
            }
            return rawValue
        case .labrador:
            if rawValue.hasPrefix("westie_") {
                return "lab_" + rawValue.dropFirst("westie_".count)
            }
            if self == .badgeIcon {
                return "lab_badge_icon"
            }
            return rawValue
        case .chinchilla:
            if rawValue.hasPrefix("westie_") {
                return "chinchilla_" + rawValue.dropFirst("westie_".count)
            }
            if self == .badgeIcon {
                return "chinchilla_badge_icon"
            }
            if self == .boneTreat {
                return "dried_fish_treat"
            }
            return rawValue
        case .silverChinchilla:
            if rawValue.hasPrefix("westie_") {
                return "chinchilla2_" + rawValue.dropFirst("westie_".count)
            }
            if self == .badgeIcon {
                return "chinchilla2_badge_icon"
            }
            if self == .boneTreat {
                return "dried_fish_treat"
            }
            return rawValue
        }
    }

    public var isPetSpecific: Bool {
        rawValue.hasPrefix("westie_") || self == .badgeIcon || self == .boneTreat
    }
}

@MainActor
public final class SpriteBank {
    public static let shared = SpriteBank()

    private var cache: [String: SKTexture] = [:]
    private var preloadedSpecies: Set<PetSpecies> = []

    private init() {}

    /// Warms decoded CGImages off the main thread (never calling `SKTexture.preload`, which can stall
    /// SpriteKit's Metal display link on macOS 26!) and installs crisp nearest-neighbor `SKTexture`s on MainActor.
    public func preloadSpecies(_ species: PetSpecies) {
        guard !preloadedSpecies.contains(species) else { return }
        preloadedSpecies.insert(species)

        var workItems: [(name: String, url: URL)] = []
        for key in SpriteAssetKey.allCases {
            let name = key.resourceName(for: species)
            if cache[name] != nil { continue }
            if let url = locateSpriteURL(named: name) {
                workItems.append((name, url))
            }
        }
        guard !workItems.isEmpty else { return }
        let itemsToDecode = workItems

        DispatchQueue.global(qos: .userInitiated).async {
            var decoded: [(String, CGImage)] = []
            decoded.reserveCapacity(itemsToDecode.count)
            let opts: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            for item in itemsToDecode {
                if let src = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                   let cg = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
                {
                    decoded.append((item.name, cg))
                }
            }
            Task { @MainActor in
                for (name, cg) in decoded {
                    if self.cache[name] == nil {
                        let tex = SKTexture(cgImage: cg)
                        tex.filteringMode = .nearest
                        self.cache[name] = tex
                    }
                }
            }
        }
    }

    public func texture(for key: SpriteAssetKey, species: PetSpecies = .westie) -> SKTexture {
        let name = key.resourceName(for: species)
        if let existing = cache[name] {
            return existing
        }
        let loaded = loadFromBundle(resourceName: name)
            ?? (species != .westie ? loadFromBundle(resourceName: key.rawValue) : nil)
            ?? makeProceduralFallback(for: key, species: species)
        loaded.filteringMode = .nearest
        cache[name] = loaded
        return loaded
    }

    public func nsImage(for key: SpriteAssetKey, species: PetSpecies = .westie) -> NSImage? {
        let name = key.resourceName(for: species)
        if let url = locateSpriteURL(named: name),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        if species != .westie,
           let url = locateSpriteURL(named: key.rawValue),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return nil
    }

    public func hasRealSprite(for key: SpriteAssetKey, species: PetSpecies = .westie) -> Bool {
        locateSpriteURL(named: key.resourceName(for: species)) != nil
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

    private func loadFromBundle(resourceName: String) -> SKTexture? {
        guard let url = locateSpriteURL(named: resourceName) else {
            return nil
        }
        // Decode PNG directly into an immediately-cached premultiplied CGImage -> SKTexture(cgImage:)
        // to avoid NSImage Retina rep overhead & first-frame Metal upload white-flash!
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let cgImage = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) {
                return SKTexture(cgImage: cgImage)
            }
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        return SKTexture(image: image)
    }

    /// Crisp pixel-art fallback so tests and headless environments never fail if PNGs aren't unpacked yet.
    private func makeProceduralFallback(for key: SpriteAssetKey, species: PetSpecies) -> SKTexture {
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
