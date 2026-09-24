import AppKit
import SwiftUI

/// Preference panes hosted by `SettingsTabController` (toolbar tabs).
/// The SwiftUI `Settings` scene also embeds these so a fallback window
/// still matches if it ever appears.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsPane()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AccountSettingsPane()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            AdvancedSettingsPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: SettingsTabController.paneWidth)
    }
}

struct GeneralSettingsPane: View {
    @AppStorage(AppDelegate.hideFromDockKey) private var hideFromDock = false
    @AppStorage(ClipboardPreference.autoIncludeKey) private var autoIncludeClipboard = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var newChat = HotkeyManager.shared.combo(for: .newChat)
    @State private var summon = HotkeyManager.shared.combo(for: .summon)
    @State private var voiceChat = HotkeyManager.shared.combo(for: .voiceChat)
    @State private var quickChat = HotkeyManager.shared.combo(for: .quickChat)
    @State private var newChatStatus = HotkeyManager.shared.status(for: .newChat)
    @State private var summonStatus = HotkeyManager.shared.status(for: .summon)
    @State private var voiceChatStatus = HotkeyManager.shared.status(for: .voiceChat)
    @State private var quickChatStatus = HotkeyManager.shared.status(for: .quickChat)

    var body: some View {
        Form {
            Section {
                LabeledContent("Quick Chat") {
                    HotkeyRecorder(action: .quickChat, combo: $quickChat, status: quickChatStatus) {
                        refreshHotkeys()
                    }
                }
                LabeledContent("New Chat") {
                    HotkeyRecorder(action: .newChat, combo: $newChat, status: newChatStatus) {
                        refreshHotkeys()
                    }
                }
                LabeledContent("Show Grock") {
                    HotkeyRecorder(action: .summon, combo: $summon, status: summonStatus) {
                        refreshHotkeys()
                    }
                }
                LabeledContent("Voice Chat") {
                    HotkeyRecorder(action: .voiceChat, combo: $voiceChat, status: voiceChatStatus) {
                        refreshHotkeys()
                    }
                }
            } header: {
                Text("Hotkeys")
            }

            Section {
                Toggle("Include Recent Clipboard in Quick Chat", isOn: $autoIncludeClipboard)
            } footer: {
                Text("Stages content copied in the last minute. Skips content marked confidential or temporary. You can always paste deliberately.")
            }

            Section {
                Toggle("Hide from Dock", isOn: $hideFromDock)
                    .onChange(of: hideFromDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LaunchAtLogin.setEnabled(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTabController.paneWidth)
        .onAppear {
            syncHotkeys()
            launchAtLogin = LaunchAtLogin.isEnabled
            refreshHotkeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: HotkeyManager.didChangeNotification)) { _ in
            syncHotkeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: .grockSettingsDidReset)) { _ in
            launchAtLogin = LaunchAtLogin.isEnabled
            syncHotkeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshHotkeys()
        }
        .task {
            while !Task.isCancelled {
                refreshHotkeys()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func syncHotkeys() {
        newChat = HotkeyManager.shared.combo(for: .newChat)
        summon = HotkeyManager.shared.combo(for: .summon)
        voiceChat = HotkeyManager.shared.combo(for: .voiceChat)
        quickChat = HotkeyManager.shared.combo(for: .quickChat)
        newChatStatus = HotkeyManager.shared.status(for: .newChat)
        summonStatus = HotkeyManager.shared.status(for: .summon)
        voiceChatStatus = HotkeyManager.shared.status(for: .voiceChat)
        quickChatStatus = HotkeyManager.shared.status(for: .quickChat)
    }

    private func refreshHotkeys() {
        HotkeyManager.shared.retryInstallIfNeeded()
        syncHotkeys()
    }
}

struct AppearanceSettingsPane: View {
    @AppStorage(AppearancePreference.defaultsKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(ChromePreference.hideSidebarOnLaunchKey) private var hideSidebarOnLaunch = true
    @AppStorage(ChromePreference.hideImagineKey) private var hideImagine = false
    @AppStorage(ChromePreference.hideLibraryKey) private var hideLibrary = false
    @AppStorage(ChromePreference.hideAutomationsKey) private var hideAutomations = false
    @AppStorage(ChromePreference.hideProjectsKey) private var hideProjects = false
    @AppStorage(ChromePreference.hidePluginsKey) private var hidePlugins = false
    @AppStorage(ChromePreference.hideGrokBotKey) private var hideGrokBot = true
    @AppStorage(ChromePreference.hidePrivateKey) private var hidePrivate = true
    @AppStorage(ChromePreference.hideDictationKey) private var hideDictation = false
    @AppStorage(ChromePreference.hideVoiceKey) private var hideVoice = false

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceRaw) { _, newValue in
                    if let mode = AppearancePreference(rawValue: newValue) {
                        AppearancePreference.apply(mode)
                    }
                }
            }

            Section {
                Toggle("Hide Sidebar on Launch", isOn: $hideSidebarOnLaunch)
            }

            Section {
                Toggle("Imagine", isOn: $hideImagine)
                Toggle("Library", isOn: $hideLibrary)
                Toggle("Automations", isOn: $hideAutomations)
                Toggle("Projects", isOn: $hideProjects)
                Toggle("Plugins", isOn: $hidePlugins)
                Toggle("Grok Bot", isOn: $hideGrokBot)
                Toggle("Private", isOn: $hidePrivate)
                Toggle("Dictation", isOn: $hideDictation)
                Toggle("Voice mode", isOn: $hideVoice)
            } header: {
                Text("Hide Features")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTabController.paneWidth)
        .onAppear {
            if let mode = AppearancePreference(rawValue: appearanceRaw) {
                AppearancePreference.apply(mode)
            }
        }
        .onChange(of: hideSidebarOnLaunch) { _, on in
            if on {
                ChromePreference.setSidebarHidden(true)
            } else {
                ChromePreference.apply()
            }
        }
        .onChange(of: hideImagine) { _, _ in ChromePreference.apply() }
        .onChange(of: hideLibrary) { _, _ in ChromePreference.apply() }
        .onChange(of: hideAutomations) { _, _ in ChromePreference.apply() }
        .onChange(of: hideProjects) { _, _ in ChromePreference.apply() }
        .onChange(of: hidePlugins) { _, _ in ChromePreference.apply() }
        .onChange(of: hideGrokBot) { _, _ in ChromePreference.apply() }
        .onChange(of: hidePrivate) { _, _ in ChromePreference.apply() }
        .onChange(of: hideDictation) { _, _ in ChromePreference.apply() }
        .onChange(of: hideVoice) { _, _ in ChromePreference.apply() }
    }
}

enum AccountHelp {
    static let footer = "Grock uses your grok.com login. If X sign-in gets stuck, open the page in your browser or clear web data."
}

struct AccountSettingsPane: View {
    var body: some View {
        Form {
            Section {
                Button("Open Current Page in Browser…") {
                    WebViewStore.shared.openCurrentPageInBrowser()
                }
                Button("Clear Web Data…", role: .destructive) {
                    _ = ClearWebData.confirmAndClear()
                }
            } footer: {
                Text(AccountHelp.footer)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTabController.paneWidth)
    }
}

struct AdvancedSettingsPane: View {
    @AppStorage(WebViewStore.webInspectorKey) private var webInspector = false
    @State private var confirmReset = false
    @State private var cliStatus = GrockCLIInstaller.status()
    @State private var cliCommand: GrockCLIInstaller.Command?
    @State private var cliError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Web Inspector", isOn: $webInspector)
                    .onChange(of: webInspector) { _, newValue in
                        WebViewStore.shared.setWebInspectorEnabled(newValue)
                    }
            } footer: {
                Text("Right-click the page and choose Inspect Element.")
            }

            Section {
                LabeledContent("CLI") {
                    Text(cliStatusLabel)
                        .foregroundStyle(.secondary)
                }
                Button(cliButtonTitle) {
                    performCLIAction()
                }
            } header: {
                Text("Command Line")
            } footer: {
                Text("Use grock from Terminal to open Grock and prepare a prompt. Install or remove it with a command you copy into Terminal.")
            }

            Section {
                Button("Reset Settings…", role: .destructive) {
                    confirmReset = true
                }
            } footer: {
                Text("Restores to default Grock settings. Does not sign you out or clear Grok data.")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsTabController.paneWidth)
        .onAppear {
            webInspector = WebViewStore.shared.isWebInspectorEnabled
            refreshCLI()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCLI()
        }
        .sheet(item: $cliCommand, onDismiss: refreshCLI) { command in
            CLICommandSheet(command: command) { cliCommand = nil }
        }
        .alert("Reset Settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive, action: SettingsReset.restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This puts Grock settings back to their defaults.")
        }
        .alert("CLI", isPresented: Binding(
            get: { cliError != nil },
            set: { if !$0 { cliError = nil } }
        )) {
            Button("OK", role: .cancel) { cliError = nil }
        } message: {
            Text(cliError ?? "")
        }
    }

    private var cliStatusLabel: String {
        switch cliStatus {
        case .notInstalled:
            return "Not installed"
        case .installed(let url):
            return url.path
        case .foreign(let url):
            return "Existing file or link at \(url.path)"
        }
    }

    private var cliButtonTitle: String {
        switch cliStatus {
        case .notInstalled:
            return "Install CLI…"
        case .installed:
            return "Uninstall CLI…"
        case .foreign:
            return "Install CLI…"
        }
    }

    private func refreshCLI() {
        cliStatus = GrockCLIInstaller.status()
    }

    private func performCLIAction() {
        refreshCLI()
        do {
            switch cliStatus {
            case .installed(let url):
                cliCommand = try GrockCLIInstaller.uninstallCommand(at: url)
            case .notInstalled:
                cliCommand = try GrockCLIInstaller.installCommand()
            case .foreign(let url):
                throw GrockCLIInstaller.InstallError.occupied(url)
            }
        } catch {
            cliError = error.localizedDescription
        }
    }
}

private struct CLICommandSheet: View {
    let command: GrockCLIInstaller.Command
    var onDone: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command.title)
                .font(.headline)
            Text("Copy this command, paste it in Terminal, and press Return. Terminal may ask for your Mac password.")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView([.horizontal, .vertical]) {
                Text(command.text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 150)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copied ? "Copied" : "Copy Command") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    copied = pasteboard.setString(command.text, forType: .string)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

/// Signs out of grok.com in Grock. Confirm first — this is destructive.
enum ClearWebData {
    @MainActor
    static func confirmAndClear() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Clear Web Data?"
        alert.informativeText = "This signs you out of grok.com in Grock."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        WebViewStore.shared.clearWebsiteData()
        return true
    }
}

/// Clears Grock prefs and reapplies side effects. Leaves the grok.com session alone.
enum SettingsReset {
    static func restorePreferenceDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppearancePreference.defaultsKey)
        for key in ChromePreference.allKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: WebViewStore.webInspectorKey)
        defaults.removeObject(forKey: AppDelegate.hideFromDockKey)
        defaults.removeObject(forKey: AppDelegate.windowFrameKey)
        ClipboardPreference.reset(defaults: defaults)
    }

    @MainActor
    static func restoreDefaults() {
        restorePreferenceDefaults()
        _ = HotkeyManager.shared.setCombo(nil, for: .newChat)
        _ = HotkeyManager.shared.setCombo(nil, for: .summon)
        _ = HotkeyManager.shared.setCombo(nil, for: .voiceChat)
        _ = HotkeyManager.shared.setCombo(.optionSpace, for: .quickChat)
        AppearancePreference.apply(.system)
        ChromePreference.applyLaunchSidebarPolicy()
        ChromePreference.apply()
        WebViewStore.shared.setWebInspectorEnabled(false)
        NSApp.setActivationPolicy(.regular)
        _ = LaunchAtLogin.setEnabled(false)
        NotificationCenter.default.post(name: .grockSettingsDidReset, object: nil)
    }
}

enum SettingsPane: String {
    case general = "General"
    case appearance = "Appearance"
    case account = "Account"
    case advanced = "Advanced"

    static let notificationKey = "pane"
}

/// Toolbar-style preference window (General / Appearance / Account).
final class SettingsTabController: NSTabViewController {
    static let paneWidth: CGFloat = 500

    @discardableResult
    func select(_ pane: SettingsPane) -> Bool {
        guard let index = tabViewItems.firstIndex(where: { $0.label == pane.rawValue }) else {
            return false
        }
        selectedTabViewItemIndex = index
        return true
    }

    static func make() -> SettingsTabController {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        tabs.addPane("General", symbol: "gearshape", GeneralSettingsPane())
        tabs.addPane("Appearance", symbol: "paintbrush", AppearanceSettingsPane())
        tabs.addPane("Account", symbol: "person.crop.circle", AccountSettingsPane())
        tabs.addPane("Advanced", symbol: "wrench.and.screwdriver", AdvancedSettingsPane())
        return tabs
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        resizeWindowToSelectedTab()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        resizeWindowToSelectedTab()
    }

    private func addPane<V: View>(_ title: String, symbol: String, _ view: V) {
        let host = NSHostingController(rootView: view)
        // NSHostingController defaults to "Untitled"; toolbar-style tabs
        // copy that onto the window title.
        host.title = title
        host.sizingOptions = [.intrinsicContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    private func resizeWindowToSelectedTab() {
        guard let window = view.window,
              selectedTabViewItemIndex >= 0,
              selectedTabViewItemIndex < tabViewItems.count
        else { return }

        let item = tabViewItems[selectedTabViewItemIndex]
        window.title = item.label
        guard let content = item.viewController?.view else { return }

        content.layoutSubtreeIfNeeded()
        var size = content.fittingSize
        size.width = Self.paneWidth
        if size.height < 160 {
            size.height = 240
        }
        window.setContentSize(size)
    }
}

/// Click to record the next shortcut. Esc cancels. Requires ⌘, ⌥, or ⌃. Clear is valid.
struct HotkeyRecorder: View {
    let action: HotkeyAction
    @Binding var combo: HotkeyManager.Combo?
    var status: HotkeyStatus = .unset
    var retry: () -> Void = {}
    @State private var recording = false
    @State private var monitor: Any?

    private var showsClear: Bool { combo != nil && !recording }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 16, height: 16)

                Button {
                    if recording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(recording ? "Press shortcut…" : (combo?.displayString ?? "None"))
                        .font(.body.monospaced())
                        .frame(minWidth: 108)
                }
                .buttonStyle(.bordered)
                .help(recording ? "Press a shortcut, or Esc to cancel" : "Click to change the hotkey")

                Button {
                    apply(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .accessibilityLabel("Clear")
                .opacity(showsClear ? 1 : 0)
                .allowsHitTesting(showsClear)
                .accessibilityHidden(!showsClear)
            }

            if status == .failed, !recording {
                VStack(alignment: .trailing, spacing: 2) {
                    if let combo {
                        Text("Another app may already own \(combo.displayString).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Try Again", action: retry)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .registered:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Active")
                .accessibilityLabel("Active")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Could not register")
                .accessibilityLabel("Could not register")
        case .unset:
            Color.clear
        }
    }

    private func startRecording() {
        stopRecording()
        recording = true
        HotkeyManager.shared.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let next = HotkeyManager.Combo(nsEvent: event)
            if next.isValidShortcut {
                apply(next)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = false
        HotkeyManager.shared.isRecording = false
    }

    private func apply(_ next: HotkeyManager.Combo?) {
        guard HotkeyManager.shared.setCombo(next, for: action) else { return }
        combo = next
    }
}

#Preview {
    SettingsView()
}
