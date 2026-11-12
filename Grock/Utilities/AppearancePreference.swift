import AppKit

/// User-facing appearance for shell + WebView color-scheme.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "app.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static var current: AppearancePreference {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let value = AppearancePreference(rawValue: raw) {
            return value
        }
        return .system
    }

    static func setCurrent(_ value: AppearancePreference) {
        UserDefaults.standard.set(value.rawValue, forKey: defaultsKey)
        apply(value)
    }

    /// Applies to NSApp and the shared WebView (prefers-color-scheme for grok.com).
    static func apply(_ value: AppearancePreference = .current) {
        let appearance: NSAppearance? = {
            switch value {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }()
        NSApp.appearance = appearance
        Task { @MainActor in
            WebViewStore.shared.applyAppearance(appearance)
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The page's own fill, so a 1px window sliver or a rubber-band edge
    /// cannot show as a different shade. grok.com's is `--grok-chrome`
    /// (#F9F8F7 light, #1E1D1D dark); the Mac style is plain white or
    /// #1E1E1E.
    static var pageBackdrop: NSColor {
        switch PageStyle.current {
        case .grok:
            return NSColor(name: "GrockPageBackdrop") { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 30 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1)
                    : NSColor(srgbRed: 249 / 255, green: 248 / 255, blue: 247 / 255, alpha: 1)
            }
        case .mac:
            return NSColor(name: "GrockPlainPageBackdrop") { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)
                    : .white
            }
        }
    }
}

/// How grok.com is dressed (Appearance → Style, DEC-073). The Mac
/// overrides live in `GrokThemeScript.swift`.
enum PageStyle: String, CaseIterable, Identifiable {
    /// grok.com as it ships.
    case grok
    /// Neutral colors, the system font and accent, a Finder-style sidebar
    /// on glass, and AppKit-style controls.
    case mac

    static let defaultsKey = "app.pageStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grok: return "Grok"
        case .mac: return "Mac"
        }
    }

    /// The Mac sidebar is see-through, with the window's glass behind it.
    var hasGlassSidebar: Bool { self == .mac }

    static var current: PageStyle {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let value = PageStyle(rawValue: raw) {
            return value
        }
        return .grok
    }

    static func setCurrent(_ value: PageStyle) {
        UserDefaults.standard.set(value.rawValue, forKey: defaultsKey)
        apply()
    }

    static func apply() {
        Task { @MainActor in
            WebViewStore.shared.pageStyleDidChange()
        }
    }

    /// What the theme script needs: the style, and the accent color from
    /// System Settings in both appearances.
    var scriptConfig: String {
        let config = [
            "style": self == .grok ? "" : rawValue,
            "accentLight": Self.accentHex(.aqua),
            "accentDark": Self.accentHex(.darkAqua)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    static func accentHex(_ name: NSAppearance.Name) -> String {
        var resolved: NSColor?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        guard let color = resolved else { return name == .darkAqua ? "#0a84ff" : "#007aff" }
        let parts = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { Int(($0 * 255).rounded()) }
        return String(format: "#%02x%02x%02x", parts[0], parts[1], parts[2])
    }
}

/// grok.com chrome we can hide or collapse. Labels, not routes (DEC-020).
enum ChromePreference {
    /// Appearance “Hide Sidebar on Launch”. Same store key as the old
    /// collapse-to-rail toggle (DEC-020 / DEC-028).
    static let hideSidebarOnLaunchKey = "chrome.collapseSidebar"
    static let collapseSidebarKey = hideSidebarOnLaunchKey
    static let sidebarHiddenKey = "chrome.sidebarHidden"
    static let hideImagineKey = "chrome.hideImagine"
    static let hideLibraryKey = "chrome.hideLibrary"
    static let hideAutomationsKey = "chrome.hideAutomations"
    static let hideProjectsKey = "chrome.hideProjects"
    static let hidePluginsKey = "chrome.hidePlugins"
    static let hideGrokBotKey = "chrome.hideGrokBot"
    static let hidePrivateKey = "chrome.hidePrivate"
    static let hideDictationKey = "chrome.hideDictation"
    static let hideVoiceKey = "chrome.hideVoice"

    static var allKeys: [String] {
        [
            collapseSidebarKey,
            sidebarHiddenKey,
            hideImagineKey,
            hideLibraryKey,
            hideAutomationsKey,
            hideProjectsKey,
            hidePluginsKey,
            hideGrokBotKey,
            hidePrivateKey,
            hideDictationKey,
            hideVoiceKey
        ]
    }

    /// Hide-on-launch and sidebar-hidden default on. Grok Bot / Private hide
    /// default on now that the titlebar owns those verbs (DEC-026).
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hideSidebarOnLaunchKey: true,
            sidebarHiddenKey: true,
            hideGrokBotKey: true,
            hidePrivateKey: true
        ])
    }

    struct Snapshot: Equatable, Encodable {
        var collapseSidebar: Bool
        var sidebarHidden: Bool
        var hideImagine: Bool
        var hideLibrary: Bool
        var hideAutomations: Bool
        var hideProjects: Bool
        var hidePlugins: Bool
        var hideGrokBot: Bool
        var hidePrivate: Bool
        var hideDictation: Bool
        var hideVoice: Bool

        var jsonString: String {
            guard let data = try? JSONEncoder().encode(self),
                  let text = String(data: data, encoding: .utf8)
            else { return "{}" }
            return text
        }
    }

    static var current: Snapshot {
        Snapshot(
            collapseSidebar: bool(hideSidebarOnLaunchKey, default: true),
            sidebarHidden: bool(sidebarHiddenKey, default: true),
            hideImagine: bool(hideImagineKey, default: false),
            hideLibrary: bool(hideLibraryKey, default: false),
            hideAutomations: bool(hideAutomationsKey, default: false),
            hideProjects: bool(hideProjectsKey, default: false),
            hidePlugins: bool(hidePluginsKey, default: false),
            hideGrokBot: bool(hideGrokBotKey, default: true),
            hidePrivate: bool(hidePrivateKey, default: true),
            hideDictation: bool(hideDictationKey, default: false),
            hideVoice: bool(hideVoiceKey, default: false)
        )
    }

    static func apply(
        _ value: Snapshot = current,
        collapse: Bool = false,
        forceCollapse: Bool = false,
        expand: Bool = false
    ) {
        Task { @MainActor in
            WebViewStore.shared.applyChrome(
                value,
                collapse: collapse,
                forceCollapse: forceCollapse,
                expand: expand
            )
            NotificationCenter.default.post(name: .grockChromeDidChange, object: nil)
        }
    }

    static func setSidebarHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: sidebarHiddenKey)
        apply(current, expand: !hidden)
    }

    /// Titlebar show/hide persists. If Hide Sidebar on Launch is on, that
    /// last-session value must not win the next process start (DEC-028).
    static func applyLaunchSidebarPolicy() {
        if bool(hideSidebarOnLaunchKey, default: true) {
            UserDefaults.standard.set(true, forKey: sidebarHiddenKey)
        }
    }

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
}
