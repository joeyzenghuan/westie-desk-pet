import AppKit

@MainActor
public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var scene: DesktopScene?

    private var toggleTennisItem: NSMenuItem!
    private var sleepModeItem: NSMenuItem!
    private var difficultyCasualItem: NSMenuItem!
    private var difficultyProItem: NSMenuItem!
    private var speedMenuItems: [TennisGameSpeed: NSMenuItem] = [:]

    public init(scene: DesktopScene) {
        self.scene = scene
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusButton()
        rebuildMenu()

        let prevCallback = scene.onModeChanged
        scene.onModeChanged = { [weak self] mode in
            prevCallback?(mode)
            self?.syncMenuState(mode: mode)
        }
        scene.tennis.onGameSpeedChanged = { [weak self] spd in
            self?.syncSpeedCheckmarks(selected: spd)
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        if let icon = SpriteBank.shared.nsImage(for: .badgeIcon) {
            let resized = NSImage(size: NSSize(width: 18, height: 18))
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none
            icon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            resized.unlockFocus()
            button.image = resized
            button.imagePosition = .imageLeading
            button.title = ""
        } else {
            button.title = "🐶🎾"
        }
        button.toolTip = "Westie Desk Pet — 西高地桌面陪伴 & 网球"
    }

    private func rebuildMenu() {
        let menu = NSMenu(title: "Westie Desk Pet")

        let header = NSMenuItem(title: "🐶 西高地桌面伙伴 (Westie)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        toggleTennisItem = NSMenuItem(
            title: "🎾 开始打网球 (WASD + 鼠标)",
            action: #selector(toggleTennisMode),
            keyEquivalent: "t"
        )
        toggleTennisItem.keyEquivalentModifierMask = [.command, .shift]
        toggleTennisItem.target = self
        menu.addItem(toggleTennisItem)

        let inviteItem = NSMenuItem(
            title: "🟢 让西高地叼网球过来",
            action: #selector(triggerInvite),
            keyEquivalent: ""
        )
        inviteItem.target = self
        menu.addItem(inviteItem)

        menu.addItem(.separator())

        let summonItem = NSMenuItem(
            title: "📍 移到当前窗口正上方",
            action: #selector(moveWindowTop),
            keyEquivalent: "w"
        )
        summonItem.keyEquivalentModifierMask = [.command, .shift]
        summonItem.target = self
        menu.addItem(summonItem)

        let rightPeekItem = NSMenuItem(
            title: "👀 移到右侧探头模式",
            action: #selector(moveRightPeek),
            keyEquivalent: "e"
        )
        rightPeekItem.keyEquivalentModifierMask = [.command, .shift]
        rightPeekItem.target = self
        menu.addItem(rightPeekItem)

        let treatItem = NSMenuItem(
            title: "🦴 投喂一根骨头饼干",
            action: #selector(feedTreat),
            keyEquivalent: "b"
        )
        treatItem.keyEquivalentModifierMask = [.command, .shift]
        treatItem.target = self
        menu.addItem(treatItem)

        sleepModeItem = NSMenuItem(
            title: "💤 安静趴睡模式",
            action: #selector(toggleQuietSleep),
            keyEquivalent: ""
        )
        sleepModeItem.target = self
        menu.addItem(sleepModeItem)

        menu.addItem(.separator())

        let speedSubmenu = NSMenu(title: "网球球速")
        speedMenuItems.removeAll()
        let currentSpeed = scene?.tennis.gameSpeed ?? .slow
        for spd in TennisGameSpeed.allCases {
            let suffix = (spd == .slow) ? " (默认)" : ""
            let item = NSMenuItem(title: "\(spd.displayName)\(suffix)", action: #selector(selectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spd.rawValue
            item.state = (spd == currentSpeed) ? .on : .off
            speedSubmenu.addItem(item)
            speedMenuItems[spd] = item
        }
        let speedParent = NSMenuItem(title: "⏱ 网球球速", action: nil, keyEquivalent: "")
        speedParent.submenu = speedSubmenu
        menu.addItem(speedParent)

        let diffSubmenu = NSMenu(title: "网球难度")
        difficultyCasualItem = NSMenuItem(title: "休闲小狗 (Casual)", action: #selector(selectCasual), keyEquivalent: "")
        difficultyCasualItem.target = self
        difficultyCasualItem.state = .on
        diffSubmenu.addItem(difficultyCasualItem)

        difficultyProItem = NSMenuItem(title: "网球狗王 (Pro)", action: #selector(selectPro), keyEquivalent: "")
        difficultyProItem.target = self
        diffSubmenu.addItem(difficultyProItem)

        let diffParent = NSMenuItem(title: "🏆 网球对手难度", action: nil, keyEquivalent: "")
        diffParent.submenu = diffSubmenu
        menu.addItem(diffParent)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Westie Desk Pet", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func syncMenuState(mode: AppInteractionMode) {
        switch mode {
        case .companion:
            toggleTennisItem.title = "🎾 开始打网球 (WASD + 鼠标)"
        case .tennis:
            toggleTennisItem.title = "🏡 收起球场回到桌面陪伴"
        }
    }

    @objc private func toggleTennisMode() {
        guard let scene else { return }
        scene.switchToMode(scene.mode == .companion ? .tennis : .companion)
    }

    @objc private func triggerInvite() {
        scene?.triggerDogTennisInvite()
    }

    @objc private func moveWindowTop() {
        scene?.companion.perchPreference = .auto
        scene?.moveDogToZone(.windowTop)
    }

    @objc private func moveRightPeek() {
        scene?.moveDogToZone(.windowRightPeek)
    }

    @objc private func selectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let spd = TennisGameSpeed(rawValue: raw)
        else { return }
        scene?.tennis.gameSpeed = spd
        syncSpeedCheckmarks(selected: spd)
    }

    private func syncSpeedCheckmarks(selected: TennisGameSpeed) {
        for (spd, item) in speedMenuItems {
            item.state = (spd == selected) ? .on : .off
        }
    }

    @objc private func feedTreat() {
        scene?.feedBoneTreat()
    }

    @objc private func toggleQuietSleep() {
        guard let scene else { return }
        scene.companion.forceQuietSleep.toggle()
        sleepModeItem.state = scene.companion.forceQuietSleep ? .on : .off
    }

    @objc private func selectCasual() {
        scene?.tennis.difficulty = .casual
        difficultyCasualItem.state = .on
        difficultyProItem.state = .off
    }

    @objc private func selectPro() {
        scene?.tennis.difficulty = .pro
        difficultyCasualItem.state = .off
        difficultyProItem.state = .on
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
