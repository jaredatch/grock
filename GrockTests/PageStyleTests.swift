import AppKit
import WebKit
import XCTest
@testable import Grock

@MainActor
final class PageStyleTests: XCTestCase {
    /// grok.com declares its colors on `:root` and again on a `[data-theme]`
    /// wrapper around the app. A style that only reached `:root` would leave
    /// the whole app in grok.com's own colors.
    func testStyleReachesThePageAndItsThemeWrapper() async throws {
        let page = try await load(url: "https://grok.com/", style: .mac)
        defer { page.window.close() }
        let styled = try await colors(in: page.webView)
        XCTAssertEqual(styled["sidebar"], "rgb(255, 255, 255)")
        XCTAssertEqual(styled["portal"], "rgb(255, 255, 255)")
        XCTAssertEqual(styled["accent"], "rgb(1, 2, 3)")

        // Back to Grok: the page is grok.com's again, with nothing of ours left in it.
        let plain = try await page.webView.callAsyncJavaScript("""
        window.__grockTheme.set({ style: '' });
        return { sidebar: getComputedStyle(document.getElementById('sidebar')).backgroundColor,
                 left: !!document.getElementById('grock-theme-style') };
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(plain?["sidebar"] as? String, "rgb(249, 248, 247)")
        XCTAssertEqual(plain?["left"] as? Bool, false)
    }

    /// The Mac sidebar dims when the window is not in front. The page cannot
    /// see that for itself, so the app marks `<html>`, and only while a
    /// style is on.
    func testWindowActivityMarksTheStyledPage() async throws {
        let page = try await load(url: "https://grok.com/", style: .mac)
        defer { page.window.close() }
        let result = try await page.webView.callAsyncJavaScript("""
        var root = document.documentElement, mark = 'data-grock-window-inactive', seen = {};
        seen.start = root.hasAttribute(mark);
        window.__grockTheme.set({ inactive: true });
        seen.inactive = root.hasAttribute(mark);
        window.__grockTheme.set({ inactive: false });
        seen.active = root.hasAttribute(mark);
        window.__grockTheme.set({ inactive: true });
        window.__grockTheme.set({ style: '' });
        seen.unstyled = root.hasAttribute(mark);
        return seen;
        """, in: nil, contentWorld: .page) as? [String: Bool]
        XCTAssertEqual(result, ["start": false, "inactive": true, "active": false, "unstyled": false])
        XCTAssertTrue(WebViewStore.macInactiveCSS.contains("html:root[data-grock-window-inactive] #app-sidebar"))
    }

    /// Sign-in happens on other hosts, in the same WebView. They are never restyled.
    func testOtherHostsAreLeftAlone() async throws {
        let page = try await load(url: "https://accounts.x.ai/sign-in", style: .mac)
        defer { page.window.close() }
        let result = try await page.webView.callAsyncJavaScript("""
        return { script: !!window.__grockTheme, sheet: !!document.getElementById('grock-theme-style'),
                 sidebar: getComputedStyle(document.getElementById('sidebar')).backgroundColor };
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["script"] as? Bool, false)
        XCTAssertEqual(result?["sheet"] as? Bool, false)
        XCTAssertEqual(result?["sidebar"] as? String, "rgb(249, 248, 247)")
    }

    private func colors(in webView: WKWebView) async throws -> [String: String] {
        let result = try await webView.callAsyncJavaScript("""
        function fill(id) { return getComputedStyle(document.getElementById(id)).backgroundColor; }
        return { sidebar: fill('sidebar'), portal: fill('portal'), accent: fill('accent') };
        """, in: nil, contentWorld: .page)
        return try XCTUnwrap(result as? [String: String])
    }

    /// The shape of grok.com that matters here: tokens on `:root`, the same
    /// tokens again on a theme wrapper, and a portal outside that wrapper.
    private func load(url: String, style: PageStyle) async throws -> (webView: WKWebView, window: NSWindow) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let start = [
            "window.__grockThemeConfig = {style: '\(style.rawValue)', accentLight: '#010203', accentDark: '#010203'};",
            WebViewStore.themeScript
        ]
        for source in start {
            config.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        let loaded = expectation(description: "page-style-fixture")
        let loader = Loader(loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString("""
        <html style="color-scheme:light"><head><style>
          :root, .theme { --grok-chrome: #f9f8f7; --grok-accent: #1084fe; }
          .fill { background-color: var(--grok-chrome); }
          #accent { background-color: var(--grok-accent); }
        </style></head><body>
          <div class="theme" data-theme="light">
            <aside id="sidebar" class="fill">Chats</aside>
            <a id="accent">Link</a>
          </div>
          <div id="portal" class="fill">Menu</div>
        </body></html>
        """, baseURL: URL(string: url))
        await fulfillment(of: [loaded], timeout: 4)
        withExtendedLifetime(loader) {}
        return (webView, window)
    }
}

private final class Loader: NSObject, WKNavigationDelegate {
    private let loaded: XCTestExpectation
    private var done = false

    init(_ loaded: XCTestExpectation) { self.loaded = loaded }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) { finish() }

    private func finish() {
        guard !done else { return }
        done = true
        loaded.fulfill()
    }
}
