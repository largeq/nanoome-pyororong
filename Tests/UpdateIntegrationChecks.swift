import AppKit
import CryptoKit
import Network
import Sparkle

private final class AppcastTestServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.phronesis.pyororong.tests.appcast")
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var ready = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.lock.lock()
            if case .ready = state { self.ready = true }
            self.lock.unlock()
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection)
        }
        listener.start(queue: queue)
    }

    var port: UInt16? { listener.port?.rawValue }
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }
    func stop() { listener.cancel() }

    func requestCount(_ path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[path, default: 0]
    }

    private func receive(_ connection: NWConnection, previous: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, finished, error in
            guard let self else { connection.cancel(); return }
            let received = previous + (data ?? Data())
            if let request = String(data: received, encoding: .utf8), request.contains("\r\n\r\n") {
                let components = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard components.count >= 2 else { connection.cancel(); return }
                let path = String(components[1].split(separator: "?")[0])
                self.lock.lock()
                self.counts[path, default: 0] += 1
                self.lock.unlock()
                let (status, body) = self.response(path)
                let content = Data(body.utf8)
                let header = "HTTP/1.1 \(status)\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: \(content.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + content, completion: .contentProcessed { _ in connection.cancel() })
            } else if finished || error != nil || received.count >= 8192 {
                connection.cancel()
            } else {
                self.receive(connection, previous: received)
            }
        }
    }

    private func response(_ path: String) -> (String, String) {
        let item: (Int, String) -> String = { version, extra in
            """
            <item><title>Version \(version)</title>
            <sparkle:version>\(version)</sparkle:version>
            <sparkle:shortVersionString>2.\(version)</sparkle:shortVersionString>
            \(extra)
            <enclosure url="http://127.0.0.1:\(self.port!)/archive.zip" length="1" type="application/octet-stream" />
            </item>
            """
        }
        let items: String
        switch path {
        case "/current.xml": items = item(1, "")
        case "/newer.xml": items = item(2, "")
        case "/unsupported.xml": items = item(2, "<sparkle:minimumSystemVersion>99.0.0</sparkle:minimumSystemVersion>")
        case "/preview.xml": items = item(999, "<sparkle:channel>beta</sparkle:channel>") + item(1, "")
        case "/malformed.xml": return ("200 OK", "this is not an appcast")
        default: return ("404 Not Found", "not found")
        }
        return ("200 OK", """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel><title>표로롱 시험 업데이트</title>\(items)</channel></rss>
            """)
    }
}

@MainActor
private final class UpdateChecksDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await UpdateIntegrationChecks.run()
                print("Update integration checks passed: isolated Sparkle preferences, default automatic checks, disabled automatic installation, real appcast discovery/current/unsupported/preview/error cases, gentle reminders, conversion protection, and configuration fallback.")
                NSApp.terminate(nil)
            } catch {
                fputs("Update integration check failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
}

@main
struct UpdateIntegrationChecks {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = UpdateChecksDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    fileprivate static func run() async throws {
        let appBundle = try unwrap(Bundle(path: CommandLine.arguments[1]), "Built app bundle is missing")
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let clipboardRevision = NSPasteboard.general.changeCount
        try require((appBundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? NSNumber)?.boolValue == true,
                    "Distributed apps must default automatic update checks to enabled")
        for key in ["SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling"] {
            try require((appBundle.object(forInfoDictionaryKey: key) as? NSNumber)?.boolValue == false,
                        "\(key) must be explicitly disabled")
        }
        try require((appBundle.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? NSNumber)?.intValue == 86400,
                    "Automatic checks must use a daily schedule")
        let productionKey = appBundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        try require(Data(base64Encoded: productionKey)?.count == 32, "The built app must have a valid public update key")
        let productionFeed = appBundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        try require(URL(string: productionFeed)?.scheme == "https", "Production update information must use HTTPS")

        let server = try AppcastTestServer()
        defer { server.stop() }
        try await wait("Loopback appcast server did not start") { server.isReady && server.port != nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("PyororongUpdates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var domains: [String] = []
        var controllers: [UpdateController] = []
        defer {
            for controller in controllers { controller.automaticallyChecksForUpdates = false }
            for domain in domains { UserDefaults.standard.removePersistentDomain(forName: domain) }
            try? FileManager.default.removeItem(at: temporary)
        }
        // Test signing material remains in memory; no production keychain item is read or changed.
        let testKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        func fixture(_ path: String, automatic: Bool = false, publicKey: String? = nil) throws -> Bundle {
            let domain = "com.phronesis.pyororong.tests.updates.\(UUID().uuidString)"
            domains.append(domain)
            let url = temporary.appendingPathComponent("\(domain).app", isDirectory: true)
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info: [String: Any] = [
                "CFBundleIdentifier": domain, "CFBundleName": "표로롱 업데이트 시험",
                "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "2.0",
                "CFBundleExecutable": "PyororongUpdateFixture", "LSUIElement": true,
                "SUFeedURL": "http://127.0.0.1:\(server.port!)\(path)", "SUPublicEDKey": publicKey ?? testKey,
                "SUEnableAutomaticChecks": automatic, "SUScheduledCheckInterval": 86400,
                "SUAutomaticallyUpdate": false, "SUAllowsAutomaticUpdates": false,
                "SUVerifyUpdateBeforeExtraction": true, "SUEnableSystemProfiling": false
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
            return try unwrap(Bundle(url: url), "Could not load isolated fixture bundle")
        }
        func controller(_ path: String) throws -> UpdateController {
            let value = UpdateController(bundle: try fixture(path))
            controllers.append(value)
            value.start()
            return value
        }

        let defaultsBundle = try fixture("/current.xml", automatic: true)
        let defaultsDomain = defaultsBundle.bundleIdentifier!
        let isolatedDefaults = UserDefaults(suiteName: defaultsDomain)!
        isolatedDefaults.set(true, forKey: "SUAutomaticallyUpdate")
        let defaultsController = UpdateController(bundle: defaultsBundle)
        controllers.append(defaultsController)
        try require(defaultsController.automaticallyChecksForUpdates, "Fresh settings must use the enabled app default")
        try require(!defaultsController.updater.allowsAutomaticUpdates && !defaultsController.updater.automaticallyDownloadsUpdates,
                    "Automatic installation must remain disabled even with an older saved opt-in")
        defaultsController.automaticallyChecksForUpdates = false
        let reopened = UpdateController(bundle: defaultsBundle)
        controllers.append(reopened)
        try require(!reopened.automaticallyChecksForUpdates, "User choice must persist across controller recreation")
        reopened.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(reopened.canCheckForUpdates && server.requestCount("/current.xml") == 0,
                    "Disabling automatic checking must prevent background requests while allowing a manual check")
        try await probe(reopened)
        try require(!reopened.hasUpdate && isNoUpdate(reopened.lastCheckError),
                    "Current feed must report no new version: \(String(describing: reopened.lastCheckError))")
        let currentError = reopened.lastCheckError! as NSError
        try require((currentError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue == 1,
                    "The current version must be distinguished from an incompatible version")
        let parsedItem = try unwrap(currentError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem,
                                    "Sparkle must supply the actual parsed current appcast item")

        let newer = try controller("/newer.xml")
        try require(newer.responds(to: NSSelectorFromString("updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")),
                    "Sparkle must see the exact relaunch postponement delegate selector")
        var stateChanges = 0
        newer.onStateChange = { stateChanges += 1 }
        try await probe(newer)
        try require(newer.hasUpdate && newer.lastCheckError == nil && stateChanges > 0,
                    "An actual newer appcast must update the menu state without an error")
        try require(newer.supportsGentleScheduledUpdateReminders
                    && !newer.standardUserDriverShouldHandleShowingScheduledUpdate(parsedItem, andInImmediateFocus: true)
                    && !newer.standardUserDriverShouldHandleShowingScheduledUpdate(parsedItem, andInImmediateFocus: false),
                    "Scheduled reminders must defer window presentation to the menu")
        newer.standardUserDriverDidReceiveUserAttention(forUpdate: parsedItem)
        try require(!newer.hasUpdate, "Reading the update must clear the menu reminder")
        newer.updater(newer.updater, didFindValidUpdate: parsedItem)
        newer.standardUserDriverWillFinishUpdateSession()
        try require(!newer.hasUpdate, "Finishing an update session must clear the menu reminder")

        var installs = 0
        newer.isConverting = true
        try require(!newer.canCheckForUpdates, "Update actions must not interrupt an active table conversion")
        try require(newer.updater(newer.updater, shouldPostponeRelaunchForUpdate: parsedItem,
                                  untilInvokingBlock: { installs += 1 }) && installs == 0,
                    "Installation must wait while conversion is running")
        newer.isConverting = false
        try await wait("Deferred install was not resumed after conversion") { installs == 1 }
        newer.isConverting = false
        try require(installs == 1 && newer.canCheckForUpdates, "The deferred install must resume only once")
        try require(!newer.updater(newer.updater, shouldPostponeRelaunchForUpdate: parsedItem,
                                   untilInvokingBlock: { installs += 1 }), "Idle conversion state must not postpone installation")

        let unsupported = try controller("/unsupported.xml")
        try await probe(unsupported)
        let unsupportedError = unsupported.lastCheckError as NSError?
        let unsupportedReason = (unsupportedError?.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        try require(!unsupported.hasUpdate && isNoUpdate(unsupported.lastCheckError)
                    && [3, 5].contains(unsupportedReason ?? -1),
                    "An unsupported macOS/hardware requirement must not be offered as an installable update")

        let preview = try controller("/preview.xml")
        try await probe(preview)
        try require(!preview.hasUpdate && isNoUpdate(preview.lastCheckError), "Preview-channel builds must not replace stable releases")
        for path in ["/missing.xml", "/malformed.xml"] {
            let failed = try controller(path)
            try await probe(failed)
            try require(!failed.hasUpdate && failed.lastCheckError != nil && !isNoUpdate(failed.lastCheckError),
                        "\(path) must report a real error instead of claiming the app is current")
        }

        var fallbackAlerts = 0
        var fallbackURLs: [URL] = []
        let broken = UpdateController(bundle: try fixture("/current.xml", publicKey: "invalid-key"),
                                      openURL: { fallbackURLs.append($0); return true }, runAlert: { alert in
            fallbackAlerts += 1
            precondition(alert.messageText == "업데이트를 확인할 수 없습니다")
            return .alertFirstButtonReturn
        })
        controllers.append(broken)
        broken.start()
        try require(broken.canCheckForUpdates, "A configuration failure must leave the manual fallback available")
        broken.checkForUpdates()
        try await wait("Manual configuration fallback was not presented") { fallbackAlerts == 1 }
        try require(fallbackURLs == [SupportController.repositoryURL.appendingPathComponent("releases")],
                    "The configuration fallback must open the official release page")
        try require(server.requestCount("/archive.zip") == 0, "Checking must never download an update archive without consent")
        try require(NSPasteboard.general.changeCount == clipboardRevision, "Update checks must preserve the general clipboard")
        try "All isolated Sparkle update checks passed. No production feed, preferences, signing keys, clipboard data, or installed app were changed.\n"
            .write(to: output.appendingPathComponent("results.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func probe(_ controller: UpdateController) async throws {
        try require(controller.canCheckForUpdates, "The fixture updater failed to start")
        controller.updater.checkForUpdateInformation()
        try await wait("Sparkle appcast probe did not finish") {
            !controller.updater.sessionInProgress && (controller.hasUpdate || controller.lastCheckError != nil)
        }
        try require(controller.canCheckForUpdates, "Finishing a check must restore the manual update action")
    }

    private static func isNoUpdate(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SUSparkleErrorDomain && error.code == 1001
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "UpdateIntegrationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: "UpdateIntegrationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }

    @MainActor
    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        try require(condition(), message)
    }
}
