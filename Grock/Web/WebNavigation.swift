import AppKit
import WebKit

// MARK: - Download boundary

enum DownloadRequestPolicy {
    static let maximumBytes = 64 * 1024 * 1024
    /// Exact asset hosts, not all of x.ai or user-controlled Grok subdomains.
    /// Grok's public web bundle/CSP and xAI's Imagine output documentation identify these CDNs.
    static let assetHosts: Set<String> = [
        "assets.grok.com", "assets.grokusercontent.com", "imagine-public.x.ai",
        "imgen.x.ai", "vidgen.x.ai", "files-cdn.x.ai",
    ]

    static func isAssetURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased()
        else { return false }
        return assetHosts.contains(host)
    }

    static func isMainGrokURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["grok.com", "www.grok.com"].contains(url.host?.lowercased() ?? "")
    }

    static func permitsSender(isExpectedView: Bool, isMainFrame: Bool, frameURL: URL?,
                              currentURL: URL?, originScheme: String, originHost: String, originPort: Int) -> Bool {
        isExpectedView && isMainFrame && isMainGrokURL(frameURL) && isMainGrokURL(currentURL)
            && originScheme.lowercased() == "https" && [0, 443].contains(originPort)
            && originHost.lowercased() == frameURL?.host?.lowercased()
            && originHost.lowercased() == currentURL?.host?.lowercased()
    }

    static func permitsMessage(_ message: WKScriptMessage, expectedWebView: WKWebView?) -> Bool {
        let frame = message.frameInfo
        let origin = frame.securityOrigin
        return permitsSender(
            isExpectedView: message.webView === expectedWebView && expectedWebView != nil,
            isMainFrame: frame.isMainFrame, frameURL: frame.request.url, currentURL: expectedWebView?.url,
            originScheme: origin.protocol, originHost: origin.host, originPort: origin.port
        )
    }

    static func request(url: URL, method: String = "GET", headers: [[String]] = []) throws -> URLRequest {
        guard isAssetURL(url), method.uppercased() == "GET", headers.count <= 8,
              url.absoluteString.utf8.count <= 16_384 else { throw DownloadFailure.disallowedRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "GET"
        for pair in headers {
            guard pair.count == 2, pair[0].lowercased() == "accept", pair[1].utf8.count <= 1024,
                  pair[1].unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
                throw DownloadFailure.disallowedRequest
            }
            request.setValue(pair[1], forHTTPHeaderField: "Accept")
        }
        return request
    }

    static func validateResponse(_ response: URLResponse, maximumBytes: Int = maximumBytes) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse, isAssetURL(response.url) else {
            throw DownloadFailure.disallowedRequest
        }
        guard (200...299).contains(response.statusCode) else { throw DownloadFailure.http(response.statusCode) }
        guard response.expectedContentLength <= maximumBytes else { throw DownloadFailure.tooLarge }
        return response
    }
}

enum DownloadFailure: LocalizedError {
    case disallowedRequest, tooLarge, empty, http(Int), staleDocument, tooManyDownloads

    var errorDescription: String? {
        switch self {
        case .disallowedRequest: return "This file cannot be downloaded here. Open it in your browser to save it."
        case .tooLarge: return "This file exceeds the 64 MB download limit. Open it in your browser to save it."
        case .empty: return "The download was empty. Please try again."
        case .http(let code): return "The server could not provide this file (HTTP \(code)). Please try again."
        case .staleDocument: return "The page changed before the download finished. Please try again."
        case .tooManyDownloads: return "A download is already in progress. Please try again when it finishes."
        }
    }
}

/// Streams and bounds bytes before they can accumulate. An ephemeral session does
/// not import app cookies/credentials into this narrowly scoped CORS fallback.
final class AssetTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Output { let data: Data; let response: HTTPURLResponse }
    private var session: URLSession?
    private let sessionLock = NSLock()
    private var response: HTTPURLResponse?
    private var bytes = Data()
    private var redirects = 0
    private let maximumBytes: Int
    private var completion: ((Result<Output, Error>) -> Void)?

    init(maximumBytes: Int = DownloadRequestPolicy.maximumBytes) { self.maximumBytes = maximumBytes }

    func start(_ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral,
               completion: @escaping (Result<Output, Error>) -> Void) {
        self.completion = completion
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 120
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        sessionLock.lock()
        self.session = session
        sessionLock.unlock()
        session.dataTask(with: request).resume()
    }

    func cancel() {
        sessionLock.lock()
        let session = self.session
        sessionLock.unlock()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            self.response = try DownloadRequestPolicy.validateResponse(response, maximumBytes: maximumBytes)
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard completion != nil else { return }
        guard bytes.count <= maximumBytes - data.count else {
            dataTask.cancel()
            finish(.failure(DownloadFailure.tooLarge))
            return
        }
        bytes.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url,
              let approved = try? DownloadRequestPolicy.request(url: url) else {
            completionHandler(nil)
            finish(.failure(DownloadFailure.disallowedRequest))
            return
        }
        completionHandler(approved)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if let response, !bytes.isEmpty { finish(.success(Output(data: bytes, response: response))) }
        else { finish(.failure(DownloadFailure.empty)) }
    }

    private func finish(_ result: Result<Output, Error>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
        bytes.removeAll()
        sessionLock.lock()
        let session = self.session
        self.session = nil
        sessionLock.unlock()
        session?.invalidateAndCancel()
    }
}

enum DownloadFeedback {
    static let didChangeNotification = Notification.Name("com.jaredatch.Grock.downloadFeedback")

    static func saved(_ url: URL) { post("Saved \(url.lastPathComponent) to Downloads.", fileURL: url) }
    static func failed(_ error: Error) { post("Download failed. " + error.localizedDescription) }

    private static func post(_ message: String, fileURL: URL? = nil) {
        DispatchQueue.main.async {
            var info: [String: Any] = ["message": message, "success": fileURL != nil]
            if let fileURL { info["fileURL"] = fileURL }
            NotificationCenter.default.post(name: didChangeNotification, object: nil, userInfo: info)
        }
    }
}

/// A provisional load may turn into a download and leave the committed page
/// alive. Remember that page, but never let an older cancellation authorize a
/// replacement navigation. A fresh token also keeps canceled transfer replies stale.
struct DownloadDocumentAuthorization {
    private(set) var token: String?
    private var committedGrokDocument = false
    private var provisionalNavigation: AnyObject?
    private var awaitingCommit = false

    mutating func navigationStarted(_ navigation: AnyObject?) {
        token = nil
        provisionalNavigation = navigation
        awaitingCommit = true
    }

    mutating func documentCommitted(isGrok: Bool) -> String? {
        committedGrokDocument = isGrok
        provisionalNavigation = nil
        awaitingCommit = false
        token = isGrok ? UUID().uuidString : nil
        return token
    }

    mutating func provisionalNavigationFailed(_ navigation: AnyObject?) -> String? {
        guard awaitingCommit, navigation === provisionalNavigation else { return nil }
        provisionalNavigation = nil
        awaitingCommit = false
        guard committedGrokDocument else { return nil }
        token = UUID().uuidString
        return token
    }

    mutating func invalidate() { self = Self() }
}

/// Only the committed main Grok document in the owned WebView may use this channel.
/// Each full navigation revokes its document token and any in-flight transfers.
final class DownloadBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let channelName = "grockBridge"
    weak var expectedWebView: WKWebView?
    private(set) var imageURL: URL?
    private(set) var linkURL: URL?
    private var authorization = DownloadDocumentAuthorization()
    private var documentToken: String? { authorization.token }
    private var transfers: [UUID: AssetTransfer] = [:]

    func invalidateDocument() {
        authorization.invalidate()
        cancelTransfers()
    }

    func navigationDidStart(_ navigation: WKNavigation?) {
        authorization.navigationStarted(navigation)
        cancelTransfers()
    }

    private func cancelTransfers() {
        imageURL = nil
        linkURL = nil
        transfers.values.forEach { $0.cancel() }
        transfers.removeAll()
    }

    func documentDidCommit(in webView: WKWebView) {
        guard webView === expectedWebView else { return }
        if let token = authorization.documentCommitted(isGrok: DownloadRequestPolicy.isMainGrokURL(webView.url)) {
            sendDocumentToken(token, in: webView)
        }
    }

    /// WebKit reports a provisional failure when a response becomes a download.
    /// No new document commits in that case, so explicitly reauthorize the survivor.
    @discardableResult
    func provisionalNavigationFailed(_ navigation: WKNavigation?, in webView: WKWebView) -> Bool {
        guard webView === expectedWebView, DownloadRequestPolicy.isMainGrokURL(webView.url),
              let token = authorization.provisionalNavigationFailed(navigation) else { return false }
        sendDocumentToken(token, in: webView)
        return true
    }

    private func sendDocumentToken(_ token: String, in webView: WKWebView) {
        webView.evaluateJavaScript("document.dispatchEvent(new CustomEvent('grock-download-document', {detail: '\(token)'}));",
                                   completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @Sendable (Any?, String?) -> Void) {
        guard DownloadRequestPolicy.permitsMessage(message, expectedWebView: expectedWebView), let body = message.body as? [String: Any],
              let token = body["documentToken"] as? String, token == documentToken,
              let kind = body["kind"] as? String else {
            replyHandler(nil, "This page is not allowed to use the download bridge.")
            return
        }
        switch kind {
        case "context":
            imageURL = Self.assetURL(body["image"])
            linkURL = Self.assetURL(body["link"])
            replyHandler(["ok": true], nil)
        case "proxy":
            proxy(body, token: token, reply: replyHandler)
        default:
            replyHandler(nil, "Unknown download request.")
        }
    }

    private static func assetURL(_ value: Any?) -> URL? {
        guard let string = value as? String, let url = URL(string: string), DownloadRequestPolicy.isAssetURL(url)
        else { return nil }
        return url
    }

    private func proxy(_ body: [String: Any], token: String,
                       reply: @escaping @Sendable (Any?, String?) -> Void) {
        do {
            guard let url = Self.assetURL(body["href"]), transfers.count < 2 else {
                throw transfers.count >= 2 ? DownloadFailure.tooManyDownloads : DownloadFailure.disallowedRequest
            }
            let request = try DownloadRequestPolicy.request(url: url, method: body["verb"] as? String ?? "GET",
                                                             headers: body["headerPairs"] as? [[String]] ?? [])
            let id = UUID()
            let transfer = AssetTransfer()
            transfers[id] = transfer
            transfer.start(request) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, token == self.documentToken else {
                        reply(nil, DownloadFailure.staleDocument.localizedDescription)
                        return
                    }
                    self.transfers[id] = nil
                    switch result {
                    case .success(let output):
                        reply(["code": output.response.statusCode,
                               "mime": output.response.mimeType ?? "application/octet-stream",
                               "disposition": output.response.value(forHTTPHeaderField: "Content-Disposition") ?? "",
                               "bytes": output.data.base64EncodedString()], nil)
                    case .failure(let error):
                        reply(nil, error.localizedDescription)
                        DownloadFeedback.failed(error)
                    }
                }
            }
        } catch {
            reply(nil, error.localizedDescription)
            DownloadFeedback.failed(error)
        }
    }

}

// MARK: - Offsite link policy

/// Overlay stays on grok.com. Citations, FAQ, and other http(s) leave for the
/// default browser. X / Apple sign-in popups stay in-process (DEC-032).
enum NavigationPolicy {
    static func isGrokHost(_ host: String?) -> Bool {
        guard let host = normalizedHost(host) else { return false }
        return host == "grok.com" || host.hasSuffix(".grok.com")
    }

    static func isAuthHost(_ host: String?) -> Bool {
        guard let host = normalizedHost(host) else { return false }
        if exactAuthHosts.contains(host) { return true }
        for allowed in authHosts {
            if host == allowed || host.hasSuffix("." + allowed) { return true }
        }
        return false
    }

    /// http(s) that must not replace the grok.com overlay, plus mailto-style schemes.
    /// Dedicated xAI account pages may replace it temporarily. Once there, keep the
    /// allowlisted identity-provider redirect chain in WebKit so its cookies reach Grok.
    static func shouldOpenInBrowser(_ url: URL?, from currentURL: URL? = nil) -> Bool {
        guard let url else { return false }
        switch url.scheme?.lowercased() {
        case "http", "https":
            if isGrokHost(url.host) { return false }
            if isAuthEntryHost(url.host) { return false }
            if isAuthHost(currentURL?.host), isAuthHost(url.host) { return false }
            return true
        case "mailto", "tel", "sms", "facetime", "facetime-audio":
            return true
        default:
            return false
        }
    }

    /// New window that still needs the shared cookie jar (X / Apple OAuth).
    static func shouldPresentAuthPopup(_ url: URL?) -> Bool {
        guard let url else { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" { return true }
        if scheme == "http" || scheme == "https" {
            return isAuthHost(url.host)
        }
        return false
    }

    private static let authHosts = [
        "x.com",
        "twitter.com",
        "t.co",
        "accounts.x.ai",
        "auth.x.ai",
        "appleid.apple.com",
    ]

    private static let exactAuthHosts = [
        "auth.grokusercontent.com",
        "auth.grokipedia.com",
    ]

    /// Hosts Grok may use for a same-frame login start. Broad IdP hosts such as
    /// x.com are deliberately excluded so ordinary links still open in a browser.
    private static func isAuthEntryHost(_ host: String?) -> Bool {
        guard let host = normalizedHost(host) else { return false }
        return authEntryHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let authEntryHosts = [
        "accounts.x.ai",
        "auth.x.ai",
    ]

    private static func normalizedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }
}

// MARK: - Delegates (media + downloads + auth popups)

final class WebViewDelegate: NSObject, WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    weak var bridge: DownloadBridge?
    weak var overlayWebView: WKWebView?

    private var downloadDestinations: [ObjectIdentifier: (staging: URL, name: String)] = [:]

    private var lastBrowserURL: URL?
    private var lastBrowserOpenUptime: TimeInterval = 0

    private func isOverlay(_ webView: WKWebView) -> Bool {
        webView === overlayWebView
    }

    private func openInBrowser(_ url: URL) {
        let now = ProcessInfo.processInfo.systemUptime
        if lastBrowserURL == url, now - lastBrowserOpenUptime < 1 {
            return
        }
        lastBrowserURL = url
        lastBrowserOpenUptime = now
        NSWorkspace.shared.open(url)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let allowed = DownloadRequestPolicy.permitsSender(
            isExpectedView: isOverlay(webView), isMainFrame: frame.isMainFrame,
            frameURL: frame.request.url, currentURL: webView.url,
            originScheme: origin.protocol, originHost: origin.host, originPort: origin.port
        )
        // Let WebKit remember the user's website permission; OS-level app access
        // is not permission for an arbitrary embedded frame or OAuth popup.
        guard allowed else { decisionHandler(.deny); return }
        switch type {
        case .microphone, .cameraAndMicrophone, .camera: decisionHandler(.prompt)
        @unknown default: decisionHandler(.deny)
        }
    }

    /// X / OAuth often needs a real popup that shares the same cookie jar.
    /// Citations and Help links (`target=_blank`) must not become a "Sign in" window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url

        if NavigationPolicy.isGrokHost(url?.host) {
            (overlayWebView ?? webView).load(navigationAction.request)
            return nil
        }

        if NavigationPolicy.shouldPresentAuthPopup(url) {
            // Must use the provided configuration (shares process pool + data store with parent).
            // WebKit loads `navigationAction` into the returned view — do not load again.
            let popup = MenuAwareWebView(frame: .zero, configuration: configuration)
            popup.uiDelegate = self
            popup.navigationDelegate = self
            popup.customUserAgent = webView.customUserAgent
            popup.appearance = webView.appearance

            DispatchQueue.main.async {
                _ = AuthPopupPresenter.shared.present(
                    webView: popup,
                    requestedURL: url
                )
            }
            return popup
        }

        if let url, NavigationPolicy.shouldOpenInBrowser(url) {
            openInBrowser(url)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        DispatchQueue.main.async {
            AuthPopupPresenter.shared.close(webView: webView)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard isOverlay(webView) else { return }
        bridge?.navigationDidStart(navigation)
        Task { @MainActor in WebViewStore.shared.handleNavigationStarted() }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard isOverlay(webView) else { return }
        bridge?.documentDidCommit(in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isOverlay(webView) else { return }
        webView.evaluateJavaScript(WebViewStore.edgeFixScript, completionHandler: nil)
        Task { @MainActor in WebViewStore.shared.handleNavigationFinished() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isOverlay(webView) else { return }
        Task { @MainActor in WebViewStore.shared.handleNavigationFailed(error: error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isOverlay(webView) else { return }
        let restoredDocument = bridge?.provisionalNavigationFailed(navigation, in: webView) == true
        Task { @MainActor in
            if restoredDocument, WebRecoveryState.navigation(error) == nil {
                WebViewStore.shared.probeSessionActions()
            }
            WebViewStore.shared.handleNavigationFailed(error: error)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard isOverlay(webView) else { return }
        bridge?.invalidateDocument()
        Task { @MainActor in WebViewStore.shared.handleWebContentProcessTerminated() }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(Self.shouldSave(navigationResponse) ? .download : .allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        let url = navigationAction.request.url
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let overlay = isOverlay(webView)

        if isMainFrame, NavigationPolicy.shouldOpenInBrowser(url, from: webView.url) {
            let authInPopup = !overlay && NavigationPolicy.isAuthHost(url?.host)
            if !authInPopup {
                if let url {
                    openInBrowser(url)
                }
                if !overlay {
                    DispatchQueue.main.async {
                        AuthPopupPresenter.shared.close(webView: webView)
                    }
                }
                decisionHandler(.cancel, preferences)
                return
            }
        }

        // target=_blank without createWebView — grok.com stays in this view.
        if navigationAction.targetFrame == nil {
            if let url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                webView.load(navigationAction.request)
            }
            decisionHandler(.cancel, preferences)
            return
        }
        if overlay, isMainFrame, let url {
            Task { @MainActor in WebViewStore.shared.handleMainFrameNavigation(to: url) }
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            DownloadFeedback.failed(DownloadFailure.http(http.statusCode))
            completionHandler(nil)
            return
        }
        do {
            let staging = try DownloadPaths.stagingDestination()
            downloadDestinations[ObjectIdentifier(download)] = (staging, suggestedFilename)
            completionHandler(staging)
        } catch {
            DownloadFeedback.failed(error)
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try DownloadPaths.finishStagedDownload(destination.staging, suggestedName: destination.name)
                DownloadFeedback.saved(url)
            } catch { DownloadFeedback.failed(error) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: destination.staging.deletingLastPathComponent())
        }
        DownloadFeedback.failed(error)
    }

    private static func shouldSave(_ response: WKNavigationResponse) -> Bool {
        if !response.canShowMIMEType { return true }
        guard let http = response.response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Content-Disposition")
        else { return false }
        return header.range(of: "attachment", options: .caseInsensitive) != nil
    }
}

// MARK: - Context-menu download WebView

/// WebKit's built-in "Download Image" still goes through the page and hits CORS.
/// Swap those items so we fetch with URLSession instead.
final class MenuAwareWebView: WKWebView {
    weak var bridge: DownloadBridge?

    /// Tahoe titled windows report corner-radius safe areas. grok.com treats
    /// those as `env(safe-area-inset-*)` and leaves a strip on the bottom/right.
    /// Safari does not. Zero them so the page fills the view.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    /// Transparent titlebar does not claim empty space, so those points
    /// hit this view. Decline them so the drag strip / theme frame can.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let inWindow = convert(local, to: nil)
        let inset = PanelGeometry.titlebarInset(in: window)
        if inWindow.y >= window.frame.height - inset {
            return nil
        }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyEdgeFixes()
    }

    override func layout() {
        super.layout()
        applyEdgeFixes()
    }

    private func applyEdgeFixes() {
        focusRingType = .none
        additionalSafeAreaInsets = NSEdgeInsets()
        let insets = obscuredContentInsets
        if insets.top != 0 || insets.left != 0 || insets.bottom != 0 || insets.right != 0 {
            obscuredContentInsets = NSEdgeInsets()
        }
        stripAutomaticInsets(from: self)
    }

    /// Inner NSScrollView can pick up a 1px safe-area inset (no public WKWebView API).
    private func stripAutomaticInsets(from root: NSView) {
        if let scroll = root as? NSScrollView {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets()
        }
        root.subviews.forEach { stripAutomaticInsets(from: $0) }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierDownloadImage" where bridge?.imageURL != nil:
                rewire(item, action: #selector(saveContextImage))
            case "WKMenuItemIdentifierDownloadLinkedFile" where bridge?.linkURL != nil:
                rewire(item, action: #selector(saveContextLink))
            default:
                break
            }
        }
        super.willOpenMenu(menu, with: event)
    }

    private func rewire(_ item: NSMenuItem, action: Selector) {
        item.action = action
        item.target = self
        item.representedObject = nil
    }

    @objc private func saveContextImage() {
        guard let url = bridge?.imageURL else { return }
        pull(url, defaultExt: "png")
    }

    @objc private func saveContextLink() {
        guard let url = bridge?.linkURL else { return }
        pull(url, defaultExt: nil)
    }

    private func pull(_ url: URL, defaultExt: String?) {
        do {
            let request = try DownloadRequestPolicy.request(url: url)
            let transfer = AssetTransfer()
            transfer.start(request) { result in
                switch result {
                case .success(let output):
                    let name = Self.filename(from: output.response, url: url, defaultExt: defaultExt)
                    do {
                        let destination = try DownloadPaths.write(output.data, suggestedName: name)
                        DownloadFeedback.saved(destination)
                    } catch { DownloadFeedback.failed(error) }
                case .failure(let error): DownloadFeedback.failed(error)
                }
            }
        } catch { DownloadFeedback.failed(error) }
    }

    private static func filename(from response: URLResponse?, url: URL, defaultExt: String?) -> String {
        if let suggested = response?.suggestedFilename, !suggested.isEmpty, suggested != "/" {
            return suggested
        }
        let last = url.lastPathComponent
        if !last.isEmpty, last != "/" { return last }
        return "download.\(defaultExt ?? "bin")"
    }
}

extension DownloadBridge {
    /// Context-menu hit + fetch() fallback through `DownloadBridge`.
    static let pageScript = """
    (function () {
      var handlers = window.webkit && window.webkit.messageHandlers;
      var bridge = handlers && handlers.grockBridge;
      if (!bridge || window.top !== window || location.protocol !== 'https:' ||
          !['grok.com', 'www.grok.com'].includes(location.hostname)) return;
      var documentToken = null;
      document.addEventListener('grock-download-document', function (event) {
        documentToken = event.detail;
      });
      var assetHosts = ['assets.grok.com', 'assets.grokusercontent.com', 'imagine-public.x.ai',
                        'imgen.x.ai', 'vidgen.x.ai', 'files-cdn.x.ai'];

      function hrefOf(input) {
        if (typeof input === 'string') return input;
        if (input && typeof input.url === 'string') return input.url;
        return '';
      }

      function headerList(headers) {
        var pairs = [];
        if (!headers) return pairs;
        if (Array.isArray(headers)) return headers;
        if (typeof Headers !== 'undefined' && headers instanceof Headers) {
          headers.forEach(function (value, key) { pairs.push([key, value]); });
          return pairs;
        }
        if (typeof headers === 'object') {
          Object.keys(headers).forEach(function (key) {
            pairs.push([key, String(headers[key])]);
          });
        }
        return pairs;
      }

      function isOtherOrigin(href) {
        try {
          var url = new URL(href, location.href);
          return Boolean(href) && url.protocol === 'https:' && (!url.port || url.port === '443') &&
            !url.username && !url.password && assetHosts.includes(url.hostname);
        } catch (_) {
          return false;
        }
      }

      function backgroundURL(el) {
        var raw = window.getComputedStyle(el).backgroundImage;
        if (!raw || raw === 'none') return null;
        var start = raw.indexOf('url(');
        if (start < 0) return null;
        var s = raw.slice(start + 4).trim();
        var quote = s.charAt(0);
        if (quote === '"' || quote === "'") s = s.slice(1);
        var end = s.lastIndexOf(')');
        if (end >= 0) s = s.slice(0, end);
        var last = s.charAt(s.length - 1);
        if (last === '"' || last === "'") s = s.slice(0, -1);
        return s || null;
      }

      function imageFromEvent(target) {
        if (target.tagName === 'IMG') {
          return target.currentSrc || target.src || null;
        }
        var picture = target.closest && target.closest('picture');
        if (picture) {
          var img = picture.querySelector('img');
          if (img) return img.currentSrc || img.src || null;
        }
        return backgroundURL(target);
      }

      document.addEventListener('contextmenu', function (event) {
        var target = event.target;
        var link = target.closest && target.closest('a');
        if (!documentToken) return;
        bridge.postMessage({
          kind: 'context',
          documentToken: documentToken,
          image: imageFromEvent(target),
          link: (link && link.href) ? link.href : null
        }).catch(function () {});
      }, true);

      var browserFetch = window.fetch.bind(window);
      window.fetch = async function (input, init) {
        try {
          return await browserFetch(input, init);
        } catch (error) {
          var signal = (init && init.signal) || (input && input.signal);
          if ((error && error.name === 'AbortError') || (signal && signal.aborted)) throw error;
          var href = hrefOf(input);
          var method = (init && init.method) || (input && input.method) || 'GET';
          if (!documentToken || method.toUpperCase() !== 'GET' || !isOtherOrigin(href)) throw error;
          var headers = headerList((init && init.headers) || (input && input.headers));
          if (headers.some(function (pair) { return pair[0].toLowerCase() !== 'accept'; })) throw error;
          var result = await bridge.postMessage({
            kind: 'proxy',
            documentToken: documentToken,
            href: new URL(href, location.href).href,
            verb: method,
            headerPairs: headers
          });
          if (!result || !result.bytes) throw error;
          var raw = atob(result.bytes);
          var buffer = new ArrayBuffer(raw.length);
          var bytes = new Uint8Array(buffer);
          for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
          return new Response(buffer, {
            status: result.code || 200,
            headers: {
              'Content-Type': result.mime || 'application/octet-stream',
              'Content-Disposition': result.disposition || ''
            }
          });
        }
      };
    })();
    """

}
