import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import Grock

final class CorePolicyTests: XCTestCase {
    func testExpectedBundleIdentifier() {
        XCTAssertEqual(AppInfo.expectedBundleIdentifier, "com.jaredatch.Grock")
    }

    func testMarketingVersionMatchesProject() {
        XCTAssertEqual(AppInfo.expectedMarketingVersion, "1.0.0")
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            AppInfo.expectedMarketingVersion
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
            AppInfo.aboutDisclaimer
        )
    }

    func testAboutDisclaimer() {
        XCTAssertEqual(
            AppInfo.aboutDisclaimer,
            "Unofficial. Not affiliated with xAI or SpaceX."
        )
    }

    func testGitHubHelpLinks() {
        XCTAssertEqual(AppInfo.githubRepository, "https://github.com/jaredatch/grock")
        XCTAssertEqual(AppInfo.githubIssues, "https://github.com/jaredatch/grock/issues")
    }

    func testDownloadPathsUniqueWhenExists() {
        let dir = URL(fileURLWithPath: "/tmp/grock-downloads-test")
        let existing = [
            dir.appendingPathComponent("image.png").path,
            dir.appendingPathComponent("image (1).png").path
        ]
        let exists: (String) -> Bool = { existing.contains($0) }
        let result = DownloadPaths.uniqueDestination(
            filename: "image.png",
            in: dir,
            fileExists: exists
        )
        XCTAssertEqual(result.lastPathComponent, "image (2).png")
    }

    func testDownloadPathsNoCollision() {
        let dir = URL(fileURLWithPath: "/tmp/grock-downloads-test")
        let result = DownloadPaths.uniqueDestination(
            filename: "fresh.bin",
            in: dir,
            fileExists: { _ in false }
        )
        XCTAssertEqual(result.lastPathComponent, "fresh.bin")
    }

    func testHotkeyOptionSpaceDisplay() {
        XCTAssertEqual(HotkeyManager.Combo.optionSpace.displayString, "⌥Space")
    }

    func testHotkeyLetterDisplay() {
        let combo = HotkeyManager.Combo(
            keyCode: 5,
            flags: CGEventFlags.maskAlternate.rawValue
        )
        XCTAssertEqual(combo.displayString, "⌥G")
    }

    func testHotkeyCarbonModifiersOption() {
        XCTAssertEqual(
            HotkeyManager.Combo.optionSpace.carbonModifiers,
            UInt32(optionKey)
        )
        let commandG = HotkeyManager.Combo(
            keyCode: 5,
            flags: CGEventFlags.maskCommand.rawValue
        )
        XCTAssertEqual(commandG.carbonModifiers, UInt32(cmdKey))
    }

    func testFreshInstallDefaultsQuickChatToOptionSpace() {
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: nil,
            savedQuickChat: nil,
            didMigrateDual: false,
            didMigrateQuickChatDefault: false
        )
        XCTAssertNil(snapshot.summon)
        XCTAssertNil(snapshot.newChat)
        XCTAssertEqual(snapshot.quickChat, .optionSpace)
    }

    func testLegacySummonIsKeptAndDefaultsStayUnset() throws {
        let data = try JSONEncoder().encode(HotkeyManager.Combo.optionSpace)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: data,
            savedNewChat: nil,
            savedQuickChat: nil,
            didMigrateDual: false,
            didMigrateQuickChatDefault: false
        )
        XCTAssertEqual(snapshot.summon, .optionSpace)
        XCTAssertNil(snapshot.newChat)
        XCTAssertNil(snapshot.quickChat)
    }

    func testFactoryNewChatMovesToQuickChat() throws {
        let data = try JSONEncoder().encode(HotkeyManager.Combo.optionSpace)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: data,
            savedQuickChat: nil,
            didMigrateDual: true,
            didMigrateQuickChatDefault: false
        )
        XCTAssertNil(snapshot.summon)
        XCTAssertNil(snapshot.newChat)
        XCTAssertEqual(snapshot.quickChat, .optionSpace)
    }

    func testCustomizedNewChatIsNotStolen() throws {
        let custom = HotkeyManager.Combo(
            keyCode: 5,
            flags: CGEventFlags.maskCommand.rawValue
        )
        let data = try JSONEncoder().encode(custom)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: data,
            savedQuickChat: nil,
            didMigrateDual: true,
            didMigrateQuickChatDefault: false
        )
        XCTAssertEqual(snapshot.newChat, custom)
        XCTAssertNil(snapshot.quickChat)
    }

    func testAssignedQuickChatIsLeftAlone() throws {
        let newChat = try JSONEncoder().encode(HotkeyManager.Combo.optionSpace)
        let quick = HotkeyManager.Combo(
            keyCode: 5,
            flags: CGEventFlags.maskCommand.rawValue
        )
        let quickData = try JSONEncoder().encode(quick)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: newChat,
            savedQuickChat: quickData,
            didMigrateDual: true,
            didMigrateQuickChatDefault: false
        )
        XCTAssertEqual(snapshot.newChat, .optionSpace)
        XCTAssertEqual(snapshot.quickChat, quick)
    }

    func testClearedNewChatDoesNotGainQuickChatDefault() {
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: nil,
            savedQuickChat: nil,
            didMigrateDual: true,
            didMigrateQuickChatDefault: false
        )
        XCTAssertNil(snapshot.newChat)
        XCTAssertNil(snapshot.quickChat)
    }

    func testClearedBindingsStayClearedAfterQuickChatDefaultMigrate() {
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: nil,
            savedQuickChat: nil,
            didMigrateDual: true,
            didMigrateQuickChatDefault: true
        )
        XCTAssertNil(snapshot.summon)
        XCTAssertNil(snapshot.newChat)
        XCTAssertNil(snapshot.quickChat)
    }

    func testPersistedQuickChatLoadsAfterMigrate() throws {
        let data = try JSONEncoder().encode(HotkeyManager.Combo.optionSpace)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: nil,
            savedQuickChat: data,
            didMigrateDual: true,
            didMigrateQuickChatDefault: true
        )
        XCTAssertNil(snapshot.summon)
        XCTAssertNil(snapshot.newChat)
        XCTAssertEqual(snapshot.quickChat, .optionSpace)
    }

    func testPersistedNewChatLoadsAfterQuickChatDefaultMigrate() throws {
        let data = try JSONEncoder().encode(HotkeyManager.Combo.optionSpace)
        let snapshot = HotkeyBindings.migrate(
            savedSummon: nil,
            savedNewChat: data,
            savedQuickChat: nil,
            didMigrateDual: true,
            didMigrateQuickChatDefault: true
        )
        XCTAssertNil(snapshot.summon)
        XCTAssertEqual(snapshot.newChat, .optionSpace)
        XCTAssertNil(snapshot.quickChat)
    }

    func testHotkeyBindingsDecodeRejectsEmptyData() {
        XCTAssertNil(HotkeyBindings.decode(Data()))
        XCTAssertNil(HotkeyBindings.decode(nil))
    }

    func testVoiceChatHotkeyIsUnsetByDefault() {
        XCTAssertEqual(HotkeyAction.voiceChat.carbonID, 3)
        XCTAssertEqual(HotkeyAction.voiceChat.defaultsKey, "hotkey.voiceChat")
        XCTAssertTrue(WebViewStore.enterVoiceScript.contains("Enter voice mode"))
    }

    func testQuickChatHotkeyIdentity() {
        XCTAssertEqual(HotkeyAction.quickChat.carbonID, 4)
        XCTAssertEqual(HotkeyAction.quickChat.defaultsKey, "hotkey.quickChat")
        let ids = HotkeyAction.allCases.map(\.carbonID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testHotkeyRequiresNonShiftModifier() {
        XCTAssertTrue(HotkeyManager.Combo.optionSpace.isValidShortcut)
        XCTAssertFalse(HotkeyManager.Combo(keyCode: 0, flags: 0).isValidShortcut)
        XCTAssertFalse(
            HotkeyManager.Combo(keyCode: 49, flags: CGEventFlags.maskShift.rawValue).isValidShortcut
        )
        XCTAssertTrue(
            HotkeyManager.Combo(
                keyCode: 5,
                flags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
            ).isValidShortcut
        )
    }

    func testHomeURLIsGrok() {
        XCTAssertEqual(WebViewStore.homeURL.host, "grok.com")
    }

    @MainActor
    func testGrokPageDetection() {
        XCTAssertTrue(WebViewStore.isGrokPage(URL(string: "https://grok.com")))
        XCTAssertTrue(WebViewStore.isGrokPage(URL(string: "https://grok.com/c/abc")))
        XCTAssertTrue(WebViewStore.isGrokPage(URL(string: "https://grok.com?referrer=grock-macos")))
        XCTAssertTrue(WebViewStore.isGrokStartPage(URL(string: "https://grok.com?referrer=grock-macos")))
        XCTAssertFalse(WebViewStore.isGrokStartPage(URL(string: "https://grok.com/c/abc")))
        XCTAssertFalse(WebViewStore.isGrokPage(URL(string: "https://x.com")))
        XCTAssertFalse(WebViewStore.isGrokPage(nil))
        XCTAssertTrue(NavigationPolicy.isGrokHost("www.grok.com"))
        XCTAssertTrue(NavigationPolicy.isGrokHost("GROK.COM."))
        XCTAssertFalse(NavigationPolicy.isGrokHost("notgrok.com"))
        XCTAssertFalse(NavigationPolicy.isGrokHost("grok.com.evil.com"))
    }

    func testOffsiteLinksOpenInBrowser() {
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://grok.com")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://grok.com/c/abc")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://www.grok.com/imagine")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://accounts.x.ai/sign-in")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://auth.x.ai/start")))
        XCTAssertTrue(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://docs.x.ai/grok/faq")))
        XCTAssertTrue(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://example.com")))
        XCTAssertTrue(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://x.com/foo")))
        XCTAssertTrue(NavigationPolicy.shouldOpenInBrowser(URL(string: "https://accounts.x.ai.evil.com/sign-in")))
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://x.com/i/oauth2/authorize"),
                from: URL(string: "https://accounts.x.ai/sign-in")
            )
        )
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://appleid.apple.com/auth/authorize"),
                from: URL(string: "https://auth.x.ai/continue")
            )
        )
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://auth.grokusercontent.com/set-cookie"),
                from: URL(string: "https://accounts.x.ai/sign-in")
            )
        )
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://auth.x.ai/set-cookie"),
                from: URL(string: "https://auth.grokusercontent.com/set-cookie")
            )
        )
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://auth.grokipedia.com/set-cookie"),
                from: URL(string: "https://auth.x.ai/set-cookie")
            )
        )
        XCTAssertFalse(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://accounts.x.ai/account"),
                from: URL(string: "https://auth.grokipedia.com/set-cookie")
            )
        )
        XCTAssertTrue(
            NavigationPolicy.shouldOpenInBrowser(
                URL(string: "https://docs.x.ai/grok/faq"),
                from: URL(string: "https://accounts.x.ai/sign-in")
            )
        )
        XCTAssertTrue(NavigationPolicy.shouldOpenInBrowser(URL(string: "mailto:hi@example.com")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "about:blank")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(URL(string: "blob:https://grok.com/abc")))
        XCTAssertFalse(NavigationPolicy.shouldOpenInBrowser(nil))
    }

    func testAuthHostsStayInProcessPopups() {
        XCTAssertTrue(NavigationPolicy.isAuthHost("x.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("www.x.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("twitter.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("mobile.twitter.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("t.co"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("accounts.x.ai"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("auth.x.ai"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("auth.grokusercontent.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("auth.grokipedia.com"))
        XCTAssertTrue(NavigationPolicy.isAuthHost("appleid.apple.com"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("other.auth.grokusercontent.com"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("other.auth.grokipedia.com"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("auth.grokusercontent.com.evil.com"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("auth.grokipedia.com.evil.com"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("docs.x.ai"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("x.ai"))
        XCTAssertFalse(NavigationPolicy.isAuthHost("grok.com"))
        XCTAssertTrue(NavigationPolicy.shouldPresentAuthPopup(nil))
        XCTAssertTrue(NavigationPolicy.shouldPresentAuthPopup(URL(string: "about:blank")))
        XCTAssertTrue(NavigationPolicy.shouldPresentAuthPopup(URL(string: "https://x.com/i/oauth2/authorize")))
        XCTAssertFalse(NavigationPolicy.shouldPresentAuthPopup(URL(string: "https://docs.x.ai/grok/faq")))
        XCTAssertFalse(NavigationPolicy.shouldPresentAuthPopup(URL(string: "https://grok.com")))
    }

}
