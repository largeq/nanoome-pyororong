import Foundation
import XCTest
@testable import TableConverterMac

final class AppPreferencesMigrationTests: XCTestCase {
    func testLegacyShortcutAndGuideSettingsSurviveReloadWithoutImportingOtherKeys() throws {
        let suite = "com.phronesis.pyororong.tests.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = ShortcutPreferences(isEnabled: false)
        let legacy: [String: Any] = [
            ShortcutPreferences.storageKey: try JSONEncoder().encode(shortcut),
            UsageGuidePreferences.storageKey: false,
            UsageGuidePreferences.completionKey: true,
            "unrelatedLegacySetting": "leave behind",
        ]

        AppPreferencesMigration.migrate(from: legacy, to: defaults)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(ShortcutPreferences.load(from: reopened), shortcut)
        XCTAssertFalse(UsageGuidePreferences.shouldShowAtLaunch(from: reopened))
        XCTAssertEqual(reopened.object(forKey: UsageGuidePreferences.storageKey) as? Bool, false)
        XCTAssertTrue(reopened.bool(forKey: UsageGuidePreferences.completionKey))
        XCTAssertNil(reopened.object(forKey: "unrelatedLegacySetting"))
    }

    func testExistingNewAppChoicesTakePrecedenceIncludingFalseValues() throws {
        let suite = "com.phronesis.pyororong.tests.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let current = ShortcutPreferences(isEnabled: false)
        current.save(to: defaults)
        defaults.set(false, forKey: UsageGuidePreferences.storageKey)
        defaults.set(false, forKey: UsageGuidePreferences.completionKey)

        AppPreferencesMigration.migrate(from: [
            ShortcutPreferences.storageKey: try JSONEncoder().encode(ShortcutPreferences()),
            UsageGuidePreferences.storageKey: true,
            UsageGuidePreferences.completionKey: true,
        ], to: defaults)

        XCTAssertEqual(ShortcutPreferences.load(from: defaults), current)
        XCTAssertFalse(defaults.bool(forKey: UsageGuidePreferences.storageKey))
        XCTAssertFalse(defaults.bool(forKey: UsageGuidePreferences.completionKey))
    }

    func testMigrationRunsOnlyOnceAndDoesNotRestoreADeletedNewPreference() throws {
        let suite = "com.phronesis.pyororong.tests.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy: [String: Any] = [UsageGuidePreferences.storageKey: true]
        AppPreferencesMigration.migrate(from: legacy, to: defaults)
        defaults.removeObject(forKey: UsageGuidePreferences.storageKey)

        AppPreferencesMigration.migrate(from: legacy, to: defaults)

        XCTAssertNil(defaults.object(forKey: UsageGuidePreferences.storageKey))
    }

    func testNoLegacySettingsPreservesFirstRunBehavior() throws {
        let suite = "com.phronesis.pyororong.tests.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppPreferencesMigration.migrate(from: [:], to: defaults)

        XCTAssertNil(defaults.object(forKey: ShortcutPreferences.storageKey))
        XCTAssertNil(defaults.object(forKey: UsageGuidePreferences.storageKey))
        XCTAssertNil(defaults.object(forKey: UsageGuidePreferences.completionKey))
        XCTAssertTrue(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
    }
}
