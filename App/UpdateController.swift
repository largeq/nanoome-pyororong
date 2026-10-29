import AppKit
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var hasUpdate: Bool { get }
    var isConverting: Bool { get set }
    var onStateChange: (() -> Void)? { get set }
    func start()
    func checkForUpdates()
}

@MainActor
final class UpdateController: NSObject, UpdateChecking, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private let bundle: Bundle
    private let openURL: @MainActor (URL) -> Bool
    private let runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse
    private var observation: NSKeyValueObservation?
    private var started = false
    private var startupError: Error?
    private var postponedInstall: (() -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var lastCheckError: Error?
    private(set) var hasUpdate = false {
        didSet { if hasUpdate != oldValue { onStateChange?() } }
    }
    var isConverting = false {
        didSet {
            guard isConverting != oldValue else { return }
            onStateChange?()
            if !isConverting, let install = postponedInstall {
                postponedInstall = nil
                install()
            }
        }
    }
    // A custom host bundle also lets integration checks use isolated preferences and feeds.
    lazy var updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle,
                                 userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: self), delegate: self)

    init(bundle: Bundle = .main,
         openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
         runAlert: @escaping @MainActor (NSAlert) -> NSApplication.ModalResponse = {
             NSApp.activate(ignoringOtherApps: true)
             return $0.runModal()
         }) {
        self.bundle = bundle
        self.openURL = openURL
        self.runAlert = runAlert
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        !isConverting && (startupError != nil || (started && updater.canCheckForUpdates))
    }

    func start() {
        guard !started, startupError == nil else { return }
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onStateChange?() }
        }
        do {
            try updater.start()
            started = true
        } catch {
            // A release configuration problem must not interrupt normal clipboard conversion.
            startupError = error
        }
        onStateChange?()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        // Finish status-menu tracking before presenting update UI.
        DispatchQueue.main.async { [self] in
            guard canCheckForUpdates else { return }
            if let startupError {
                let alert = NSAlert()
                alert.messageText = "업데이트를 확인할 수 없습니다"
                alert.informativeText = "다운로드 페이지에서 새 버전을 확인하거나 나중에 다시 시도해 주세요.\n\n" + startupError.localizedDescription
                alert.addButton(withTitle: "다운로드 페이지 열기")
                alert.addButton(withTitle: "닫기").keyEquivalent = "\u{1b}"
                if runAlert(alert) == .alertFirstButtonReturn {
                    _ = openURL(SupportController.repositoryURL.appendingPathComponent("releases"))
                }
            } else {
                updater.checkForUpdates()
            }
        }
    }

    // Menu-bar apps announce background discoveries in their menu without stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate { hasUpdate = true }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { hasUpdate = false }
    func standardUserDriverWillFinishUpdateSession() { hasUpdate = false }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        lastCheckError = nil
        hasUpdate = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        lastCheckError = error
        hasUpdate = false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { lastCheckError = error }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isConverting else { return false }
        postponedInstall = installHandler
        return true
    }
}
