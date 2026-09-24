import AppKit
import WebKit

/// Hosts OAuth / X login popups in a normal titled window sharing the WebView session.
/// Uses the configuration WebKit provides so the session shares cookies with the main WebView.
@MainActor
final class AuthPopupPresenter: NSObject, NSWindowDelegate {
    static let shared = AuthPopupPresenter()

    private var windows: [ObjectIdentifier: NSWindow] = [:]

    func present(webView: WKWebView, requestedURL: URL?) -> WKWebView {
        webView.allowsBackForwardNavigationGestures = true
        WebViewStore.shared.applyWebInspector(to: webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.level = .normal
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows[ObjectIdentifier(webView)] = window
        return webView
    }

    func close(webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        if let window = windows[id] {
            window.orderOut(nil)
            windows.removeValue(forKey: id)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        windows = windows.filter { $0.value !== sender }
        return false
    }
}
