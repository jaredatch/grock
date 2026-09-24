import AppKit
import SwiftUI

/// Two-step capture card (DEC-041). Short prompt is one Spotlight-sized line.
/// Wrapping snaps to a smaller font in a five-line viewport. Staged files sit
/// under the field as Spotlight-style rows.
enum QuickChatComposer {
    static let cardWidth: CGFloat = 640
    static let headerHeight: CGFloat = 56
    static let headerHorizontalInset: CGFloat = 20
    static let headerVerticalInset: CGFloat = 13
    static let leadingIconSide: CGFloat = 24
    static let leadingIconSpacing: CGFloat = 14
    static let sendSpacing: CGFloat = 12
    static let sendSide: CGFloat = 28
    static let shortFontSize: CGFloat = 26
    static let longFontSize: CGFloat = 16
    static let secondaryFontSize: CGFloat = 13
    static let shortLineLimit = 1
    static let longLineLimit = 5
    static let rowHeight: CGFloat = 56
    static let rowArtWidth: CGFloat = 28
    static let rowArtHeight: CGFloat = 36
    static let rowIconSpacing: CGFloat = 19
    static let rowContentHorizontalInset: CGFloat = 14
    static let rowBackgroundHorizontalInset: CGFloat = 10
    static let rowHoverCornerRadius: CGFloat = 18
    static let maxVisibleRows = 7
    static let dividerHeight: CGFloat = 1
    static let listTopInset: CGFloat = 10
    static let listBottomInset: CGFloat = 9
    static let errorTopInset: CGFloat = 10
    static let errorBottomInset: CGFloat = 13
    static let cardCornerRadius: CGFloat = 30

    static var fieldWidth: CGFloat {
        cardWidth
            - headerHorizontalInset * 2
            - leadingIconSide
            - leadingIconSpacing
            - sendSide
            - sendSpacing
    }

    static var minHeight: CGFloat {
        cardHeight(text: "", itemCount: 0, hasError: false)
    }

    static func stagedItemCount(textChip: String?, attachments: [QuickChatAttachment]) -> Int {
        (textChip != nil ? 1 : 0) + attachments.count
    }

    static func itemListHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return dividerHeight + itemListViewportHeight(itemCount: itemCount)
    }

    static func itemListViewportHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let visible = min(itemCount, maxVisibleRows)
        return listTopInset
            + CGFloat(visible) * rowHeight
            + listBottomInset
    }

    static func lineHeight(for fontSize: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: fontSize))
    }

    static func isExpanded(_ text: String) -> Bool {
        lineCount(text, fontSize: shortFontSize, width: fieldWidth) > shortLineLimit
    }

    static func visibleFieldLines(_ text: String) -> Int {
        if !isExpanded(text) { return 1 }
        return longLineLimit
    }

    static func needsVerticalScroller(_ text: String) -> Bool {
        lineCount(text, fontSize: longFontSize, width: fieldWidth) > longLineLimit
    }

    static func fieldHeight(for text: String) -> CGFloat {
        if !isExpanded(text) {
            return lineHeight(for: shortFontSize)
        }
        return CGFloat(visibleFieldLines(text)) * lineHeight(for: longFontSize)
    }

    static func accessoryTopInset(side: CGFloat, for text: String) -> CGFloat {
        let line = isExpanded(text) ? lineHeight(for: longFontSize) : lineHeight(for: shortFontSize)
        return max(0, (line - side) / 2)
    }

    static func composerHeight(for text: String) -> CGFloat {
        max(headerHeight, headerVerticalInset * 2 + fieldHeight(for: text))
    }

    static func lineCount(_ text: String, fontSize: CGFloat, width: CGFloat) -> Int {
        if text.isEmpty { return 1 }
        let font = NSFont.systemFont(ofSize: fontSize)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(width, 1), height: 10_000))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let glyphCount = manager.numberOfGlyphs
        if glyphCount == 0 {
            return max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        }
        var lines = 0
        var glyph = 0
        while glyph < glyphCount {
            var lineRange = NSRange()
            manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
            lines += 1
            glyph = NSMaxRange(lineRange)
        }
        if text.hasSuffix("\n") { lines += 1 }
        return max(1, lines)
    }

    static func cardHeight(text: String, itemCount: Int, hasError: Bool) -> CGFloat {
        var height = composerHeight(for: text)
        height += itemListHeight(itemCount: itemCount)
        if hasError {
            height += errorTopInset + ceil(secondaryFontSize * 1.35) + errorBottomInset
        }
        return height
    }

    @MainActor
    static func cardSize(for controller: QuickChatController) -> NSSize {
        NSSize(
            width: cardWidth,
            height: cardHeight(
                text: controller.draft,
                itemCount: controller.stagedItemCount,
                hasError: false
            ) + controller.statusFooterHeight
        )
    }
}

/// Lets AppKit's glass foreground treatment reach the SwiftUI subtree.
final class QuickChatHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { true }
}

/// Steals Finder file drags from the SwiftUI text field. NSTextView's default
/// is to insert the POSIX path into the prompt.
final class QuickChatDropHost: NSView {
    weak var controller: QuickChatController?
    private let hosting: NSHostingView<QuickChatView>
    /// `NSPasteboard.drag` keeps the last drop. Clicks in-panel remember that
    /// changeCount so leftover files do not steal text selection.
    private var ignoreDragChangeCount: Int?

    init(controller: QuickChatController, hosting: NSHostingView<QuickChatView>) {
        self.controller = controller
        self.hosting = hosting
        super.init(frame: .zero)
        addSubview(hosting)
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            .pdf,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        Self.unregisterFileDrags(in: self)
    }

    func prepareForDrops() {
        Self.unregisterFileDrags(in: self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Self.unregisterFileDrags(in: self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let event = NSApp.currentEvent
        let pasteboard = NSPasteboard(name: .drag)
        if event?.window === window,
           event?.type == .leftMouseDown || event?.type == .rightMouseDown {
            ignoreDragChangeCount = pasteboard.changeCount
        }
        if Self.shouldStealFileDrag(
            hasFiles: Self.canAccept(pasteboard),
            pressedButtons: Int(NSEvent.pressedMouseButtons),
            eventType: event?.type,
            eventIsInPanel: event?.window === window,
            isLeftoverDrag: ignoreDragChangeCount == pasteboard.changeCount
        ) {
            return self
        }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.unregisterFileDrags(in: self)
        return Self.canAccept(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        ignoreDragChangeCount = sender.draggingPasteboard.changeCount
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ignoreDragChangeCount = sender.draggingPasteboard.changeCount
        guard let controller else { return false }
        return controller.addDroppedPasteboard(sender.draggingPasteboard)
    }

    func focusComposer(tries: Int = 0) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        guard let window else {
            scheduleFocusRetry(tries: tries)
            return
        }
        if let text = Self.firstTextView(in: self) {
            window.makeFirstResponder(text)
            return
        }
        scheduleFocusRetry(tries: tries)
    }

    private func scheduleFocusRetry(tries: Int) {
        guard tries < 16 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.focusComposer(tries: tries + 1)
        }
    }

    static func firstTextView(in view: NSView) -> NSTextView? {
        if let text = view as? QuickChatNSTextView { return text }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            if let text = firstTextView(in: document) { return text }
        }
        for subview in view.subviews {
            if let text = firstTextView(in: subview) { return text }
        }
        return nil
    }

    /// Finder file drags must beat a focused NSTextView. A leftover drag
    /// pasteboard after a drop must not steal text selection.
    static func shouldStealFileDrag(
        hasFiles: Bool,
        pressedButtons: Int,
        eventType: NSEvent.EventType?,
        eventIsInPanel: Bool,
        isLeftoverDrag: Bool
    ) -> Bool {
        guard hasFiles, pressedButtons & 1 != 0 else { return false }
        if eventIsInPanel, let eventType {
            switch eventType {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
                return false
            case .leftMouseDragged, .rightMouseDragged:
                return !isLeftoverDrag
            default:
                break
            }
        }
        return !isLeftoverDrag
    }

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: FileIntake.draggedTypes) != nil
    }

    static func unregisterFileDrags(in view: NSView) {
        if let text = view as? NSTextView {
            let allowed = text.registeredDraggedTypes.filter { type in
                type != .fileURL
                    && type != .png
                    && type != .tiff
                    && type != .pdf
                    && type.rawValue != "NSFilenamesPboardType"
            }
            text.unregisterDraggedTypes()
            if !allowed.isEmpty {
                text.registerForDraggedTypes(allowed)
            }
        }
        view.subviews.forEach { unregisterFileDrags(in: $0) }
    }
}

/// Small activating HUD. Not a WebView. Not the overlay (DEC-041).
final class QuickChatPanel: NSPanel, NSWindowDelegate {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static let cardWidth = QuickChatComposer.cardWidth
    static var minHeight: CGFloat { QuickChatComposer.minHeight }

    private let hosting: NSHostingView<QuickChatView>
    private let dropHost: QuickChatDropHost
    private let glassView: NSGlassEffectView
    private weak var controller: QuickChatController?

    init(controller: QuickChatController) {
        let hosting = QuickChatHostingView(rootView: QuickChatView(controller: controller))
        self.hosting = hosting
        self.dropHost = QuickChatDropHost(controller: controller, hosting: hosting)
        self.glassView = NSGlassEffectView()
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: QuickChatComposer.cardWidth,
                height: QuickChatComposer.minHeight
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.controller = controller
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        delegate = self
        glassView.style = .regular
        glassView.cornerRadius = QuickChatComposer.cardCornerRadius
        glassView.wantsLayer = true
        glassView.clipsToBounds = true
        glassView.layer?.cornerRadius = QuickChatComposer.cardCornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.contentView = dropHost
        contentView = glassView
        invalidateShadow()
    }

    func relayout(keepTop: Bool = true) {
        let size: NSSize
        if let controller {
            size = QuickChatComposer.cardSize(for: controller)
        } else {
            size = NSSize(width: Self.cardWidth, height: Self.minHeight)
        }
        applyContentSize(size, keepTop: keepTop)
    }

    private func applyContentSize(_ size: NSSize, keepTop: Bool) {
        let nextSize = NSSize(
            width: Self.cardWidth,
            height: max(size.height, Self.minHeight)
        )
        if abs(contentLayoutRect.width - nextSize.width) < 0.5,
           abs(contentLayoutRect.height - nextSize.height) < 0.5 {
            return
        }
        let top = frame.maxY
        var nextFrame = frameRect(
            forContentRect: NSRect(origin: .zero, size: nextSize)
        )
        nextFrame.origin.x = frame.origin.x
        nextFrame.origin.y = keepTop ? top - nextFrame.height : frame.origin.y
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            setFrame(nextFrame, display: true)
            glassView.needsLayout = true
            glassView.cornerRadius = QuickChatComposer.cardCornerRadius
            glassView.layer?.cornerRadius = QuickChatComposer.cardCornerRadius
            invalidateShadow()
        }
    }

    /// Center on the display under the cursor, this Space (DEC-024 family).
    func applySummonPlacement() {
        relayout(keepTop: false)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        var next = frame
        next.origin.x = visible.midX - next.width / 2
        next.origin.y = visible.midY - next.height / 2 + 72
        next = PanelGeometry.constrainedFrame(
            next,
            visibleScreens: [visible],
            minSize: NSSize(width: 280, height: Self.minHeight)
        )
        setFrame(next, display: true)
        dropHost.prepareForDrops()
    }

    func prepareForDrops() {
        dropHost.prepareForDrops()
    }

    func focusComposer() {
        makeKeyAndOrderFront(nil)
        dropHost.focusComposer()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        dropHost.prepareForDrops()
        dropHost.focusComposer()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        controller?.dismiss()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        controller?.handleResignKey()
    }
}

/// Steals Finder file drags so the status button does not eat them.
final class FileDropCatcher: NSView {
    var onDrop: ((NSPasteboard) -> Bool)?
    /// Status extra: clicks fall through to the button so the system menu highlight stays.
    var clicksFallThrough = false
    private var ignoreDragChangeCount: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FileIntake.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        QuickChatDropHost.unregisterFileDrags(in: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let event = NSApp.currentEvent
        let pasteboard = NSPasteboard(name: .drag)
        if event?.window === window,
           event?.type == .leftMouseDown || event?.type == .rightMouseDown {
            ignoreDragChangeCount = pasteboard.changeCount
        }
        if QuickChatDropHost.shouldStealFileDrag(
            hasFiles: QuickChatDropHost.canAccept(pasteboard),
            pressedButtons: Int(NSEvent.pressedMouseButtons),
            eventType: event?.type,
            eventIsInPanel: event?.window === window,
            isLeftoverDrag: ignoreDragChangeCount == pasteboard.changeCount
        ) {
            return self
        }
        if clicksFallThrough { return nil }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        QuickChatDropHost.unregisterFileDrags(in: self)
        return QuickChatDropHost.canAccept(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        ignoreDragChangeCount = sender.draggingPasteboard.changeCount
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ignoreDragChangeCount = sender.draggingPasteboard.changeCount
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}
