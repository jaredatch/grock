import AppKit
import QuartzCore
import WebKit

/// Overlay default size, floor, restore clamp, and summon placement (DEC-023, DEC-024).
enum PanelGeometry {
    static let defaultContentSize = NSSize(width: 920, height: 680)
    static let minContentSize = NSSize(width: 720, height: 520)
    static let fallbackTitlebarInset: CGFloat = 52
    /// grok.com's sidebar at its default width (254pt, rounded). Used to park
    /// the native sidebar toggle on its trailing edge (Notes / Mail). The
    /// page's resize handle is muted so the two stay lined up.
    static let grokSidebarWidth: CGFloat = 256
    /// Gap between the open rail and the first content-column title. Matches
    /// the usual Tahoe spacing between two titlebar capsules.
    static let appSwitchRailGap: CGFloat = 8

    /// Unified titlebar height. `fullSizeContentView` can report a zero
    /// layout rect before the window is on screen; treat that as unknown.
    static func titlebarInset(in window: NSWindow) -> CGFloat {
        let fromLayout = window.frame.height - window.contentLayoutRect.maxY
        if fromLayout > 8, fromLayout < 120 { return fromLayout }
        if let bar = window.standardWindowButton(.closeButton)?.superview, bar.bounds.height > 8, bar.bounds.height < 120 {
            return bar.bounds.height
        }
        return fallbackTitlebarInset
    }

    struct Screen: Equatable {
        var frame: NSRect
        var visible: NSRect
    }

    /// Keep `frame` on a visible screen and at least `minSize`.
    /// Off-screen frames are centered on the nearest screen.
    static func constrainedFrame(
        _ frame: NSRect,
        visibleScreens: [NSRect],
        minSize: NSSize
    ) -> NSRect {
        var f = frame
        f.size.width = max(f.size.width, minSize.width)
        f.size.height = max(f.size.height, minSize.height)
        guard let screen = pickScreen(for: f, in: visibleScreens) else { return f }

        if f.width > screen.width { f.size.width = screen.width }
        if f.height > screen.height { f.size.height = screen.height }

        if !screen.intersects(f) {
            f.origin.x = screen.midX - f.width / 2
            f.origin.y = screen.midY - f.height / 2
        }
        if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width }
        if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height }
        if f.minX < screen.minX { f.origin.x = screen.minX }
        if f.minY < screen.minY { f.origin.y = screen.minY }
        return f
    }

    private static func pickScreen(for frame: NSRect, in screens: [NSRect]) -> NSRect? {
        guard !screens.isEmpty else { return nil }
        let overlapping = screens.filter { $0.intersects(frame) }
        if let best = overlapping.max(by: { $0.intersection(frame).area < $1.intersection(frame).area }) {
            return best
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { a, b in
            hypot(a.midX - center.x, a.midY - center.y) < hypot(b.midX - center.x, b.midY - center.y)
        }
    }

    /// Same screen: leave the parked frame. Other screen: keep size, same
    /// offset from that screen's visible origin, then clamp.
    static func summonFrame(
        current: NSRect,
        cursor: CGPoint,
        screens: [Screen],
        minSize: NSSize
    ) -> NSRect {
        guard let destination = screen(at: cursor, in: screens) else { return current }
        if let source = screen(containing: current, in: screens),
           source.visible == destination.visible {
            return current
        }
        var next = current
        if let source = screen(containing: current, in: screens) {
            next.origin.x = destination.visible.minX + (current.minX - source.visible.minX)
            next.origin.y = destination.visible.minY + (current.minY - source.visible.minY)
        }
        return constrainedFrame(next, visibleScreens: [destination.visible], minSize: minSize)
    }

    static func screen(at point: CGPoint, in screens: [Screen]) -> Screen? {
        screens.first { $0.frame.contains(point) }
            ?? screens.first { $0.visible.contains(point) }
    }

    static func screen(containing frame: NSRect, in screens: [Screen]) -> Screen? {
        screens
            .filter { $0.visible.intersects(frame) }
            .max { $0.visible.intersection(frame).area < $1.visible.intersection(frame).area }
    }
}

enum PageTitle {
    /// Home and untitled chat. grok.com's name, not the app's (DEC-040).
    static let fallback = "Grok"

    /// Place names win for grok.com destinations. Conversations use the
    /// sidebar thread name (or document.title), not reply headings.
    static func display(_ raw: String?, url: URL? = nil) -> String {
        if let place = placeName(for: url) { return place }
        return conversationTitle(raw)
    }

    static func placeName(for url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased(),
              host == "grok.com" || host.hasSuffix(".grok.com")
        else { return nil }
        let path = url.path.lowercased()
        if GrockWebApp.isImaginePath(path) { return "Imagine" }
        if path == "/library" || path.hasPrefix("/library/")
            || path == "/files" || path.hasPrefix("/files/") {
            return "Library"
        }
        if path.hasPrefix("/automation") { return "Automations" }
        if path.hasPrefix("/skill") { return "Plugins" }
        if path.hasPrefix("/project") { return "Projects" }
        if path.isEmpty || path == "/" { return fallback }
        return nil
    }

    static func conversationTitle(_ raw: String?) -> String {
        var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for suffix in [" | Grok", " - Grok", " • Grok"] {
            if let range = trimmed.range(
                of: suffix,
                options: [.caseInsensitive, .anchored, .backwards]
            ) {
                trimmed = String(trimmed[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if trimmed.isEmpty { return fallback }
        if trimmed.compare("Grok", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return fallback
        }
        if isJunk(trimmed) { return fallback }
        return trimmed
    }

    /// OneTrust / cookie chrome leaks into document.title and page headings.
    static func isJunk(_ raw: String) -> Bool {
        let low = raw.lowercased()
        if low.contains("privacy preference") { return true }
        if low.contains("cookie preference") { return true }
        if low.contains("onetrust") { return true }
        return false
    }
}

/// Overlay is one window and one WebView. grok.com's `/imagine` paths are
/// still a different page shell (DEC-035, DEC-048). Titlebar chrome is one
/// app; this type is the path check, not a toolbar switch.
enum GrockWebApp: Int {
    case chat = 0
    case imagine = 1

    static func isImaginePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower == "/imagine" || lower.hasPrefix("/imagine/") || lower.hasPrefix("/imagine-")
    }

    static func from(url: URL?) -> GrockWebApp {
        guard NavigationPolicy.isGrokHost(url?.host), let url else { return .chat }
        return isImaginePath(url.path) ? .imagine : .chat
    }
}

/// Titlebar place menu when the sidebar is hidden (DEC-031, DEC-048). CTAs,
/// not toggles. One menu everywhere: New Chat, then Imagine / Library /
/// Automations, then Projects, then History, then Plugins. Search stays out
/// (trailing titlebar). Plugins is grok.com's modal (DEC-038). Library is
/// `/library`. Projects clicks grok.com's All projects control. Add Project
/// is hover-only on their rail, so it is not in this menu.
enum TitleDestination: Int, CaseIterable {
    case newChat = 1
    case imagine
    case library
    case automations
    case projects
    case history
    case plugins

    var title: String {
        switch self {
        case .newChat: return "New Chat"
        case .imagine: return "Imagine"
        case .library: return "Library"
        case .automations: return "Automations"
        case .plugins: return "Plugins"
        case .projects: return "Projects"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .newChat: return "square.and.pencil"
        case .imagine: return "photo"
        case .library: return "tray"
        case .automations: return "bolt"
        case .plugins: return "square.grid.2x2"
        case .projects: return "folder"
        case .history: return "clock"
        }
    }

    /// Path to load, if this destination is a route. Plugins and Projects
    /// are clicks. New Chat is `startNewChat`.
    var href: String? {
        switch self {
        case .imagine: return "/imagine"
        case .library: return "/library"
        case .automations: return "/automations"
        case .history: return "/history"
        default: return nil
        }
    }

    func isAvailable(in pref: ChromePreference.Snapshot) -> Bool {
        switch self {
        case .newChat, .history: return true
        case .imagine: return !pref.hideImagine
        case .library: return !pref.hideLibrary
        case .automations: return !pref.hideAutomations
        case .plugins: return !pref.hidePlugins
        case .projects: return !pref.hideProjects
        }
    }

    static func available(in pref: ChromePreference.Snapshot) -> [TitleDestination] {
        allCases.filter { $0.isAvailable(in: pref) }
    }

    static func rebuildMenu(
        _ menu: NSMenu,
        pref: ChromePreference.Snapshot = ChromePreference.current,
        signedIn: Bool = true,
        target: AnyObject,
        action: Selector
    ) {
        menu.removeAllItems()
        // Signed out, every place but the start page is a sign-in wall.
        // New Chat stays: it is also the way back from a provider's page.
        menu.autoenablesItems = signedIn
        let available = available(in: pref)
        func add(_ destination: TitleDestination) {
            let item = NSMenuItem(
                title: destination.title,
                action: action,
                keyEquivalent: ""
            )
            item.target = target
            item.tag = destination.rawValue
            item.image = NSImage(
                systemSymbolName: destination.symbol,
                accessibilityDescription: destination.title
            )
            item.image?.isTemplate = true
            item.isEnabled = signedIn || destination == .newChat
            menu.addItem(item)
        }
        if available.contains(.newChat) {
            add(.newChat)
        }
        let places = available.filter {
            switch $0 {
            case .imagine, .library, .automations: return true
            default: return false
            }
        }
        if !places.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            places.forEach(add)
        }
        if available.contains(.projects) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            add(.projects)
        }
        if available.contains(.history) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            add(.history)
        }
        if available.contains(.plugins) {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            add(.plugins)
        }
    }
}

private extension NSRect {
    var area: CGFloat { width * height }
}

extension NSToolbarItem.Identifier {
    static let grockSidebar = NSToolbarItem.Identifier("grock.sidebar")
    static let grockRailIndent = NSToolbarItem.Identifier("grock.railIndent")
    static let grockSearch = NSToolbarItem.Identifier("grock.search")
    static let grockTitle = NSToolbarItem.Identifier("grock.title")
    static let grockNewChat = NSToolbarItem.Identifier("grock.newChat")
    static let grockPrivate = NSToolbarItem.Identifier("grock.private")
    static let grockSessionMore = NSToolbarItem.Identifier("grock.session.more")
    static let grockSessionShare = NSToolbarItem.Identifier("grock.session.share")
}

/// Overlay panel with a real system titlebar.
///
/// Titlebar sits on the WebView (`fullSizeContentView`). grok.com keeps a
/// 56px band of its own chrome at the top of every view and fades the thread
/// out under it, so the bar rests in that band and the page script only
/// hides the controls the bar replaces (DEC-071).
/// We still zero WebKit safe-area — that was the old corner-hairline path.
///
/// Not a permanently floating / nonactivating panel: summon brings it forward;
/// other apps can cover it; clicks activate Grock so Settings and focus work.
///
/// WKWebView fills a host content view (flush — a 1px mismatch makes grok.com
/// overflow and draw hairlines). A transparent strip in the titlebar band
/// claims empty-bar clicks so the window can drag; toolbar items stay above.
final class FloatingPanel: NSPanel, NSToolbarDelegate, NSMenuDelegate {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleRetry: DispatchWorkItem?
    private weak var titleItem: NSToolbarItem?
    private let titleMenu = NSMenu()
    let sessionMoreMenu = NSMenu()
    /// Last grok.com Pin/Unpin read. Cleared when leaving a chat.
    var sessionPinned: Bool?
    var sessionProjectAvailable = false
    private var copiedTitleRestore: DispatchWorkItem?
    private var titlebarDragHeight: NSLayoutConstraint?
    private var webViewTop: NSLayoutConstraint?
    private var showingAuthPage = false
    private weak var sidebarButton: SidebarRailButton?
    private var sidebarButtonTrailing: NSLayoutConstraint?
    private var sidebarButtonCenterY: NSLayoutConstraint?
    private weak var railIndentView: ToolbarRailIndentView?
    private var launchLoadingView: LaunchLoadingView?
    private var launchLoadingObserver: NSObjectProtocol?
    private var recoveryView: WebRecoveryView?
    private var downloadStatus: DownloadStatusView?
    private var downloadStatusHeight: NSLayoutConstraint?
    private var feedbackObservers: [NSObjectProtocol] = []

    deinit {
        if let launchLoadingObserver {
            NotificationCenter.default.removeObserver(launchLoadingObserver)
        }
        launchLoadingView?.stop()
        feedbackObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    convenience init() {
        self.init(
            contentRect: NSRect(origin: .zero, size: PanelGeometry.defaultContentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureChrome()
    }

    private func configureChrome() {
        // Overlay presentation is summon-to-front, not NSFloatingWindowLevel.
        isFloatingPanel = false
        level = .normal
        // Come to the Space you are on. Do not live on every Space (DEC-024).
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = true
        backgroundColor = AppearancePreference.pageBackdrop
        hasShadow = true
        title = PageTitle.fallback
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        contentMinSize = PanelGeometry.minContentSize
        installToolbar()
    }

    private func installToolbar() {
        let bar = NSToolbar(identifier: "GrockOverlayToolbar")
        bar.delegate = self
        bar.displayMode = .iconOnly
        bar.allowsUserCustomization = false
        bar.autosavesConfiguration = false
        bar.showsBaselineSeparator = false
        toolbar = bar
        toolbarStyle = .unified
        syncToolbar()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = []
        if ChromePreference.current.sidebarHidden {
            ids.append(.grockSidebar)
        } else {
            ids.append(.grockRailIndent)
        }
        ids += [.grockTitle, .flexibleSpace, .grockNewChat, .grockPrivate, .grockSearch]
        return ids
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .grockSidebar, .grockRailIndent, .grockTitle,
            .flexibleSpace, .grockSessionMore, .grockSessionShare, .space,
            .grockNewChat, .grockPrivate, .grockSearch
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .grockSidebar:
            let hidden = ChromePreference.current.sidebarHidden
            return makeIconItem(
                itemIdentifier,
                symbol: "sidebar.left",
                label: "Sidebar",
                action: #selector(toolbarToggleSidebar),
                navigational: true,
                toolTip: hidden ? "Show Sidebar" : "Hide Sidebar"
            )
        case .grockSearch:
            // 1-item group so Search stays its own glass and does not glue
            // to New Chat / Private (DEC-029, DEC-039).
            return makeActionGroup(
                itemIdentifier,
                innerIdentifier: NSToolbarItem.Identifier("grock.search.button"),
                symbol: "magnifyingglass",
                label: "Search",
                action: #selector(toolbarToggleSearch)
            )
        case .grockTitle:
            return makeTitleItem()
        case .grockRailIndent:
            return makeRailIndentItem()
        case .grockSessionMore:
            sessionMoreMenu.delegate = self
            return makeIconItem(
                itemIdentifier,
                symbol: "ellipsis",
                label: "More",
                action: #selector(toolbarSessionMore)
            )
        case .grockSessionShare:
            return makeIconItem(
                itemIdentifier,
                symbol: "link",
                label: "Share",
                action: #selector(toolbarSessionShare)
            )
        case .grockNewChat:
            return makeIconItem(
                itemIdentifier,
                symbol: "square.and.pencil",
                label: "New Chat",
                action: #selector(toolbarNewChat),
                toolTip: "New Chat"
            )
        case .grockPrivate:
            return makeIconItem(
                itemIdentifier,
                symbol: "eye.slash",
                label: "New Private Chat",
                action: #selector(toolbarPrivate),
                toolTip: "New Private Chat"
            )
        default:
            return nil
        }
    }

    private func makeIconItem(
        _ identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector,
        navigational: Bool = false,
        toolTip: String? = nil
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = toolTip ?? label
        item.image = Self.toolbarSymbol(symbol, description: label)
        item.target = self
        item.action = action
        item.autovalidates = false
        item.isBordered = true
        item.isNavigational = navigational
        Self.applyToolbarItemChrome(item)
        return item
    }

    /// Same glyph treatment for standalone items and groups so hover fill
    /// matches in light and dark (Search was the odd one out).
    private static func toolbarSymbol(_ name: String, description: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        let configured = image.withSymbolConfiguration(.preferringMonochrome())
        configured?.isTemplate = true
        return configured ?? image
    }

    private static func applyToolbarItemChrome(_ item: NSToolbarItem) {
        item.style = .plain
    }

    /// Blank leading indent so the title sits after the open rail. Not
    /// bordered and not `NSToolbarItem.Identifier.space`, which Tahoe glues
    /// to the next item (DEC-029, DEC-037).
    private func makeRailIndentItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .grockRailIndent)
        let view = ToolbarRailIndentView()
        view.width = appSwitchRailIndentWidth()
        item.view = view
        item.isBordered = false
        item.isNavigational = false
        item.label = ""
        item.paletteLabel = "Sidebar Gap"
        railIndentView = view
        return item
    }

    /// Indent so the first content-column item's leading edge sits just
    /// after the open rail. Toolbar items already start after the traffic
    /// lights; subtract that real origin or the item sits a capsule-width
    /// too far right.
    private func appSwitchRailIndentWidth() -> CGFloat {
        let target = PanelGeometry.grokSidebarWidth + PanelGeometry.appSwitchRailGap
        return max(1, target - toolbarItemsLeadingX())
    }

    /// Window-x where the first leading toolbar item is drawn.
    private func toolbarItemsLeadingX() -> CGFloat {
        if let view = railIndentView, view.superview != nil, let host = contentView {
            let x = view.convert(.zero, to: host).x
            if x > 1 { return x }
        }
        let lightsMax = standardWindowButton(.zoomButton)?.frame.maxX ?? 78
        return lightsMax + 10
    }

    /// One glass capsule. A lone bordered item glues to its neighbors on
    /// Tahoe; a 1-item group does not (DEC-029, DEC-035).
    private func makeActionGroup(
        _ identifier: NSToolbarItem.Identifier,
        innerIdentifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> NSToolbarItem {
        let inner = makeIconItem(
            innerIdentifier,
            symbol: symbol,
            label: label,
            action: action,
            toolTip: label
        )
        let group = NSToolbarItemGroup(itemIdentifier: identifier)
        group.subitems = [inner]
        group.controlRepresentation = .expanded
        group.label = label
        group.paletteLabel = label
        group.toolTip = label
        group.autovalidates = false
        Self.applyToolbarItemChrome(group)
        return group
    }

    /// Sidebar hidden: Mail Flag split (`NSMenuToolbarItem` + dummy action so
    /// Tahoe draws title | chevron as two segments). The title segment is a
    /// real button and will hover; that is AppKit, not something we can strip
    /// without looking custom. Sidebar open: semibold label, no glass.
    /// Recreate the item on toggle.
    private func makeTitleItem() -> NSToolbarItem {
        if ChromePreference.current.sidebarHidden {
            return makeTitleMenuItem()
        }
        return makeTitleLabelItem()
    }

    private func makeTitleMenuItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: .grockTitle)
        let text = Self.truncatedToolbarTitle(title)
        item.label = text
        item.paletteLabel = "Title"
        item.title = text
        item.toolTip = Self.copyLinkToolTip(for: title)
        item.menu = titleMenu
        item.showsIndicator = true
        item.isBordered = true
        Self.applyToolbarItemChrome(item)
        item.autovalidates = false
        item.target = self
        item.action = #selector(toolbarTitlePrimary(_:))
        titleMenu.delegate = self
        titleItem = item
        queueToolbarTooltips()
        return item
    }

    private func makeTitleLabelItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .grockTitle)
        let text = Self.truncatedToolbarTitle(title, font: TitleLabelField.titleFont)
        item.label = text
        item.paletteLabel = "Title"
        item.toolTip = title
        item.isBordered = false
        let field = TitleLabelField()
        field.stringValue = text
        field.toolTip = title
        item.view = field
        titleItem = item
        return item
    }

    /// Truncate conversation names so a long title cannot shove Search off.
    private static let toolbarTitleMaxWidth: CGFloat = 280
    private static let copiedConfirmation = "URL Copied"

    private static func truncatedToolbarTitle(
        _ text: String,
        font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    ) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attrs).width <= toolbarTitleMaxWidth {
            return text
        }
        var low = 0
        var high = text.count
        var fit = PageTitle.fallback
        while low <= high {
            let mid = (low + high) / 2
            let index = text.index(text.startIndex, offsetBy: mid)
            let candidate = String(text[..<index]) + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= toolbarTitleMaxWidth {
                fit = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return fit
    }

    private func applyTitleChrome() {
        let wantSplit = ChromePreference.current.sidebarHidden
        let isSplit = titleItem is NSMenuToolbarItem
        if wantSplit != isSplit {
            replaceTitleItem()
        }
    }

    private func replaceTitleItem() {
        guard let bar = toolbar,
              let index = bar.items.firstIndex(where: { $0.itemIdentifier == .grockTitle })
        else { return }
        bar.removeItem(at: index)
        bar.insertItem(withItemIdentifier: .grockTitle, at: index)
    }

    private func queueToolbarTooltips() {
        DispatchQueue.main.async { [weak self] in
            self?.applyToolbarTooltips()
        }
    }

    /// Grouped titlebar items are segmented controls. Segment tooltips are
    /// the hover that actually shows.
    private func applyToolbarTooltips() {
        applyTitleSplitTooltips()
    }

    /// Flag split is one item; segment tooltips are the only way the chevron
    /// can say something different from Copy Link.
    private func applyTitleSplitTooltips() {
        guard let item = titleItem as? NSMenuToolbarItem else { return }
        guard let split = segmentedControl(for: item) ?? titleSplitControl(),
              split.segmentCount >= 2
        else { return }
        split.setToolTip(Self.copyLinkToolTip(for: title), forSegment: 0)
        split.setToolTip("Go to", forSegment: 1)
    }

    private func segmentedControl(for item: NSToolbarItem) -> NSSegmentedControl? {
        if let split = item.view as? NSSegmentedControl { return split }
        if let view = item.view {
            return firstSegmentedControl(in: view)
        }
        return nil
    }

    private func titleSplitControl() -> NSSegmentedControl? {
        guard let item = titleItem as? NSMenuToolbarItem,
              let chrome = standardWindowButton(.closeButton)?.superview
        else { return nil }
        let titleText = item.title
        return firstSegmentedControl(in: chrome) { split in
            split.segmentCount >= 2 && split.label(forSegment: 0) == titleText
        }
    }

    private func firstSegmentedControl(
        in view: NSView,
        matching: ((NSSegmentedControl) -> Bool)? = nil
    ) -> NSSegmentedControl? {
        if let split = view as? NSSegmentedControl {
            if matching?(split) ?? true { return split }
        }
        for sub in view.subviews {
            if let found = firstSegmentedControl(in: sub, matching: matching) {
                return found
            }
        }
        return nil
    }

    /// Title segment: copy the current grok.com URL. Option-click opens it
    /// in the default browser (Mac alternate-action).
    @objc private func toolbarTitlePrimary(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.option) {
            WebViewStore.shared.openCurrentPageInBrowser()
            return
        }
        WebViewStore.shared.copyCurrentPageURL()
        flashCopiedTitle()
    }

    func confirmCopiedLink() {
        WebViewStore.shared.copyCurrentPageURL()
        flashCopiedTitle()
    }

    private func flashCopiedTitle() {
        guard let item = titleItem as? NSMenuToolbarItem else {
            announceCopiedLink()
            return
        }
        copiedTitleRestore?.cancel()
        item.title = Self.copiedConfirmation
        announceCopiedLink()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let item = self.titleItem as? NSMenuToolbarItem else { return }
            if item.title == Self.copiedConfirmation {
                item.title = Self.truncatedToolbarTitle(self.title)
            }
        }
        copiedTitleRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func announceCopiedLink() {
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "URL copied" as Any,
                .priority: NSAccessibilityPriorityLevel.medium
            ]
        )
    }

    private static func copyLinkToolTip(for title: String) -> String {
        "\(title)\nCopy Link. Option-click opens in your browser."
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === sessionMoreMenu {
            rebuildSessionMoreMenu()
            return
        }
        guard menu === titleMenu else { return }
        TitleDestination.rebuildMenu(
            menu,
            signedIn: WebViewStore.shared.isSignedIn,
            target: self,
            action: #selector(titleMenuChosen(_:))
        )
    }

    func syncToolbar() {
        syncSidebarToolbarItem()
        syncRailIndentToolbarItem()
        syncSessionToolbarItem()
        applyAuthenticationItemState()
        let hidden = ChromePreference.current.sidebarHidden
        applyTitleChrome()
        sidebarButton?.isHidden = hidden
        sidebarButton?.toolTip = hidden ? "Show Sidebar" : "Hide Sidebar"
        if let item = toolbar?.items.first(where: { $0.itemIdentifier == .grockSidebar }) {
            item.toolTip = hidden ? "Show Sidebar" : "Hide Sidebar"
        }
        sidebarButtonCenterY?.constant = PanelGeometry.titlebarInset(in: self) / 2
        sidebarButtonTrailing?.constant = PanelGeometry.grokSidebarWidth - 16
        queueToolbarTooltips()
    }

    /// grok.com exposes these actions only after login. Use AppKit's disabled
    /// state so the toolbar is honest while the page shows Sign in.
    private func applyAuthenticationItemState() {
        let enabled = WebViewStore.shared.isSignedIn
        let identifiers: Set<NSToolbarItem.Identifier> = [
            .grockSidebar, .grockNewChat, .grockPrivate, .grockSearch
        ]
        for item in toolbar?.items ?? [] where identifiers.contains(item.itemIdentifier) {
            item.autovalidates = false
            item.isEnabled = enabled
            if let group = item as? NSToolbarItemGroup {
                for subitem in group.subitems {
                    subitem.autovalidates = false
                    subitem.isEnabled = enabled
                }
            }
        }
        sidebarButton?.isEnabled = enabled
    }

    /// Open sidebar: a blank indent pushes the title past the rail (DEC-037).
    private func syncRailIndentToolbarItem() {
        guard let bar = toolbar else { return }
        let wantIndent = !ChromePreference.current.sidebarHidden

        let indentIndex = bar.items.firstIndex { $0.itemIdentifier == .grockRailIndent }
        if wantIndent, indentIndex == nil {
            bar.insertItem(withItemIdentifier: .grockRailIndent, at: 0)
        } else if !wantIndent, let indentIndex {
            bar.removeItem(at: indentIndex)
            railIndentView = nil
        }
        applyRailIndentWidth()
        if wantIndent {
            DispatchQueue.main.async { [weak self] in
                self?.applyRailIndentWidth()
            }
        }
    }

    /// Mail: closed = native glass toolbar item by the lights. Open = flat
    /// icon on the rail. A spacer+item pair becomes one Tahoe capsule.
    private func syncSidebarToolbarItem() {
        guard let bar = toolbar else { return }
        let wantItem = ChromePreference.current.sidebarHidden
        let index = bar.items.firstIndex { $0.itemIdentifier == .grockSidebar }
        if wantItem, index == nil {
            bar.insertItem(withItemIdentifier: .grockSidebar, at: 0)
        } else if !wantItem, let index {
            bar.removeItem(at: index)
        }
    }

    /// Same sidebar.left glyph as the toolbar item, no glass. Hover only.
    private func installSidebarButton(on host: NSView) {
        sidebarButton?.removeFromSuperview()
        let button = SidebarRailButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(toolbarToggleSidebar)
        host.addSubview(button)
        sidebarButton = button
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: SidebarRailButton.extent),
            button.heightAnchor.constraint(equalToConstant: SidebarRailButton.extent)
        ])

        let trailing = button.trailingAnchor.constraint(
            equalTo: host.leadingAnchor,
            constant: PanelGeometry.grokSidebarWidth - 16
        )
        let centerY = button.centerYAnchor.constraint(
            equalTo: host.topAnchor,
            constant: PanelGeometry.fallbackTitlebarInset / 2
        )
        NSLayoutConstraint.activate([trailing, centerY])
        sidebarButtonTrailing = trailing
        sidebarButtonCenterY = centerY
        button.isHidden = ChromePreference.current.sidebarHidden
    }

    @objc private func titleMenuChosen(_ sender: NSMenuItem) {
        guard let destination = TitleDestination(rawValue: sender.tag) else { return }
        guard destination == .newChat || WebViewStore.shared.isSignedIn else { return }
        Task { @MainActor in
            switch destination {
            case .newChat:
                WebViewStore.shared.startNewChat()
            case .imagine:
                WebViewStore.shared.openApp(.imagine)
            case .plugins:
                WebViewStore.shared.openPlugins()
            case .projects:
                WebViewStore.shared.openAllProjects()
            case .library, .automations, .history:
                if let href = destination.href {
                    WebViewStore.shared.openGrokPath(href)
                }
            }
        }
    }

    @objc private func toolbarToggleSidebar() {
        guard WebViewStore.shared.isSignedIn else { return }
        ChromePreference.setSidebarHidden(!ChromePreference.current.sidebarHidden)
        syncToolbar()
    }

    @objc private func toolbarNewChat() {
        guard WebViewStore.shared.isSignedIn else { return }
        Task { @MainActor in
            WebViewStore.shared.startNewChat()
        }
    }

    @objc private func toolbarToggleSearch() {
        guard WebViewStore.shared.isSignedIn else { return }
        Task { @MainActor in
            WebViewStore.shared.toggleSearch()
        }
    }

    @objc private func toolbarPrivate() {
        guard WebViewStore.shared.isSignedIn else { return }
        Task { @MainActor in
            WebViewStore.shared.startPrivateChat()
        }
    }

    /// Session-only More + Share group, left of New Chat (DEC-055).
    private func syncSessionToolbarItem() {
        guard let bar = toolbar else { return }
        let want = WebViewStore.shared.sessionActions.showsToolbar
        let hasActions = bar.items.contains { $0.itemIdentifier == .grockSessionMore }
        if want {
            if !hasActions {
                let at = bar.items.firstIndex { $0.itemIdentifier == .grockNewChat } ?? bar.items.count
                bar.insertItem(withItemIdentifier: .grockSessionMore, at: at)
                bar.insertItem(withItemIdentifier: .grockSessionShare, at: at + 1)
                bar.insertItem(withItemIdentifier: .space, at: at + 2)
            }
            applySessionItemState()
        } else if hasActions {
            // Remove only the spacer belonging to this pair.
            if let share = bar.items.firstIndex(where: { $0.itemIdentifier == .grockSessionShare }),
               share + 1 < bar.items.count, bar.items[share + 1].itemIdentifier == .space {
                bar.removeItem(at: share + 1)
            }
            for id in [NSToolbarItem.Identifier.grockSessionShare, .grockSessionMore] {
                if let index = bar.items.firstIndex(where: { $0.itemIdentifier == id }) {
                    bar.removeItem(at: index)
                }
            }
            sessionPinned = nil
            sessionProjectAvailable = false
        }
    }

    private func applySessionItemState() {
        let actions = WebViewStore.shared.sessionActions
        for item in toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case .grockSessionMore: item.isEnabled = actions.showsMore
            case .grockSessionShare: item.isEnabled = actions.share
            default: break
            }
        }
    }

    func rebuildSessionMoreMenu() {
        sessionMoreMenu.removeAllItems()
        let actions = WebViewStore.shared.sessionActions
        if actions.more {
            let title = sessionPinned == true ? "Unpin" : "Pin"
            let pin = NSMenuItem(title: title, action: #selector(toolbarSessionPin), keyEquivalent: "")
            pin.target = self
            sessionMoreMenu.addItem(pin)
        }
        if actions.more && sessionProjectAvailable {
            let project = NSMenuItem(title: "Add to Project…", action: #selector(toolbarSessionProject), keyEquivalent: "")
            project.target = self
            sessionMoreMenu.addItem(project)
        }
        if actions.panel {
            let panel = NSMenuItem(
                title: "Toggle Right Pane",
                action: #selector(toolbarSessionPanel),
                keyEquivalent: ""
            )
            panel.target = self
            sessionMoreMenu.addItem(panel)
        }
        if actions.more {
            if !sessionMoreMenu.items.isEmpty {
                sessionMoreMenu.addItem(.separator())
            }
            // grok.com's menu ends in Archive, in red. It used to be Delete.
            let archive = NSMenuItem(title: "Archive", action: #selector(toolbarSessionArchive), keyEquivalent: "")
            archive.target = self
            archive.attributedTitle = NSAttributedString(
                string: "Archive",
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.menuFont(ofSize: NSFont.systemFontSize)
                ]
            )
            sessionMoreMenu.addItem(archive)
        }
    }

    @objc private func toolbarSessionShare() {
        WebViewStore.shared.clickSessionAction("share")
    }

    @objc private func toolbarSessionMore() {
        let location = NSApp.currentEvent?.locationInWindow
        var shown = false
        let show = { [weak self] in
            guard let self, !shown else { return }
            shown = true
            self.rebuildSessionMoreMenu()
            self.popSessionMoreMenu(at: location)
        }
        WebViewStore.shared.inspectSessionMenu { [weak self] pinned, panel, project in
            guard let self else { return }
            self.sessionProjectAvailable = project
            self.sessionPinned = pinned ?? self.sessionPinned
            var actions = WebViewStore.shared.sessionActions
            if actions.panel != panel {
                actions.panel = panel
                WebViewStore.shared.applySessionActions(actions)
            }
            show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: show)
    }

    private func popSessionMoreMenu(at locationInWindow: NSPoint?) {
        if let chrome = standardWindowButton(.closeButton)?.superview,
           let button = sessionMoreButton(in: chrome) {
            sessionMoreMenu.popUp(
                positioning: nil,
                at: Self.sessionMenuOrigin(bounds: button.bounds, flipped: button.isFlipped),
                in: button
            )
            return
        }
        guard let content = contentView, let locationInWindow else { return }
        var point = content.convert(locationInWindow, from: nil)
        let inset = PanelGeometry.titlebarInset(in: self)
        point.y = content.isFlipped ? content.bounds.minY + inset : content.bounds.maxY - inset
        sessionMoreMenu.popUp(positioning: nil, at: point, in: content)
    }

    static func sessionMenuOrigin(bounds: NSRect, flipped: Bool) -> NSPoint {
        NSPoint(x: bounds.minX, y: flipped ? bounds.maxY + 5 : bounds.minY - 5)
    }

    private func sessionMoreButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.action == #selector(toolbarSessionMore) || button.toolTip == "More" {
            return button
        }
        for child in view.subviews {
            if let button = sessionMoreButton(in: child) { return button }
        }
        return nil
    }

    @objc private func toolbarSessionPin() {
        WebViewStore.shared.clickSessionAction("pin")
        if let pinned = sessionPinned {
            sessionPinned = !pinned
        }
    }

    @objc private func toolbarSessionProject() {
        WebViewStore.shared.clickSessionAction("project")
    }

    @objc private func toolbarSessionPanel() {
        WebViewStore.shared.clickSessionAction("panel")
    }

    @objc private func toolbarSessionArchive() {
        WebViewStore.shared.clickSessionAction("archive")
    }

    /// Hosts the shared WKWebView flush in the window, plus a drag strip
    /// under the native titlebar so empty bar space moves the window.
    func installWebView(_ webView: WKWebView) {
        if webView.window === self { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.focusRingType = .none

        let host = NSView(frame: contentRect(forFrameRect: frame))
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = AppearancePreference.pageBackdrop.cgColor

        host.addSubview(webView)
        let status = DownloadStatusView()
        status.translatesAutoresizingMaskIntoConstraints = false
        status.isHidden = true
        host.addSubview(status)
        let statusHeight = status.heightAnchor.constraint(equalToConstant: 0)
        downloadStatus = status
        downloadStatusHeight = statusHeight
        status.onDismiss = { [weak self] in
            self?.downloadStatusHeight?.constant = 0
            self?.downloadStatus?.isHidden = true
        }
        let webTop = webView.topAnchor.constraint(equalTo: host.topAnchor)
        webViewTop = webTop
        showingAuthPage = NavigationPolicy.isSignInHost(webView.url?.host)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webTop,
            webView.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            statusHeight
        ])

        let recovery = WebRecoveryView()
        recovery.translatesAutoresizingMaskIntoConstraints = false
        recovery.onRetry = { WebViewStore.shared.reload() }
        recovery.onOpenBrowser = { WebViewStore.shared.openCurrentPageInBrowser() }
        host.addSubview(recovery)
        NSLayoutConstraint.activate([
            recovery.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            recovery.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            recovery.topAnchor.constraint(equalTo: host.topAnchor, constant: PanelGeometry.fallbackTitlebarInset),
            recovery.bottomAnchor.constraint(equalTo: status.topAnchor)
        ])
        recoveryView = recovery
        recovery.show(WebViewStore.shared.recoveryState)
        feedbackObservers.forEach { NotificationCenter.default.removeObserver($0) }
        feedbackObservers = [
            NotificationCenter.default.addObserver(forName: .grockRecoveryDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoveryView?.show(WebViewStore.shared.recoveryState) }
            },
            NotificationCenter.default.addObserver(forName: DownloadFeedback.didChangeNotification, object: nil, queue: .main) { [weak self] note in
                guard let message = note.userInfo?["message"] as? String else { return }
                let fileURL = note.userInfo?["fileURL"] as? URL
                Task { @MainActor in
                    self?.downloadStatus?.show(message: message, fileURL: fileURL)
                    self?.downloadStatus?.isHidden = false
                    self?.downloadStatusHeight?.constant = 44
                }
            }
        ]

        installLaunchLoading(on: host)

        let drag = TitlebarDragRegion()
        drag.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(drag)
        let height = drag.heightAnchor.constraint(equalToConstant: PanelGeometry.fallbackTitlebarInset)
        titlebarDragHeight = height
        NSLayoutConstraint.activate([
            drag.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            drag.topAnchor.constraint(equalTo: host.topAnchor),
            height
        ])

        installSidebarButton(on: host)
        contentView = host
        syncTitlebarDragHeight()
        syncToolbar()
        observePageTitle(webView)
        observeLaunchLoading()
        setLaunchLoadingVisible(WebViewStore.shared.showsLaunchLoading)
    }

    var isLaunchLoadingVisible: Bool {
        guard let launchLoadingView else { return false }
        return !launchLoadingView.isHidden
    }

    func setLaunchLoadingVisible(_ visible: Bool, animated: Bool = true) {
        guard let launchLoadingView else { return }
        launchLoadingView.layer?.removeAllAnimations()
        if visible {
            launchLoadingView.alphaValue = 1
            launchLoadingView.isHidden = false
            launchLoadingView.start()
            return
        }
        if !animated || launchLoadingView.isHidden {
            launchLoadingView.stop()
            launchLoadingView.alphaValue = 1
            launchLoadingView.isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = LaunchLoadingLayout.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            launchLoadingView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, let view = self.launchLoadingView else { return }
            if WebViewStore.shared.showsLaunchLoading { return }
            view.stop()
            view.isHidden = true
            view.alphaValue = 1
        })
    }

    private func installLaunchLoading(on host: NSView) {
        let loading = LaunchLoadingView()
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.isHidden = true
        host.addSubview(loading)
        let size = LaunchLoadingLayout.canvas
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            loading.centerYAnchor.constraint(
                equalTo: host.centerYAnchor,
                constant: LaunchLoadingLayout.centerYOffset
            ),
            loading.widthAnchor.constraint(equalToConstant: size),
            loading.heightAnchor.constraint(equalToConstant: size)
        ])
        launchLoadingView = loading
    }

    private func observeLaunchLoading() {
        if launchLoadingObserver != nil { return }
        launchLoadingObserver = NotificationCenter.default.addObserver(
            forName: .grockLaunchLoadingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setLaunchLoadingVisible(WebViewStore.shared.showsLaunchLoading)
            }
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        syncTitlebarDragHeight()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        syncTitlebarDragHeight()
        DispatchQueue.main.async { [weak self] in
            self?.syncToolbar()
        }
    }

    private func syncTitlebarDragHeight() {
        let inset = PanelGeometry.titlebarInset(in: self)
        if titlebarDragHeight?.constant != inset {
            titlebarDragHeight?.constant = inset
        }
        // Account / OAuth pages do not run our grok.com inset script. Give
        // their entire viewport the space below the bar, including fixed headers.
        let webInset = showingAuthPage ? inset : 0
        if webViewTop?.constant != webInset {
            webViewTop?.constant = webInset
            WebViewStore.shared.markViewportUnitsStale()
        }
        sidebarButtonCenterY?.constant = inset / 2
        applyRailIndentWidth()
    }

    private func applyRailIndentWidth() {
        railIndentView?.width = appSwitchRailIndentWidth()
    }

    /// Keep size. If the cursor is on another display, park the same rectangle there.
    func applySummonPlacement() {
        let screens = NSScreen.screens.map {
            PanelGeometry.Screen(frame: $0.frame, visible: $0.visibleFrame)
        }
        let next = PanelGeometry.summonFrame(
            current: frame,
            cursor: NSEvent.mouseLocation,
            screens: screens,
            minSize: minSize
        )
        if next != frame {
            setFrame(next, display: false)
        }
    }

    private func observePageTitle(_ webView: WKWebView) {
        titleObservation = webView.observe(\.title, options: [.new, .initial]) { [weak self] view, _ in
            self?.refreshTitle(from: view)
        }
        urlObservation = webView.observe(\.url, options: [.new, .initial]) { [weak self] view, _ in
            self?.handleURLChange(view)
        }
    }

    private func handleURLChange(_ webView: WKWebView) {
        WebViewStore.shared.handlePageURLChanged(webView.url)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showingAuthPage = NavigationPolicy.isSignInHost(webView.url?.host)
            self.syncTitlebarDragHeight()
            WebViewStore.shared.applyChrome()
            self.sessionPinned = nil
            self.syncToolbar()
            self.refreshTitle(from: webView, attemptsLeft: 6)
        }
    }

    private func refreshTitle(from webView: WKWebView, attemptsLeft: Int = 0) {
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            let next = PageTitle.display(webView.title, url: webView.url)
            self.applyDisplayedTitle(next)
            self.pullConversationTitle(webView, current: next, attemptsLeft: attemptsLeft)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// grok.com is late to name a thread. Ask the page, then retry a few times.
    private func pullConversationTitle(_ webView: WKWebView, current: String, attemptsLeft: Int) {
        titleRetry?.cancel()
        guard PageTitle.placeName(for: webView.url) == nil else { return }
        Task { @MainActor [weak self] in
            webView.evaluateJavaScript(WebViewStore.placeTitleScript) { result, _ in
                let pulled = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolved = pulled.isEmpty ? current : PageTitle.display(pulled, url: webView.url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.applyDisplayedTitle(resolved)
                    guard attemptsLeft > 0, resolved == PageTitle.fallback else { return }
                    let work = DispatchWorkItem { [weak self] in
                        self?.refreshTitle(from: webView, attemptsLeft: attemptsLeft - 1)
                    }
                    self.titleRetry = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
                }
            }
        }
    }

    private func applyDisplayedTitle(_ text: String) {
        title = text
        if let menuItem = titleItem as? NSMenuToolbarItem {
            let shown = Self.truncatedToolbarTitle(text)
            if menuItem.title != Self.copiedConfirmation {
                menuItem.title = shown
            }
            menuItem.label = shown
            menuItem.toolTip = Self.copyLinkToolTip(for: text)
            queueToolbarTooltips()
        } else if let field = titleItem?.view as? TitleLabelField {
            let shown = Self.truncatedToolbarTitle(text, font: TitleLabelField.titleFont)
            field.stringValue = shown
            field.toolTip = text
            field.invalidateIntrinsicContentSize()
            titleItem?.label = shown
            titleItem?.toolTip = text
        }
    }

    func applyPageBackdrop() {
        backgroundColor = AppearancePreference.pageBackdrop
        contentView?.layer?.backgroundColor = AppearancePreference.pageBackdrop.cgColor
    }
}

/// Invisible toolbar leading indent. Empty space still drags the window.
final class ToolbarRailIndentView: NSView {
    private var widthConstraint: NSLayoutConstraint?

    var width: CGFloat = 1 {
        didSet {
            guard abs(width - oldValue) > 0.5 else { return }
            widthConstraint?.constant = width
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = widthAnchor.constraint(equalToConstant: width)
        widthConstraint.priority = .required
        widthConstraint.isActive = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        self.widthConstraint = widthConstraint
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

/// Open-rail sidebar toggle. NSButton cells are not square, so a layer
/// corner-radius hover became an oval. Draw our own circle instead.
final class SidebarRailButton: NSControl {
    static let extent: CGFloat = 32

    private let glyph = NSImageView()
    private var hovered = false

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false }
            glyph.contentTintColor = isEnabled ? .labelColor : .disabledControlTextColor
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.extent, height: Self.extent)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        let image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")
        image?.isTemplate = true
        glyph.image = image
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleNone
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered && isEnabled {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSColor.labelColor.withAlphaComponent(dark ? 0.18 : 0.08).setFill()
            NSBezierPath(ovalIn: bounds).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        hovered = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        hovered = inside
        needsDisplay = true
        if inside { sendAction(action, to: target) }
    }
}

/// Semibold place / conversation name when the sidebar is open. No glass,
/// no hover, window still drags from the text. Leading pad matches the
/// rail-to-pill gap; a capsule has internal icon inset, this label does not.
final class TitleLabelField: NSTextField {
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let leadingPadding = PanelGeometry.appSwitchRailGap

    override var mouseDownCanMoveWindow: Bool { true }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += Self.leadingPadding
        return size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        let cell = TitleLabelCell(textCell: "")
        cell.font = Self.titleFont
        cell.textColor = .labelColor
        cell.isBezeled = false
        cell.isBordered = false
        cell.drawsBackground = false
        cell.isEditable = false
        cell.isSelectable = false
        cell.lineBreakMode = .byTruncatingTail
        cell.usesSingleLineMode = true
        cell.truncatesLastVisibleLine = true
        self.cell = cell
        isBezeled = false
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        refusesFirstResponder = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}

private final class TitleLabelCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var r = super.titleRect(forBounds: rect)
        let pad = TitleLabelField.leadingPadding
        r.origin.x += pad
        r.size.width = max(0, r.size.width - pad)
        return r
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
}

/// Transparent titlebar band. Toolbar items sit above this in the theme
/// frame; the WebView sits below. Without it, empty bar clicks fall through
/// to grok.com (I-beam, text selection, no window drag).
final class TitlebarDragRegion: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2, let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        default:
            window.performZoom(nil)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
    }
}
