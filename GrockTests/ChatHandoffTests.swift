import AppKit
import WebKit
import XCTest
@testable import Grock

/// Runs the production bridge in a local, nonpersistent WebKit document. No
/// signed-in session or network-backed conversation is involved.
@MainActor
final class ChatHandoffTests: XCTestCase {
    func testMissingSendDoesNotPretendEnterWasAccepted() async throws {
        let fixture = try await fixture(button: "", script: "")
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "no-send")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["draft"] as? String, "Hello Grok")
        XCTAssertEqual(state["enters"] as? Int, 0)
        XCTAssertEqual(WebViewStore.handoffOutcome(result), .notSent)
    }

    func testDisabledSendDoesNotReceiveClickOrEnter() async throws {
        let fixture = try await fixture(button: "<button id='send' disabled>Send</button>")
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "no-send")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 0)
        XCTAssertEqual(state["enters"] as? Int, 0)
    }

    func testIgnoredClickIsUncertainAndDispatchesOnlyOnce() async throws {
        let fixture = try await fixture()
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "uncertain")
        XCTAssertEqual(WebViewStore.handoffOutcome(result), .uncertain)
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 1)
        XCTAssertEqual(state["draft"] as? String, "Hello Grok")
    }

    func testEmptyRemountedComposerAloneIsNotAcceptance() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          document.getElementById('composer').outerHTML = '<textarea id="composer"></textarea>';
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "uncertain")
    }

    func testDelayedMatchingTurnAndConsumedDraftConfirmAcceptance() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          setTimeout(function () {
            document.getElementById('composer').value = '';
            var turn = document.createElement('article');
            turn.dataset.messageAuthorRole = 'user';
            turn.textContent = 'Hello Grok';
            document.body.appendChild(turn);
          }, 120);
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, acceptWaitMS: 600)
        XCTAssertEqual(result, "accepted")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 1)
    }

    func testGenerationAfterComposerRemountConfirmsAcceptance() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          setTimeout(function () {
            document.getElementById('composer').outerHTML = '<textarea id="composer"></textarea>';
            send.textContent = 'Stop generating';
            history.replaceState({}, '', '/c/accepted');
          }, 80);
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, acceptWaitMS: 600)
        XCTAssertEqual(result, "accepted")
    }

    func testNewDraftAfterClickIsNeitherOverwrittenNorCleared() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          document.getElementById('composer').value = 'A new thought';
          send.textContent = 'Stop generating';
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "uncertain")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["draft"] as? String, "A new thought")
    }

    func testBadAttachmentStopsBeforeClick() async throws {
        let fixture = try await fixture()
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, files: [
            ["name": "broken.txt", "mime": "text/plain", "b64": "%%%"]
        ])
        XCTAssertEqual(result, "attachment-failed")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 0)
    }

    func testUnacknowledgedFileInputDoesNotSendPartialPackage() async throws {
        let fixture = try await fixture(extra: "<input type='file'>")
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, files: [file])
        XCTAssertEqual(result, "attachment-unconfirmed")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 0)
    }

    func testAttachmentChipAndEnabledSendAllowOneCompleteSubmission() async throws {
        let fixture = try await fixture(extra: "<input type='file'>", script: """
        send.disabled = true;
        document.querySelector('input').addEventListener('change', function () {
          setTimeout(function () {
            var chip = document.createElement('span');
            chip.textContent = 'notes.txt';
            document.querySelector('form').appendChild(chip);
            send.disabled = false;
          }, 80);
        });
        send.addEventListener('click', function () {
          document.getElementById('composer').value = '';
          send.textContent = 'Stop generating';
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, files: [file], sendWaitMS: 600)
        XCTAssertEqual(result, "accepted")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 1)
    }

    func testNavigationDuringReadinessNeverSendsOnNewRoute() async throws {
        let fixture = try await fixture(button: "<button id='send' disabled>Send</button>", script: """
        document.getElementById('composer').addEventListener('input', function () {
          setTimeout(function () {
            history.replaceState({}, '', '/c/somewhere-else');
            document.getElementById('composer').value = 'Keep this draft';
            send.disabled = false;
          }, 20);
        }, {once:true});
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "navigation-changed")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 0)
        XCTAssertEqual(state["draft"] as? String, "Keep this draft")
    }

    func testCancellationDuringReadinessStopsBeforeSend() async throws {
        let fixture = try await fixture(button: "<button id='send' disabled>Send</button>", script: """
        document.getElementById('composer').addEventListener('input', function () {
          setTimeout(function () {
            \(WebViewStore.cancelComposerOperationScript)
            send.disabled = false;
          }, 20);
        }, {once:true});
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "cancelled")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 0)
    }

    func testCancellationAfterDispatchRequiresReview() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          \(WebViewStore.cancelComposerOperationScript)
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView)
        XCTAssertEqual(result, "uncertain-cancelled")
        XCTAssertEqual(WebViewStore.handoffOutcome(result), .uncertain)
    }

    func testPrefillBoundToAnotherDestinationDoesNotTouchOldComposer() async throws {
        let fixture = try await fixture(script: "document.getElementById('composer').value = 'Old draft';")
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript(
            WebViewStore.fillComposerScript,
            arguments: ["promptText": "New context", "files": [], "operationID": "fill", "expectedPath": "/imagine"],
            in: nil, contentWorld: .page
        )
        XCTAssertEqual(result as? String, "navigation-changed")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["draft"] as? String, "Old draft")
        XCTAssertEqual(state["clicks"] as? Int, 0)
    }

    func testPrefillWaitsForVisibleUploadAcknowledgmentWithoutSending() async throws {
        let fixture = try await fixture(extra: "<input type='file'>", script: """
        document.querySelector('input').addEventListener('change', function () {
          var chip = document.createElement('span');
          chip.textContent = 'notes.txt'; chip.setAttribute('aria-busy', 'true');
          document.querySelector('form').appendChild(chip);
          setTimeout(function () { chip.removeAttribute('aria-busy'); window.uploadReady = true; }, 120);
        });
        """)
        defer { fixture.window.close() }
        let result = try await fixture.webView.callAsyncJavaScript(
            WebViewStore.fillComposerScript,
            arguments: ["promptText": "", "files": [file], "operationID": "file-prefill", "expectedPath": "/",
                        "attachmentWaitMS": 600], in: nil, contentWorld: .page
        )
        XCTAssertEqual(result as? String, "filled")
        let ready = try await fixture.webView.evaluateJavaScript("window.uploadReady")
        XCTAssertEqual(ready as? Bool, true)
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["draft"] as? String, "")
        XCTAssertEqual(state["clicks"] as? Int, 0)
        XCTAssertEqual(state["enters"] as? Int, 0)
    }

    func testIgnoredPrefillUploadIsRecoverableAndRetriesInFreshDocument() async throws {
        let fixture = try await fixture(extra: "<input type='file'>", script: """
        window.fileDispatches = 0;
        document.querySelector('input').addEventListener('change', function () {
          window.fileDispatches++;
          setTimeout(function () { document.getElementById('composer').value = 'My newer draft'; }, 20);
        });
        """)
        defer { fixture.window.close() }
        // Short enough to fail the ignored upload quickly, long enough that
        // the retry's real upload lands in time on a slow CI runner. The same
        // window applies to both attempts; 220ms flaked there.
        let store = WebViewStore(webView: fixture.webView, attachmentWaitMilliseconds: 1_000)
        let attachment = QuickChatAttachment(filename: "notes.txt", mimeType: "text/plain", data: Data("saved notes".utf8))
        store.fillComposer(text: "Keep everything", attachments: [attachment])
        for _ in 0..<120 where store.recoveryState == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(store.recoveryState, .contextNotAdded)
        let dispatches = try await fixture.webView.evaluateJavaScript("window.fileDispatches")
        XCTAssertEqual(dispatches as? Int, 1)
        let before = try await state(fixture.webView)
        XCTAssertEqual(before["clicks"] as? Int, 0)
        let state = try await completeLocalRetry(store)
        XCTAssertEqual(state["draft"] as? String, "My newer draft")
        XCTAssertEqual(state["filename"] as? String, "notes.txt")
        XCTAssertEqual(state["bytes"] as? String, "saved notes")
        XCTAssertEqual(state["files"] as? Int, 1)
        XCTAssertEqual(state["fileDispatches"] as? Int, 1)
        XCTAssertEqual(state["sends"] as? Int, 0)
    }

    func testFreshSessionWaitsForOldComposerToLeaveAfterSPARouteChange() async throws {
        let fixture = try await fixture(script: """
        window.__grockPreviousComposer = document.getElementById('composer');
        history.replaceState({}, '', '/');
        """)
        defer { fixture.window.close() }
        let script = WebViewStore.composerReadyScript(pathBefore: "/c/old")
        let oldReady = try await fixture.webView.evaluateJavaScript(script)
        XCTAssertEqual(oldReady as? Bool, false)
        _ = try await fixture.webView.evaluateJavaScript("document.getElementById('composer').outerHTML = '<textarea id=\"composer\"></textarea>'")
        let freshReady = try await fixture.webView.evaluateJavaScript(script)
        XCTAssertEqual(freshReady as? Bool, true)
    }

    func testNavigationFailureKeepsPrefillForExplicitRetry() async throws {
        let fixture = try await fixture(extra: "<input type='file'>")
        defer { fixture.window.close() }
        let store = WebViewStore(webView: fixture.webView)
        let attachment = QuickChatAttachment(filename: "notes.txt", mimeType: "text/plain", data: Data("saved notes".utf8))
        store.fillComposer(text: "Keep my context", attachments: [attachment])
        store.handleNavigationFailed(error: URLError(.notConnectedToInternet))
        XCTAssertNotNil(store.recoveryState)
        fixture.window.makeFirstResponder(nil)
        store.focusInput()
        XCTAssertFalse(fixture.window.firstResponder === fixture.webView)

        let state = try await completeLocalRetry(store)
        XCTAssertEqual(state["draft"] as? String, "Keep my context")
        XCTAssertEqual(state["filename"] as? String, "notes.txt")
        XCTAssertEqual(state["bytes"] as? String, "saved notes")
        XCTAssertEqual(state["sends"] as? Int, 0)
    }

    func testJavaScriptPrefillFailureKeepsContextForExplicitRetry() async throws {
        let fixture = try await fixture(script: """
        Object.defineProperty(window, '__grockComposerOperation', {
          get: function () { throw new Error('Fixture bridge failure'); }, configurable: true
        });
        """)
        defer { fixture.window.close() }
        let store = WebViewStore(webView: fixture.webView)
        store.fillComposer(text: "Still here")
        for _ in 0..<40 where store.recoveryState == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(store.recoveryState, .contextNotAdded)
        let state = try await completeLocalRetry(store)
        XCTAssertEqual(state["draft"] as? String, "Still here")
        XCTAssertEqual(state["sends"] as? Int, 0)
    }

    func testDifferentNavigationCancelsRecoverablePrefill() async throws {
        let fixture = try await fixture()
        defer { fixture.window.close() }
        let store = WebViewStore(webView: fixture.webView)
        let token = store.composerFillToken
        store.fillComposer(text: "Superseded context")
        store.handleNavigationFailed(error: URLError(.notConnectedToInternet))
        store.handlePageURLChanged(URL(string: "https://grok.com/imagine")!)
        store.fillComposer(text: "Late result from superseded intake", expectedGeneration: token)
        let state = try await completeLocalRetry(store)
        XCTAssertEqual(state["draft"] as? String, "")
        XCTAssertEqual(state["sends"] as? Int, 0)
    }

    func testIntakeFinishingAfterNavigationFailureWaitsForExplicitRetry() async throws {
        let fixture = try await fixture()
        defer { fixture.window.close() }
        let store = WebViewStore(webView: fixture.webView)
        store.startNewChat()
        let token = store.composerFillToken
        store.handleNavigationFailed(error: URLError(.notConnectedToInternet))
        let attachment = QuickChatAttachment(filename: "late.txt", mimeType: "text/plain", data: Data("late bytes".utf8))
        store.fillComposer(text: "Loaded after failure", attachments: [attachment], expectedGeneration: token)
        let beforeRetry = try await state(fixture.webView)
        XCTAssertEqual(beforeRetry["draft"] as? String, "")
        XCTAssertNotNil(store.recoveryState)
        let state = try await completeLocalRetry(store)
        XCTAssertEqual(state["draft"] as? String, "Loaded after failure")
        XCTAssertEqual(state["filename"] as? String, "late.txt")
        XCTAssertEqual(state["bytes"] as? String, "late bytes")
        XCTAssertEqual(state["sends"] as? Int, 0)
    }

    /// grok.com's bubble reads "You" to a screen reader ahead of the text, so
    /// only the text span matches what was sent.
    func testNewTurnInGrokMessageBubbleConfirmsAcceptance() async throws {
        let fixture = try await fixture(script: """
        send.addEventListener('click', function () {
          setTimeout(function () {
            document.getElementById('composer').value = '';
            var turn = document.createElement('div');
            turn.setAttribute('role', 'article');
            turn.setAttribute('data-testid', 'user-message');
            turn.innerHTML = '<h2>You</h2><span data-bubble-text></span>';
            turn.querySelector('[data-bubble-text]').textContent = 'Hello Grok';
            document.body.appendChild(turn);
          }, 120);
        });
        """)
        defer { fixture.window.close() }
        let result = try await submit(fixture.webView, acceptWaitMS: 600)
        XCTAssertEqual(result, "accepted")
        let state = try await state(fixture.webView)
        XCTAssertEqual(state["clicks"] as? Int, 1)
    }

    /// `/imagine` lands on the start page with an Imagine chip in the ordinary
    /// composer. A fill meant for Imagine waits for that chip, then goes in
    /// after it.
    func testImagineFillWaitsForTheCommandChipAndKeepsIt() async throws {
        let fixture = try await editableFixture(content: "<p><br></p>")
        defer { fixture.window.close() }
        let early = try await fill(fixture.webView, text: "A red fox", keepCommand: true)
        XCTAssertEqual(early, "no-composer")
        let untouched = try await editableState(fixture.webView)
        XCTAssertEqual(untouched["text"] as? String, "")

        _ = try await fixture.webView.callAsyncJavaScript(
            "document.getElementById('composer').innerHTML = chip;",
            arguments: ["chip": Self.imagineChip], in: nil, contentWorld: .page
        )
        let filled = try await fill(fixture.webView, text: "A red fox", keepCommand: true)
        XCTAssertEqual(filled, "filled")
        let state = try await editableState(fixture.webView)
        XCTAssertEqual(state["chip"] as? String, "Imagine")
        let text = try XCTUnwrap(state["text"] as? String)
        XCTAssertTrue(text.hasPrefix("Imagine"), text)
        XCTAssertTrue(text.hasSuffix("A red fox"), text)
        XCTAssertEqual(state["clicks"] as? Int, 0)
    }

    func testOrdinaryFillReplacesTheDraftAndAnyCommandChip() async throws {
        for keepCommand in [nil, false] as [Bool?] {
            let fixture = try await editableFixture(content: Self.imagineChip + "<p>Old draft</p>")
            defer { fixture.window.close() }
            let result = try await fill(fixture.webView, text: "A red fox", keepCommand: keepCommand)
            XCTAssertEqual(result, "filled")
            let state = try await editableState(fixture.webView)
            XCTAssertEqual(state["chip"] as? String, "", "keepCommand=\(String(describing: keepCommand))")
            XCTAssertEqual(state["text"] as? String, "A red fox", "keepCommand=\(String(describing: keepCommand))")
            XCTAssertEqual(state["clicks"] as? Int, 0)
        }
    }

    /// Cancels the remote Retry request before it loads, then supplies another
    /// local document at that destination. This exercises the native retained
    /// package and actual prefill script without contacting grok.com.
    private func completeLocalRetry(_ store: WebViewStore) async throws -> [String: Any] {
        let requested = expectation(description: "Retry chose its recorded destination")
        let loaded = expectation(description: "Local retry document loaded")
        let loader = HandoffRetryLoader(requested: requested, loaded: loaded)
        let webView = store.webView
        webView.navigationDelegate = loader
        store.reload()
        await fulfillment(of: [requested], timeout: 4)
        XCTAssertEqual(loader.requestedURL?.host, "grok.com")
        XCTAssertEqual(loader.requestedURL?.path ?? "", "/")
        webView.loadHTMLString("""
        <!doctype html><html><body><form onsubmit="return false">
        <textarea id="composer" style="width:320px;height:70px"></textarea><input type="file">
        <button type="button" onclick="window.sends++">Send</button>
        </form><script>
        window.sends = 0; window.fileDispatches = 0;
        document.querySelector('input').addEventListener('change', function () {
          window.fileDispatches++;
          Array.from(this.files).forEach(function (file) {
            var chip = document.createElement('span'); chip.textContent = file.name;
            document.querySelector('form').appendChild(chip);
          });
        });
        </script></body></html>
        """, baseURL: URL(string: "https://grok.com/"))
        await fulfillment(of: [loaded], timeout: 4)
        store.handleNavigationFinished()
        for _ in 0..<80 where store.showsLaunchLoading || store.isFillingComposer {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(store.isFillingComposer)
        XCTAssertNil(store.recoveryState)
        let result = try await webView.callAsyncJavaScript("""
        var input = document.querySelector('input');
        return {draft: document.getElementById('composer').value, sends: window.sends,
                files: input.files.length, fileDispatches: window.fileDispatches,
                filename: input.files.length ? input.files[0].name : '',
                bytes: input.files.length ? await input.files[0].text() : ''};
        """, in: nil, contentWorld: .page)
        return try XCTUnwrap(result as? [String: Any])
    }

    private var file: [String: Any] {
        ["name": "notes.txt", "mime": "text/plain", "b64": Data("notes".utf8).base64EncodedString()]
    }

    private func submit(
        _ webView: WKWebView,
        files: [[String: Any]] = [],
        sendWaitMS: Int = 220,
        acceptWaitMS: Int = 220
    ) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            WebViewStore.submitPayloadScript,
            arguments: ["promptText": "Hello Grok", "files": files, "operationID": UUID().uuidString,
                        "expectedPath": "/", "sendWaitMS": sendWaitMS, "acceptWaitMS": acceptWaitMS],
            in: nil, contentWorld: .page
        )
        return result as? String ?? "unexpected"
    }

    private static let imagineChip = """
    <p><span contenteditable="false"><span data-composer-command data-composer-chip>Imagine</span></span> </p>
    """

    private func fill(_ webView: WKWebView, text: String, keepCommand: Bool?) async throws -> String {
        var arguments: [String: Any] = [
            "promptText": text, "files": [], "operationID": UUID().uuidString,
            "expectedPath": "/", "attachmentWaitMS": 200
        ]
        if let keepCommand { arguments["keepCommand"] = keepCommand }
        let result = try await webView.callAsyncJavaScript(
            WebViewStore.fillComposerScript, arguments: arguments, in: nil, contentWorld: .page
        )
        return result as? String ?? "unexpected"
    }

    private func editableState(_ webView: WKWebView) async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript("""
        (function () {
          var composer = document.getElementById('composer');
          var chip = composer.querySelector('[data-composer-command]');
          return {clicks: window.clicks, chip: chip ? chip.textContent : '',
                  text: composer.textContent.split(String.fromCharCode(160)).join(' ').split(' ').filter(Boolean).join(' ')};
        })()
        """)
        return try XCTUnwrap(result as? [String: Any])
    }

    /// The composer as grok.com builds it: a rich-text box, not a textarea.
    private func editableFixture(content: String) async throws -> (webView: WKWebView, window: NSWindow) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        let loaded = expectation(description: "Local rich-text composer fixture loaded")
        let loader = ChatHandoffLoader(loaded: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString("""
        <!doctype html><html><body><form data-composer onsubmit="return false">
          <div id="composer" contenteditable="true" role="textbox" aria-label="Message Grok"
               style="width:320px;min-height:70px">\(content)</div>
          <button id="send" type="button" style="min-width:80px;min-height:24px">Send</button>
        </form><script>
        window.clicks = 0;
        document.getElementById('send').addEventListener('click', function () { window.clicks++; });
        </script></body></html>
        """, baseURL: URL(string: "https://grok.com/"))
        await fulfillment(of: [loaded], timeout: 4)
        if let error = loader.error { throw error }
        return (webView, window)
    }

    private func state(_ webView: WKWebView) async throws -> [String: Any] {
        let result = try await webView.evaluateJavaScript("""
        ({clicks: window.clicks, enters: window.enters,
          draft: document.getElementById('composer').value})
        """)
        return try XCTUnwrap(result as? [String: Any])
    }

    private func fixture(
        button: String = "<button id='send' type='button'>Send</button>",
        extra: String = "",
        script: String = ""
    ) async throws -> (webView: WKWebView, window: NSWindow) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        let loaded = expectation(description: "Local chat handoff fixture loaded")
        let loader = ChatHandoffLoader(loaded: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString("""
        <!doctype html><html><head><style>
        textarea { width: 320px; height: 70px; } button { min-width: 80px; min-height: 24px; }
        </style></head><body><form onsubmit="return false">
          <textarea id="composer"></textarea>\(button)\(extra)
        </form><script>
        window.clicks = 0; window.enters = 0;
        var send = document.getElementById('send');
        if (send) send.addEventListener('click', function () { window.clicks++; });
        document.addEventListener('keydown', function (event) { if (event.key === 'Enter') window.enters++; });
        \(script)
        </script></body></html>
        """, baseURL: URL(string: "https://grok.com/"))
        await fulfillment(of: [loaded], timeout: 4)
        if let error = loader.error { throw error }
        return (webView, window)
    }
}

private final class ChatHandoffLoader: NSObject, WKNavigationDelegate {
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

private final class HandoffRetryLoader: NSObject, WKNavigationDelegate {
    let requested: XCTestExpectation
    let loaded: XCTestExpectation
    var requestedURL: URL?

    init(requested: XCTestExpectation, loaded: XCTestExpectation) {
        self.requested = requested
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if requestedURL == nil {
            requestedURL = navigationAction.request.url
            decisionHandler(.cancel)
            requested.fulfill()
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
