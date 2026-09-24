import AppKit
import WebKit

struct WebRecoveryState: Equatable {
    let title: String
    let message: String

    static func navigation(_ error: Error) -> WebRecoveryState? {
        let error = error as NSError
        // WebKit cancels replaced loads and navigations handed to a download/browser.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return nil }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return nil }
        return WebRecoveryState(
            title: "Grok couldn't load",
            message: "Check your connection and try again. You can also open Grok in your browser."
        )
    }

    static let contextNotAdded = WebRecoveryState(
        title: "Grok couldn't add your context",
        message: "Your text and files are still here. Retry reloads the page and adds them to the composer."
    )

    static let processTerminated = WebRecoveryState(
        title: "Grok's page stopped",
        message: "Reload the page to continue. If you were sending a message, check the chat before trying again."
    )
}

/// Native recovery lives above a hidden WKWebView, which otherwise paints over siblings.
final class WebRecoveryView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let retry = NSButton(title: "Retry", target: nil, action: nil)
    var onRetry: (() -> Void)?
    var onOpenBrowser: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.alignment = .center
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        retry.target = self
        retry.action = #selector(retryPage)
        retry.bezelStyle = .rounded
        let browser = NSButton(title: "Open in Browser", target: self, action: #selector(openBrowser))
        browser.bezelStyle = .rounded
        let actions = NSStackView(views: [retry, browser])
        actions.spacing = 12
        let stack = NSStackView(views: [titleLabel, messageLabel, actions])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ state: WebRecoveryState?) {
        isHidden = state == nil
        titleLabel.stringValue = state?.title ?? ""
        messageLabel.stringValue = state?.message ?? ""
        retry.keyEquivalent = state == nil ? "" : "\r"
        if let state {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isHidden, let window = self.window, window.isKeyWindow else { return }
                window.makeFirstResponder(self.retry)
            }
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: state.title, .priority: NSAccessibilityPriorityLevel.high])
        }
    }

    @objc private func retryPage() { onRetry?() }
    @objc private func openBrowser() { onOpenBrowser?() }
}

/// A footer gets its own space below WebKit so it remains visible without a popup.
final class DownloadStatusView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let reveal = NSButton(title: "Show in Finder", target: nil, action: nil)
    private var fileURL: URL?
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        reveal.target = self
        reveal.action = #selector(revealFile)
        reveal.bezelStyle = .rounded
        let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss download status") ?? NSImage(), target: self, action: #selector(dismissStatus))
        dismiss.isBordered = false
        let stack = NSStackView(views: [label, reveal, dismiss])
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(message: String, fileURL: URL?) {
        label.stringValue = message
        self.fileURL = fileURL
        reveal.isHidden = fileURL == nil
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium])
    }

    @objc private func revealFile() {
        if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
    }
    @objc private func dismissStatus() { onDismiss?() }
}
