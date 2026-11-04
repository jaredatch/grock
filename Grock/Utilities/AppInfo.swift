import AppKit
import Foundation

/// Bundle metadata used by Settings, About, and tests. Keeps Info.plist reads in one place.
enum AppInfo {
    /// Marketing version. Keep in lockstep with
    /// `project.yml` `MARKETING_VERSION` (DEC-016).
    static let expectedMarketingVersion = "1.0.1"

    /// `NSHumanReadableCopyright`. About and Finder Get Info. The MIT
    /// copyright notice stays in LICENSE, not on this panel (DEC-016).
    static let aboutDisclaimer = "Unofficial. Not affiliated with xAI or SpaceX."

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.jaredatch.Grock"
    }

    /// Canonical product bundle ID (compile-time constant for tests / docs).
    static let expectedBundleIdentifier = "com.jaredatch.Grock"

    static let githubRepository = "https://github.com/jaredatch/grock"
    static let githubIssues = "https://github.com/jaredatch/grock/issues"

    static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
