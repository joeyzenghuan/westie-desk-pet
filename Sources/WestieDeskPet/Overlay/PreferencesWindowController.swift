import AppKit
import SwiftUI

@MainActor
public final class PreferencesWindowController {
    public static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private var onPreviewPeek: (() -> Void)?
    private var onPlayEffect: ((TopBarEffect) -> Void)?

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    private init() {}

    public func show(
        preferences: CompanionPreferences = .shared,
        onPreviewPeek: (() -> Void)? = nil,
        onPlayEffect: ((TopBarEffect) -> Void)? = nil
    ) {
        if let onPreviewPeek {
            self.onPreviewPeek = onPreviewPeek
        }
        if let onPlayEffect {
            self.onPlayEffect = onPlayEffect
        }
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = CompanionPreferencesView(
            preferences: preferences,
            onPreviewPeek: { [weak self] in
                self?.onPreviewPeek?()
            },
            onPlayEffect: { [weak self] effect in
                self?.onPlayEffect?(effect)
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 780),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "⚙️ 桌面宠物陪伴偏好设置"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = hostingController
        panel.center()
        self.window = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct CompanionPreferencesView: View {
    @ObservedObject var preferences: CompanionPreferences
    let onPreviewPeek: () -> Void
    let onPlayEffect: (TopBarEffect) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            // Section 0: Pet Species & Appearance Size
            GroupBox(label: Label("宠物角色与外观大小", systemImage: "pawprint.circle")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("当前桌面宠物", selection: $preferences.petSpecies) {
                        ForEach(PetSpecies.allCases) { sp in
                            Text(sp.shortName).tag(sp)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("宠物尺寸")
                        Spacer()
                        Text(CompanionPreferences.formatScale(preferences.dogScale))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $preferences.dogScale,
                        in: 0.60...1.60,
                        step: 0.05
                    )
                    HStack(spacing: 6) {
                        ForEach([0.75, 1.0, 1.25, 1.50], id: \.self) { val in
                            Button(CompanionPreferences.formatScale(val)) {
                                preferences.dogScale = val
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(6)
            }

            // Section 1: Window Switch Stealth Delay
            GroupBox(label: Label("换窗潜行节奏", systemImage: "macwindow.on.rectangle")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("切窗等待时长")
                        Spacer()
                        Text(CompanionPreferences.formatDuration(preferences.windowSwitchDelaySeconds))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $preferences.windowSwitchDelaySeconds,
                        in: 0...15,
                        step: 1
                    )
                    Text("当小狗在窗口上方（或开启跟随窗口右侧）时，切到新窗口停留超过该时间后才会悄悄收起并切换位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Picker("陪伴位置偏好", selection: $preferences.perchPreference) {
                        ForEach(PerchPreference.allCases, id: \.self) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(6)
            }

            // Section 2: Right -> Top Initial Peek & Periodic Independent Top-Bar Effects
            GroupBox(label: Label("右侧→顶栏陪伴与独立特效", systemImage: "pawprint.fill")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("从右侧自动爬上窗口顶栏（左看右看后趴窗朝前）", isOn: $preferences.climbToTopEnabled)

                    HStack {
                        Text("右侧→顶栏等待时长")
                        Spacer()
                        Text(CompanionPreferences.formatDuration(preferences.climbToTopIntervalSeconds))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(preferences.climbToTopEnabled ? 1.0 : 0.45)

                    Slider(
                        value: $preferences.climbToTopIntervalSeconds,
                        in: 3...3600,
                        step: 1
                    )
                    .disabled(!preferences.climbToTopEnabled)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            ForEach([3.0, 30.0, 60.0, 300.0], id: \.self) { secs in
                                Button(CompanionPreferences.formatDuration(secs)) {
                                    preferences.climbToTopEnabled = true
                                    preferences.climbToTopIntervalSeconds = secs
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        HStack(spacing: 5) {
                            ForEach([600.0, 900.0, 1800.0, 2700.0, 3600.0], id: \.self) { secs in
                                Button(CompanionPreferences.formatDuration(secs)) {
                                    preferences.climbToTopEnabled = true
                                    preferences.climbToTopIntervalSeconds = secs
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .disabled(!preferences.climbToTopEnabled)

                    Divider()

                    Toggle("在顶栏定时触发独立特效", isOn: $preferences.topEffectsEnabled)

                    HStack {
                        Text("顶栏特效触发间隔")
                        Spacer()
                        Text(CompanionPreferences.formatDuration(preferences.topEffectIntervalSeconds))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(preferences.topEffectsEnabled ? 1.0 : 0.45)

                    Slider(
                        value: $preferences.topEffectIntervalSeconds,
                        in: 5...3600,
                        step: 5
                    )
                    .disabled(!preferences.topEffectsEnabled)

                    HStack(spacing: 5) {
                        ForEach([15.0, 45.0, 300.0, 900.0, 1800.0, 3600.0], id: \.self) { secs in
                            Button(CompanionPreferences.formatDuration(secs)) {
                                preferences.topEffectsEnabled = true
                                preferences.topEffectIntervalSeconds = secs
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .disabled(!preferences.topEffectsEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("自动触发包含的独立特效（右键也可单独即时播放）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(TopBarEffect.allCases) { effect in
                            HStack {
                                let binding = Binding<Bool>(
                                    get: { preferences.isTopEffectEnabled(effect) },
                                    set: { preferences.setTopEffect(effect, enabled: $0) }
                                )
                                Toggle(effect.displayName, isOn: binding)
                                    .disabled(!preferences.topEffectsEnabled || (preferences.isTopEffectEnabled(effect) && preferences.enabledTopEffects.count == 1))
                                Spacer()
                                Button("播放") {
                                    onPlayEffect(effect)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }

                    Text("爬上顶栏后默认左看右看并保持朝前趴窗姿态；之后按设定间隔随机播放上方勾选的独立特效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            // Section 3: Top-Bar Single-Click Pose Cycle
            GroupBox(label: Label("窗顶单击切换姿态", systemImage: "hand.tap")) {
                VStack(alignment: .leading, spacing: 6) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(TopTapPose.allCases) { pose in
                            let binding = Binding<Bool>(
                                get: { preferences.isTopTapPoseEnabled(pose) },
                                set: { preferences.setTopTapPose(pose, enabled: $0) }
                            )
                            Toggle(pose.displayName, isOn: binding)
                                .disabled(preferences.isTopTapPoseEnabled(pose) && preferences.topTapEnabledPoses.count == 1)
                        }
                    }
                    Text("在窗口顶栏轻点小狗时，会在已勾选的姿态之间循环切换（至少保留 1 项）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            // Section 4: Zero-Intrusion Micro-Interactions
            GroupBox(label: Label("零打扰微交互细节", systemImage: "sparkles")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("防误点害羞缩头（鼠标高速划过微缩，慢靠近才探头）", isOn: $preferences.shyRetreatEnabled)
                    Toggle("打字免打扰（持续输入时暂缓爬顶，停手后再打招呼）", isOn: $preferences.typingPauseEnabled)
                    Toggle("顶栏先搭爪探头（先露耳尖小爪张望，再翻身上顶）", isOn: $preferences.climbPawsPeekEnabled)
                }
                .padding(6)
            }

            HStack {
                Button("恢复默认") {
                    preferences.resetToDefaults()
                }
                Button("👀 预览趴窗") {
                    onPreviewPeek()
                }
                Button("⚡ 闪身步") {
                    onPlayEffect(.flashStep)
                }
                Spacer()
                Button("完成") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        }
        .frame(width: 450, height: 780)
    }
}
