import Foundation

extension Notification.Name {
    static let grockNewChat = Notification.Name("com.jaredatch.Grock.newChat")
    static let grockNewVoiceChat = Notification.Name("com.jaredatch.Grock.newVoiceChat")
    static let grockQuickChat = Notification.Name("com.jaredatch.Grock.quickChat")
    static let grockReload = Notification.Name("com.jaredatch.Grock.reload")
    static let grockShowSettings = Notification.Name("com.jaredatch.Grock.showSettings")
    static let grockSettingsDidReset = Notification.Name("com.jaredatch.Grock.settingsDidReset")
    static let grockChromeDidChange = Notification.Name("com.jaredatch.Grock.chromeDidChange")
    static let grockLaunchLoadingDidChange = Notification.Name("com.jaredatch.Grock.launchLoadingDidChange")
    static let grockRecoveryDidChange = Notification.Name("com.jaredatch.Grock.recoveryDidChange")
    /// grok.com finished a reply. AppDelegate decides whether the extra fills.
    static let grockReplyLanded = Notification.Name("com.jaredatch.Grock.replyLanded")
    /// Conversation More / Share / panel cluster appeared or left (DEC-055).
    static let grockSessionActionsDidChange = Notification.Name("com.jaredatch.Grock.sessionActionsDidChange")
    /// The main grok.com surface entered or left its signed-in state.
    static let grockAuthenticationDidChange = Notification.Name("com.jaredatch.Grock.authenticationDidChange")
}
