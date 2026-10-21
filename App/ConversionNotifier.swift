import AppKit
import UserNotifications

@MainActor
final class ConversionNotifier: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func show(title: String, message: String, isError: Bool = false) {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let settings = await center.notificationSettings()
                let allowed: Bool
                if settings.authorizationStatus == .notDetermined {
                    allowed = try await center.requestAuthorization(options: [.alert, .sound])
                } else {
                    allowed = [.authorized, .provisional].contains(settings.authorizationStatus)
                }
                guard allowed else {
                    showAlert(title: title, message: message, isError: isError)
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = message
                content.sound = .default
                try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                showAlert(title: title, message: message, isError: isError)
            }
        }
    }

    private func showAlert(title: String, message: String, isError: Bool) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = isError ? .warning : .informational
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
