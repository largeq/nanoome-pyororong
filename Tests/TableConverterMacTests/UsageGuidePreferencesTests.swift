import Foundation
import XCTest
@testable import TableConverterMac

final class UsageGuidePreferencesTests: XCTestCase {
    func testGuideIsShownWithoutASavedChoice() throws {
        let suite = "com.phronesis.pyororong.tests.guide.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
        XCTAssertFalse(UsageGuidePreferences.load(from: defaults).showAtLaunch)
        XCTAssertNil(defaults.object(forKey: UsageGuidePreferences.storageKey))
        UsageGuidePreferences.markCompleted(in: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(UsageGuidePreferences.shouldShowAtLaunch(from: reopened))
        XCTAssertNil(defaults.object(forKey: UsageGuidePreferences.storageKey))
    }

    func testHiddenGuideSurvivesReloadAndShortcutChangesAndCanBeReenabled() throws {
        let suite = "com.phronesis.pyororong.tests.guide.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UsageGuidePreferences(showAtLaunch: false).save(to: defaults)
        XCTAssertFalse(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
        UsageGuidePreferences.markCompleted(in: defaults)
        ShortcutPreferences(isEnabled: false).save(to: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(UsageGuidePreferences.load(from: reopened).showAtLaunch)
        XCTAssertFalse(ShortcutPreferences.load(from: reopened).isEnabled)
        UsageGuidePreferences(showAtLaunch: true).save(to: reopened)
        UsageGuidePreferences.markCompleted(in: reopened)
        XCTAssertTrue(UsageGuidePreferences.load(from: defaults).showAtLaunch)
        XCTAssertTrue(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
        XCTAssertFalse(ShortcutPreferences.load(from: defaults).isEnabled)
    }

    func testInvalidStoredChoiceKeepsTheGuideAvailable() throws {
        let suite = "com.phronesis.pyororong.tests.guide.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("invalid", forKey: UsageGuidePreferences.storageKey)
        XCTAssertFalse(UsageGuidePreferences.load(from: defaults).showAtLaunch)
        XCTAssertTrue(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
        UsageGuidePreferences.markCompleted(in: defaults)
        XCTAssertFalse(UsageGuidePreferences.shouldShowAtLaunch(from: defaults))
    }
}
