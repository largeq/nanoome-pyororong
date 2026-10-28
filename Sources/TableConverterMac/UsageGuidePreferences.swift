import Foundation

/// Kept separately from shortcut settings so updates and shortcut changes do not reset it.
public struct UsageGuidePreferences: Equatable, Sendable {
    public var showAtLaunch: Bool

    public init(showAtLaunch: Bool = false) {
        self.showAtLaunch = showAtLaunch
    }

    public static let storageKey = "showUsageGuideAtLaunch"
    public static let completionKey = "hasCompletedUsageGuide"

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(showAtLaunch: defaults.object(forKey: storageKey) as? Bool ?? false)
    }

    public static func shouldShowAtLaunch(from defaults: UserDefaults = .standard) -> Bool {
        // An existing explicit choice takes precedence over the first-run policy.
        if let choice = defaults.object(forKey: storageKey) as? Bool { return choice }
        return !defaults.bool(forKey: completionKey)
    }

    public static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(showAtLaunch, forKey: Self.storageKey)
    }
}
