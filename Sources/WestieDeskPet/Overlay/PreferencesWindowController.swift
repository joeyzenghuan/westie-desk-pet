import AppKit
import SwiftUI

@MainActor
public final class PreferencesWindowController {
    public static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private var onPreviewClimb: (() -> Void)?
    private var onPreviewFlashStep: (() -> Void)?

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    private init() {}

    public func show(
        preferences: CompanionPreferences = .shared,
        onPreviewClimb: (() -> Void)? = nil,
        onPreviewFlashStep: (() -> Void)? = nil
    ) {
        if let onPreviewClimb {
            self.onPreviewClimb = onPreviewClimb
        }
        if let onPreviewFlashStep {
            self.onPreviewFlashStep = onPreviewFlashStep
        }
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = CompanionPreferencesView(
            preferences: preferences,
            onPreviewClimb: { [weak self] in
                self?.onPreviewClimb?()
            },
            onPreviewFlashStep: { [weak self] in
                self?.onPreviewFlashStep?()
            },
            onClose: { [weak self] in
                self?.window?.close()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 740),
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
    let onPreviewClimb: () -> Void
    let onPreviewFlashStep: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            // Section 0: Pet Species & Appearance Size
            GroupBox(label: Label("宠物角色与外观大小", systemImage: "pawprint.circle")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("当前桌面宠物", selection: $preferences.petSpecies) {
                        ForEach(PetSpecies.allCases) { sp in
                            Text(sp.displayName).tag(sp)
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

            // Section 2: Right -> Top Climb & Animation Effect
            GroupBox(label: Label("同窗口专注陪伴与动态特效", systemImage: "pawprint.fill")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("停留满时长后自动爬上顶栏互动", isOn: $preferences.climbToTopEnabled)

                    Picker("爬顶动态特效", selection: $preferences.topClimbRoutine) {
                        ForEach(TopClimbRoutine.allCases) { rt in
                            Text(rt.displayName).tag(rt)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!preferences.climbToTopEnabled)

                    HStack {
                        Text("爬上顶栏触发间隔")
                        Spacer()
                        Text(CompanionPreferences.formatDuration(preferences.climbToTopIntervalSeconds))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(preferences.climbToTopEnabled ? 1.0 : 0.45)

                    Slider(
                        value: $preferences.climbToTopIntervalSeconds,
                        in: 3...300,
                        step: 1
                    )
                    .disabled(!preferences.climbToTopEnabled)

                    HStack(spacing: 6) {
                        ForEach([3.0, 15.0, 30.0, 60.0, 180.0], id: \.self) { secs in
                            Button(CompanionPreferences.formatDuration(secs)) {
                                preferences.climbToTopEnabled = true
                                preferences.climbToTopIntervalSeconds = secs
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .disabled(!preferences.climbToTopEnabled)

                    HStack {
                        Text("上顶互动等待时长")
                        Spacer()
                        Text(CompanionPreferences.formatDuration(preferences.greetingDurationSeconds))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(preferences.climbToTopEnabled ? 1.0 : 0.45)

                    Slider(
                        value: $preferences.greetingDurationSeconds,
                        in: 5...20,
                        step: 1
                    )
                    .disabled(!preferences.climbToTopEnabled)

                    Text("默认在屏幕右侧边安静探头，不挡应用窗口；在当前窗口停留满时长后会自动爬上顶栏互动，之后打哈欠趴下睡觉。")
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
                Button("🐾 预览爬顶") {
                    onPreviewClimb()
                }
                Button("⚡ 预览闪身步") {
                    onPreviewFlashStep()
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
        .frame(width: 440, height: 740)
    }
}
