import Foundation

public enum AppPreferencesMigration {
    static let completionKey = "hasMigratedLegacyPreferences"

    public static func migrate(from legacy: [String: Any], to defaults: UserDefaults) {
        guard !defaults.bool(forKey: completionKey) else { return }
        for key in [ShortcutPreferences.storageKey, UsageGuidePreferences.storageKey, UsageGuidePreferences.completionKey] {
            if defaults.object(forKey: key) == nil, let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: completionKey)
    }
}
