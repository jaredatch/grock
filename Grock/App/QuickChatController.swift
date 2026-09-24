import AppKit
import Observation
import QuickLookUI

struct StagedAttachment: Identifiable, Equatable {
    let id: UUID
    var attachment: QuickChatAttachment

    init(id: UUID = UUID(), attachment: QuickChatAttachment) {
        self.id = id
        self.attachment = attachment
    }
}

/// Native intake for Quick Chat (DEC-041). Gather, package, throw.
@MainActor
@Observable
final class QuickChatController {
    static let shared = QuickChatController()

    var draft = ""
    var textChip: String?
    var textChipCopiedAt: Date?
    var attachments: [StagedAttachment] = []
    var isPresented = false
    var composerFocusGeneration = 0
    var sendFailed = false
    var sendFailedDetail: String?
    var sendUncertain = false
    var intakeError: String? { intakeFailures.first?.message }
    private(set) var pendingIntakeCount = 0
    private(set) var isChoosingFile = false

    typealias FileChooser = (URL, @escaping (URL?) -> Void) -> NSOpenPanel?
    private let fileChooser: FileChooser
    var fileLoader = FileIntake.load

    init(fileChooser: @escaping FileChooser = FileIntake.chooseFile) {
        self.fileChooser = fileChooser
    }

    private struct FileAddition {
        var urls: [URL]
        var source: QuickChatSource
        var copiedAt: Date?
    }

    private struct IntakeFailure {
        let id: UUID
        var message: String
        var addition: FileAddition?
        var deniedFile: URL?
    }

    private var intakeFailures: [IntakeFailure] = []
    private var filePicker: NSOpenPanel?
    private var recoveredPrefill: ((QuickChatPayload) -> Void)?

    var canChooseFile: Bool {
        intakeFailures.first?.deniedFile != nil && intakeFailures.first?.addition != nil
    }

    let pasteboardMonitor = PasteboardMonitor()

    private var panel: QuickChatPanel?
    private var isSending = false
    private var isQuickLooking = false
    private let previewController = QuickChatPreviewController()
    private var previewDirectory: URL?
    private var previewCloseObserver: NSObjectProtocol?
    private var clipboardPreferenceObserver: NSObjectProtocol?
    private var packageGeneration = UUID()
    private var submissionID: UUID?
    private var intakeTask: Task<Void, Never>?
    private var intakeTasks: [Task<Void, Never>] = []

    var canSend: Bool {
        guard !isSending, !isChoosingFile, pendingIntakeCount == 0, intakeError == nil, !sendUncertain,
              makePayload().validationError == nil else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || textChip != nil
            || !attachments.isEmpty
    }

    var sendFailedMessage: String {
        if sendUncertain {
            return "Grok may have received this. Check the chat before trying again to avoid sending it twice."
        }
        switch sendFailedDetail {
        case "no-composer":
            return "Grok wasn't ready. Try Send again."
        case nil, .some(""):
            return "Couldn't send. The package is still here."
        case "attachment-failed", "attachment-unconfirmed":
            return "Grok couldn't attach every file. The package is still here."
        default:
            return "Couldn't send. The package is still here."
        }
    }

    var statusMessage: String? {
        if let intakeError { return intakeError + " No files from that addition were attached." }
        if pendingIntakeCount > 0 { return "Preparing files…" }
        return sendFailed ? sendFailedMessage : nil
    }

    var statusFooterHeight: CGFloat {
        guard let message = statusMessage else { return 0 }
        let width = QuickChatComposer.cardWidth - QuickChatComposer.headerHorizontalInset * 2
        let bounds = (message as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: QuickChatComposer.secondaryFontSize)]
        )
        return ceil(bounds.height) + QuickChatComposer.errorTopInset + QuickChatComposer.errorBottomInset
            + (intakeError != nil || sendUncertain ? 30 : 0)
    }

    var textChipPreview: String {
        guard let textChip else { return "" }
        return QuickChatAttachment.collapsedSnippet(textChip)
    }

    var stagedItemCount: Int {
        (textChip != nil ? 1 : 0) + attachments.count
    }

    /// Watches the pasteboard only while clipboard capture is on, and
    /// follows the Settings toggle (and Reset) without a relaunch.
    func startMonitoring() {
        syncClipboardMonitoring()
        guard clipboardPreferenceObserver == nil else { return }
        clipboardPreferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncClipboardMonitoring() }
        }
    }

    private func syncClipboardMonitoring() {
        pasteboardMonitor.sync(enabled: ClipboardPreference.autoInclude())
    }

    func present() {
        if isPresented {
            panel?.applySummonPlacement()
            NSApp.activate(ignoringOtherApps: true)
            panel?.focusComposer()
            composerFocusGeneration += 1
            return
        }
        if !sendUncertain { gather() }
        presentAssembled()
    }

    /// Land a `grock://ask` package. Does not read the clipboard (DEC-049).
    func present(chip text: String?, files: [URL] = []) {
        clearPackage()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        textChip = trimmed.isEmpty ? nil : trimmed
        textChipCopiedAt = textChip == nil ? nil : Date()
        presentAssembled()
        addFiles(files)
    }

    /// OS-handed files (DEC-050). No clipboard gather, no send. Appends if the card is up.
    @discardableResult
    func presentFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        if !isPresented { clearPackage() }
        presentAssembled()
        addFiles(urls)
        return true
    }

    /// Status extra file drops (DEC-050). Overlay drops stay with grok.com.
    @discardableResult
    func presentDropped(_ pasteboard: NSPasteboard) -> Bool {
        let files = FileIntake.fileURLs(from: pasteboard, validate: false)
        if !files.isEmpty { return presentFiles(files) }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return false }
        if !isPresented { clearPackage() }
        presentAssembled()
        addImage(data, source: .disk, copiedAt: nil)
        return true
    }

    /// Synchronous compatibility hook for isolated tests; app callers use addFiles.
    @discardableResult
    func ingestOSFiles(_ urls: [URL]) -> Int {
        do {
            let incoming = try FileIntake.loadSynchronously(urls,
                existingBytes: isPresented ? attachmentBytes : 0,
                existingCount: isPresented ? attachments.count : 0)
            guard !incoming.isEmpty else { return 0 }
            applyOSAttachments(incoming)
            return incoming.count
        } catch {
            recordIntakeFailure(error, addition: FileAddition(urls: urls, source: .disk))
            return 0
        }
    }

    func dismiss() {
        guard !isSending else { return }
        isPresented = false
        panel?.orderOut(nil)
        clearPackage()
    }

    func handleResignKey() {
        guard isPresented, !isSending else { return }
        if shouldStayForKeyWindow() { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isPresented, !self.isSending else { return }
            if self.shouldStayForKeyWindow() { return }
            if self.sendUncertain {
                self.isPresented = false
                self.panel?.orderOut(nil)
                return
            }
            self.dismiss()
        }
    }

    func isPanel(_ window: NSWindow) -> Bool {
        window === panel
    }

    func removeTextChip() {
        textChip = nil
        textChipCopiedAt = nil
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    @discardableResult
    func addDroppedPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let isClipboard = pasteboard == NSPasteboard.general
        let source: QuickChatSource = isClipboard ? .clipboard : .disk
        let copiedAt: Date? = isClipboard ? Date() : nil
        // An explicit Paste is intentional and does not use automatic-capture filters.
        let files = FileIntake.fileURLs(from: pasteboard, validate: false)
        if !files.isEmpty { addFiles(files, source: source, copiedAt: copiedAt); return true }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            addImage(data, source: source, copiedAt: copiedAt)
            return true
        }
        return false
    }

    func addFiles(_ urls: [URL], source: QuickChatSource = .disk, copiedAt: Date? = nil) {
        guard !urls.isEmpty else { return }
        enqueueFiles(FileAddition(urls: urls, source: source, copiedAt: copiedAt))
    }

    private func enqueueFiles(_ addition: FileAddition, retrying failureID: UUID? = nil) {
        let loader = fileLoader
        enqueueIntake(addition: addition, retrying: failureID) { bytes, count in
            try await loader(addition.urls, addition.source, addition.copiedAt, bytes, count)
        }
    }

    private func addImage(_ data: Data, source: QuickChatSource, copiedAt: Date?) {
        enqueueIntake { _, _ in try await FileIntake.loadImage(data, source: source, copiedAt: copiedAt) }
    }

    private var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.attachment.data.count } }

    private func enqueueIntake(addition: FileAddition? = nil, retrying failureID: UUID? = nil,
                               _ load: @escaping (Int, Int) async throws -> [QuickChatAttachment]) {
        let previous = intakeTask
        let generation = packageGeneration
        pendingIntakeCount += 1
        let task = Task { [weak self] in
            await previous?.value
            guard let self, generation == self.packageGeneration, !Task.isCancelled else { return }
            defer {
                if generation == self.packageGeneration {
                    self.pendingIntakeCount -= 1
                    if self.pendingIntakeCount == 0 { self.intakeTasks = [] }
                    self.finishRecoveredPrefill()
                }
            }
            do {
                let incoming = try await load(self.attachmentBytes, self.attachments.count)
                guard generation == self.packageGeneration, !Task.isCancelled else { return }
                let combined = self.attachments.map(\.attachment) + incoming
                if let error = QuickChatPayload(text: "", attachments: combined).validationError {
                    self.recordIntakeFailure(message: error, addition: addition, retrying: failureID)
                    return
                }
                if let failureID { self.intakeFailures.removeAll { $0.id == failureID } }
                self.attachments.append(contentsOf: incoming.map { StagedAttachment(attachment: $0) })
            } catch is CancellationError { return }
            catch {
                guard generation == self.packageGeneration, !Task.isCancelled else { return }
                self.recordIntakeFailure(error, addition: addition, retrying: failureID)
            }
        }
        intakeTask = task
        intakeTasks.append(task)
    }

    func waitForPendingIntake() async { await intakeTask?.value }

    func discardFailedAddition() {
        guard !isChoosingFile, pendingIntakeCount == 0, !intakeFailures.isEmpty else { return }
        intakeFailures.removeFirst()
        finishRecoveredPrefill()
    }

    private func recordIntakeFailure(_ error: Error, addition: FileAddition? = nil, retrying id: UUID? = nil) {
        let denied: URL?
        if case .permissionDenied(let url) = error as? FileIntake.IntakeError { denied = url }
        else { denied = nil }
        recordIntakeFailure(message: error.localizedDescription, addition: addition, deniedFile: denied, retrying: id)
    }

    private func recordIntakeFailure(message: String, addition: FileAddition?, deniedFile: URL? = nil,
                                     retrying id: UUID? = nil) {
        let failure = IntakeFailure(id: id ?? UUID(), message: message, addition: addition, deniedFile: deniedFile)
        if let id, let index = intakeFailures.firstIndex(where: { $0.id == id }) { intakeFailures[index] = failure }
        else { intakeFailures.append(failure) }
    }

    func chooseDeniedFile() {
        guard !isChoosingFile, pendingIntakeCount == 0, let failure = intakeFailures.first,
              let requested = failure.deniedFile, var addition = failure.addition else { return }
        let generation = packageGeneration
        isChoosingFile = true
        filePicker = fileChooser(requested) { [weak self] selected in
            // The picker starts access implicitly. The loader manages its own
            // balanced start/stop on the retained URL when the queued read runs.
            defer { selected?.stopAccessingSecurityScopedResource() }
            guard let self, self.packageGeneration == generation,
                  let index = self.intakeFailures.firstIndex(where: { $0.id == failure.id }) else { return }
            self.filePicker = nil
            self.isChoosingFile = false
            defer { self.panel?.focusComposer() }
            guard let selected else { return }
            func path(_ url: URL) -> String {
                url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
            }
            guard selected.isFileURL, path(selected) == path(requested) else {
                self.intakeFailures[index].message = "Choose \(requested.lastPathComponent). The selected file wasn't attached."
                return
            }
            addition.urls = addition.urls.map { path($0) == path(requested) ? selected : $0 }
            self.enqueueFiles(addition, retrying: failure.id)
        }
    }

    private func finishRecoveredPrefill() {
        guard pendingIntakeCount == 0, !isChoosingFile, intakeFailures.isEmpty,
              let completion = recoveredPrefill else { return }
        let payload = makePayload()
        recoveredPrefill = nil
        dismiss()
        completion(payload)
    }

    func acknowledgeUncertainSend() {
        sendUncertain = false
        sendFailed = false
        sendFailedDetail = nil
    }

    func reviewUncertainSend() {
        isPresented = false
        panel?.orderOut(nil)
        AppDelegate.shared?.showPanel(focusInput: false)
    }

    func presentIntakeError(_ error: Error, retrying files: [URL] = [],
                            onRecovered: ((QuickChatPayload) -> Void)? = nil) {
        if !isPresented { clearPackage() }
        recoveredPrefill = onRecovered
        recordIntakeFailure(error, addition: files.isEmpty ? nil : FileAddition(urls: files, source: .disk))
        presentAssembled()
    }

    func previewTextChip() {
        guard let textChip else { return }
        guard let url = materializePreview(filename: "Clipboard.txt", data: Data(textChip.utf8)) else { return }
        presentPreview(url: url)
    }

    func previewAttachment(_ id: UUID) {
        guard let item = attachments.first(where: { $0.id == id }) else { return }
        let name = item.attachment.filename.isEmpty ? "attachment" : item.attachment.filename
        guard let url = materializePreview(filename: name, data: item.attachment.data) else { return }
        presentPreview(url: url)
    }

    func send() {
        guard canSend, !isSending else { return }
        if recoveredPrefill != nil { finishRecoveredPrefill(); return }
        let payload = makePayload()
        let generation = packageGeneration
        let attempt = UUID()
        submissionID = attempt
        let restoreDraft = draft
        let restoreText = textChip
        let restoreCopiedAt = textChipCopiedAt
        let restoreFiles = attachments
        isSending = true
        sendFailed = false
        sendFailedDetail = nil
        isPresented = false
        panel?.orderOut(nil)

        guard let app = AppDelegate.shared else {
            isSending = false
            sendFailedDetail = "no-app"
            restore(
                draft: restoreDraft,
                text: restoreText,
                copiedAt: restoreCopiedAt,
                files: restoreFiles,
                failed: true
            )
            return
        }
        app.startNewChat(payload: payload) { [weak self] outcome in
            guard let self else { return }
            guard self.submissionID == attempt else { return }
            self.submissionID = nil
            self.isSending = false
            guard self.packageGeneration == generation else { return }
            guard self.makePayload() == payload else {
                self.presentAssembled()
                return
            }
            if outcome == .accepted {
                self.clearPackage()
            } else {
                self.sendUncertain = outcome == .uncertain
                self.sendFailedDetail = WebViewStore.shared.lastPayloadOutcome
                self.restore(
                    draft: restoreDraft,
                    text: restoreText,
                    copiedAt: restoreCopiedAt,
                    files: restoreFiles,
                    failed: true
                )
            }
        }
    }

    func makePayload() -> QuickChatPayload {
        QuickChatPayload(
            text: QuickChatAttachment.combinedText(draft: draft, clipboardText: textChip),
            attachments: attachments.map(\.attachment)
        )
    }

    private func applyOSAttachments(_ incoming: [QuickChatAttachment]) {
        let staged = incoming.map { StagedAttachment(attachment: $0) }
        if isPresented {
            attachments.append(contentsOf: staged)
            return
        }
        draft = ""
        textChip = nil
        textChipCopiedAt = nil
        attachments = staged
    }

    private func presentAssembled() {
        if !sendUncertain {
            sendFailed = false
            sendFailedDetail = nil
        }
        isPresented = true
        composerFocusGeneration += 1
        let panel = ensurePanel()
        panel.applySummonPlacement()
        NSApp.activate(ignoringOtherApps: true)
        panel.focusComposer()
    }

    private func gather() {
        clearPackage()
        pasteboardMonitor.poll()
        guard let snap = pasteboardMonitor.snapshotIfRecent() else { return }
        textChip = snap.text
        textChipCopiedAt = snap.text == nil ? nil : snap.copiedAt
        attachments = snap.attachments.map { StagedAttachment(attachment: $0) }
        addFiles(snap.fileURLs, source: .clipboard, copiedAt: snap.copiedAt)
        if let data = snap.imageData { addImage(data, source: .clipboard, copiedAt: snap.copiedAt) }
    }

    private func clearPackage() {
        packageGeneration = UUID()
        intakeTasks.forEach { $0.cancel() }
        intakeTasks = []
        intakeTask = nil
        pendingIntakeCount = 0
        intakeFailures = []
        recoveredPrefill = nil
        let picker = filePicker
        filePicker = nil
        isChoosingFile = false
        picker?.cancel(nil)
        sendUncertain = false
        draft = ""
        textChip = nil
        textChipCopiedAt = nil
        attachments = []
        sendFailed = false
        sendFailedDetail = nil
        closePreview()
        cleanupPreviews()
    }

    func syncPanelSize(keepTop: Bool = true) {
        guard isPresented else { return }
        // SwiftUI calls this from `onChange` while it is still reconciling the
        // text view's font and line geometry. Resize on the next main-loop turn
        // so AppKit never mutates the panel and Tahoe glass mid-layout.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            self.panel?.relayout(keepTop: keepTop)
        }
    }

    func prepareForDrops() {
        panel?.prepareForDrops()
    }

    private func restore(
        draft: String,
        text: String?,
        copiedAt: Date?,
        files: [StagedAttachment],
        failed: Bool
    ) {
        self.draft = draft
        textChip = text
        textChipCopiedAt = copiedAt
        attachments = files
        sendFailed = failed
        isPresented = true
        composerFocusGeneration += 1
        let panel = ensurePanel()
        panel.applySummonPlacement()
        NSApp.activate(ignoringOtherApps: true)
        panel.focusComposer()
    }

    private func shouldStayForKeyWindow() -> Bool {
        if isChoosingFile { return true }
        if let key = NSApp.keyWindow {
            if isPanel(key) { return true }
            if key is QLPreviewPanel { return true }
        }
        if isQuickLooking { return true }
        return isPreviewPanelVisible()
    }

    private func presentPreview(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        listenForPreviewClose()
        previewController.urls = [url]
        panel.dataSource = previewController
        isQuickLooking = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePreview() {
        if isQuickLooking, isPreviewPanelVisible() {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        previewDidClose()
    }

    private func isPreviewPanelVisible() -> Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else { return false }
        return panel.isVisible
    }

    private func previewDidClose() {
        guard isQuickLooking else { return }
        isQuickLooking = false
        previewController.urls = []
        guard isPresented else { return }
        if NSApp.isActive == false {
            dismiss()
            return
        }
        if let key = NSApp.keyWindow, !isPanel(key) {
            dismiss()
            return
        }
        panel?.focusComposer()
    }

    private func listenForPreviewClose() {
        guard previewCloseObserver == nil else { return }
        previewCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, window is QLPreviewPanel else { return }
            Task { @MainActor in
                guard let self else { return }
                if self.isPreviewPanelVisible() {
                    return
                }
                self.previewDidClose()
            }
        }
    }

    private func materializePreview(filename: String, data: Data) -> URL? {
        let dir: URL
        if let previewDirectory {
            dir = previewDirectory
        } else {
            let next = FileManager.default.temporaryDirectory
                .appendingPathComponent("grock-ql-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
            } catch {
                return nil
            }
            previewDirectory = next
            dir = next
        }
        let safe = filename.isEmpty ? "attachment" : filename
        let url = dir.appendingPathComponent("\(UUID().uuidString)-\(safe)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private func cleanupPreviews() {
        if let previewDirectory {
            try? FileManager.default.removeItem(at: previewDirectory)
            self.previewDirectory = nil
        }
    }

    private func ensurePanel() -> QuickChatPanel {
        if let panel { return panel }
        let panel = QuickChatPanel(controller: self)
        self.panel = panel
        return panel
    }
}

private final class QuickChatPreviewController: NSObject, QLPreviewPanelDataSource {
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        urls[index] as NSURL
    }
}
