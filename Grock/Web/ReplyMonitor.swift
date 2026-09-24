import Foundation
import WebKit

/// Native side of the grok.com reply observer (DEC-054).
///
/// JS reports a generation start/stop. Unread is armed when you are not
/// looking (hidden, or open behind another app) at the moment it lands.
/// One bit, not a count.
struct ReplyMonitor: Equatable {
    private(set) var isGenerating = false
    private(set) var hasUnread = false

    mutating func noteGenerating(_ generating: Bool) {
        isGenerating = generating
    }

    /// Reply finished. Returns whether unread newly turned on.
    @discardableResult
    mutating func noteLanded(userIsWatching: Bool) -> Bool {
        isGenerating = false
        guard !userIsWatching, !hasUnread else { return false }
        hasUnread = true
        return true
    }

    /// Showing the overlay (or starting a new chat) consumes the fill.
    @discardableResult
    mutating func clearUnread() -> Bool {
        guard hasUnread else { return false }
        hasUnread = false
        return true
    }

    /// One bit on the Dock tile. Not a running count.
    static func dockBadgeLabel(unread: Bool) -> String? {
        unread ? "1" : nil
    }
}

/// Page → native channel for generation edges. Fire-and-forget; replies `ok`.
final class ReplyBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let channelName = "grockReply"

    weak var expectedWebView: WKWebView?
    var handler: (([String: Any]) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @Sendable (Any?, String?) -> Void
    ) {
        guard DownloadRequestPolicy.permitsMessage(message, expectedWebView: expectedWebView) else {
            replyHandler(nil, "This page is not allowed to update Grock.")
            return
        }
        let body = message.body as? [String: Any] ?? [:]
        DispatchQueue.main.async { [weak self] in
            guard let self, DownloadRequestPolicy.permitsMessage(message, expectedWebView: self.expectedWebView) else { return }
            self.handler?(body)
        }
        replyHandler(["ok": true], nil)
    }
}
