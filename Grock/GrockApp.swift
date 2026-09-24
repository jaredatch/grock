import SwiftUI

@main
struct GrockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var updater = UpdaterController.shared

    var body: some Scene {
        // Overlay-first: no main WindowGroup. AppDelegate owns the floating panel.
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .grockShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .grockNewChat, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Voice Chat") {
                    NotificationCenter.default.post(name: .grockNewVoiceChat, object: nil)
                }

                Button("Quick Chat") {
                    NotificationCenter.default.post(name: .grockQuickChat, object: nil)
                }

                #if DEBUG
                Divider()
                Button("Debug: Quick Chat Send Text") {
                    appDelegate.debugQuickChatSendText()
                }
                Button("Debug: Quick Chat Send Image") {
                    appDelegate.debugQuickChatSendImage()
                }
                Button("Debug: Quick Chat Send File…") {
                    appDelegate.debugQuickChatSendFile()
                }
                Button("Debug: Quick Chat Send Text + Image") {
                    appDelegate.debugQuickChatSendTextAndImage()
                }
                #endif
            }

            CommandGroup(replacing: .toolbar) {
                Button("Customize Appearance…") {
                    NotificationCenter.default.post(
                        name: .grockShowSettings,
                        object: nil,
                        userInfo: [SettingsPane.notificationKey: SettingsPane.appearance.rawValue]
                    )
                }
                Divider()
                Button("Reload") {
                    NotificationCenter.default.post(name: .grockReload, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .sidebar) {
                EmptyView()
            }

            CommandGroup(replacing: .help) {
                Button("Grock Help") {
                    AppInfo.open(AppInfo.githubRepository)
                }
                Button("Report Bug") {
                    AppInfo.open(AppInfo.githubIssues)
                }
            }
        }
    }
}
