import AppKit
import TableConverterMac

@main
@MainActor
enum PyororongApp {
    static func main() {
        let application = NSApplication.shared
        AppPreferencesMigration.migrate(
            from: UserDefaults.standard.persistentDomain(forName: "com.phronesis.tableconverter") ?? [:],
            to: .standard
        )
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
