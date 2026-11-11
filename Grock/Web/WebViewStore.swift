import AppKit
import QuartzCore
import WebKit

// MARK: - Conversation session actions (DEC-055)

/// grok.com's More / Share / Build-panel cluster on `/c/…`. Native titlebar
/// owns those once the page script has marked the cluster.
struct SessionActions: Equatable {
    var more = false
    var share = false
    var panel = false

    var showsToolbar: Bool { more || share || panel }
    var showsMore: Bool { more || panel }

    static func from(_ body: [String: Any]) -> SessionActions {
        SessionActions(
            more: Self.flag(body["more"]),
            share: Self.flag(body["share"]),
            panel: Self.flag(body["panel"])
        )
    }

    private static func flag(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}

/// Page → native: the conversation action cluster appeared or left.
final class SessionActionsBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let channelName = "grockSession"

    weak var expectedWebView: WKWebView?
    var handler: ((WKWebView?, [String: Any]) -> Void)?

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
            self.handler?(message.webView, body)
        }
        replyHandler(["ok": true], nil)
    }
}

/// Only an observed Grok acceptance clears a native package. An ambiguous result
/// requires review before the user deliberately retries it.
enum ChatHandoffOutcome: Equatable {
    case accepted
    case notSent
    case uncertain
}

// MARK: - Shared store

/// Single owner of the WKWebView session. Overlay and any future companion share this instance.
@MainActor
final class WebViewStore {
    static let shared = WebViewStore()

    static let homeURL = URL(string: "https://grok.com?referrer=grock-macos")!

    let webView: WKWebView
    private let webViewDelegate = WebViewDelegate()
    private let downloadBridge = DownloadBridge()
    private let replyBridge = ReplyBridge()
    private let sessionBridge = SessionActionsBridge()
    /// Live More / Share / panel controls on the current grok.com chat.
    private(set) var sessionActions = SessionActions()
    /// Fail closed until the main grok.com surface reports that Sign in is gone.
    private(set) var isSignedIn = false
    private var pendingFocusInput = false
    private var pendingEnterVoice = false
    private var pendingPayload: QuickChatPayload?
    private var pendingPayloadCompletion: ((ChatHandoffOutcome) -> Void)?
    private var payloadSubmitGeneration = 0
    private var fillComposerGeneration = 0
    private var composerIntakeGeneration = 0
    private var attachmentWaitMilliseconds = 12_000
    private var payloadScriptActive = false
    private var freshSessionInProgress = false
    private var freshSessionLoadAttempts = 0
    private var intendedComposerPath: String?
    private struct ComposerFill {
        let text: String
        let attachments: [QuickChatAttachment]
        let path: String
        let generation: Int
    }
    private var pendingComposerFill: ComposerFill?
    private var activeComposerFill: ComposerFill?
    private var recoverableComposerFill: ComposerFill?
    private var recoveryComposerPath: String?
    /// Last Quick Chat handoff outcome (`accepted`, `uncertain`, `no-composer`, …).
    private(set) var lastPayloadOutcome: String?
    private var waitingForComposer = false
    private var isWebViewCovered = false
    private var freshSessionGeneration = 0
    /// Cold load has not shown a usable grok.com surface yet (DEC-042).
    private(set) var awaitingFirstPaint = true
    private var firstPaintGeneration = 0
    private var revealWork: DispatchWorkItem?
    private(set) var recoveryState: WebRecoveryState? {
        didSet {
            NotificationCenter.default.post(name: .grockRecoveryDidChange, object: nil)
        }
    }

    var showsLaunchLoading: Bool { awaitingFirstPaint }

    /// Isolated lifecycle verification supplies a local, nonpersistent WebView.
    /// The application uses `shared`, whose initializer installs the native bridges.
    init(webView: WKWebView, attachmentWaitMilliseconds: Int = 12_000) {
        self.webView = webView
        self.attachmentWaitMilliseconds = attachmentWaitMilliseconds
        awaitingFirstPaint = false
    }

    private init() {
        Self.keepWebInspectorDetached()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        #if DEBUG
        // `-freshStore YES` runs signed out with nothing saved, to check the
        // logged-out page and sign-in without clearing the real session.
        if UserDefaults.standard.bool(forKey: "freshStore") {
            config.websiteDataStore = .nonPersistent()
        }
        #endif
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        config.userContentController.addScriptMessageHandler(
            downloadBridge,
            contentWorld: .page,
            name: DownloadBridge.channelName
        )
        config.userContentController.addScriptMessageHandler(
            replyBridge,
            contentWorld: .page,
            name: ReplyBridge.channelName
        )
        config.userContentController.addScriptMessageHandler(
            sessionBridge,
            contentWorld: .page,
            name: SessionActionsBridge.channelName
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.edgeFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.edgeFixScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.chromeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: Self.replyObserverScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        #if DEBUG
        if let script = Self.debugPageScript() {
            config.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        }
        #endif

        webViewDelegate.bridge = downloadBridge

        let view = MenuAwareWebView(frame: .zero, configuration: config)
        downloadBridge.expectedWebView = view
        replyBridge.expectedWebView = view
        sessionBridge.expectedWebView = view
        view.bridge = downloadBridge
        view.uiDelegate = webViewDelegate
        view.navigationDelegate = webViewDelegate
        webViewDelegate.overlayWebView = view
        view.focusRingType = .none
        // Safari-like UA reduces some WebView auth friction.
        view.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView = view
        replyBridge.handler = { [weak self] body in
            self?.handleReplyMessage(body)
        }
        sessionBridge.handler = { [weak self] source, body in
            guard let self, source === self.webView else { return }
            self.applyPageState(body)
        }
        applyAppearance(AppearancePreference.current.nsAppearance)
        applyWebInspector()
        applyChrome()
        setWebViewCovered(true)
        loadHome()
        #if DEBUG
        startDebugPageProbe()
        #endif
    }

    func loadHome() {
        webView.load(URLRequest(url: Self.homeURL))
    }

    /// Sign-in pages get a shorter WebView (they start below the titlebar).
    /// A page that loads across that change keeps the old height as `svh` and
    /// `lvh` until the window is next resized. grok.com sizes its shell in
    /// `svh`, so coming back from sign-in left a blank band along the bottom.
    /// Once the page has loaded, make WebKit measure the frame it has now.
    private var viewportUnitsStale = false

    func markViewportUnitsStale() {
        viewportUnitsStale = true
    }

    private func refreshViewportUnitsIfStale() {
        guard viewportUnitsStale else { return }
        viewportUnitsStale = false
        // Setting the same insets again is ignored, so change them and put them back.
        let nudge = NSEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)
        webView.setMinimumViewportInset(nudge, maximumViewportInset: nudge)
        webView.setMinimumViewportInset(NSEdgeInsetsZero, maximumViewportInset: NSEdgeInsetsZero)
    }

    /// Fresh conversation: click grok.com's New Chat when the SPA is warm.
    /// `payload` (DEC-041) fills the composer and submits instead of only focusing.
    func startNewChat(payload: QuickChatPayload? = nil, completion: ((ChatHandoffOutcome) -> Void)? = nil) {
        let cancelledPayload = pendingPayload != nil || pendingPayloadCompletion != nil
        finishPayload(cancelComposerOperations())
        intendedComposerPath = "/"
        pendingEnterVoice = false
        if let payload {
            pendingPayload = payload
            pendingPayloadCompletion = completion
            pendingFocusInput = false
            setWebViewCovered(true)
        } else {
            pendingPayload = nil
            pendingFocusInput = true
            if cancelledPayload {
                revealWebView()
            }
        }
        requestFreshSession()
    }

    /// New chat, then click grok.com's voice-mode control.
    func startNewVoiceChat() {
        let cancelledPayload = pendingPayload != nil || pendingPayloadCompletion != nil
        finishPayload(cancelComposerOperations())
        intendedComposerPath = "/"
        pendingPayload = nil
        pendingFocusInput = false
        pendingEnterVoice = true
        if cancelledPayload {
            revealWebView()
        }
        requestFreshSession()
    }

    func handleNavigationStarted() {
        applySignedInState(false)
        applySessionActions(SessionActions())
        recoveryState = nil
        // A document disappearing during injection is ambiguous. Do not run the
        // payload again in the new document, even if its completion arrives late.
        if payloadScriptActive {
            finishPayload(cancelComposerOperations())
        }
        if let fill = activeComposerFill {
            fillComposerGeneration += 1
            webView.evaluateJavaScript(Self.cancelComposerOperationScript, completionHandler: nil)
            activeComposerFill = nil
            pendingComposerFill = ComposerFill(text: fill.text, attachments: fill.attachments,
                                               path: fill.path, generation: fillComposerGeneration)
        }
        waitingForComposer = false
        if awaitingFirstPaint {
            firstPaintGeneration += 1
        }
        // Full navigation after New Chat (or fallback load): hide the dying page.
        if pendingFocusInput || pendingEnterVoice || pendingPayload != nil || pendingComposerFill != nil {
            setWebViewCovered(true)
        }
    }

    func handleNavigationFinished() {
        recoveryState = nil
        refreshViewportUnitsIfStale()
        applyChrome()
        if pendingPayload != nil {
            waitingForComposer = true
            waitForComposerThenComplete(
                generation: freshSessionGeneration,
                pathBefore: webView.url?.path ?? ""
            )
            return
        }
        if awaitingFirstPaint {
            waitForFirstPaintThenReveal(generation: firstPaintGeneration)
            return
        }
        revealWebView()
        completePendingAction()
        attemptPendingComposerFill()
    }

    func handleNavigationFailed(error: Error) {
        guard let state = WebRecoveryState.navigation(error) else { return }
        presentRecovery(state)
    }

    func handleWebContentProcessTerminated() {
        presentRecovery(.processTerminated)
    }

    private func presentRecovery(_ state: WebRecoveryState) {
        let savedFill = pendingComposerFill ?? activeComposerFill ?? recoverableComposerFill
        let savedPath = intendedComposerPath ?? recoveryComposerPath ?? savedFill?.path
        pendingFocusInput = false
        pendingEnterVoice = false
        waitingForComposer = false
        finishPayload(cancelComposerOperations(preservingIntake: true))
        recoverableComposerFill = savedFill
        recoveryComposerPath = savedPath
        awaitingFirstPaint = false
        firstPaintGeneration += 1
        revealWork?.cancel()
        setWebViewCovered(true)
        isSignedIn = false
        NotificationCenter.default.post(name: .grockAuthenticationDidChange, object: nil)
        NotificationCenter.default.post(name: .grockLaunchLoadingDidChange, object: nil)
        recoveryState = state
    }

    private func waitForFirstPaintThenReveal(generation: Int, tries: Int = 0) {
        webView.evaluateJavaScript(Self.composerPresentScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self, self.awaitingFirstPaint, generation == self.firstPaintGeneration else { return }
                if result as? Bool == true || tries >= 50 {
                    let voice = self.pendingEnterVoice
                    let payload = self.pendingPayload != nil
                    self.revealWebView()
                    self.completePendingAction()
                    if !voice, !payload {
                        self.focusInput()
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard generation == self.firstPaintGeneration else { return }
                    self.waitForFirstPaintThenReveal(generation: generation, tries: tries + 1)
                }
            }
        }
    }

    /// Prefer grok.com's own New Chat. Full load only if the SPA is cold or the control is gone.
    private func requestFreshSession() {
        freshSessionGeneration += 1
        let generation = freshSessionGeneration
        waitingForComposer = false
        freshSessionInProgress = true
        freshSessionLoadAttempts = 0

        guard let url = webView.url, Self.isGrokPage(url) else {
            loadHomeCovered()
            return
        }
        if webView.isLoading {
            if Self.isGrokStartPage(url) {
                setWebViewCovered(true)
                return
            }
            loadHomeCovered()
            return
        }
        // Already on `/`. Clicking New Chat remounts, then often full-loads `/`
        // (href="/", referrer query stripped). Just focus / enter voice.
        // Payload send still waits: the composer may not be in the DOM yet.
        if Self.isGrokStartPage(url) {
            if pendingPayload != nil {
                waitingForComposer = true
                waitForComposerThenComplete(generation: generation, pathBefore: url.path)
            } else {
                completePendingAction()
            }
            return
        }

        let pathBefore = url.path
        webView.evaluateJavaScript(Self.freshSessionScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self, generation == self.freshSessionGeneration else { return }
                let outcome = result as? String ?? "missing"
                switch outcome {
                case "already-fresh":
                    if self.pendingPayload != nil {
                        self.waitingForComposer = true
                        self.waitForComposerThenComplete(
                            generation: generation,
                            pathBefore: pathBefore
                        )
                    } else {
                        self.completePendingAction()
                    }
                case "clicked":
                    self.waitingForComposer = true
                    self.waitForComposerThenComplete(
                        generation: generation,
                        pathBefore: pathBefore
                    )
                default:
                    self.loadHomeCovered()
                }
            }
        }
    }

    private func waitForComposerThenComplete(generation: Int, pathBefore: String, tries: Int = 0) {
        guard generation == freshSessionGeneration, waitingForComposer else { return }
        let readyScript = Self.composerReadyScript(pathBefore: pathBefore)
        webView.evaluateJavaScript(readyScript) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                guard generation == self.freshSessionGeneration, self.waitingForComposer else { return }
                if result as? Bool == true {
                    self.waitingForComposer = false
                    self.completePendingAction()
                    return
                }
                if tries >= 16 {
                    self.waitingForComposer = false
                    self.loadHomeCovered()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.waitForComposerThenComplete(
                        generation: generation,
                        pathBefore: pathBefore,
                        tries: tries + 1
                    )
                }
            }
        }
    }

    private func completePendingAction() {
        freshSessionInProgress = false
        attemptPendingComposerFill()
        if pendingEnterVoice {
            pendingEnterVoice = false
            pendingFocusInput = false
            enterVoiceMode()
            return
        }
        if let payload = pendingPayload, !payloadScriptActive {
            submitPayload(payload)
            return
        }
        guard pendingFocusInput else { return }
        pendingFocusInput = false
        focusInput()
    }

    /// Invalidate Swift retries and the async script running in the current page.
    /// Recovery uses the returned outcome before completing the pending package.
    @discardableResult
    func cancelComposerOperations(preservingIntake: Bool = false) -> ChatHandoffOutcome {
        if !preservingIntake { composerIntakeGeneration += 1 }
        let outcome: ChatHandoffOutcome = payloadScriptActive ? .uncertain : .notSent
        payloadSubmitGeneration += 1
        fillComposerGeneration += 1
        freshSessionGeneration += 1
        payloadScriptActive = false
        waitingForComposer = false
        freshSessionInProgress = false
        intendedComposerPath = nil
        pendingComposerFill = nil
        activeComposerFill = nil
        recoverableComposerFill = nil
        recoveryComposerPath = nil
        webView.evaluateJavaScript(Self.cancelComposerOperationScript, completionHandler: nil)
        return outcome
    }

    /// The navigation delegate calls this only for the shared main frame.
    /// Expected New Chat loads retain their queued fill; another destination cancels it.
    func handleMainFrameNavigation(to url: URL) {
        guard intendedComposerPath != nil || recoveryComposerPath != nil else { return }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let intended = (intendedComposerPath ?? recoveryComposerPath)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if Self.isGrokPage(url), let intended,
           path == intended || path == Self.landingPath(intended) { return }
        finishPayload(cancelComposerOperations())
        pendingFocusInput = false
        pendingEnterVoice = false
    }

    func handlePageURLChanged(_ url: URL?) {
        guard let url, !payloadScriptActive else { return }
        handleMainFrameNavigation(to: url)
    }

    static let cancelComposerOperationScript = """
    if (window.__grockComposerOperation) window.__grockComposerOperation.cancelled = true;
    """

    private func finishPayload(_ outcome: ChatHandoffOutcome) {
        payloadSubmitGeneration += 1
        payloadScriptActive = false
        let done = pendingPayloadCompletion
        pendingPayloadCompletion = nil
        pendingPayload = nil
        done?(outcome)
    }

    static func handoffOutcome(_ result: String) -> ChatHandoffOutcome {
        if result == "accepted" { return .accepted }
        if result.hasPrefix("uncertain") { return .uncertain }
        return .notSent
    }

    /// One dispatch, followed by an observable acceptance signal. A timeout after
    /// dispatch never retries the send and never discards the native package.
    private func submitPayload(_ payload: QuickChatPayload, tries: Int = 0) {
        if tries == 0 {
            payloadSubmitGeneration += 1
            lastPayloadOutcome = nil
        }
        let generation = payloadSubmitGeneration
        if let error = payload.validationError {
            lastPayloadOutcome = error
            revealWebView()
            finishPayload(.notSent)
            return
        }
        guard Self.isGrokStartPage(webView.url), !webView.isLoading else {
            lastPayloadOutcome = "navigation-changed"
            revealWebView()
            finishPayload(.notSent)
            return
        }
        let files = payload.attachments.map { attachment -> [String: Any] in
            ["name": attachment.filename, "mime": attachment.mimeType,
             "b64": attachment.data.base64EncodedString()]
        }
        payloadScriptActive = true
        let arguments: [String: Any] = [
            "promptText": payload.promptForSubmit, "files": files,
            "operationID": UUID().uuidString, "expectedPath": webView.url?.path ?? "/",
            "sendWaitMS": 12_000, "acceptWaitMS": 10_000
        ]
        if let window = webView.window { window.makeFirstResponder(webView) }
        webView.callAsyncJavaScript(
            Self.submitPayloadScript, arguments: arguments, in: nil, in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.payloadSubmitGeneration else { return }
                self.payloadScriptActive = false
                let detail: String
                switch result {
                case .success(let value):
                    detail = value as? String ?? "uncertain-result"
                    // This is the only safe retry: no composer means no mutation
                    // or attachment/submit event has happened in this attempt.
                    if detail == "no-composer", tries < 10 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            guard generation == self.payloadSubmitGeneration else { return }
                            self.submitPayload(payload, tries: tries + 1)
                        }
                        return
                    }
                case .failure:
                    // WebKit may lose the reply after Grok accepts a send.
                    detail = "uncertain-script"
                }
                self.lastPayloadOutcome = detail
                let outcome = Self.handoffOutcome(detail)
                self.revealWebView()
                if outcome == .accepted { self.focusInput() }
                self.finishPayload(outcome)
            }
        }
    }

    private func loadHomeCovered() {
        waitingForComposer = false
        guard freshSessionLoadAttempts < 1 else {
            lastPayloadOutcome = "no-composer"
            freshSessionInProgress = false
            pendingFocusInput = false
            pendingEnterVoice = false
            finishPayload(.notSent)
            revealWebView()
            return
        }
        freshSessionLoadAttempts += 1
        setWebViewCovered(true)
        loadHome()
    }

    private func revealWebView() {
        let fromLoader = awaitingFirstPaint
        awaitingFirstPaint = false
        if fromLoader {
            revealAfterLaunchLoading()
        } else {
            setWebViewCovered(false)
            NotificationCenter.default.post(name: .grockLaunchLoadingDidChange, object: nil)
        }
    }

    /// Fade the orbit out on the backdrop, then ease grok.com in. WKWebView's
    /// remote layer paints over siblings, so a true crossfade is not available.
    private func revealAfterLaunchLoading() {
        NotificationCenter.default.post(name: .grockLaunchLoadingDidChange, object: nil)
        revealWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fadeInWebView()
        }
        revealWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LaunchLoadingLayout.hideDuration,
            execute: work
        )
    }

    private func fadeInWebView() {
        guard recoveryState == nil else { return }
        isWebViewCovered = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LaunchLoadingLayout.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            webView.animator().alphaValue = 1
        }
        if pendingFocusInput, pendingPayload == nil, !pendingEnterVoice { focusInput() }
    }

    /// Panel may not exist yet when we cover. Re-apply after it is on screen.
    func resignIfCovered() {
        guard isWebViewCovered else { return }
        setWebViewCovered(true)
        if showsLaunchLoading {
            NotificationCenter.default.post(name: .grockLaunchLoadingDidChange, object: nil)
        }
    }

    private func setWebViewCovered(_ covered: Bool) {
        isWebViewCovered = covered
        webView.alphaValue = covered ? 0 : 1
        if covered, let window = webView.window {
            if let responder = window.firstResponder as? NSView,
               responder === webView || responder.isDescendant(of: webView) {
                window.makeFirstResponder(nil)
            }
        }
    }

    static func isGrokPage(_ url: URL?) -> Bool {
        NavigationPolicy.isGrokHost(url?.host)
    }

    static func isGrokStartPage(_ url: URL?) -> Bool {
        guard isGrokPage(url), let url else { return false }
        return url.path.isEmpty || url.path == "/"
    }

    /// Where a requested composer path ends up, without slashes. grok.com
    /// folded Imagine into the start page: `/imagine` lands on `/` with an
    /// Imagine chip already in the composer.
    static func landingPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed == "imagine" ? "" : trimmed
    }

    func reload() {
        if recoveryState != nil {
            let savedFill = recoverableComposerFill
            let savedPath = recoveryComposerPath ?? savedFill?.path
            cancelComposerOperations(preservingIntake: true)
            recoveryState = nil
            awaitingFirstPaint = true
            firstPaintGeneration += 1
            setWebViewCovered(true)
            NotificationCenter.default.post(name: .grockLaunchLoadingDidChange, object: nil)
            if let savedPath,
               let url = URL(string: "https://grok.com" + (savedPath.isEmpty ? "/" : savedPath)) {
                // Only the user's Retry replays retained context, after a fresh
                // document at the original destination has loaded. Never send.
                intendedComposerPath = savedPath
                if let savedFill {
                    pendingComposerFill = ComposerFill(
                        text: savedFill.text, attachments: savedFill.attachments,
                        path: savedFill.path, generation: fillComposerGeneration
                    )
                }
                webView.load(URLRequest(url: url))
                return
            }
        }
        if webView.url == nil { loadHome() }
        else { webView.reload() }
    }

    func openCurrentPageInBrowser() {
        let url = webView.url ?? Self.homeURL
        NSWorkspace.shared.open(url)
    }

    /// Current grok.com URL (home if the view has not loaded yet).
    var currentPageURL: URL {
        webView.url ?? Self.homeURL
    }

    @discardableResult
    func copyCurrentPageURL() -> URL {
        let url = currentPageURL
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        return url
    }

    /// Nuclear option for auth / stuck session gremlins.
    func clearWebsiteData(completion: (() -> Void)? = nil) {
        let store = webView.configuration.websiteDataStore
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor in
                self?.loadHome()
                completion?()
            }
        }
    }

    /// Click grok.com's voice control. Works even if Appearance hid the button.
    func enterVoiceMode() {
        webView.evaluateJavaScript(Self.enterVoiceScript, completionHandler: nil)
    }

    func handleReplyMessage(_ body: [String: Any]) {
        guard let kind = body["kind"] as? String else { return }
        if kind == "state" {
            let generating: Bool
            if let value = body["generating"] as? Bool {
                generating = value
            } else if let value = body["generating"] as? NSNumber {
                generating = value.boolValue
            } else {
                return
            }
            NSLog("[Grock] reply generating=\(generating)")
            return
        }
        guard kind == "landed" else { return }
        NotificationCenter.default.post(name: .grockReplyLanded, object: nil)
    }

    /// Last assistant turn, with the titlebar offset so the start is not under the bar.
    func scrollToUnreadAnswer() {
        webView.evaluateJavaScript(
            "window.__grockReply && window.__grockReply.scrollToAnswer()",
            completionHandler: nil
        )
    }

    static let enterVoiceScript = """
    (function () {
      var tries = 0;
      function attempt() {
        var btn = document.querySelector(
          'form[data-composer] button[data-composer-action="voice"],'
          + 'button[aria-label="Voice mode"], button[aria-label^="Enter voice mode"]'
        );
        if (btn) {
          btn.click();
          return;
        }
        tries += 1;
        if (tries < 20) setTimeout(attempt, 250);
      }
      attempt();
    })();
    """

    /// Click grok.com's New chat, or report that the start page is already blank.
    /// Do not open Search to get there: it flashes the command menu.
    /// Order: the sidebar's New chat row, then any nav control with that exact
    /// label. "New chat in <project>" is a different button and never matches.
    static let freshSessionScript = """
    (function () {
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }
      function hostOk() {
        var host = String(location.hostname || '').toLowerCase();
        return host === 'grok.com' || host.slice(-9) === '.grok.com';
      }
      function startPath() {
        var path = location.pathname;
        return path === '/' || path === '';
      }
      // A sidebar row's text also holds its keyboard shortcut. The label is
      // in its own span.
      function labelOf(el) {
        var span = el.querySelector('[data-sidebar-item-label]');
        return norm(el.getAttribute('aria-label') || el.getAttribute('title')
          || (span ? span.textContent : el.textContent)).toLowerCase();
      }
      function isNewChat(el) {
        var label = labelOf(el);
        return label === 'new chat' || label === 'create new chat';
      }
      if (!hostOk()) return 'missing';
      // Path `/` is already a new chat. Do not click New chat: grok.com
      // remounts the composer for nothing.
      if (startPath()) return 'already-fresh';
      window.__grockPreviousPath = location.pathname;
      window.__grockPreviousComposer = document.querySelector('textarea, [contenteditable], [role="textbox"]');

      var rows = document.querySelectorAll('#app-sidebar button, #app-sidebar a');
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].querySelector('[data-sidebar-item-label]') && isNewChat(rows[i])) {
          rows[i].click();
          return 'clicked';
        }
      }
      var nodes = document.querySelectorAll(
        '#app-sidebar a, #app-sidebar button, nav a, nav button, aside a, aside button, header a, header button'
      );
      for (var j = 0; j < nodes.length; j++) {
        if (nodes[j].closest('[aria-label="Right pane"]')) continue;
        if (isNewChat(nodes[j])) {
          nodes[j].click();
          return 'clicked';
        }
      }
      return 'missing';
    })();
    """

    /// Payload inject only needs the composer mounted, not a blank new thread.
    static let composerPresentScript = """
    (function () {
      var nodes = document.querySelectorAll(
        'textarea, [contenteditable="true"], [contenteditable=""], [contenteditable], [role="textbox"]'
      );
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.disabled || el.getAttribute('contenteditable') === 'false') continue;
        if (el.closest('[role="dialog"], [role="search"], nav, aside')) continue;
        var style = window.getComputedStyle(el);
        if (!style || style.display === 'none' || style.visibility === 'hidden') continue;
        if (parseFloat(style.opacity) === 0) continue;
        var box = el.getBoundingClientRect();
        if (box.width >= 8 && box.height >= 8) return true;
      }
      return false;
    })();
    """

    static func composerReadyScript(pathBefore: String) -> String {
        let escaped = pathBefore
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function () {
          var oldPath = '\(escaped)';
          if (location.pathname !== '/' && location.pathname !== '') return false;
          var previous = window.__grockPreviousComposer;
          if (oldPath !== '/' && oldPath !== '' && previous && previous.isConnected) return false;
          return \(composerPresentScript.trimmingCharacters(in: CharacterSet(charactersIn: ";\n ")));
        })();
        """
    }

    /// Focus Grok's input so typing works immediately after summon.
    func focusInput() {
        guard recoveryState == nil else { return }
        guard !isWebViewCovered else {
            pendingFocusInput = true
            return
        }
        pendingFocusInput = false
        if let window = webView.window {
            window.makeFirstResponder(webView)
        }
        webView.evaluateJavaScript(Self.focusInputScript, completionHandler: nil)
    }

    /// Toolbar New Chat steals first responder. grok.com also remounts the
    /// composer, so one shot on `textarea` often misses. Retry, and take
    /// `[contenteditable]` without a true-value (DEC-038).
    static let focusInputScript = """
    (function () {
      function find() {
        var nodes = document.querySelectorAll(
          'textarea, [contenteditable="true"], [contenteditable=""], [contenteditable], [role="textbox"]'
        );
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var style = window.getComputedStyle(el);
          if (!style || style.display === 'none' || style.visibility === 'hidden') continue;
          if (parseFloat(style.opacity) === 0) continue;
          var box = el.getBoundingClientRect();
          if (box.width < 8 || box.height < 8) continue;
          return el;
        }
        return null;
      }
      function attempt(tries) {
        var el = find();
        if (el) {
          try { el.focus(); } catch (err) {}
          return;
        }
        if (tries < 16) setTimeout(function () { attempt(tries + 1); }, 80);
      }
      attempt(0);
    })();
    """

    /// Shared by send (`submitPayloadScript`) and fill-without-send (`fillComposerScript`).
    static let composerHelperScript = """
    function grockFindComposer() {
      var nodes = document.querySelectorAll(
        'textarea, [contenteditable="true"], [contenteditable=""], [contenteditable], [role="textbox"]'
      );
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.disabled || el.getAttribute('contenteditable') === 'false') continue;
        if (el.closest('[role="dialog"], [role="search"], nav, aside')) continue;
        var style = window.getComputedStyle(el);
        if (!style || style.display === 'none' || style.visibility === 'hidden') continue;
        if (parseFloat(style.opacity) === 0) continue;
        var box = el.getBoundingClientRect();
        if (box.width < 8 || box.height < 8) continue;
        return el;
      }
      return null;
    }
    // An Imagine composer starts with a command chip. Selecting everything
    // would replace it, so that text goes in after the chip instead.
    function grockHasCommand(el) {
      return !!(el && el.querySelector && el.querySelector('[data-composer-command], [data-composer-chip]'));
    }
    function grockSetText(el, text, keepCommand) {
      if (!el || !text) return;
      try { el.focus(); } catch (err) {}
      var tag = String(el.tagName || '').toUpperCase();
      if (tag === 'TEXTAREA' || tag === 'INPUT') {
        var proto = tag === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        var desc = Object.getOwnPropertyDescriptor(proto, 'value');
        if (desc && desc.set) desc.set.call(el, text);
        else el.value = text;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        try {
          el.dispatchEvent(new InputEvent('input', {
            bubbles: true,
            cancelable: true,
            inputType: 'insertText',
            data: text
          }));
        } catch (err) {}
        return;
      }
      if (keepCommand && grockHasCommand(el)) {
        try {
          var range = document.createRange();
          range.selectNodeContents(el);
          range.collapse(false);
          var selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
        } catch (err) {}
      } else {
        try { document.execCommand('selectAll', false, null); } catch (err) {}
      }
      try { document.execCommand('insertText', false, text); } catch (err) {}
      if (!(el.innerText || el.textContent || '').trim()) {
        el.textContent = text;
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }
    }
    """

    static let composerAttachScript = """
    function grockComposerText(el) {
      if (!el) return '';
      var tag = String(el.tagName || '').toUpperCase();
      if (tag === 'TEXTAREA' || tag === 'INPUT') return String(el.value || '');
      return String(el.innerText || el.textContent || '');
    }
    function grockIsStockAttachPrompt(text) {
      var t = String(text || '').replace(/\\s+/g, ' ').trim().toLowerCase();
      if (!t) return false;
      return t.indexOf('refer to the following content') === 0 && t.length < 80;
    }
    function grockClearText(el) {
      if (!el) return;
      try { el.focus(); } catch (err) {}
      var tag = String(el.tagName || '').toUpperCase();
      if (tag === 'TEXTAREA' || tag === 'INPUT') {
        var proto = tag === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        var desc = Object.getOwnPropertyDescriptor(proto, 'value');
        if (desc && desc.set) desc.set.call(el, '');
        else el.value = '';
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return;
      }
      try { document.execCommand('selectAll', false, null); } catch (err) {}
      try { document.execCommand('delete', false, null); } catch (err) {}
      el.textContent = '';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    }
    function grockFilesToDataTransfer(files) {
      var dt = new DataTransfer();
      if (!files || !files.length) return dt;
      for (var i = 0; i < files.length; i++) {
        var item = files[i] || {};
        var b64 = String(item.b64 || '');
        var bin = atob(b64);
        var bytes = new Uint8Array(bin.length);
        for (var j = 0; j < bin.length; j++) bytes[j] = bin.charCodeAt(j);
        var type = String(item.mime || 'application/octet-stream');
        var name = String(item.name || 'attachment');
        dt.items.add(new File([bytes], name, { type: type }));
      }
      return dt;
    }
    function grockAttach(files) {
      if (!files || !files.length) return 'none';
      var dt = grockFilesToDataTransfer(files);
      var inputs = document.querySelectorAll('input[type="file"]');
      for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        try {
          input.files = dt.files;
          input.dispatchEvent(new Event('change', { bubbles: true }));
          if (input.files && input.files.length) return 'input';
        } catch (err) {}
      }
      var composer = grockFindComposer();
      if (composer) {
        try {
          var drop = new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: dt });
          composer.dispatchEvent(drop);
          return 'drop';
        } catch (err) {}
        try {
          composer.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: dt }));
        } catch (err) {}
      }
      return 'missing';
    }
    """

    /// Every async step checks the operation and route before touching the page.
    /// A cancellation after dispatch is ambiguous; it must never trigger a retry.
    static let composerOperationScript = """
    function grockPath(path) { return String(path || '/').replace(/\\/+$/, '') || '/'; }
    function grockSleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
    if (location.hostname !== 'grok.com' || grockPath(location.pathname) !== grockPath(expectedPath)) {
      return 'navigation-changed';
    }
    var operation = { id: operationID, cancelled: false, dispatched: false };
    if (window.__grockComposerOperation) window.__grockComposerOperation.cancelled = true;
    window.__grockComposerOperation = operation;
    function grockCancelled() {
      return operation.cancelled || window.__grockComposerOperation !== operation;
    }
    function grockOnRoute() {
      return location.hostname === 'grok.com' && grockPath(location.pathname) === grockPath(expectedPath);
    }
    """

    /// Shared upload acknowledgment for both handoff paths. Dispatch once,
    /// then observe stable filename evidence while honoring cancellation.
    static let composerAttachmentAcknowledgmentScript = """
    function grockVisible(el) {
      if (!el) return false;
      var style = getComputedStyle(el), box = el.getBoundingClientRect();
      return style.display !== 'none' && style.visibility !== 'hidden'
        && parseFloat(style.opacity) !== 0 && box.width >= 4 && box.height >= 4;
    }
    // FileList assignment / dispatch only proves the browser accepted an event.
    // Require new visible filename evidence from Grok before accepting a prefill or enabling submission.
    function grockAttachmentEvidence(file) {
      var name = String(file.name || '');
      if (!name) return [];
      return Array.from(document.querySelectorAll('[data-filename], [title], [aria-label], span, p, button, img'))
        .filter(function (el) {
          if (!grockVisible(el) || el.closest('textarea, [contenteditable], [role="textbox"]')) return false;
          if (el.closest('[aria-busy="true"], [aria-invalid="true"], [data-state="uploading"], [data-state="error"]')) return false;
          var chip = el.closest('[data-attachment-id], [data-file-id], [data-testid="attachment"]') || el.parentElement;
          if (chip && Array.from(chip.querySelectorAll('[role="progressbar"], progress, [role="alert"], [aria-busy="true"]')).some(grockVisible)) return false;
          var values = [el.getAttribute('data-filename'), el.getAttribute('title'),
                        el.getAttribute('aria-label'), el.getAttribute('alt'), el.textContent];
          return values.some(function (value) {
            value = String(value || '').trim();
            return value === name || value === 'Remove ' + name || value === 'Remove attachment ' + name;
          });
        });
    }
    function grockAttachmentsReady(files, baseline) {
      return (files || []).every(function (file, index) {
        return grockAttachmentEvidence(file).some(function (el) { return baseline[index].indexOf(el) < 0; });
      });
    }
    async function grockWaitForAttachments(files, baseline, waitMS, draftUnchanged) {
      if (!files || !files.length) return 'attached';
      var deadline = Date.now() + waitMS, readySince = null;
      while (Date.now() < deadline) {
        if (grockCancelled()) return 'cancelled';
        if (!grockOnRoute()) return 'navigation-changed';
        if (!draftUnchanged()) return 'draft-changed';
        if (grockAttachmentsReady(files, baseline)) {
          if (readySince !== null && Date.now() - readySince >= 80) return 'attached';
          if (readySince === null) readySince = Date.now();
        } else readySince = null;
        await grockSleep(80);
      }
      return 'attachment-unconfirmed';
    }
    """

    static let fillComposerScript = composerHelperScript + composerAttachScript + composerOperationScript
        + composerAttachmentAcknowledgmentScript + """
    var composer = grockFindComposer();
    if (!composer) return 'no-composer';
    if (window.__grockPreviousComposer === composer && window.__grockPreviousPath !== location.pathname) {
      return 'no-composer';
    }
    // Imagine is the same composer once grok.com has put its chip in.
    var wantsCommand = typeof keepCommand !== 'undefined' && !!keepCommand;
    if (wantsCommand && !grockHasCommand(composer)) return 'no-composer';
    if (grockCancelled() || !grockOnRoute()) return 'cancelled';
    var attachmentBaseline = (files || []).map(grockAttachmentEvidence);
    var attached;
    try { attached = grockAttach(files); } catch (err) { return 'attachment-failed'; }
    if (attached === 'missing' && files && files.length) return 'attachment-failed';
    if (String(promptText || '').length) grockSetText(composer, promptText, wantsCommand);
    else if (grockIsStockAttachPrompt(grockComposerText(composer))) grockClearText(composer);
    var expectedDraft = grockComposerText(composer);
    var outcome = await grockWaitForAttachments(files, attachmentBaseline, attachmentWaitMS, function () {
      var current = grockFindComposer();
      // Typing into the same composer while an upload runs is intentional.
      // A replacement composer must retain the draft before we accept it.
      return current && (current === composer || grockComposerText(current) === expectedDraft);
    });
    if (grockCancelled()) return 'cancelled';
    if (!grockOnRoute()) return 'navigation-changed';
    var current = grockFindComposer();
    if (outcome !== 'attached') {
      // If the user edited during an unsuccessful upload, retain their newer
      // draft with the original files. Never replace it with the initial text.
      if (current && (current === composer || grockComposerText(current))) {
        return { outcome: outcome, draft: grockComposerText(current) };
      }
      return outcome;
    }
    if (!current) return 'draft-changed';
    return 'filled';
    """

    /// Uses the website's controls, then waits for a new matching user turn or
    /// generation edge and a consumed draft. Dispatch itself is never success.
    static let submitPayloadScript = composerHelperScript + composerAttachScript + composerOperationScript
        + composerAttachmentAcknowledgmentScript + """
    function grockLabel(el) {
      return String(el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '')
        .replace(/\\s+/g, ' ').trim().toLowerCase();
    }
    function grockFindSend(composer) {
      var root = composer.closest('form') || composer.closest('[data-grock-composer]') || document;
      var nodes = root.querySelectorAll('button, [role="button"]');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i], label = grockLabel(el);
        if (!grockVisible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') continue;
        if (label === 'submit' || label === 'send' || label.indexOf('send message') === 0) return el;
      }
      return null;
    }
    function grockGenerating() {
      return Array.from(document.querySelectorAll('button, [role="button"]')).some(function (el) {
        if (!grockVisible(el) || el.disabled) return false;
        var label = grockLabel(el);
        return label === 'stop' || /^stop (generating|generation|response|thinking)/.test(label);
      });
    }
    function grockNormalize(text) { return String(text || '').replace(/\\s+/g, ' ').trim(); }
    function grockMatchingTurns() {
      return Array.from(document.querySelectorAll(
        '[data-testid="user-message"] [data-bubble-text], [data-testid="user-message"], '
        + '[data-message-author-role="user"], [data-role="user"], [data-author="user"], .message-bubble'
      )).filter(function (el) {
        return !el.closest('form, [contenteditable], [role="textbox"]')
          && grockNormalize(el.innerText || el.textContent) === grockNormalize(promptText);
      });
    }
    var composer = grockFindComposer();
    if (!composer) return 'no-composer';
    if (grockGenerating()) return 'already-generating';
    var baselineTurns = grockMatchingTurns();
    var attachmentBaseline = (files || []).map(grockAttachmentEvidence);
    var attached;
    try { attached = grockAttach(files); } catch (err) { return 'attachment-failed'; }
    if (files && files.length && attached === 'missing') return 'attachment-failed';
    var wantsText = String(promptText || '').length > 0;
    if (wantsText) grockSetText(composer, promptText);
    else if (grockIsStockAttachPrompt(grockComposerText(composer))) grockClearText(composer);
    var expectedText = grockNormalize(promptText);
    var deadline = Date.now() + sendWaitMS;
    var uploadOutcome = await grockWaitForAttachments(files, attachmentBaseline, sendWaitMS, function () {
      var current = grockFindComposer();
      return current && grockNormalize(grockComposerText(current)) === expectedText;
    });
    if (uploadOutcome !== 'attached') return uploadOutcome;
    var attachmentsReady = true;
    var send = null;
    while (Date.now() < deadline) {
      if (grockCancelled()) return 'cancelled';
      if (!grockOnRoute()) return 'navigation-changed';
      composer = grockFindComposer();
      // Do not retype over an edit or a React remount. Preserve the package for review.
      if (!composer || grockNormalize(grockComposerText(composer)) !== expectedText) return 'draft-changed';
      attachmentsReady = grockAttachmentsReady(files, attachmentBaseline);
      send = attachmentsReady ? grockFindSend(composer) : null;
      if (send) break;
      await grockSleep(80);
    }
    if (!attachmentsReady) return 'attachment-unconfirmed';
    if (!send) return 'no-send';
    if (grockCancelled() || !grockOnRoute()) return 'cancelled';
    if (grockGenerating()) return 'already-generating';
    // Recheck the draft immediately before the sole dispatch.
    if (grockNormalize(grockComposerText(composer)) !== expectedText) return 'draft-changed';
    operation.dispatched = true;
    send.click();
    deadline = Date.now() + acceptWaitMS;
    while (Date.now() < deadline) {
      if (grockCancelled()) return 'uncertain-cancelled';
      if (location.hostname !== 'grok.com') return 'uncertain-navigation';
      var route = grockPath(location.pathname);
      if (!grockOnRoute() && !/^\\/c\\/[^/]+$/.test(route)) return 'uncertain-navigation';
      var current = grockFindComposer();
      var consumed = current && !grockNormalize(grockComposerText(current));
      var newTurn = grockMatchingTurns().some(function (el) { return baselineTurns.indexOf(el) < 0; });
      if (consumed && (newTurn || grockGenerating())) return 'accepted';
      await grockSleep(80);
    }
    return 'uncertain';
    """

    static let webInspectorKey = "app.webInspector"

    var isWebInspectorEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.webInspectorKey)
    }

    func setWebInspectorEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.webInspectorKey)
        applyWebInspector()
    }

    /// The inspector opens in its own window. Docked, it resizes the WebView
    /// from under our layout and comes up blank. WebKit remembers where it was
    /// last put in this default and reads it when the WebView is created, so
    /// this runs first on every launch.
    private static func keepWebInspectorDetached() {
        UserDefaults.standard.set(false, forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
    }

    /// Safari Web Inspector + right-click Inspect Element. Not Chromium DevTools.
    func applyWebInspector(to target: WKWebView? = nil) {
        let webView = target ?? self.webView
        let on = isWebInspectorEnabled
        webView.isInspectable = on
        // Long-standing WKPreferences switch. Turns on the page context-menu item.
        webView.configuration.preferences.setValue(on, forKey: "developerExtrasEnabled")
    }

    /// Push current chrome prefs into the page script (live, no reload).
    /// Hide-only updates must not click grok.com's collapse control: it is a
    /// toggle, and a second click opens the sidebar again.
    func applyChrome(
        _ pref: ChromePreference.Snapshot = ChromePreference.current,
        collapse: Bool = false,
        forceCollapse: Bool = false,
        expand: Bool = false
    ) {
        let json = pref.jsonString
        let js = """
        window.__grockChromeConfig = \(json);
        window.__grockChrome && window.__grockChrome.set(\(json), {collapse: \(collapse), forceCollapse: \(forceCollapse), expand: \(expand)});
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor in
                self?.probeSessionActions()
            }
        }
    }

    /// Push the current More / Share / panel presence into the titlebar.
    func applySessionActions(_ next: SessionActions) {
        guard sessionActions != next else { return }
        sessionActions = next
        NotificationCenter.default.post(name: .grockSessionActionsDidChange, object: nil)
    }

    /// Native compose/navigation controls only work on an authenticated Grok surface.
    func applySignedInState(_ next: Bool) {
        guard isSignedIn != next else { return }
        isSignedIn = next
        NotificationCenter.default.post(name: .grockAuthenticationDidChange, object: nil)
    }

    private func applyPageState(_ body: [String: Any]) {
        applySessionActions(.from(body))
        if let authenticated = Self.boolFlag(body["authenticated"]) {
            applySignedInState(authenticated)
        }
    }

    private static func boolFlag(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    func probeSessionActions() {
        webView.evaluateJavaScript(
            "window.__grockChrome && window.__grockChrome.session && window.__grockChrome.session()"
        ) { [weak self] result, _ in
            let body = result as? [String: Any] ?? [:]
            Task { @MainActor in
                self?.applyPageState(body)
            }
        }
    }

    /// Click grok.com's hidden conversation action (`share`, `panel`, `pin`, `project`, `archive`).
    func clickSessionAction(_ name: String) {
        let allowed: Set<String> = ["share", "panel", "pin", "project", "archive"]
        guard allowed.contains(name) else { return }
        webView.callAsyncJavaScript(
            "return await window.__grockChrome.clickSession(action);",
            arguments: ["action": name],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    /// Read Pin vs Unpin and panel availability from grok.com's More menu,
    /// then close that source menu before native AppKit presents its copy.
    func inspectSessionMenu(completion: @escaping (Bool?, Bool, Bool) -> Void) {
        webView.callAsyncJavaScript(
            "return await window.__grockChrome.inspectSessionMenu();",
            arguments: [:],
            in: nil,
            in: .page
        ) { result in
            let body = (try? result.get()) as? [String: Any] ?? [:]
            let text = (body["pin"] as? String)?.lowercased() ?? ""
            let pinned: Bool?
            if text.hasPrefix("unpin") {
                pinned = true
            } else if text.hasPrefix("pin") {
                pinned = false
            } else {
                pinned = nil
            }
            let panel = SessionActions.from(["panel": body["panel"] ?? false]).panel
            let project = body["project"] as? Bool ?? false
            Task { @MainActor in
                completion(pinned, panel, project)
            }
        }
    }

    /// Open grok.com Search, or dismiss it if the modal is already up.
    func toggleSearch() {
        webView.evaluateJavaScript(Self.toggleSearchScript, completionHandler: nil)
    }

    /// Title menu Search is a CTA: open, don't dismiss.
    func openSearch() {
        webView.evaluateJavaScript(Self.openSearchScript, completionHandler: nil)
    }

    /// Title menu Plugins is a CTA: open grok.com's connectors/skills modal.
    func openPlugins() {
        webView.evaluateJavaScript(Self.openPluginsScript, completionHandler: nil)
    }

    /// Title menu Projects. grok.com's Projects page is a plain route now;
    /// the sidebar has no All projects control to click.
    func openAllProjects() {
        openGrokPath("/project")
    }

    /// Place destinations with a real grok.com path (Imagine, Projects, …).
    func openGrokPath(_ path: String) {
        let trimmed = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: "https://grok.com\(trimmed)") else { return }
        // Preserve a queued fill when a requested SPA transition falls back to a load.
        let fill = intendedComposerPath == trimmed ? pendingComposerFill : nil
        if fill == nil { finishPayload(cancelComposerOperations()) }
        intendedComposerPath = trimmed
        webView.load(URLRequest(url: url))
    }

    /// Open Chat home (New Chat) or Imagine home. Click grok.com's own
    /// control when we can. Full load only if that node is gone.
    func openApp(_ app: GrockWebApp) {
        switch app {
        case .chat:
            startNewChat()
        case .imagine:
            openImagineHome()
        }
    }

    /// Capture before asynchronous file loading; intervening navigation invalidates it.
    var composerFillToken: Int { composerIntakeGeneration }
    var isFillingComposer: Bool { pendingComposerFill != nil || activeComposerFill != nil }

    /// Queue a prefill for the requested destination. The old page's composer
    /// must never receive context while New Chat / Imagine is navigating.
    func fillComposer(
        text: String,
        attachments: [QuickChatAttachment] = [],
        expectedGeneration: Int? = nil
    ) {
        if let expectedGeneration, expectedGeneration != composerIntakeGeneration { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { focusInput(); return }
        let payload = QuickChatPayload(text: trimmed, attachments: attachments)
        guard payload.validationError == nil else { return }
        fillComposerGeneration += 1
        webView.evaluateJavaScript(Self.cancelComposerOperationScript, completionHandler: nil)
        activeComposerFill = nil
        recoverableComposerFill = nil
        let fill = ComposerFill(
            text: trimmed, attachments: attachments,
            path: intendedComposerPath ?? recoveryComposerPath ?? webView.url?.path ?? "/",
            generation: fillComposerGeneration
        )
        if recoveryState != nil {
            // File loading may finish after navigation failed. Retain the
            // completed package; only Retry may place it on a web page.
            recoverableComposerFill = fill
            recoveryComposerPath = fill.path
            return
        }
        pendingComposerFill = fill
        attemptPendingComposerFill()
    }

    private func attemptPendingComposerFill(tries: Int = 0) {
        guard let fill = pendingComposerFill, fill.generation == fillComposerGeneration else { return }
        guard tries < 100 else {
            presentRecovery(.contextNotAdded)
            return
        }
        let landing = Self.landingPath(fill.path)
        // A fill meant for Imagine waits for that chip, so it can never land
        // in an ordinary chat that happens to be on the same path.
        let wantsImagine = landing != fill.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !webView.isLoading, !freshSessionInProgress,
              Self.isGrokPage(webView.url),
              (webView.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "") == landing else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.pendingComposerFill?.generation == fill.generation else { return }
                self.attemptPendingComposerFill(tries: tries + 1)
            }
            return
        }
        // Remove from the queue before invoking JS; didFinish cannot inject it twice.
        pendingComposerFill = nil
        activeComposerFill = fill
        let files = fill.attachments.map { attachment -> [String: Any] in
            ["name": attachment.filename, "mime": attachment.mimeType,
             "b64": attachment.data.base64EncodedString()]
        }
        webView.callAsyncJavaScript(
            Self.fillComposerScript,
            arguments: ["promptText": fill.text, "files": files,
                        "operationID": UUID().uuidString, "expectedPath": "/\(landing)",
                        "keepCommand": wantsImagine,
                        "attachmentWaitMS": attachmentWaitMilliseconds],
            in: nil, in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, fill.generation == self.fillComposerGeneration else { return }
                if case .success(let value) = result, value as? String == "no-composer" {
                    self.activeComposerFill = nil
                    self.pendingComposerFill = fill
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        guard fill.generation == self.fillComposerGeneration else { return }
                        self.attemptPendingComposerFill(tries: tries + 1)
                    }
                    return
                }
                if case .success(let value) = result, value as? String == "filled" {
                    self.activeComposerFill = nil
                    self.focusInput()
                    return
                }
                // A route change belongs to a newer user action. Failures on
                // the intended page retain bytes and offer an explicit Retry.
                let path = self.webView.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard path == landing else {
                    self.activeComposerFill = nil
                    return
                }
                if case .success(let value) = result,
                   let body = value as? [String: Any], let draft = body["draft"] as? String {
                    self.activeComposerFill = ComposerFill(text: draft, attachments: fill.attachments,
                                                           path: fill.path, generation: fill.generation)
                }
                self.presentRecovery(.contextNotAdded)
            }
        }
    }

    /// App menu New Generation: a fresh composer in Imagine mode.
    func startNewGeneration() {
        openImagineHome()
        pendingFocusInput = true
    }

    /// grok.com has no Imagine page or control to click now. Its `/imagine`
    /// link is the way in, and a load starts before any queued fill can run.
    private func openImagineHome() {
        finishPayload(cancelComposerOperations())
        openGrokPath("/imagine")
    }

    /// grok.com's conversation history page (same destination as the sidebar item).
    func openHistory() {
        openGrokPath("/history")
    }

    /// grok.com's Private toggle.
    func startPrivateChat() {
        webView.evaluateJavaScript(Self.privateChatScript, completionHandler: nil)
    }

    /// grok.com's Search is a command menu opened by a button it draws beside
    /// the traffic lights. The titlebar hides that button and clicks it.
    private static let searchHelperScript = """
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }
      function visible(el) {
        if (!el) return false;
        var box = el.getBoundingClientRect();
        if (box.width < 8 || box.height < 8) return false;
        var style = window.getComputedStyle(el);
        return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
      }
      function findSearch() {
        var nodes = document.querySelectorAll(
          '[data-leading-chrome] button, #app-sidebar a, #app-sidebar button,'
          + ' nav a, nav button, aside a, aside button, header a, header button'
        );
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (el.closest('[aria-label="Right pane"]')) continue;
          var aria = norm(el.getAttribute('aria-label'));
          var title = norm(el.getAttribute('title'));
          var text = norm(el.textContent);
          if (aria === 'Search' || title === 'Search' || text === 'Search') return el;
        }
        return null;
      }
      // Settings and Library have search fields of their own. The command
      // menu is the dialog built around a combobox.
      function searchDialog() {
        var nodes = document.querySelectorAll('[role="dialog"], [role="search"], [cmdk-dialog]');
        for (var i = 0; i < nodes.length; i++) {
          if (!visible(nodes[i])) continue;
          if (nodes[i].matches('[data-analytics-name="command_menu"]')) return nodes[i];
          if (nodes[i].querySelector('[role="combobox"], [role="searchbox"], [cmdk-input]')) return nodes[i];
        }
        return null;
      }
    """

    static let toggleSearchScript = """
    (function () {
    \(searchHelperScript)
      var open = searchDialog();
      if (open) {
        var close = open.querySelector(
          'button[aria-label="Close"], button[aria-label="close"], button[aria-label*="Close"]'
        );
        if (close) close.click();
        else {
          document.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true
          }));
        }
        return 'closed';
      }
      var btn = findSearch();
      if (!btn) return 'missing';
      btn.click();
      return 'opened';
    })();
    """

    static let openSearchScript = """
    (function () {
    \(searchHelperScript)
      if (searchDialog()) return 'already-open';
      var btn = findSearch();
      if (!btn) return 'missing';
      btn.click();
      return 'opened';
    })();
    """

    /// Plugins are the Connect Apps and Skills pages of grok.com's Settings.
    /// The sidebar's Connect apps button opens Settings there.
    static let openPluginsScript = """
    (function () {
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }
      function visible(el) {
        if (!el) return false;
        var box = el.getBoundingClientRect();
        if (box.width < 8 || box.height < 8) return false;
        var style = window.getComputedStyle(el);
        return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
      }
      function pluginsDialog() {
        var nodes = document.querySelectorAll('[role="dialog"]');
        for (var i = 0; i < nodes.length; i++) {
          if (!visible(nodes[i])) continue;
          var text = String(nodes[i].textContent || '').toLowerCase();
          if (text.indexOf('connect apps') !== -1 && text.indexOf('skills') !== -1) return nodes[i];
        }
        return null;
      }
      if (pluginsDialog()) return 'already-open';
      var names = ['connect apps', 'plugins'];
      var nodes = document.querySelectorAll(
        '#app-sidebar a, #app-sidebar button, nav a, nav button, aside a, aside button'
      );
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.closest('[aria-label="Right pane"]')) continue;
        var span = el.querySelector('[data-sidebar-item-label]');
        var label = norm(el.getAttribute('aria-label') || el.getAttribute('title')
          || (span ? span.textContent : el.textContent)).toLowerCase();
        if (names.indexOf(label) === -1) continue;
        el.click();
        return 'opened';
      }
      return 'missing';
    })();
    """

    /// Private is a toggle in the band over the main column. Its label reads
    /// "Switch to Private Chat" or "Exit Private Chat"; the visible text is
    /// "Private". Leaving is the same click, or grok.com's New chat.
    static let privateChatScript = """
    (function () {
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }
      var scope = document.querySelector('#grok-content-area header') ? '#grok-content-area header ' : '';
      var nodes = document.querySelectorAll(scope + 'a, ' + scope + 'button');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var aria = norm(el.getAttribute('aria-label'));
        var title = norm(el.getAttribute('title'));
        var text = norm(el.textContent);
        if (aria === 'Private' || title === 'Private' || text === 'Private'
            || /\\bprivate chat\\b/i.test(aria)) {
          el.click();
          return 'clicked';
        }
      }
      return 'missing';
    })();
    """

    /// Place / conversation label for the native titlebar (DEC-025).
    /// Thread name is the sidebar row for `/c/{id}`, not reply markdown.
    static let placeTitleScript = """
    (function () {
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim();
      }
      function junk(text) {
        var low = String(text || '').toLowerCase();
        return low.indexOf('privacy preference') !== -1
          || low.indexOf('cookie preference') !== -1
          || low.indexOf('onetrust') !== -1;
      }
      function hostOk() {
        var host = String(location.hostname || '').toLowerCase();
        return host === 'grok.com' || host.slice(-9) === '.grok.com';
      }
      function isPlaceName(text) {
        var low = String(text || '').toLowerCase();
        return low === 'new chat' || low === 'chat' || low === 'imagine' || low === 'library'
          || low === 'automations'
          || low === 'projects' || low === 'history' || low === 'plugins'
          || low === 'search' || low === 'private' || low === 'grok bot'
          || low === 'skills and connectors' || low === 'chats'
          || low === 'today' || low === 'yesterday';
      }
      function usable(text) {
        if (!text) return '';
        var low = text.toLowerCase();
        if (low === 'grok' || low === 'supergrok') return '';
        if (junk(text) || isPlaceName(text)) return '';
        return text;
      }
      function labelOf(el) {
        if (!el) return '';
        var aria = usable(norm(el.getAttribute('aria-label')));
        if (aria) return aria;
        var titled = usable(norm(el.getAttribute('title')));
        if (titled) return titled;
        var span = el.matches('[data-sidebar-item-label]') ? el : el.querySelector('[data-sidebar-item-label]');
        var text = span ? norm(span.textContent) : norm(el.textContent);
        if (text.length > 80) return '';
        return usable(text);
      }
      if (!hostOk()) return '';
      var path = String(location.pathname || '');
      var lower = path.toLowerCase();
      if (lower.indexOf('/imagine') === 0) return 'Imagine';
      if (lower === '/library' || lower.indexOf('/library/') === 0
          || lower === '/files' || lower.indexOf('/files/') === 0) return 'Library';
      if (lower.indexOf('/automation') === 0) return 'Automations';
      if (lower.indexOf('/skill') === 0) return 'Plugins';
      if (lower === '/project' || lower === '/project/') return 'Projects';
      if (lower === '/history' || lower.indexOf('/history/') === 0) return 'History';
      if (path === '/' || path === '') return 'Grok';

      // Reply h1/h2 is not the thread name. grok.com prints the name in the
      // band over the chat, which the titlebar covers, and on the sidebar's
      // current row (the hidden sidebar stays in the DOM, DEC-025).
      var heading = document.querySelector('#grok-content-area [data-testid="conversation-title"]');
      if (heading) {
        var fromHeading = labelOf(heading);
        if (fromHeading) return fromHeading;
      }

      var active = document.querySelector(
        '#app-sidebar [aria-current="true"], #app-sidebar [aria-current="page"]'
      );
      if (active) {
        var fromActive = labelOf(active);
        if (fromActive) return fromActive;
      }

      // Every page is titled "<name> - Grok".
      var title = norm(document.title).replace(/\\s+[-\\u2013\\u2014|]\\s+Grok$/i, '');
      if (!title || title.toLowerCase() === 'grok' || junk(title)) return '';
      return usable(title);
    })();
    """

    /// Drive `prefers-color-scheme` for the page via the WebView's appearance.
    func applyAppearance(_ appearance: NSAppearance?) {
        webView.appearance = appearance
        webView.underPageBackgroundColor = AppearancePreference.pageBackdrop
        for window in NSApp.windows {
            (window as? FloatingPanel)?.applyPageBackdrop()
        }
    }

    /// Stop grok.com treating the Mac window's corner radius as a safe-area
    /// inset, and kill WebKit overlay-scrollbar hairlines on the bottom/right.
    ///
    /// The node that paints the lines is not `<main>` (already overflow:hidden).
    /// It is a nested chat column: `#grok-content-area … .overflow-scroll`
    /// (`flex flex-col … h-full … overflow-scroll`). Safari paints overlay
    /// scrollbar tracks / a 1px gutter there; Chrome does not. Flattening
    /// that class is safe — chat / sidebar still scroll on inner overflow:auto.
    static let edgeFixScript = """
    (function () {
      // Account pages use their own document scrolling, especially in short
      // windows. Only grok.com's full-window shell needs this cleanup.
      var host = String(location.hostname || '').toLowerCase();
      if (host !== 'grok.com' && host.slice(-9) !== '.grok.com') return;
      var css = 'html,body{margin:0!important;padding:0!important;overflow:hidden!important;background-color:transparent!important;}'
        + 'html::-webkit-scrollbar,body::-webkit-scrollbar{width:0!important;height:0!important;display:none!important;}'
        + '.overflow-scroll,[data-grock-edge-shell]{overflow:hidden!important;overflow-x:hidden!important;overflow-y:hidden!important;}'
        + '.overflow-scroll::-webkit-scrollbar,[data-grock-edge-shell]::-webkit-scrollbar{width:0!important;height:0!important;display:none!important;}';

      function ensureStyle() {
        var root = document.documentElement;
        if (!root) return;
        var el = document.getElementById('grock-edge-fix');
        if (!el) {
          el = document.createElement('style');
          el.id = 'grock-edge-fix';
          (document.head || root).appendChild(el);
        }
        if (el.textContent !== css) el.textContent = css;
      }

      function pinBox(el, flag) {
        if (!el || el.getAttribute(flag)) return;
        el.setAttribute(flag, '1');
        el.style.setProperty('overflow', 'hidden', 'important');
        el.style.setProperty('padding', '0', 'important');
        el.style.setProperty('margin', '0', 'important');
      }

      function pinRoot() {
        pinBox(document.documentElement, 'data-grock-edge-root');
        pinBox(document.body, 'data-grock-edge-body');
        var meta = document.querySelector('meta[name="viewport"]');
        if (meta && meta.content.indexOf('viewport-fit') === -1) {
          meta.content += ', viewport-fit=contain';
        }
      }

      function flatten(el) {
        if (!el || el === document.documentElement || el === document.body) return;
        if (el.getAttribute('data-grock-edge-shell')) return;
        el.setAttribute('data-grock-edge-shell', '1');
        el.style.setProperty('overflow', 'hidden', 'important');
        el.style.setProperty('overflow-x', 'hidden', 'important');
        el.style.setProperty('overflow-y', 'hidden', 'important');
      }

      function apply() {
        ensureStyle();
        pinRoot();
        var nodes = document.querySelectorAll('.overflow-scroll:not([data-grock-edge-shell])');
        for (var i = 0; i < nodes.length; i++) flatten(nodes[i]);
      }

      if (window.__grockEdgeFix) {
        window.__grockEdgeFix.apply();
        return;
      }

      var scheduled = false;
      function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(function () {
          scheduled = false;
          apply();
        });
      }

      window.__grockEdgeFix = { apply: apply };
      apply();
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', apply);
      }
      window.addEventListener('resize', schedule);
      if (document.documentElement) {
        new MutationObserver(function (records) {
          for (var i = 0; i < records.length; i++) {
            var r = records[i];
            if (r.target && r.target.id === 'grock-edge-fix') continue;
            var nodes = r.addedNodes;
            for (var j = 0; j < nodes.length; j++) {
              if (nodes[j].nodeType === 1) { schedule(); return; }
            }
          }
        }).observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      }
    })();
    """

    private static let pageScript = DownloadBridge.pageScript

    #if DEBUG
    /// Development builds only. `-pageScript /path/to/file.js` on the command
    /// line (`open Grock.app --args -pageScript …`) injects that file into
    /// grok.com at document end, for example to stand in generic content
    /// while taking screenshots. Compiled out of Release.
    private static func debugPageScript() -> String? {
        guard let path = UserDefaults.standard.string(forKey: "pageScript"),
              let script = try? String(contentsOfFile: path, encoding: .utf8),
              !script.isEmpty else { return nil }
        return script
    }

    /// Development builds only. `-pageProbe /path/to/dir` polls that folder
    /// for `in.js`, runs it in grok.com as an async function body, and writes
    /// the returned value to `out.json`. This is how selector drift gets
    /// checked against the live page. Compiled out of Release.
    private var debugProbeTimer: Timer?
    private func startDebugPageProbe() {
        guard let dir = UserDefaults.standard.string(forKey: "pageProbe"), !dir.isEmpty else { return }
        let input = URL(fileURLWithPath: dir).appendingPathComponent("in.js")
        let output = URL(fileURLWithPath: dir).appendingPathComponent("out.json")
        debugProbeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let script = try? String(contentsOf: input, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: input)
            Task { @MainActor in
                self?.webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                    var reply: [String: Any]
                    switch result {
                    case .success(let value): reply = ["ok": true, "value": value]
                    case .failure(let error): reply = ["ok": false, "error": String(describing: error)]
                    }
                    if !JSONSerialization.isValidJSONObject(reply) {
                        reply = ["ok": true, "value": String(describing: reply["value"] ?? "")]
                    }
                    let data = (try? JSONSerialization.data(withJSONObject: reply, options: [.fragmentsAllowed])) ?? Data()
                    try? data.write(to: output, options: .atomic)
                }
            }
        }
    }
    #endif

    /// Honest "reply is done" hook (DEC-054). Chat Stop controls, not tokens.
    /// Voice is in-front; we do not watch Exit-voice. Idle when grok.com is idle:
    /// childList plus aria-label / title / disabled.
    static let replyObserverScript = """
    (function () {
      if (window.__grockReply) return;
      var handlers = window.webkit && window.webkit.messageHandlers;
      var bridge = handlers && handlers.grockReply;
      var generating = false;
      var TITLEBAR = 52;

      function hostOk() {
        var host = String(location.hostname || '').toLowerCase();
        return host === 'grok.com' || host.slice(-9) === '.grok.com';
      }
      function norm(value) {
        return String(value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
      }
      function labelOf(el) {
        if (!el) return '';
        return norm(el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent);
      }
      function visible(el) {
        if (!el) return false;
        var s = window.getComputedStyle(el);
        if (!s || s.display === 'none' || s.visibility === 'hidden') return false;
        if (parseFloat(s.opacity) === 0) return false;
        var box = el.getBoundingClientRect();
        return box.width >= 4 && box.height >= 4;
      }
      function isStop(el) {
        if (!el || !visible(el) || el.disabled) return false;
        var s = labelOf(el);
        if (s === 'stop' || s === 'stop generating' || s === 'stop response') return true;
        if (s === 'stop generation' || s === 'stop thinking') return true;
        if (s.indexOf('stop generating') === 0) return true;
        if (s.indexOf('stop ') === 0 && s.indexOf('voice') === -1 && s.indexOf('listen') === -1) {
          return true;
        }
        return false;
      }
      function isBusy() {
        if (!hostOk()) return false;
        var nodes = document.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          if (isStop(nodes[i])) return true;
        }
        return false;
      }
      function post(kind, extra) {
        if (!bridge) return;
        var body = { kind: kind };
        if (extra) {
          for (var key in extra) body[key] = extra[key];
        }
        try { bridge.postMessage(body); } catch (err) {}
      }
      function tick() {
        var next = isBusy();
        if (next === generating) return;
        var was = generating;
        generating = next;
        post('state', { generating: next });
        if (was && !next) post('landed');
      }
      function contentRoot() {
        return document.getElementById('grok-content-area') || document.body;
      }
      function isComposerTree(el) {
        if (!el || !el.closest) return false;
        if (el.closest('textarea, [contenteditable="true"], [role="textbox"]')) return true;
        var form = el.closest('form');
        if (!form) return false;
        var box = form.getBoundingClientRect();
        return box.height > 0 && box.height < 320;
      }
      function isMessageCopy(s) {
        return s === 'copy' || s === 'copy message' || s === 'copy response' || s === 'copy answer';
      }
      function lastCopy(root) {
        var copy = null;
        var nodes = root.querySelectorAll('button, [role="button"]');
        for (var i = 0; i < nodes.length; i++) {
          if (isComposerTree(nodes[i])) continue;
          if (isMessageCopy(labelOf(nodes[i]))) copy = nodes[i];
        }
        return copy;
      }
      function lastAnswer() {
        var root = contentRoot();
        if (!root) return null;
        var answers = root.querySelectorAll('[data-testid="assistant-message"]');
        if (answers.length) return answers[answers.length - 1];
        var copy = lastCopy(root);
        if (copy) {
          return copy.closest('article')
            || copy.closest('[data-testid]')
            || copy.parentElement;
        }
        var blocks = root.querySelectorAll('article, [data-testid="markdown"], .prose');
        if (blocks.length) return blocks[blocks.length - 1];
        return null;
      }
      function findScroller() {
        var root = contentRoot();
        if (!root) return document.scrollingElement;
        var transcript = root.querySelector('[data-testid="chat-transcript-scroller"]');
        if (transcript) return transcript;
        var nodes = root.querySelectorAll('div, section, main, article');
        var best = null;
        var bestScore = -1;
        var limit = Math.min(nodes.length, 80);
        for (var i = 0; i < limit; i++) {
          var el = nodes[i];
          var s = window.getComputedStyle(el);
          if (!s) continue;
          var oy = s.overflowY;
          if (oy !== 'auto' && oy !== 'scroll' && oy !== 'overlay') continue;
          if (el.offsetHeight < 80) continue;
          var score = 0;
          if (el.scrollHeight > el.clientHeight + 8) score += 3;
          if (el.offsetHeight >= 200) score += 2;
          if (score > bestScore) {
            bestScore = score;
            best = el;
          }
        }
        return best || root;
      }
      function scrollToAnswer() {
        var target = lastAnswer();
        var scroller = findScroller();
        if (target && target.scrollIntoView) {
          target.scrollIntoView({ block: 'start', inline: 'nearest' });
        } else if (scroller) {
          scroller.scrollTop = scroller.scrollHeight;
        }
        if (scroller) {
          scroller.scrollTop = Math.max(0, scroller.scrollTop - TITLEBAR);
        }
        return target ? 'scrolled' : (scroller ? 'bottom' : 'missing');
      }

      window.__grockReply = {
        state: function () { return { generating: generating, busy: isBusy() }; },
        tick: tick,
        scrollToAnswer: scrollToAnswer
      };

      tick();
      if (document.documentElement) {
        new MutationObserver(function (records) {
          for (var i = 0; i < records.length; i++) {
            var r = records[i];
            if (r.type === 'attributes') { tick(); return; }
            var added = r.addedNodes;
            for (var j = 0; j < added.length; j++) {
              if (added[j].nodeType === 1) { tick(); return; }
            }
            var removed = r.removedNodes;
            for (var k = 0; k < removed.length; k++) {
              if (removed[k].nodeType === 1) { tick(); return; }
            }
          }
        }).observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['aria-label', 'title', 'disabled']
        });
      }
    })();
    """

}
