import AppKit

@MainActor
public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var scene: DesktopScene?

    private var headerItem: NSMenuItem!
    private var toggleTennisItem: NSMenuItem!
    private var inviteItem: NSMenuItem!
    private var treatItem: NSMenuItem!
    private var sleepModeItem: NSMenuItem!
    private var difficultyCasualItem: NSMenuItem!
    private var difficultyProItem: NSMenuItem!
    private var speedMenuItems: [TennisGameSpeed: NSMenuItem] = [:]
    private var petSpeciesParentItem: NSMenuItem!
    private var petSpeciesItems: [(species: PetSpecies, item: NSMenuItem)] = []
    private var switchDelayParentItem: NSMenuItem!
    private var switchDelayItems: [(seconds: TimeInterval, item: NSMenuItem)] = []
    private var climbIntervalParentItem: NSMenuItem!
    private var climbIntervalItems: [(enabled: Bool, seconds: TimeInterval, item: NSMenuItem)] = []
    private var effectIntervalParentItem: NSMenuItem!
    private var effectIntervalItems: [(enabled: Bool, seconds: TimeInterval, item: NSMenuItem)] = []
    private var dogScaleParentItem: NSMenuItem!
    private var dogScaleItems: [(scale: Double, item: NSMenuItem)] = []

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
        let prevPrefCallback = scene.companion.preferences.onChanged
        scene.companion.preferences.onChanged = { [weak self] in
            prevPrefCallback?()
            self?.syncPreferenceCheckmarks()
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let species = scene?.companion.preferences.petSpecies ?? .westie
        if let icon = SpriteBank.shared.nsImage(for: .badgeIcon, species: species) {
            let resized = NSImage(size: NSSize(width: 18, height: 18))
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none
            icon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            resized.unlockFocus()
            button.image = resized
            button.imagePosition = .imageLeading
            button.title = ""
        } else {
            switch species {
            case .goldenCat: button.title = "🐱🎾"
            case .chinchilla: button.title = "🐈🎾"
            case .labrador: button.title = "🐕🎾"
            case .westie: button.title = "🐶🎾"
            }
        }
        button.toolTip = "Westie Desk Pet — \(species.displayName)桌面陪伴 & 网球"
    }

    private func rebuildMenu() {
        let menu = NSMenu(title: "Westie Desk Pet")

        headerItem = NSMenuItem(title: "🐶 西高地桌面伙伴", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // 1. Most-used: Playable Top-Bar Effects right on Level 1!
        let peekItem = NSMenuItem(title: "👀 探头张望", action: #selector(previewClimb), keyEquivalent: "")
        peekItem.target = self
        menu.addItem(peekItem)

        for effect in TopBarEffect.allCases {
            let item = NSMenuItem(title: effect.displayName, action: #selector(playTopBarEffect(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = effect.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 2. Feed Snack & Quiet Sleep right after effects!
        treatItem = NSMenuItem(
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

        // 3. Tennis + Speed + Difficulty grouped together!
        toggleTennisItem = NSMenuItem(
            title: "🎾 开始打网球 (WASD + 鼠标)",
            action: #selector(toggleTennisMode),
            keyEquivalent: "t"
        )
        toggleTennisItem.keyEquivalentModifierMask = [.command, .shift]
        toggleTennisItem.target = self
        menu.addItem(toggleTennisItem)

        inviteItem = NSMenuItem(
            title: "🟢 让西高地叼网球过来",
            action: #selector(triggerInvite),
            keyEquivalent: ""
        )
        inviteItem.target = self
        menu.addItem(inviteItem)

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

        // 4. Quick Position Move
        let summonItem = NSMenuItem(
            title: "📍 移到当前窗口正上方",
            action: #selector(moveWindowTop),
            keyEquivalent: "w"
        )
        summonItem.keyEquivalentModifierMask = [.command, .shift]
        summonItem.target = self
        menu.addItem(summonItem)

        let rightPeekItem = NSMenuItem(
            title: "👀 移到屏幕右侧边",
            action: #selector(moveRightPeek),
            keyEquivalent: "e"
        )
        rightPeekItem.keyEquivalentModifierMask = [.command, .shift]
        rightPeekItem.target = self
        menu.addItem(rightPeekItem)

        menu.addItem(.separator())

        // 5. Pet Species Switch in its own standalone section!
        let speciesSubmenu = NSMenu(title: "切换宠物")
        petSpeciesItems.removeAll()
        for sp in PetSpecies.allCases {
            let item = NSMenuItem(title: sp.displayName, action: #selector(selectPetSpecies(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sp.rawValue
            speciesSubmenu.addItem(item)
            petSpeciesItems.append((sp, item))
        }
        petSpeciesParentItem = NSMenuItem(title: "🎭 切换宠物", action: nil, keyEquivalent: "")
        petSpeciesParentItem.submenu = speciesSubmenu
        menu.addItem(petSpeciesParentItem)

        menu.addItem(.separator())

        // 5. All Settings grouped cleanly under Level-2 Submenu!
        let settingsSubmenu = NSMenu(title: "设置")

        let delaySubmenu = NSMenu(title: "换窗等待时长")
        switchDelayItems.removeAll()
        for preset in CompanionPreferences.switchDelayPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectSwitchDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.seconds
            delaySubmenu.addItem(item)
            switchDelayItems.append((preset.seconds, item))
        }
        switchDelayParentItem = NSMenuItem(title: "🕵️ 换窗等待时长", action: nil, keyEquivalent: "")
        switchDelayParentItem.submenu = delaySubmenu
        settingsSubmenu.addItem(switchDelayParentItem)

        let climbSubmenu = NSMenu(title: "爬顶等待时长")
        climbIntervalItems.removeAll()
        for preset in CompanionPreferences.climbIntervalPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectClimbInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.enabled ? preset.seconds : -1.0)
            climbSubmenu.addItem(item)
            climbIntervalItems.append((preset.enabled, preset.seconds, item))
        }
        climbIntervalParentItem = NSMenuItem(title: "🐾 爬顶等待时长", action: nil, keyEquivalent: "")
        climbIntervalParentItem.submenu = climbSubmenu
        settingsSubmenu.addItem(climbIntervalParentItem)

        let effectIntSubmenu = NSMenu(title: "顶栏特效间隔")
        effectIntervalItems.removeAll()
        for preset in CompanionPreferences.effectIntervalPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectEffectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.enabled ? preset.seconds : -1.0)
            effectIntSubmenu.addItem(item)
            effectIntervalItems.append((preset.enabled, preset.seconds, item))
        }
        effectIntervalParentItem = NSMenuItem(title: "✨ 特效间隔", action: nil, keyEquivalent: "")
        effectIntervalParentItem.submenu = effectIntSubmenu
        settingsSubmenu.addItem(effectIntervalParentItem)

        let scaleSubmenu = NSMenu(title: "宠物大小")
        dogScaleItems.removeAll()
        for preset in CompanionPreferences.dogScalePresets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectDogScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.scale)
            scaleSubmenu.addItem(item)
            dogScaleItems.append((preset.scale, item))
        }
        dogScaleParentItem = NSMenuItem(title: "📏 宠物大小", action: nil, keyEquivalent: "")
        dogScaleParentItem.submenu = scaleSubmenu
        settingsSubmenu.addItem(dogScaleParentItem)

        settingsSubmenu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "⚙️ 陪伴偏好设置…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        settingsSubmenu.addItem(prefsItem)

        let settingsParent = NSMenuItem(title: "⚙️ 设置", action: nil, keyEquivalent: "")
        settingsParent.submenu = settingsSubmenu
        menu.addItem(settingsParent)

        syncPreferenceCheckmarks()

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
        scene?.moveDogToZone(.windowTop)
    }

    @objc private func moveRightPeek() {
        if scene?.companion.perchPreference == .rightPeek {
            scene?.moveDogToZone(.windowRightPeek)
        } else {
            scene?.moveDogToZone(.screenRightPeek)
        }
    }

    @objc private func previewClimb() {
        scene?.previewClimbPeekOnTop()
    }

    @objc private func playTopBarEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effect = TopBarEffect(rawValue: raw)
        else { return }
        scene?.playTopBarEffect(effect)
    }

    @objc private func selectPetSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sp = PetSpecies(rawValue: raw)
        else { return }
        scene?.companion.preferences.petSpecies = sp
        syncPreferenceCheckmarks()
    }

    @objc private func selectEffectInterval(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let val = num.doubleValue
        if val < 0 {
            scene?.companion.preferences.topEffectsEnabled = false
        } else {
            scene?.companion.preferences.topEffectsEnabled = true
            scene?.companion.preferences.topEffectIntervalSeconds = val
        }
        syncPreferenceCheckmarks()
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

    @objc private func selectSwitchDelay(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        scene?.companion.preferences.windowSwitchDelaySeconds = secs
        syncPreferenceCheckmarks()
    }

    @objc private func selectClimbInterval(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let val = num.doubleValue
        if val < 0 {
            scene?.companion.preferences.climbToTopEnabled = false
        } else {
            scene?.companion.preferences.climbToTopEnabled = true
            scene?.companion.preferences.climbToTopIntervalSeconds = val
        }
        syncPreferenceCheckmarks()
    }

    @objc private func selectDogScale(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        scene?.companion.preferences.dogScale = num.doubleValue
        syncPreferenceCheckmarks()
    }

    @objc private func openPreferences() {
        guard let scene else { return }
        PreferencesWindowController.shared.show(
            preferences: scene.companion.preferences,
            onPreviewPeek: { [weak scene] in
                scene?.previewClimbPeekOnTop()
            },
            onPlayEffect: { [weak scene] effect in
                scene?.playTopBarEffect(effect)
            }
        )
    }

    private func syncPreferenceCheckmarks() {
        guard let prefs = scene?.companion.preferences else { return }

        configureStatusButton()
        let sp = prefs.petSpecies
        headerItem.title = "\(sp.displayName) · 桌面伙伴"
        inviteItem?.title = "🟢 让\(sp.shortName)叼网球过来"
        treatItem?.title = sp.isCat ? "🐟 投喂一条小鱼干" : "🦴 投喂一根骨头饼干"
        difficultyCasualItem?.title = "\(TennisDifficulty.casual.displayName(for: sp)) (Casual)"
        difficultyProItem?.title = "\(TennisDifficulty.pro.displayName(for: sp)) (Pro)"
        scene?.tennis.refreshPetSpeciesUI()
        petSpeciesParentItem.title = "🎭 切换宠物: \(sp.shortName)"
        for entry in petSpeciesItems {
            entry.item.state = (entry.species == sp) ? .on : .off
        }

        let curDelay = prefs.windowSwitchDelaySeconds
        switchDelayParentItem.title = "🕵️ 换窗等待: \(CompanionPreferences.formatDuration(curDelay))"
        for entry in switchDelayItems {
            entry.item.state = abs(curDelay - entry.seconds) < 0.1 ? .on : .off
        }

        let climbLabel = prefs.climbToTopEnabled
            ? CompanionPreferences.formatDuration(prefs.climbToTopIntervalSeconds)
            : "已关闭"
        climbIntervalParentItem.title = "🐾 爬顶等待: \(climbLabel)"
        for entry in climbIntervalItems {
            let selected = entry.enabled
                ? (prefs.climbToTopEnabled && abs(prefs.climbToTopIntervalSeconds - entry.seconds) < 0.5)
                : !prefs.climbToTopEnabled
            entry.item.state = selected ? .on : .off
        }

        let effectLabel = prefs.topEffectsEnabled
            ? CompanionPreferences.formatDuration(prefs.topEffectIntervalSeconds)
            : "已关闭"
        effectIntervalParentItem.title = "✨ 特效间隔: \(effectLabel)"
        for entry in effectIntervalItems {
            let selected = entry.enabled
                ? (prefs.topEffectsEnabled && abs(prefs.topEffectIntervalSeconds - entry.seconds) < 0.5)
                : !prefs.topEffectsEnabled
            entry.item.state = selected ? .on : .off
        }

        let curScale = prefs.dogScale
        dogScaleParentItem.title = "📏 宠物大小: \(CompanionPreferences.formatScale(curScale))"
        for entry in dogScaleItems {
            entry.item.state = abs(curScale - entry.scale) < 0.03 ? .on : .off
        }
    }
}
