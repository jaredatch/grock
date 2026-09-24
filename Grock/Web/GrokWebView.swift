import SwiftUI
import WebKit

/// SwiftUI host for the shared WKWebView. Must not create a second instance.
struct GrokWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        WebViewStore.shared.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
