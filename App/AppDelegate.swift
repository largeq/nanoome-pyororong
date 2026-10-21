import AppKit
import TableConverterCore
import TableConverterMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let converter = ClipboardTableConverter()
    private let notifier = ConversionNotifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "table_icon") ?? NSImage(systemSymbolName: "tablecells", accessibilityDescription: "프네 표변환")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        item.button?.image = image
        item.button?.toolTip = "프네 표변환"
        item.button?.setAccessibilityLabel("프네 표변환")
        let menu = NSMenu()
        let convert = NSMenuItem(title: "표 변환하기", action: #selector(convertTable), keyEquivalent: "")
        convert.target = self
        menu.addItem(convert)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func convertTable(_ sender: Any?) {
        do {
            let result = try converter.convert()
            var message = "표가 네이버 카페 형식으로 변환되었습니다!"
            if result.hasDiagonal { message += "\n※ 대각선이 제거되었습니다." }
            notifier.show(title: "✅ 변환 완료", message: message)
        } catch let error as ConversionError {
            notifier.show(title: error.notificationTitle, message: error.localizedDescription, isError: true)
        } catch {
            notifier.show(title: "⚠️ 변환 실패", message: "오류가 발생했습니다: \(error.localizedDescription)", isError: true)
        }
    }
}
