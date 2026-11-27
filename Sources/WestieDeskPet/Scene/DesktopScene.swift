import AppKit
import SpriteKit

public enum AppInteractionMode: Equatable, Sendable {
    case companion
    case tennis
}

@MainActor
public final class DesktopScene: SKScene {
    public let companion = CompanionController()
    public let tennis = TennisMatchController()

    public private(set) var mode: AppInteractionMode = .companion {
        didSet {
            onModeChanged?(mode)
        }
    }

    public var onModeChanged: ((AppInteractionMode) -> Void)?
    public var onPreferredFPSChanged: ((Int) -> Void)?
    /// Called during drag/drop to migrate `OverlayPanel` seamlessly across monitors and return the live cursor point in current scene coordinates.
    public var onEnsureScreenForGlobalDrag: (() -> CGPoint?)?

    private let windowTracker = WindowPlatformTracker()
    public var targetScreen: NSScreen?
    public private(set) var lastDisplayLinkUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var hasPlacedInitially: Bool = false
    private var latestSnapshot: ActiveWorkspaceSnapshot?
    private var fullSnapshotTimer: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var lastPointerScenePoint: CGPoint?
    private var lastPointerSampleTime: TimeInterval = 0
    private var smoothedPointerSpeed: CGFloat = 0

    public override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill

        addChild(companion.rootNode)
        addChild(tennis.rootNode)

        companion.onRequestStartTennis = { [weak self] in
            self?.switchToMode(.tennis)
        }
        tennis.onRequestExitTennis = { [weak self] in
            self?.switchToMode(.companion)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)
        // Warm decoded CGImages off the main thread for active species
        SpriteBank.shared.preloadSpecies(companion.preferences.petSpecies)
        refreshWindowSnapshot()
        if !hasPlacedInitially, let snap = latestSnapshot {
            hasPlacedInitially = true
            companion.placeInitially(snapshot: snap, sceneSize: size)
        }
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        tennis.layout(in: size)
        refreshWindowSnapshot()
        if mode == .companion, let snap = latestSnapshot {
            companion.update(dt: 1.0 / 60.0, snapshot: snap, sceneSize: size)
        }
    }

    public func handleWorkspaceNotification() {
        guard mode == .companion else { return }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.update(dt: 1.0 / 60.0, snapshot: snap, sceneSize: size)
        }
    }

    public func switchToMode(_ target: AppInteractionMode) {
        guard mode != target else { return }
        mode = target
        switch target {
        case .tennis:
            companion.setHovering(false)
            companion.rootNode.isHidden = true
            tennis.startMatch(in: size)
        case .companion:
            tennis.stopMatch()
            companion.rootNode.isHidden = false
            refreshWindowSnapshot()
            if let snap = latestSnapshot {
                companion.summonToFrontWindow(snapshot: snap, sceneSize: size)
            }
        }
    }

    public func summonDogToActiveWindow() {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.summonToFrontWindow(snapshot: snap, sceneSize: size)
        }
    }

    public func moveDogToZone(_ zone: PerchZone) {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.moveImmediatelyToZone(zone, snapshot: snap, sceneSize: size)
        }
    }

    public func feedBoneTreat() {
        if mode == .tennis { return }
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
            companion.dropBoneTreat(snapshot: snap, sceneSize: size)
        }
    }

    public func triggerDogTennisInvite() {
        if mode == .tennis { return }
        companion.triggerTennisInvite()
    }

    public var isActivelyInteractingWithDog: Bool {
        if companion.isPointerDownOnDog { return true }
        if case .dragged = companion.state { return true }
        return false
    }

    /// Updates continuous hover & pointer speed (for shy-retreat) & returns whether `OverlayWindow` should capture mouse events.
    public func updatePointerCaptureAndHover(atScenePoint scenePoint: CGPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let prevPt = lastPointerScenePoint {
            let dt = max(now - lastPointerSampleTime, 1.0 / 240.0)
            let instSpeed = hypot(scenePoint.x - prevPt.x, scenePoint.y - prevPt.y) / CGFloat(dt)
            smoothedPointerSpeed = smoothedPointerSpeed * 0.55 + instSpeed * 0.45
        } else {
            smoothedPointerSpeed = 0
        }
        lastPointerScenePoint = scenePoint
        lastPointerSampleTime = now

        if mode == .tennis || isActivelyInteractingWithDog {
            return true
        }
        let hitRect = companion.interactiveHitRect()
        guard !hitRect.isEmpty else {
            companion.setHovering(false, pointerSpeed: 0, nearZone: false)
            return false
        }
        // Zero outer inflation when calm so right-edge hover only triggers right at Westie's head/ears;
        // small 4pt cushion once already hovering so moving to click/right-click never flickers off!
        let captureRect = companion.isHoveringDog ? hitRect.insetBy(dx: -4, dy: -4) : hitRect
        let nearRect = hitRect.insetBy(dx: -12, dy: -12)
        let inside = captureRect.contains(scenePoint)
        let near = nearRect.contains(scenePoint)
        companion.setHovering(inside, pointerSpeed: smoothedPointerSpeed, nearZone: near)
        return inside
    }

    public func isPointOverDogForContextMenu(_ scenePoint: CGPoint) -> Bool {
        guard mode == .companion else { return false }
        let hitRect = companion.interactiveHitRect()
        guard !hitRect.isEmpty else { return false }
        return hitRect.insetBy(dx: -8, dy: -8).contains(scenePoint)
    }

    public func previewClimbPeekOnTop() {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        guard let snap = latestSnapshot, let top = snap.perchLayout.topPerch else { return }
        let targetX = top.clampedX(top.maxX - min(110, top.width * 0.26), margin: 22)
        companion.beginStealthClimbToTop(
            targetX: targetX,
            windowID: snap.perchLayout.activeWindowID ?? companion.trackedWindowID,
            effectOnArrival: nil
        )
    }

    public func playTopBarEffect(_ effect: TopBarEffect) {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        guard let snap = latestSnapshot else { return }
        companion.triggerTopBarEffect(effect, snapshot: snap, sceneSize: size)
    }

    /// Native macOS cursor matching current hover/grab state.
    public func desiredCursor(atScenePoint scenePoint: CGPoint) -> NSCursor {
        if mode == .tennis {
            return .arrow
        }
        if isActivelyInteractingWithDog {
            return .closedHand
        }
        if companion.isPointOnInviteBadge(scenePoint) {
            return .pointingHand
        }
        if companion.isHoveringDog {
            return .openHand
        }
        return .arrow
    }

    // MARK: - SpriteKit Update Loop (60Hz / 120Hz ProMotion Locked)

    public override func update(_ currentTime: TimeInterval) {
        lastDisplayLinkUptime = ProcessInfo.processInfo.systemUptime
        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(max(currentTime - lastUpdateTime, 0.001), 0.1)
        }
        lastUpdateTime = currentTime

        stepSimulation(dt: dt)
    }

    /// Fallback simulation step called by `OverlayWindowController`'s watchdog if SpriteKit's
    /// internal DisplayLink ever pauses after a multi-monitor move or wake from sleep.
    /// Intentionally does NOT update `lastDisplayLinkUptime` so the watchdog keeps reviving `SKView`
    /// while driving smooth 60 FPS fallback animation until native DisplayLink resumes.
    public func stepFallbackTick(dt: TimeInterval) {
        stepSimulation(dt: min(max(dt, 0.001), 0.08))
    }

    private func stepSimulation(dt: TimeInterval) {
        switch mode {
        case .companion:
            fullSnapshotTimer -= dt
            if fullSnapshotTimer <= 0 || latestSnapshot == nil {
                // Full frontmost window discovery (~6 Hz)
                fullSnapshotTimer = 0.16
                refreshWindowSnapshot()
            } else {
                // O(1) single-window query every frame (60/120Hz) for zero-lag window drag follow!
                fastRefreshCurrentActiveWindow()
            }
            if let snap = latestSnapshot {
                companion.update(dt: dt, snapshot: snap, sceneSize: size)
            }

        case .tennis:
            tennis.update(dt: dt)
        }
    }

    private func activeTargetScreen() -> NSScreen? {
        if let targetScreen, NSScreen.screens.contains(targetScreen) {
            return targetScreen
        }
        return view?.window?.screen ?? NSScreen.main
    }

    private func refreshWindowSnapshot() {
        guard let screen = activeTargetScreen() else { return }
        latestSnapshot = windowTracker.captureSnapshot(for: screen)
    }

    private func fastRefreshCurrentActiveWindow() {
        guard let prev = latestSnapshot,
              let screen = activeTargetScreen()
        else { return }
        latestSnapshot = windowTracker.fastRefreshActiveWindow(
            in: prev,
            for: screen,
            trackedWindowID: companion.trackedWindowID
        )
    }

    // MARK: - Mouse & Keyboard Events

    public override func mouseMoved(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else {
            companion.setHovering(companion.interactiveHitRect().insetBy(dx: -6, dy: -6).contains(pt))
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseDown(scenePoint: pt)
        } else {
            _ = companion.handleMouseDown(at: pt)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: event.location(in: self))
        } else if isActivelyInteractingWithDog {
            let livePt = onEnsureScreenForGlobalDrag?() ?? event.location(in: self)
            companion.handleMouseDragged(to: livePt)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleLeftMouseUp(scenePoint: event.location(in: self))
        } else if isActivelyInteractingWithDog {
            let livePt = onEnsureScreenForGlobalDrag?() ?? event.location(in: self)
            refreshWindowSnapshot()
            companion.handleMouseUp(at: livePt, snapshot: latestSnapshot, sceneSize: size)
        }
    }

    /// Completes a cross-monitor drop driven by the hardware pointer watcher if AppKit dropped `mouseUp` during screen handoff.
    public func finishGlobalDragDrop(atScenePoint scenePoint: CGPoint) {
        guard mode == .companion, isActivelyInteractingWithDog else { return }
        refreshWindowSnapshot()
        companion.handleMouseUp(at: scenePoint, snapshot: latestSnapshot, sceneSize: size)
    }

    public override func rightMouseDown(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleRightMouseDown(scenePoint: pt)
        } else if let view = self.view {
            let menu = buildDogContextMenu()
            let viewPt = view.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: viewPt, in: view)
        }
    }

    public override func keyDown(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleKeyDown(event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if mode == .tennis {
            tennis.handleKeyUp(event)
        }
    }

    // MARK: - Rich Context Menu on Westie

    public func buildDogContextMenu() -> NSMenu {
        let menu = NSMenu(title: "桌面宠物")
        let curSpecies = companion.preferences.petSpecies

        // 1. Most-used: Playable Top-Bar Effects right on Level 1!
        let peekEffectItem = NSMenuItem(title: "👀 探头张望", action: #selector(ctxPreviewClimb), keyEquivalent: "")
        peekEffectItem.target = self
        menu.addItem(peekEffectItem)

        for effect in TopBarEffect.allCases {
            let item = NSMenuItem(title: effect.displayName, action: #selector(ctxPlayTopBarEffect(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = effect.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 2. Feed Snack & Quiet Sleep right after effects!
        let treatTitle = curSpecies.isCat ? "🐟 喂一条小鱼干" : "🦴 喂一根骨头饼干"
        let treatItem = NSMenuItem(title: treatTitle, action: #selector(ctxFeedTreat), keyEquivalent: "")
        treatItem.target = self
        menu.addItem(treatItem)

        let sleepTitle = companion.forceQuietSleep ? "☀️ 取消固定趴睡" : "💤 安静趴睡模式"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(ctxToggleSleep), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        menu.addItem(.separator())

        // 3. Tennis & Tennis Speed grouped together!
        let tennisItem = NSMenuItem(title: "🎾 开始打网球 (WASD + 鼠标)", action: #selector(ctxStartTennis), keyEquivalent: "")
        tennisItem.target = self
        menu.addItem(tennisItem)

        let speedSubmenu = NSMenu(title: "网球球速")
        for spd in TennisGameSpeed.allCases {
            let suffix = (spd == .slow) ? " (默认)" : ""
            let item = NSMenuItem(title: "\(spd.displayName)\(suffix)", action: #selector(ctxSelectSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = spd.rawValue
            item.state = (tennis.gameSpeed == spd) ? .on : .off
            speedSubmenu.addItem(item)
        }
        let speedParent = NSMenuItem(title: "⏱ 网球球速: \(tennis.gameSpeed.rawValue)", action: nil, keyEquivalent: "")
        speedParent.submenu = speedSubmenu
        menu.addItem(speedParent)

        menu.addItem(.separator())

        // 4. Quick Position Move
        let moveTopItem = NSMenuItem(title: "📍 移到当前窗口正上方", action: #selector(ctxMoveWindowTop), keyEquivalent: "")
        moveTopItem.target = self
        menu.addItem(moveTopItem)

        let moveRightItem = NSMenuItem(title: "👀 移到屏幕右侧边", action: #selector(ctxMoveRightPeek), keyEquivalent: "")
        moveRightItem.target = self
        menu.addItem(moveRightItem)

        menu.addItem(.separator())

        // 5. Pet Species Switch in its own standalone section!
        let speciesSubmenu = NSMenu(title: "切换宠物")
        for sp in PetSpecies.allCases {
            let item = NSMenuItem(title: sp.displayName, action: #selector(ctxSelectPetSpecies(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sp.rawValue
            item.state = (curSpecies == sp) ? .on : .off
            speciesSubmenu.addItem(item)
        }
        let speciesParent = NSMenuItem(title: "🎭 切换宠物: \(curSpecies.shortName)", action: nil, keyEquivalent: "")
        speciesParent.submenu = speciesSubmenu
        menu.addItem(speciesParent)

        menu.addItem(.separator())

        // 5. All Settings neatly grouped under Level-2 Submenu!
        let settingsSubmenu = NSMenu(title: "设置")

        let prefSubmenu = NSMenu(title: "位置偏好")
        for pref in PerchPreference.allCases {
            let item = NSMenuItem(title: pref.rawValue, action: #selector(ctxSelectPerchPreference(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pref.rawValue
            item.state = (companion.perchPreference == pref) ? .on : .off
            prefSubmenu.addItem(item)
        }
        let prefParent = NSMenuItem(title: "🧭 陪伴位置偏好", action: nil, keyEquivalent: "")
        prefParent.submenu = prefSubmenu
        settingsSubmenu.addItem(prefParent)

        let delaySubmenu = NSMenu(title: "换窗等待时长")
        let curDelay = companion.preferences.windowSwitchDelaySeconds
        for preset in CompanionPreferences.switchDelayPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(ctxSelectSwitchDelay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.seconds
            item.state = abs(curDelay - preset.seconds) < 0.1 ? .on : .off
            delaySubmenu.addItem(item)
        }
        let delayParent = NSMenuItem(
            title: "🕵️ 换窗等待: \(CompanionPreferences.formatDuration(curDelay))",
            action: nil,
            keyEquivalent: ""
        )
        delayParent.submenu = delaySubmenu
        settingsSubmenu.addItem(delayParent)

        let climbSubmenu = NSMenu(title: "爬顶等待时长")
        let curClimbEnabled = companion.preferences.climbToTopEnabled
        let curClimbInterval = companion.preferences.climbToTopIntervalSeconds
        for preset in CompanionPreferences.climbIntervalPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(ctxSelectClimbInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.enabled ? preset.seconds : -1.0)
            let isSelected = preset.enabled
                ? (curClimbEnabled && abs(curClimbInterval - preset.seconds) < 0.5)
                : !curClimbEnabled
            item.state = isSelected ? .on : .off
            climbSubmenu.addItem(item)
        }
        let climbLabel = curClimbEnabled ? CompanionPreferences.formatDuration(curClimbInterval) : "已关闭"
        let climbParent = NSMenuItem(title: "🐾 爬顶等待: \(climbLabel)", action: nil, keyEquivalent: "")
        climbParent.submenu = climbSubmenu
        settingsSubmenu.addItem(climbParent)

        let effectIntSubmenu = NSMenu(title: "顶栏特效间隔")
        let curEffectEnabled = companion.preferences.topEffectsEnabled
        let curEffectInterval = companion.preferences.topEffectIntervalSeconds
        for preset in CompanionPreferences.effectIntervalPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(ctxSelectEffectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.enabled ? preset.seconds : -1.0)
            let isSelected = preset.enabled
                ? (curEffectEnabled && abs(curEffectInterval - preset.seconds) < 0.5)
                : !curEffectEnabled
            item.state = isSelected ? .on : .off
            effectIntSubmenu.addItem(item)
        }
        let effectLabel = curEffectEnabled ? CompanionPreferences.formatDuration(curEffectInterval) : "已关闭"
        let effectIntParent = NSMenuItem(title: "✨ 特效间隔: \(effectLabel)", action: nil, keyEquivalent: "")
        effectIntParent.submenu = effectIntSubmenu
        settingsSubmenu.addItem(effectIntParent)

        let scaleSubmenu = NSMenu(title: "宠物大小")
        let curScale = companion.preferences.dogScale
        for preset in CompanionPreferences.dogScalePresets {
            let item = NSMenuItem(title: preset.title, action: #selector(ctxSelectDogScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.scale)
            item.state = abs(curScale - preset.scale) < 0.03 ? .on : .off
            scaleSubmenu.addItem(item)
        }
        let scaleParent = NSMenuItem(
            title: "📏 宠物大小: \(CompanionPreferences.formatScale(curScale))",
            action: nil,
            keyEquivalent: ""
        )
        scaleParent.submenu = scaleSubmenu
        settingsSubmenu.addItem(scaleParent)

        settingsSubmenu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "⚙️ 陪伴偏好设置…", action: #selector(ctxOpenPreferences), keyEquivalent: "")
        prefsItem.target = self
        settingsSubmenu.addItem(prefsItem)

        let settingsParent = NSMenuItem(title: "⚙️ 设置", action: nil, keyEquivalent: "")
        settingsParent.submenu = settingsSubmenu
        menu.addItem(settingsParent)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Westie Desk Pet", action: #selector(ctxQuitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func ctxStartTennis() {
        switchToMode(.tennis)
    }

    @objc private func ctxMoveWindowTop() {
        moveDogToZone(.windowTop)
    }

    @objc private func ctxMoveRightPeek() {
        refreshWindowSnapshot()
        if companion.perchPreference == .rightPeek && latestSnapshot?.perchLayout.isFullScreenMode != true {
            moveDogToZone(.windowRightPeek)
        } else {
            moveDogToZone(.screenRightPeek)
        }
    }

    @objc private func ctxPreviewClimb() {
        previewClimbPeekOnTop()
    }

    @objc private func ctxPlayTopBarEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effect = TopBarEffect(rawValue: raw)
        else { return }
        playTopBarEffect(effect)
    }

    @objc private func ctxSelectPetSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sp = PetSpecies(rawValue: raw)
        else { return }
        companion.preferences.petSpecies = sp
    }

    @objc private func ctxSelectEffectInterval(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let val = num.doubleValue
        if val < 0 {
            companion.preferences.topEffectsEnabled = false
        } else {
            companion.preferences.topEffectsEnabled = true
            companion.preferences.topEffectIntervalSeconds = val
        }
    }

    @objc private func ctxSelectPerchPreference(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pref = PerchPreference(rawValue: raw)
        else { return }
        companion.perchPreference = pref
        summonDogToActiveWindow()
    }

    @objc private func ctxSelectSwitchDelay(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        companion.preferences.windowSwitchDelaySeconds = secs
    }

    @objc private func ctxSelectClimbInterval(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let val = num.doubleValue
        if val < 0 {
            companion.preferences.climbToTopEnabled = false
        } else {
            companion.preferences.climbToTopEnabled = true
            companion.preferences.climbToTopIntervalSeconds = val
        }
    }

    @objc private func ctxSelectDogScale(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        companion.preferences.dogScale = num.doubleValue
    }

    @objc private func ctxOpenPreferences() {
        PreferencesWindowController.shared.show(
            preferences: companion.preferences,
            onPreviewPeek: { [weak self] in
                self?.previewClimbPeekOnTop()
            },
            onPlayEffect: { [weak self] effect in
                self?.playTopBarEffect(effect)
            }
        )
    }

    @objc private func ctxSelectSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let spd = TennisGameSpeed(rawValue: raw)
        else { return }
        tennis.gameSpeed = spd
    }

    @objc private func ctxFeedTreat() {
        feedBoneTreat()
    }

    @objc private func ctxToggleSleep() {
        companion.forceQuietSleep.toggle()
    }

    @objc private func ctxQuitApp() {
        NSApp.terminate(nil)
    }
}
