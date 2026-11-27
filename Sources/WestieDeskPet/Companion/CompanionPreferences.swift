import Combine
import Foundation

/// User-configurable companion pacing & zero-intrusion preferences, persisted in `UserDefaults`.
@MainActor
public final class CompanionPreferences: ObservableObject {
    public static let shared = CompanionPreferences()

    private enum Keys {
        static let windowSwitchDelay = "westie.companion.v04.windowSwitchDelaySeconds"
        static let climbToTopEnabled = "westie.companion.v04.climbToTopEnabled"
        static let climbToTopInterval = "westie.companion.v04.climbToTopIntervalSeconds"
        static let topEffectsEnabled = "westie.companion.v05.topEffectsEnabled"
        static let topEffectInterval = "westie.companion.v05.topEffectIntervalSeconds"
        static let enabledTopEffects = "westie.companion.v05.enabledTopEffects"
        static let shyRetreatEnabled = "westie.companion.v04.shyRetreatEnabled"
        static let typingPauseEnabled = "westie.companion.v04.typingPauseEnabled"
        static let climbPawsPeekEnabled = "westie.companion.v04.climbPawsPeekEnabled"
        static let dogScale = "westie.companion.v04.dogScale"
        static let topTapPoses = "westie.companion.v04.topTapPoses"
        static let petSpecies = "westie.companion.v05.petSpecies"
        static let perchPreference = "westie.companion.perchPreference"
    }

    public static let effectIntervalPresets: [(title: String, enabled: Bool, seconds: TimeInterval)] = [
        ("5 秒 (快速测试)", true, 5),
        ("15 秒", true, 15),
        ("45 秒", true, 45),
        ("3 分钟", true, 180),
        ("5 分钟", true, 300),
        ("15 分钟 (默认)", true, 900),
        ("30 分钟", true, 1800),
        ("1 小时", true, 3600),
        ("关闭定时特效", false, 900)
    ]

    public static let dogScalePresets: [(title: String, scale: Double)] = [
        ("迷你 (75%)", 0.75),
        ("标准 (100%)", 1.0),
        ("大只 (125%)", 1.25),
        ("超大 (150% 默认)", 1.50)
    ]

    public static let switchDelayPresets: [(title: String, seconds: TimeInterval)] = [
        ("立即跟随 (0 秒)", 0),
        ("3 秒", 3),
        ("5 秒", 5),
        ("10 秒", 10),
        ("15 秒 (默认)", 15)
    ]

    public static let climbIntervalPresets: [(title: String, enabled: Bool, seconds: TimeInterval)] = [
        ("3 秒 (快速测试)", true, 3),
        ("15 秒", true, 15),
        ("30 秒", true, 30),
        ("1 分钟", true, 60),
        ("3 分钟", true, 180),
        ("5 分钟 (默认)", true, 300),
        ("10 分钟", true, 600),
        ("15 分钟", true, 900),
        ("30 分钟", true, 1800),
        ("45 分钟", true, 2700),
        ("60 分钟 (1 小时)", true, 3600),
        ("关闭自动爬顶", false, 300)
    ]

    private let defaults: UserDefaults

    @Published public var windowSwitchDelaySeconds: TimeInterval {
        didSet {
            let clamped = min(max(windowSwitchDelaySeconds, 0), 30)
            if clamped != windowSwitchDelaySeconds {
                windowSwitchDelaySeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.windowSwitchDelay)
            onChanged?()
        }
    }

    @Published public var climbToTopEnabled: Bool {
        didSet {
            defaults.set(climbToTopEnabled, forKey: Keys.climbToTopEnabled)
            onChanged?()
        }
    }

    @Published public var climbToTopIntervalSeconds: TimeInterval {
        didSet {
            let clamped = min(max(climbToTopIntervalSeconds, 3), 3600)
            if clamped != climbToTopIntervalSeconds {
                climbToTopIntervalSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.climbToTopInterval)
            onChanged?()
        }
    }

    @Published public var topEffectsEnabled: Bool {
        didSet {
            defaults.set(topEffectsEnabled, forKey: Keys.topEffectsEnabled)
            onChanged?()
        }
    }

    @Published public var topEffectIntervalSeconds: TimeInterval {
        didSet {
            let clamped = min(max(topEffectIntervalSeconds, 5), 3600)
            if clamped != topEffectIntervalSeconds {
                topEffectIntervalSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.topEffectInterval)
            onChanged?()
        }
    }

    @Published public var enabledTopEffects: Set<TopBarEffect> {
        didSet {
            if enabledTopEffects.isEmpty {
                enabledTopEffects = [.patrol]
                return
            }
            let rawValues = TopBarEffect.allCases.filter { enabledTopEffects.contains($0) }.map(\.rawValue)
            defaults.set(rawValues, forKey: Keys.enabledTopEffects)
            onChanged?()
        }
    }

    public var orderedEnabledTopEffects: [TopBarEffect] {
        let enabled = TopBarEffect.allCases.filter { enabledTopEffects.contains($0) }
        return enabled.isEmpty ? [.patrol] : enabled
    }

    public func isTopEffectEnabled(_ effect: TopBarEffect) -> Bool {
        enabledTopEffects.contains(effect)
    }

    public func setTopEffect(_ effect: TopBarEffect, enabled: Bool) {
        if enabled {
            enabledTopEffects.insert(effect)
        } else if enabledTopEffects.count > 1 {
            enabledTopEffects.remove(effect)
        }
    }

    @Published public var shyRetreatEnabled: Bool {
        didSet {
            defaults.set(shyRetreatEnabled, forKey: Keys.shyRetreatEnabled)
            onChanged?()
        }
    }

    @Published public var typingPauseEnabled: Bool {
        didSet {
            defaults.set(typingPauseEnabled, forKey: Keys.typingPauseEnabled)
            onChanged?()
        }
    }

    @Published public var climbPawsPeekEnabled: Bool {
        didSet {
            defaults.set(climbPawsPeekEnabled, forKey: Keys.climbPawsPeekEnabled)
            onChanged?()
        }
    }

    @Published public var dogScale: Double {
        didSet {
            let clamped = min(max(dogScale, 0.60), 1.60)
            if abs(clamped - dogScale) > 0.0001 {
                dogScale = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.dogScale)
            onChanged?()
        }
    }

    @Published public var topTapEnabledPoses: Set<TopTapPose> {
        didSet {
            if topTapEnabledPoses.isEmpty {
                topTapEnabledPoses = [.sitSmile]
                return
            }
            let rawValues = TopTapPose.allCases.filter { topTapEnabledPoses.contains($0) }.map(\.rawValue)
            defaults.set(rawValues, forKey: Keys.topTapPoses)
            onChanged?()
        }
    }

    public var orderedEnabledTopTapPoses: [TopTapPose] {
        let enabled = TopTapPose.allCases.filter { topTapEnabledPoses.contains($0) }
        return enabled.isEmpty ? [.sitSmile] : enabled
    }

    public func isTopTapPoseEnabled(_ pose: TopTapPose) -> Bool {
        topTapEnabledPoses.contains(pose)
    }

    public func setTopTapPose(_ pose: TopTapPose, enabled: Bool) {
        if enabled {
            topTapEnabledPoses.insert(pose)
        } else if topTapEnabledPoses.count > 1 {
            topTapEnabledPoses.remove(pose)
        }
    }

    @Published public var petSpecies: PetSpecies {
        didSet {
            defaults.set(petSpecies.rawValue, forKey: Keys.petSpecies)
            onChanged?()
        }
    }

    @Published public var perchPreference: PerchPreference {
        didSet {
            defaults.set(perchPreference.rawValue, forKey: Keys.perchPreference)
            onChanged?()
        }
    }

    public var onChanged: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.windowSwitchDelay) != nil {
            self.windowSwitchDelaySeconds = min(max(defaults.double(forKey: Keys.windowSwitchDelay), 0), 30)
        } else {
            self.windowSwitchDelaySeconds = 15.0
        }

        if defaults.object(forKey: Keys.climbToTopEnabled) != nil {
            self.climbToTopEnabled = defaults.bool(forKey: Keys.climbToTopEnabled)
        } else {
            self.climbToTopEnabled = true
        }

        if defaults.object(forKey: Keys.climbToTopInterval) != nil {
            self.climbToTopIntervalSeconds = min(max(defaults.double(forKey: Keys.climbToTopInterval), 3), 3600)
        } else {
            self.climbToTopIntervalSeconds = 300.0
        }

        if defaults.object(forKey: Keys.topEffectsEnabled) != nil {
            self.topEffectsEnabled = defaults.bool(forKey: Keys.topEffectsEnabled)
        } else {
            self.topEffectsEnabled = true
        }

        if defaults.object(forKey: Keys.topEffectInterval) != nil {
            self.topEffectIntervalSeconds = min(max(defaults.double(forKey: Keys.topEffectInterval), 5), 3600)
        } else {
            self.topEffectIntervalSeconds = 900.0
        }

        if let savedEffects = defaults.stringArray(forKey: Keys.enabledTopEffects) {
            let parsed = Set(savedEffects.compactMap(TopBarEffect.init(rawValue:)))
            self.enabledTopEffects = parsed.isEmpty ? Set(TopBarEffect.defaultEnabled) : parsed
        } else {
            self.enabledTopEffects = Set(TopBarEffect.defaultEnabled)
        }

        if defaults.object(forKey: Keys.shyRetreatEnabled) != nil {
            self.shyRetreatEnabled = defaults.bool(forKey: Keys.shyRetreatEnabled)
        } else {
            self.shyRetreatEnabled = true
        }

        if defaults.object(forKey: Keys.typingPauseEnabled) != nil {
            self.typingPauseEnabled = defaults.bool(forKey: Keys.typingPauseEnabled)
        } else {
            self.typingPauseEnabled = true
        }

        if defaults.object(forKey: Keys.climbPawsPeekEnabled) != nil {
            self.climbPawsPeekEnabled = defaults.bool(forKey: Keys.climbPawsPeekEnabled)
        } else {
            self.climbPawsPeekEnabled = true
        }

        if defaults.object(forKey: Keys.dogScale) != nil {
            self.dogScale = min(max(defaults.double(forKey: Keys.dogScale), 0.60), 1.60)
        } else {
            self.dogScale = 1.50
        }

        if let savedPoses = defaults.stringArray(forKey: Keys.topTapPoses) {
            let parsed = Set(savedPoses.compactMap(TopTapPose.init(rawValue:)))
            self.topTapEnabledPoses = parsed.isEmpty ? Set(TopTapPose.defaultSelection) : parsed
        } else {
            self.topTapEnabledPoses = Set(TopTapPose.defaultSelection)
        }

        if let savedSpecies = defaults.string(forKey: Keys.petSpecies),
           let sp = PetSpecies(rawValue: savedSpecies)
        {
            self.petSpecies = sp
        } else {
            self.petSpecies = .westie
        }

        if let savedPref = defaults.string(forKey: Keys.perchPreference) {
            if let pref = PerchPreference(rawValue: savedPref) {
                self.perchPreference = pref
            } else if savedPref == "优先右侧探头" || savedPref == "自动切换 (正上方 + 右侧)" {
                // Migrate legacy default/right-peek preference cleanly to the new screen-right default
                self.perchPreference = .auto
                defaults.set(PerchPreference.auto.rawValue, forKey: Keys.perchPreference)
            } else {
                self.perchPreference = .auto
            }
        } else {
            self.perchPreference = .auto
        }
    }

    public func resetToDefaults() {
        windowSwitchDelaySeconds = 15.0
        climbToTopEnabled = true
        climbToTopIntervalSeconds = 300.0
        topEffectsEnabled = true
        topEffectIntervalSeconds = 900.0
        enabledTopEffects = Set(TopBarEffect.defaultEnabled)
        shyRetreatEnabled = true
        typingPauseEnabled = true
        climbPawsPeekEnabled = true
        dogScale = 1.50
        topTapEnabledPoses = Set(TopTapPose.defaultSelection)
        petSpecies = .westie
        perchPreference = .auto
    }

    public static func formatScale(_ scale: Double) -> String {
        "\(Int((scale * 100.0).rounded()))%"
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        if rounded == 0 {
            return "立即"
        }
        if rounded >= 3600 && rounded % 3600 == 0 {
            return "\(rounded / 3600) 小时"
        }
        if rounded > 3600 {
            return "\(rounded / 3600) 小时 \((rounded % 3600) / 60) 分钟"
        }
        if rounded >= 60 && rounded % 60 == 0 {
            return "\(rounded / 60) 分钟"
        }
        if rounded > 60 {
            return "\(rounded / 60) 分 \(rounded % 60) 秒"
        }
        return "\(rounded) 秒"
    }
}
