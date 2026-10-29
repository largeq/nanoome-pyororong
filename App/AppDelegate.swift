import AppKit
import OSLog
import TableConverterCore
import TableConverterMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusMenuOpenCount = 0
    private let menuLogger = Logger(subsystem: "com.phronesis.pyororong", category: "StatusMenu")
    private var clipboardTimer: Timer?
    private var displayedState: ClipboardTableState?
    private var displayedClipboardRevision: Int?
    private var iconAnimator: MenuBarIconAnimator?
    private let converter: ClipboardTableConverter
    private let shortcutDefaults: UserDefaults
    private let supportController: SupportController
    private let updates: UpdateChecking
    private var updateMenuItems: [NSMenuItem] = []
    private let notifier = ConversionNotifier()
    private var statusMenuItem: NSMenuItem?
    private var convertMenuItem: NSMenuItem?
    private var shortcutPreferences: ShortcutPreferences
    private var shortcutSettings: ShortcutSettingsController?
    private var usageGuide: UsageGuideController?
    private var about: AboutController?
    private var isConverting = false {
        didSet { updates.isConverting = isConverting }
    }
    private var conversionTask: Task<Void, Never>?
    private lazy var shortcut = GlobalConversionShortcut { [weak self] in
        guard let self, self.shortcutSettings?.window?.isKeyWindow != true else { return }
        self.convertTable(nil)
    }

    init(converter: ClipboardTableConverter? = nil, shortcutDefaults: UserDefaults = .standard,
         supportController: SupportController? = nil, updates: UpdateChecking? = nil) {
        self.converter = converter ?? ClipboardTableConverter()
        self.shortcutDefaults = shortcutDefaults
        self.supportController = supportController ?? SupportController()
        self.updates = updates ?? UpdateController()
        self.shortcutPreferences = ShortcutPreferences.load(from: shortcutDefaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: MenuBarIconAnimator.imageSize.width)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let status: NSMenuItem
        if #available(macOS 14.0, *) {
            status = .sectionHeader(title: "변환할 표가 있습니다")
        } else {
            status = NSMenuItem(title: "변환할 표가 있습니다", action: nil, keyEquivalent: "")
        }
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)
        menu.addItem(.separator())
        let convert = NSMenuItem(title: "표 변환하기", action: #selector(performPrimaryMenuAction), keyEquivalent: "")
        convert.target = self
        convert.isEnabled = false
        convertMenuItem = convert
        menu.addItem(convert)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(showShortcutSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let guide = NSMenuItem(title: "사용법 보기", action: #selector(showUsageGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)
        menu.addItem(supportController.makeMenuItem())
        let checkUpdates = NSMenuItem(title: "업데이트 확인…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)
        let about = NSMenuItem(title: "표로롱에 관하여", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "표로롱 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        // The app menu also routes standard shortcuts while a utility window is active.
        let applicationMenu = NSMenu(title: "표로롱")
        for item in [checkUpdates, about, .separator(), settings, .separator(), quit] {
            let copy = item.copy() as! NSMenuItem
            applicationMenu.addItem(copy)
            if item === checkUpdates { updateMenuItems.append(copy) }
        }
        applicationMenu.autoenablesItems = false
        updateMenuItems.append(checkUpdates)
        updates.onStateChange = { [weak self] in self?.updateUpdateMenu() }
        updates.start()
        updateUpdateMenu()
        let applicationMenuItem = NSMenuItem()
        applicationMenuItem.submenu = applicationMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem)
        NSApplication.shared.mainMenu = mainMenu
        statusMenu = menu
        statusItem = item
        if #available(macOS 27.0, *) {
            // Keep system menu-bar navigation from intercepting the button's click delivery.
            item.button?.target = self
            item.button?.action = #selector(showStatusMenu)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            item.menu = menu
        }
        if let button = item.button { iconAnimator = MenuBarIconAnimator(button: button) }
        notifier.anchor = item.button
        notifier.onRetry = { [weak self] in self?.convertTable(nil) }
        notifier.onShowUsageGuide = { [weak self] in self?.showUsageGuide() }
        do {
            try applyShortcut(shortcutPreferences)
        } catch {
            updateShortcutMenu()
            notifier.show(title: "단축키를 사용할 수 없습니다", message: error.localizedDescription + "\n메뉴의 ‘설정…’에서 변경할 수 있습니다.", isError: true)
        }
        Task { await refreshClipboardState() }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshClipboardState() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
        if UsageGuidePreferences.shouldShowAtLaunch(from: shortcutDefaults) {
            presentUsageGuide()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardTimer?.invalidate()
        conversionTask?.cancel()
        iconAnimator?.stop()
        notifier.stop()
        shortcut.unregister()
        usageGuide?.close()
        about?.closeAll()
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuOpenCount += 1
        menuLogger.info("Status menu tracking started")
        notifier.dismiss()
        updateMenu()
        Task { await refreshClipboardState() }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuLogger.info("Status menu tracking ended")
    }

    @objc private func showStatusMenu() {
        guard let item = statusItem, let menu = statusMenu, let button = item.button else { return }
        guard item.menu == nil else {
            menuLogger.debug("Status button activation ignored while the menu is attached")
            return
        }
        let openCount = statusMenuOpenCount
        let eventType = NSApp.currentEvent?.type.rawValue ?? 0
        menuLogger.info("Status button requested menu presentation; event=\(eventType), active=\(NSApp.isActive)")
        notifier.dismiss()
        // Attach only while AppKit tracks the menu; the nil check also prevents reentry.
        item.menu = menu
        defer {
            item.menu = nil
            button.state = .off
            button.highlight(false)
            if statusMenuOpenCount == openCount {
                menuLogger.error("Status button presentation returned without opening the menu; event=\(eventType)")
            } else {
                menuLogger.info("Status button presentation finished; selection cleared")
            }
        }
        button.performClick(nil)
    }

    private func updateMenu() {
        guard let status = statusMenuItem, let primary = convertMenuItem else { return }
        let statusTitle: String
        let primaryTitle: String
        var primaryEnabled = false
        var conversionShortcut = shortcut.registeredShortcut
        if isConverting {
            statusTitle = "표를 변환하고 있습니다…"
            primaryTitle = "변환 중…"
        } else if displayedClipboardRevision == converter.clipboardRevision, let state = displayedState {
            switch state {
            case .idle:
                statusTitle = "한글에서 표를 복사하세요"
                primaryTitle = "표 변환하기"
            case .readyToConvert:
                statusTitle = "변환할 표가 있습니다"
                primaryTitle = "표 변환하기"
                primaryEnabled = true
            case .readyToPaste:
                statusTitle = "변환 완료"
                primaryTitle = "변환 결과 보기"
                primaryEnabled = true
                conversionShortcut = nil
            case .conversionFailed:
                statusTitle = "변환하지 못했습니다"
                primaryTitle = "오류 안내 보기"
                primaryEnabled = notifier.latestResult?.clipboardRevision == converter.clipboardRevision
                conversionShortcut = nil
            }
        } else {
            statusTitle = "변환할 표가 있습니다"
            primaryTitle = "표 변환하기"
        }

        let keyEquivalent = conversionShortcut?.keyEquivalent ?? ""
        let modifiers = conversionShortcut?.modifierFlags ?? []
        // Avoid invalidating AppKit's tracking state when clipboard polling changes nothing.
        if status.title != statusTitle { status.title = statusTitle }
        if primary.title != primaryTitle { primary.title = primaryTitle }
        if primary.isEnabled != primaryEnabled { primary.isEnabled = primaryEnabled }
        if primary.keyEquivalent != keyEquivalent { primary.keyEquivalent = keyEquivalent }
        if primary.keyEquivalentModifierMask != modifiers { primary.keyEquivalentModifierMask = modifiers }
    }

    @objc private func performPrimaryMenuAction(_ sender: Any?) {
        guard !isConverting, displayedClipboardRevision == converter.clipboardRevision else {
            updateMenu()
            Task { await refreshClipboardState() }
            return
        }
        switch displayedState {
        case .readyToConvert, .readyToPaste:
            convertTable(sender)
        case .conversionFailed:
            notifier.showLatestResult(clipboardRevision: converter.clipboardRevision)
        default:
            break
        }
        updateMenu()
    }

    private func refreshClipboardState(animateCompletion: Bool = false) async {
        let revision = converter.clipboardRevision
        notifier.observeClipboardRevision(revision)
        updateMenu()
        guard !isConverting else { return }
        let state = await converter.clipboardState()
        guard !isConverting, converter.clipboardRevision == revision else { return }
        let changed = state != displayedState
        displayedState = state
        displayedClipboardRevision = revision
        updateMenu()
        guard changed else { return }

        let description: String
        switch state {
        case .idle:
            description = "표로롱 — 한글에서 표 또는 문서를 복사해주세요."
        case .readyToConvert:
            let hint = shortcut.registeredShortcut.map { " 또는 \($0.displayName)" } ?? ""
            description = "표로롱 — 변환 대기: ‘표 변환하기’\(hint)를 눌러주세요."
        case .readyToPaste:
            description = "표로롱 — 변환 완료: \(ConversionFeedback.pasteInstruction)"
        case .conversionFailed:
            description = "표로롱 — 변환 실패: 오류 안내를 확인하고 다시 시도해주세요."
        }
        iconAnimator?.show(state, animateCompletion: animateCompletion)
        statusItem?.button?.toolTip = description
        statusItem?.button?.setAccessibilityLabel(description)
    }

    @objc private func convertTable(_ sender: Any?) {
        guard !isConverting else { return }
        if converter.isReadyToPaste {
            notifier.showAlreadyConverted(clipboardRevision: converter.clipboardRevision)
            return
        }
        notifier.dismiss()
        isConverting = true
        updateMenu()
        iconAnimator?.showConverting()
        let description = "표로롱 — 표를 변환하고 있습니다."
        statusItem?.button?.toolTip = description
        statusItem?.button?.setAccessibilityLabel(description)
        conversionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isConverting = false
                self.conversionTask = nil
                self.updateMenu()
            }
            do {
                let result = try await self.converter.convertAsync()
                let convertedRevision = self.converter.clipboardRevision
                try await self.iconAnimator?.finishDrawingTable()
                self.isConverting = false
                self.displayedState = nil
                guard self.converter.clipboardRevision == convertedRevision,
                      self.converter.isReadyToPaste else {
                    await self.refreshClipboardState()
                    return
                }
                await self.refreshClipboardState(animateCompletion: true)
                self.notifier.showConverted(result, clipboardRevision: convertedRevision)
            } catch {
                self.isConverting = false
                self.displayedState = nil
                await self.refreshClipboardState()
                guard !(error is CancellationError) else { return }
                self.notifier.showFailure(error, clipboardRevision: self.converter.clipboardRevision)
            }
        }
    }

    private func applyShortcut(_ preferences: ShortcutPreferences) throws {
        if preferences.isEnabled { try shortcut.register(preferences.shortcut) }
        else { shortcut.unregister() }
        shortcutPreferences = preferences
        preferences.save(to: shortcutDefaults)
        updateShortcutMenu()
    }

    private func updateShortcutMenu() {
        let active = shortcut.registeredShortcut
        usageGuide?.updateShortcut(active)
        displayedState = nil
        updateMenu()
        Task { await refreshClipboardState() }
    }

    @objc private func showShortcutSettings() {
        notifier.dismiss()
        if shortcutSettings == nil {
            shortcutSettings = ShortcutSettingsController(onApply: { [weak self] preferences in
                try self?.applyShortcut(preferences)
            }, onRecordingChanged: { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.shortcut.unregister()
                    self.updateShortcutMenu()
                } else {
                    do {
                        if self.shortcutPreferences.isEnabled { try self.shortcut.register(self.shortcutPreferences.shortcut) }
                        self.updateShortcutMenu()
                    } catch {
                        self.updateShortcutMenu()
                        self.notifier.show(title: "단축키를 사용할 수 없습니다", message: error.localizedDescription, isError: true)
                    }
                }
            }, automaticallyChecksForUpdates: { [weak self] in
                self?.updates.automaticallyChecksForUpdates ?? true
            }, onApplyUpdatePreference: { [weak self] enabled in
                self?.updates.automaticallyChecksForUpdates = enabled
            })
        }
        shortcutSettings?.show(preferences: shortcutPreferences)
    }

    private func updateUpdateMenu() {
        let title = updates.hasUpdate ? "업데이트 확인… (새 버전 있음)" : "업데이트 확인…"
        for item in updateMenuItems {
            if item.title != title { item.title = title }
            if item.isEnabled != updates.canCheckForUpdates { item.isEnabled = updates.canCheckForUpdates }
        }
    }

    @objc private func checkForUpdates() {
        notifier.dismiss()
        updates.checkForUpdates()
    }

    @objc private func showUsageGuide() {
        notifier.dismiss()
        presentUsageGuide()
    }

    private func presentUsageGuide() {
        if usageGuide == nil { usageGuide = UsageGuideController(defaults: shortcutDefaults) }
        usageGuide?.show(shortcut: shortcut.registeredShortcut)
    }

    @objc private func showAbout() {
        notifier.dismiss()
        if about == nil { about = AboutController() }
        about?.show()
    }
}
