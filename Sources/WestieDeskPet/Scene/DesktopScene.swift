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

    private let windowTracker = WindowPlatformTracker()
    public var targetScreen: NSScreen?
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
        refreshWindowSnapshot()
        if let snap = latestSnapshot {
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

    public func previewClimbToTopGreeting(routineOverride: TopClimbRoutine? = nil) {
        if mode == .tennis {
            switchToMode(.companion)
        }
        refreshWindowSnapshot()
        guard let snap = latestSnapshot, let top = snap.perchLayout.topPerch else { return }
        let targetX = top.clampedX(top.maxX - min(110, top.width * 0.26), margin: 22)
        companion.beginStealthClimbToTop(
            targetX: targetX,
            windowID: snap.perchLayout.activeWindowID ?? companion.trackedWindowID,
            climbToGreet: true,
            routineOverride: routineOverride
        )
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
        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(max(currentTime - lastUpdateTime, 0.001), 0.1)
        }
        lastUpdateTime = currentTime

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
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleMouseMoved(scenePoint: pt)
        } else if isActivelyInteractingWithDog {
            companion.handleMouseDragged(to: pt)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let pt = event.location(in: self)
        if mode == .tennis {
            tennis.handleLeftMouseUp(scenePoint: pt)
        } else if isActivelyInteractingWithDog {
            refreshWindowSnapshot()
            companion.handleMouseUp(at: pt, snapshot: latestSnapshot, sceneSize: size)
        }
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
        let menu = NSMenu(title: "西高地")

        let tennisItem = NSMenuItem(title: "🎾 开始打网球 (WASD + 鼠标)", action: #selector(ctxStartTennis), keyEquivalent: "")
        tennisItem.target = self
        menu.addItem(tennisItem)

        menu.addItem(.separator())

        let moveTopItem = NSMenuItem(title: "📍 移到当前窗口正上方", action: #selector(ctxMoveWindowTop), keyEquivalent: "")
        moveTopItem.target = self
        menu.addItem(moveTopItem)

        let moveRightItem = NSMenuItem(title: "👀 移到屏幕右侧边", action: #selector(ctxMoveRightPeek), keyEquivalent: "")
        moveRightItem.target = self
        menu.addItem(moveRightItem)

        let previewClimbItem = NSMenuItem(title: "🐾 立即预览爬顶", action: #selector(ctxPreviewClimb), keyEquivalent: "")
        previewClimbItem.target = self
        menu.addItem(previewClimbItem)

        let previewFlashItem = NSMenuItem(title: "⚡ 立即预览闪身步", action: #selector(ctxPreviewFlashStep), keyEquivalent: "")
        previewFlashItem.target = self
        menu.addItem(previewFlashItem)

        menu.addItem(.separator())

        // Pet Species Switcher (Westie Dog <-> Golden Shaded Cat!)
        let speciesSubmenu = NSMenu(title: "切换宠物")
        let curSpecies = companion.preferences.petSpecies
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

        // Top-Bar Animation Effect Switcher (Classic Story vs Flash-Step vs Random)
        let routineSubmenu = NSMenu(title: "爬顶动态特效")
        let curRoutine = companion.preferences.topClimbRoutine
        for rt in TopClimbRoutine.allCases {
            let item = NSMenuItem(title: rt.displayName, action: #selector(ctxSelectClimbRoutine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rt.rawValue
            item.state = (curRoutine == rt) ? .on : .off
            routineSubmenu.addItem(item)
        }
        let routineParent = NSMenuItem(title: "🎬 爬顶特效: \(curRoutine.shortLabel)", action: nil, keyEquivalent: "")
        routineParent.submenu = routineSubmenu
        menu.addItem(routineParent)

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
        menu.addItem(prefParent)

        // Quick v0.4 Stealth Switch Delay submenu
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
        menu.addItem(delayParent)

        // Quick v0.4 Climb-to-Top Interval submenu
        let climbSubmenu = NSMenu(title: "爬顶互动间隔")
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
        let climbParent = NSMenuItem(title: "🐾 爬顶互动: \(climbLabel)", action: nil, keyEquivalent: "")
        climbParent.submenu = climbSubmenu
        menu.addItem(climbParent)

        // Quick Dog Scale submenu
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
        menu.addItem(scaleParent)

        let settingsItem = NSMenuItem(title: "⚙️ 陪伴偏好设置…", action: #selector(ctxOpenPreferences), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

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

        let treatTitle = (companion.preferences.petSpecies == .goldenCat) ? "🐟 喂一条小鱼干" : "🦴 喂一根骨头饼干"
        let treatItem = NSMenuItem(title: treatTitle, action: #selector(ctxFeedTreat), keyEquivalent: "")
        treatItem.target = self
        menu.addItem(treatItem)

        let sleepTitle = companion.forceQuietSleep ? "☀️ 取消固定趴睡" : "💤 安静趴睡模式"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(ctxToggleSleep), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

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
        previewClimbToTopGreeting()
    }

    @objc private func ctxPreviewFlashStep() {
        previewClimbToTopGreeting(routineOverride: .flashStep)
    }

    @objc private func ctxSelectPetSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sp = PetSpecies(rawValue: raw)
        else { return }
        companion.preferences.petSpecies = sp
    }

    @objc private func ctxSelectClimbRoutine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let rt = TopClimbRoutine(rawValue: raw)
        else { return }
        companion.preferences.topClimbRoutine = rt
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
            onPreviewClimb: { [weak self] in
                self?.previewClimbToTopGreeting()
            },
            onPreviewFlashStep: { [weak self] in
                self?.previewClimbToTopGreeting(routineOverride: .flashStep)
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
