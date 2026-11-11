import AppKit
import WebKit
import XCTest
@testable import Grock

@MainActor
final class MoveToProjectTests: XCTestCase {
    /// Add to Project is a submenu. Its picker is the user's to use, so it is
    /// the one piece of Conversation Actions that comes into view.
    func testSubmenuPickerIsHandedToTheUserUnderTheTitlebar() async throws {
        let fixture = try await fixture(kind: "submenu")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        document.getElementById('composer').focus();
        var availability = await window.__grockChrome.inspectSessionMenu();
        var result = await window.__grockChrome.clickSession('project');
        var fx = window.fixture;
        var picker = document.getElementById('project-picker');
        var box = document.getElementById('projects-positioner');
        var menu = document.getElementById('menu');
        return {available: availability.project, result: result, open: !!picker,
                visible: getComputedStyle(picker).opacity !== '0',
                pinned: box.hasAttribute('data-grock-project-popover'),
                top: box.getBoundingClientRect().top, right: innerWidth - box.getBoundingClientRect().right,
                parentOpen: !!menu, parentMarked: menu.hasAttribute('data-grock-session-menu'),
                parentOpacity: getComputedStyle(menu).opacity,
                parentPointerEvents: getComputedStyle(menu).pointerEvents,
                focused: document.activeElement.id, moved: fx.moved, clicked: fx.clicked,
                pickerEscapes: fx.pickerEscapes,
                suppressed: document.documentElement.hasAttribute('data-grock-picking-menu')};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["available"] as? Bool, true)
        XCTAssertEqual(result?["result"] as? String, "opened")
        XCTAssertEqual(result?["open"] as? Bool, true)
        XCTAssertEqual(result?["visible"] as? Bool, true)
        // Its anchor is hidden, so it is pinned 8px under the 52px titlebar.
        XCTAssertEqual(result?["pinned"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(result?["top"] as? Double), 60, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(result?["right"] as? Double), 12, accuracy: 0.5)
        // The parent menu has to stay open for the submenu to live, unseen.
        XCTAssertEqual(result?["parentOpen"] as? Bool, true)
        XCTAssertEqual(result?["parentMarked"] as? Bool, true)
        XCTAssertEqual(result?["parentOpacity"] as? String, "0")
        XCTAssertEqual(result?["parentPointerEvents"] as? String, "none")
        // The user chooses. Nothing is picked or dismissed for them.
        XCTAssertEqual(result?["focused"] as? String, "project-search")
        XCTAssertEqual(result?["moved"] as? Bool, false)
        XCTAssertEqual(result?["clicked"] as? [String], [])
        XCTAssertEqual(result?["pickerEscapes"] as? Int, 0)
        XCTAssertEqual(result?["suppressed"] as? Bool, false)
    }

    /// Dismissing the picker leaves its hidden parent open on grok.com, where
    /// it would swallow the next click.
    func testClosingTheSubmenuPickerClosesItsHiddenParentMenu() async throws {
        let fixture = try await fixture(kind: "submenu")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        var fx = window.fixture;
        function settle() { return new Promise(function (resolve) { setTimeout(resolve, 50); }); }
        var out = {};
        out.first = await window.__grockChrome.clickSession('project');
        document.getElementById('project-picker').dispatchEvent(
          new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        await settle();
        out.dismissedParentOpen = !!document.getElementById('menu');
        out.dismissedEscapes = fx.menuEscapes;
        out.expanded = document.getElementById('actions').getAttribute('aria-expanded');
        // Choosing a project closes both on grok.com's side; nothing is left to close.
        out.second = await window.__grockChrome.clickSession('project');
        document.getElementById('project-choice').click();
        await settle();
        out.moved = fx.moved;
        out.chosenParentOpen = !!document.getElementById('menu');
        out.chosenEscapes = fx.menuEscapes;
        out.inspectAfter = (await window.__grockChrome.inspectSessionMenu()).project;
        return out;
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["first"] as? String, "opened")
        XCTAssertEqual(result?["dismissedParentOpen"] as? Bool, false)
        XCTAssertEqual(result?["dismissedEscapes"] as? Int, 1)
        XCTAssertEqual(result?["expanded"] as? String, "false")
        XCTAssertEqual(result?["second"] as? String, "opened")
        XCTAssertEqual(result?["moved"] as? Bool, true)
        XCTAssertEqual(result?["chosenParentOpen"] as? Bool, false)
        XCTAssertEqual(result?["chosenEscapes"] as? Int, 1)
        XCTAssertEqual(result?["inspectAfter"] as? Bool, true)
    }

    func testDialogPickerRetainsFocusAndIsNotDismissedByCleanup() async throws {
        let fixture = try await fixture(kind: "dialog")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        // Focus starts in the composer; cleanup must not hand it back there.
        document.getElementById('composer').focus();
        var result = await window.__grockChrome.clickSession('project');
        var fx = window.fixture;
        return {result: result, open: !!document.getElementById('project-picker'),
                focused: document.activeElement.id, escapes: fx.documentEscapes, moved: fx.moved};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["result"] as? String, "opened")
        XCTAssertEqual(result?["open"] as? Bool, true)
        XCTAssertEqual(result?["focused"] as? String, "project-search")
        XCTAssertEqual(result?["escapes"] as? Int, 0)
        XCTAssertEqual(result?["moved"] as? Bool, false)
    }

    func testUnavailableMoveDoesNotInventProjectControls() async throws {
        let fixture = try await fixture(kind: "none")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        var availability = await window.__grockChrome.inspectSessionMenu();
        var result = await window.__grockChrome.clickSession('project');
        return {available: availability.project, result: result,
                picker: !!document.getElementById('project-picker'),
                sourceOpen: !!document.getElementById('menu'),
                suppressed: document.documentElement.hasAttribute('data-grock-picking-menu')};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["available"] as? Bool, false)
        XCTAssertEqual(result?["result"] as? String, "unavailable")
        XCTAssertEqual(result?["picker"] as? Bool, false)
        XCTAssertEqual(result?["sourceOpen"] as? Bool, false)
        XCTAssertEqual(result?["suppressed"] as? Bool, false)
    }

    private func fixture(kind: String) async throws -> (webView: WKWebView, window: NSWindow) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: WebViewStore.chromeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        let loaded = expectation(description: "Local project picker fixture loaded")
        let loader = ProjectPickerLoader(loaded: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(GrokShellFixture.page(
            header: GrokShellFixture.conversationHeader,
            content: GrokShellFixture.transcript + GrokShellFixture.composer,
            outside: GrokShellFixture.conversationMenu(project: kind)
        ), baseURL: URL(string: "https://grok.com/c/fixture"))
        await fulfillment(of: [loaded], timeout: 4)
        if let error = loader.error { throw error }
        return (webView, window)
    }
}

private final class ProjectPickerLoader: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var error: Error?
    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error
        loaded.fulfill()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        loaded.fulfill()
    }
}
