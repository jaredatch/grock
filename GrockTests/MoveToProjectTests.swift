import AppKit
import WebKit
import XCTest
@testable import Grock

@MainActor
final class MoveToProjectTests: XCTestCase {
    func testSubmenuSurvivesNativeMenuHandoffAndWaitsForUserChoice() async throws {
        let fixture = try await fixture(kind: "submenu")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        var availability = await window.__grockChrome.inspectSessionMenu();
        var result = await window.__grockChrome.clickSession('project');
        var picker = document.getElementById('projects');
        return {available: availability.project, result: result, open: picker.dataset.state === 'open',
                visible: getComputedStyle(picker).opacity !== '0', top: picker.getBoundingClientRect().top,
                focused: document.activeElement.id, moved: window.moved,
                suppressed: document.documentElement.hasAttribute('data-grock-picking-menu')};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["available"] as? Bool, true)
        XCTAssertEqual(result?["result"] as? String, "opened")
        XCTAssertEqual(result?["open"] as? Bool, true)
        XCTAssertEqual(result?["visible"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(result?["top"] as? Double ?? 0, 52)
        XCTAssertEqual(result?["focused"] as? String, "project-choice")
        XCTAssertEqual(result?["moved"] as? Bool, false)
        XCTAssertEqual(result?["suppressed"] as? Bool, false)
    }

    func testDialogPickerRetainsFocusAndIsNotDismissedByCleanup() async throws {
        let fixture = try await fixture(kind: "dialog")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        var result = await window.__grockChrome.clickSession('project');
        var picker = document.getElementById('projects');
        return {result: result, open: picker.dataset.state === 'open',
                focused: document.activeElement.id, escapes: window.pickerEscapes, moved: window.moved};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["result"] as? String, "opened")
        XCTAssertEqual(result?["open"] as? Bool, true)
        XCTAssertEqual(result?["focused"] as? String, "project-choice")
        XCTAssertEqual(result?["escapes"] as? Int, 0)
        XCTAssertEqual(result?["moved"] as? Bool, false)
    }

    func testUnavailableMoveDoesNotInventProjectControls() async throws {
        let fixture = try await fixture(kind: "missing")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript("""
        var availability = await window.__grockChrome.inspectSessionMenu();
        var result = await window.__grockChrome.clickSession('project');
        return {available: availability.project, result: result,
                picker: !!document.getElementById('projects'),
                sourceOpen: document.getElementById('more').getAttribute('aria-expanded') === 'true'};
        """, in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["available"] as? Bool, false)
        XCTAssertEqual(result?["result"] as? String, "unavailable")
        XCTAssertEqual(result?["picker"] as? Bool, false)
        XCTAssertEqual(result?["sourceOpen"] as? Bool, false)
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
        webView.loadHTMLString("""
        <!doctype html><html><body style="margin:0">
        <div id="grok-app-root"><main id="grok-content-area" style="height:600px;width:800px;position:relative">
          <div class="absolute inset-x-0 top-0 z-10 flex h-14" style="position:absolute;top:0;right:0;left:0;height:56px;display:flex;justify-content:flex-end">
            <div class="flex flex-row items-center" style="display:flex;gap:6px">
              <button id="more" type="button" aria-label="More" aria-haspopup="menu" aria-expanded="false"></button>
              <button aria-label="Create share link"></button>
              <div class="h-8 shrink-0 overflow-hidden pointer-events-none"></div>
            </div>
          </div>
          <textarea id="composer"></textarea>
        </main></div>
        <script>
        var kind = '\(kind)', popup = null;
        window.moved = false; window.pickerEscapes = 0;
        function closeSource() {
          if (popup) popup.dataset.state = 'closed';
          document.getElementById('more').setAttribute('aria-expanded', 'false');
        }
        document.addEventListener('keydown', function (event) {
          if (event.key !== 'Escape') return;
          var picker = document.getElementById('projects');
          if (picker && picker.dataset.state === 'open') { picker.dataset.state = 'closed'; window.pickerEscapes++; }
          else closeSource();
        });
        function openPicker() {
          if (kind === 'dialog') closeSource();
          var picker = document.createElement('div');
          picker.id = 'projects'; picker.dataset.state = 'open';
          picker.setAttribute('role', kind === 'dialog' ? 'dialog' : 'menu');
          picker.setAttribute('aria-labelledby', 'move-project');
          var choice = document.createElement('button');
          choice.id = 'project-choice'; choice.textContent = 'Example project';
          choice.addEventListener('click', function () { window.moved = true; picker.dataset.state = 'closed'; closeSource(); });
          picker.appendChild(choice); document.body.appendChild(picker); choice.focus();
        }
        document.getElementById('more').addEventListener('pointerdown', function () {
          if (popup) popup.remove();
          popup = document.createElement('div');
          popup.setAttribute('role', 'menu'); popup.setAttribute('aria-labelledby', 'more'); popup.dataset.state = 'open';
          document.getElementById('more').setAttribute('aria-expanded', 'true');
          if (kind !== 'missing') {
            var move = document.createElement('button');
            move.id = 'move-project'; move.setAttribute('role', 'menuitem'); move.textContent = 'Move to project';
            if (kind === 'submenu') {
              move.setAttribute('aria-haspopup', 'menu');
              move.addEventListener('keydown', function (event) { if (event.key === 'ArrowRight') openPicker(); });
            } else move.addEventListener('click', openPicker);
            popup.appendChild(move);
          }
          document.body.appendChild(popup);
        });
        </script></body></html>
        """, baseURL: URL(string: "https://grok.com/c/fixture"))
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
