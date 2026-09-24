import AppKit
import Carbon
import SwiftUI

/// Owns the launcher surface: floating panel, status item, hotkey, lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let hideFromDockKey = "app.hideFromDock"
    static let windowFrameKey = "app.panelFrame"
    /// SwiftUI's adaptor can wrap `NSApp.delegate`, so Quick Chat cannot cast it.
    static private(set) weak var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var reply = ReplyMonitor()
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?
    private var hotkey: HotkeyManager { .shared }
    private var escMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// Captured in `applicationWillFinishLaunching` — the login-item Apple Event
    /// is often gone by `applicationDidFinishLaunching`.
    private var launchAppleEvent: NSAppleEventDescriptor?
    /// `application(_:open:)` or GetURL ran this launch, so skip the default overlay.
    private var didOpenURLDuringLaunch = false
    /// Same URL can arrive as both GetURL and `application(_:open:)`.
    private var recentOpenURLKeys: Set<String> = []
    private var serviceIntakeTask: Task<Void, Never>?

    private var hideFromDock: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hideFromDockKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hideFromDockKey) }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        launchAppleEvent = NSAppleEventManager.shared().currentAppleEvent
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        // View > Show Tab Bar is browser chrome. One window, no tabs (DEC-033).
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.servicesProvider = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ChromePreference.registerDefaults()
        ChromePreference.applyLaunchSidebarPolicy()
        AppearancePreference.apply()
        ChromePreference.apply()
        setupStatusItem()
        setupMenu()
        setupNotifications()
        polishMainMenu()
        QuickChatController.shared.startMonitoring()
        installEscMonitor()
        NSUpdateDynamicServices()
        UpdaterController.shared.start()
        // Summon never hides (DEC-013). New chat is a separate combo (DEC-019).
        hotkey.start(
            onSummon: { [weak self] in self?.showPanel(focusInput: true) },
            onNewChat: { [weak self] in self?.startNewChat() },
            onVoiceChat: { [weak self] in self?.startNewVoiceChat() },
            onQuickChat: { [weak self] in self?.showQuickChat() }
        )

        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }

        // `application(_:open:)` often arrives after this method. One turn later
        // we still know whether a grock:// URL already presented a surface (DEC-049).
        let launchEvent = launchAppleEvent ?? NSAppleEventManager.shared().currentAppleEvent
        if let url = LaunchReason.url(from: launchEvent), handleOpenURLs([url]) {
            didOpenURLDuringLaunch = true
        }
        let launchFiles = LaunchReason.fileURLs(from: launchEvent)
        if !launchFiles.isEmpty, handleOpenURLs(launchFiles) {
            didOpenURLDuringLaunch = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.showOverlayIfInteractiveLaunch()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if handleOpenURLs(urls) {
            didOpenURLDuringLaunch = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let panel {
            saveFrame(panel)
        }
        hotkey.stop()
        QuickChatController.shared.pasteboardMonitor.stop()
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(focusInput: true)
        return true
    }

    // MARK: - Panel

    func startNewChat() {
        QuickChatController.shared.dismiss()
        serviceIntakeTask?.cancel()
        consumeUnread(revealAnswer: false)
        showPanel(focusInput: false)
        WebViewStore.shared.startNewChat()
    }

    /// Overlay New Chat, then fill the grok.com composer without sending (DEC-049).
    func startNewChat(text: String?, files: [URL] = []) {
        startNewChat()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || !files.isEmpty else { return }
        let token = WebViewStore.shared.composerFillToken
        serviceIntakeTask = Task { @MainActor in
            do {
                let attachments = try await FileIntake.load(files)
                guard !Task.isCancelled else { return }
                WebViewStore.shared.fillComposer(text: trimmed, attachments: attachments, expectedGeneration: token)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, token == WebViewStore.shared.composerFillToken else { return }
                QuickChatController.shared.present(chip: trimmed)
                QuickChatController.shared.presentIntakeError(error, retrying: files) { [weak self] payload in
                    guard let self else { return }
                    self.startNewChat()
                    WebViewStore.shared.fillComposer(text: payload.text, attachments: payload.attachments,
                                                     expectedGeneration: WebViewStore.shared.composerFillToken)
                }
            }
        }
    }

    /// Finder Ask Grok (DEC-051). Overlay New Chat, file attached, no send.
    @objc func askGrok(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = FileIntake.fileURLs(from: pasteboard, validate: false)
        DispatchQueue.main.async { [weak self] in
            self?.presentServiceFiles(urls)
        }
    }

    private func presentServiceFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        didOpenURLDuringLaunch = true
        startNewChat(text: nil, files: urls)
    }

    func startNewChat(payload: QuickChatPayload, completion: ((ChatHandoffOutcome) -> Void)? = nil) {
        serviceIntakeTask?.cancel()
        consumeUnread(revealAnswer: false)
        showPanel(focusInput: false)
        WebViewStore.shared.startNewChat(payload: payload, completion: completion)
    }

    func startNewVoiceChat() {
        QuickChatController.shared.dismiss()
        serviceIntakeTask?.cancel()
        consumeUnread(revealAnswer: false)
        showPanel(focusInput: false)
        WebViewStore.shared.startNewVoiceChat()
    }

    func showPanel(focusInput: Bool) {
        let revealAnswer = consumeUnread(revealAnswer: true)
        let panel = ensurePanel()
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }
        panel.level = .normal
        // Move to this Space / cursor display before activate, or AppKit
        // will switch you to wherever the window last lived.
        panel.applySummonPlacement()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        WebViewStore.shared.resignIfCovered()
        if revealAnswer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WebViewStore.shared.scrollToUnreadAnswer()
            }
        } else if focusInput {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WebViewStore.shared.focusInput()
            }
        }
        installEscMonitor()
    }

    func hidePanel() {
        guard let panel else { return }
        saveFrame(panel)
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    func showQuickChat() {
        serviceIntakeTask?.cancel()
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }
        QuickChatController.shared.present()
    }

    func showQuickChat(chip text: String?, files: [URL] = []) {
        serviceIntakeTask?.cancel()
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }
        QuickChatController.shared.present(chip: text, files: files)
    }

    @discardableResult
    func showQuickChat(files: [URL]) -> Bool {
        serviceIntakeTask?.cancel()
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }
        return QuickChatController.shared.presentFiles(files)
    }

    func showQuickChat(dropping pasteboard: NSPasteboard) -> Bool {
        serviceIntakeTask?.cancel()
        if hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        }
        return QuickChatController.shared.presentDropped(pasteboard)
    }

    func startImagine(prompt: String?) {
        serviceIntakeTask?.cancel()
        QuickChatController.shared.dismiss()
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        showPanel(focusInput: trimmed.isEmpty)
        WebViewStore.shared.startNewGeneration()
        if !trimmed.isEmpty {
            WebViewStore.shared.fillComposer(text: trimmed)
        }
    }

    // MARK: - grock:// (DEC-049)

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        if let url = LaunchReason.url(from: event), handleOpenURLs([url]) {
            didOpenURLDuringLaunch = true
        }
    }

    private func showOverlayIfInteractiveLaunch() {
        if didOpenURLDuringLaunch { return }
        let showOnLaunch = LaunchReason.shouldShowMainWindow(
            appleEvent: launchAppleEvent ?? NSAppleEventManager.shared().currentAppleEvent,
            isHidden: NSApp.isHidden
        )
        if showOnLaunch {
            showPanel(focusInput: true)
        }
    }

    @discardableResult
    private func handleOpenURLs(_ urls: [URL]) -> Bool {
        var handled = false
        var files: [URL] = []
        for url in urls {
            let key = url.absoluteString
            if recentOpenURLKeys.contains(key) { continue }
            if let action = GrockURL.parse(url) {
                rememberOpenURL(key)
                performGrockURL(action)
                handled = true
                continue
            }
            if url.isFileURL {
                rememberOpenURL(key)
                files.append(url)
            }
        }
        if !files.isEmpty, showQuickChat(files: files) {
            handled = true
        }
        return handled
    }

    private func rememberOpenURL(_ key: String) {
        recentOpenURLKeys.insert(key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.recentOpenURLKeys.remove(key)
        }
    }

    func performGrockURL(_ action: GrockURL) {
        switch action {
        case .new(let text, let files):
            startNewChat(text: text, files: files)
        case .ask(let text, let files):
            showQuickChat(chip: text, files: files)
        case .imagine(let prompt):
            startImagine(prompt: prompt)
        case .summon:
            QuickChatController.shared.dismiss()
            showPanel(focusInput: true)
        case .invalid(let text, let reason):
            showQuickChat(chip: text)
            QuickChatController.shared.presentIntakeError(NSError(
                domain: "GrockURL", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]
            ))
        }
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let panel = FloatingPanel()
        panel.delegate = self
        panel.installWebView(WebViewStore.shared.webView)
        if !restoreFrame(panel) {
            applyDefaultPanelFrame(panel)
        }
        self.panel = panel
        return panel
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel {
            hidePanel()
            return false
        }
        if sender === settingsWindow {
            sender.orderOut(nil)
            return false
        }
        if QuickChatController.shared.isPanel(sender) {
            QuickChatController.shared.dismiss()
            return false
        }
        return true
    }

    // MARK: - Status item

    private func setupStatusItem() {
        // Assign `menu` and leave the button alone so AppKit uses the system
        // highlight (not a custom dark oval) and click opens the menu.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            applyUnreadChrome(to: button)
            let drop = FileDropCatcher(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.clicksFallThrough = true
            drop.onDrop = { [weak self] pasteboard in
                self?.showQuickChat(dropping: pasteboard) ?? false
            }
            button.addSubview(drop)
        }
        item.menu = statusMenu
        statusItem = item
    }

    /// Dock badge is the thing you can see. Extra fill is backup. Hide-from-Dock
    /// still has no tile, so that mode only gets the extra.
    private func applyUnreadChrome(to button: NSButton? = nil) {
        let unread = reply.hasUnread
        if let button = button ?? statusItem?.button {
            button.image = NSImage(
                systemSymbolName: unread ? "sparkle" : "sparkles",
                accessibilityDescription: unread ? "Grock, answer ready" : "Grock"
            )
            button.image?.isTemplate = true
            button.toolTip = unread ? "Answer ready" : nil
        }
        NSApp.dockTile.badgeLabel = ReplyMonitor.dockBadgeLabel(unread: unread)
        NSApp.dockTile.display()
    }

    /// Showing the overlay consumes the fill. New Chat skips scroll-to-answer.
    @discardableResult
    private func consumeUnread(revealAnswer: Bool) -> Bool {
        guard revealAnswer else {
            if reply.clearUnread() { applyUnreadChrome() }
            return false
        }
        let wasUnread = reply.clearUnread()
        if wasUnread { applyUnreadChrome() }
        return wasUnread
    }

    /// Looking = overlay on screen, app active, and this window is key.
    /// Open-behind-Xcode is not looking. Esc-hidden is not looking.
    private var isWatchingOverlay: Bool {
        guard let panel, panel.isVisible else { return false }
        return NSApp.isActive && panel.isKeyWindow
    }

    private func noteReplyLanded() {
        let watching = isWatchingOverlay
        let armed = reply.noteLanded(userIsWatching: watching)
        NSLog("[Grock] reply landed watching=\(watching) unread=\(reply.hasUnread)")
        if armed {
            applyUnreadChrome()
        }
    }

    /// Cmd-tab or click a window that was already open behind something.
    private func revealUnreadIfLooking() {
        guard reply.hasUnread else { return }
        guard let panel, panel.isVisible, NSApp.isActive else { return }
        consumeUnread(revealAnswer: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            WebViewStore.shared.scrollToUnreadAnswer()
        }
    }

    private func setupMenu() {
        func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            return i
        }

        statusMenu.addItem(item("Show Grock", action: #selector(menuShow)))
        statusMenu.addItem(item("New Chat", action: #selector(menuNewChat)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Settings…", action: #selector(menuSettings), key: ","))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Quit Grock", action: #selector(menuQuit), key: "q"))
    }

    /// File > Close already hides the overlay (and Settings). Title it like a window.
    private func polishMainMenu() {
        func apply() {
            let fileMenu = NSApp.mainMenu?.items
                .compactMap(\.submenu)
                .first { menu in
                    menu.items.contains { $0.action == #selector(NSWindow.performClose(_:)) }
                }
            guard let fileMenu else { return }
            for item in fileMenu.items where item.action == #selector(NSWindow.performClose(_:)) {
                item.title = "Close Window"
            }
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }

    @objc private func menuShow() {
        showPanel(focusInput: true)
    }
    @objc private func menuNewChat() {
        startNewChat()
    }
    @objc private func menuReload() {
        _ = WebViewStore.shared
        WebViewStore.shared.reload()
    }
    @objc private func menuSettings() {
        showSettings()
    }

    /// Opens Grock Settings (theme, hotkey, sign-in, dock / login).
    ///
    /// Do not `sendAction(showSettingsWindow:)` after focusing the overlay:
    /// the WebView becomes first responder and the SwiftUI Settings scene
    /// action is a silent no-op. Own the window instead.
    func showSettings(pane: SettingsPane? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        HotkeyManager.shared.retryInstallIfNeeded()
        let window = ensureSettingsWindow()
        if let pane, let tabs = window.contentViewController as? SettingsTabController {
            tabs.select(pane)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow { return settingsWindow }

        let tabs = SettingsTabController.make()
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: SettingsTabController.paneWidth, height: 360))
        window.center()
        settingsWindow = window
        return window
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    func setHideFromDock(_ hidden: Bool) {
        hideFromDock = hidden
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if let panel, panel.isVisible {
            showPanel(focusInput: false)
        }
    }

    // MARK: - Notifications / Esc / z-order

    private func setupNotifications() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .grockNewChat, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.startNewChat() }
            },
            center.addObserver(forName: .grockNewVoiceChat, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.startNewVoiceChat() }
            },
            center.addObserver(forName: .grockQuickChat, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.showQuickChat() }
            },
            center.addObserver(forName: .grockReload, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.menuReload() }
            },
            center.addObserver(forName: .grockShowSettings, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?[SettingsPane.notificationKey] as? String
                let pane = raw.flatMap(SettingsPane.init(rawValue:))
                Task { @MainActor in self?.showSettings(pane: pane) }
            },
            center.addObserver(forName: .grockSettingsDidReset, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.resetPanelFrameToDefault()
                    self?.panel?.syncToolbar()
                }
            },
            center.addObserver(forName: .grockChromeDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.panel?.syncToolbar() }
            },
            center.addObserver(forName: .grockSessionActionsDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.panel?.syncToolbar() }
            },
            center.addObserver(forName: .grockAuthenticationDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.panel?.syncToolbar() }
            },
            center.addObserver(forName: .grockReplyLanded, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.noteReplyLanded() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.revealUnreadIfLooking() }
            },
            // Settings / auth windows are normal-level by default and sit *under* a floating panel.
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor in
                    self?.ensureAuxiliaryWindowAbovePanel(window)
                    if window === self?.panel {
                        self?.revealUnreadIfLooking()
                    }
                }
            },
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                Task { @MainActor in self?.ensureAuxiliaryWindowAbovePanel(window) }
            }
        ]
    }

    /// If the launcher is ever raised above normal, lift Settings / popups with it.
    private func ensureAuxiliaryWindowAbovePanel(_ window: NSWindow) {
        guard let panel, window !== panel else { return }
        guard panel.level > .normal else { return }
        guard window.contentView != nil,
              window.styleMask.contains(.titled) || window.title.isEmpty == false || window.isVisible
        else { return }

        let minLevel = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        if window.level.rawValue < minLevel.rawValue {
            window.level = minLevel
        }
        window.orderFrontRegardless()
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                if HotkeyManager.shared.isRecording { return event }
                if let self, NSApp.keyWindow === self.settingsWindow { return event }
                if QuickChatController.shared.isPresented {
                    QuickChatController.shared.dismiss()
                    return nil
                }
                self?.hidePanel()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

    // MARK: - Frame

    private func saveFrame(_ window: NSWindow) {
        let f = window.frame
        UserDefaults.standard.set(
            ["x": f.origin.x, "y": f.origin.y, "w": f.size.width, "h": f.size.height],
            forKey: Self.windowFrameKey
        )
    }

    @discardableResult
    private func restoreFrame(_ window: NSWindow) -> Bool {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.windowFrameKey),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let w = dict["w"] as? CGFloat,
              let h = dict["h"] as? CGFloat,
              w > 0, h > 0
        else { return false }
        let saved = NSRect(x: x, y: y, width: w, height: h)
        window.setFrame(
            PanelGeometry.constrainedFrame(
                saved,
                visibleScreens: NSScreen.screens.map(\.visibleFrame),
                minSize: window.minSize
            ),
            display: false
        )
        return true
    }

    private func resetPanelFrameToDefault() {
        guard let panel else { return }
        applyDefaultPanelFrame(panel)
    }

    private func applyDefaultPanelFrame(_ window: NSWindow) {
        window.setContentSize(PanelGeometry.defaultContentSize)
        window.center()
        window.setFrame(
            PanelGeometry.constrainedFrame(
                window.frame,
                visibleScreens: NSScreen.screens.map(\.visibleFrame),
                minSize: window.minSize
            ),
            display: window.isVisible
        )
    }

    #if DEBUG
    /// Debug-only File > Debug probes for the Quick Chat send path. Not compiled into Release.
    func debugQuickChatSendText() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (text?.isEmpty == false ? text! : "Quick Chat text probe")
        startNewChat(payload: QuickChatPayload(text: prompt, attachments: [])) { outcome in
            NSLog("[Grock] Quick Chat text send \(String(describing: outcome))")
        }
    }

    func debugQuickChatSendImage() {
        let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            ?? Self.debugProbeImage()
        guard let attachment = QuickChatAttachment.fromImage(image) else {
            NSLog("[Grock] Quick Chat image probe failed to encode")
            return
        }
        startNewChat(payload: QuickChatPayload(text: "", attachments: [attachment])) { outcome in
            NSLog("[Grock] Quick Chat image send \(String(describing: outcome))")
        }
    }

    func debugQuickChatSendFile() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                do {
                    let attachments = try await FileIntake.load(picker.urls)
                    guard !attachments.isEmpty else { return }
                    self?.startNewChat(payload: QuickChatPayload(text: "", attachments: attachments)) { outcome in
                        NSLog("[Grock] Quick Chat file send \(String(describing: outcome))")
                    }
                } catch {
                    NSLog("[Grock] Quick Chat file intake failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func debugQuickChatSendTextAndImage() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = (text?.isEmpty == false ? text! : "Quick Chat text+image probe")
        let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            ?? Self.debugProbeImage()
        guard let attachment = QuickChatAttachment.fromImage(image) else {
            NSLog("[Grock] Quick Chat text+image probe failed to encode")
            return
        }
        startNewChat(payload: QuickChatPayload(text: prompt, attachments: [attachment])) { outcome in
            NSLog("[Grock] Quick Chat text+image send \(String(describing: outcome))")
        }
    }

    private static func debugProbeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }
    #endif

}
