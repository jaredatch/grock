import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct QuickChatView: View {
    @Bindable var controller: QuickChatController

    private var expanded: Bool {
        QuickChatComposer.isExpanded(controller.draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            composerRow

            if hasItems {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: QuickChatComposer.dividerHeight)
                    .padding(.horizontal, QuickChatComposer.headerHorizontalInset)
                itemList
                    .padding(.horizontal, QuickChatComposer.rowBackgroundHorizontalInset)
            }

            if let message = controller.statusMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                    .font(.system(size: QuickChatComposer.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if controller.intakeError != nil {
                        HStack(spacing: 16) {
                            if controller.canChooseFile {
                                Button("Choose File…", action: controller.chooseDeniedFile)
                            }
                            Button("Continue Without Them", action: controller.discardFailedAddition)
                        }
                        .buttonStyle(.borderless)
                        .disabled(controller.isChoosingFile || controller.pendingIntakeCount > 0)
                    } else if controller.sendUncertain {
                        HStack(spacing: 16) {
                            Button("Check in Grok", action: controller.reviewUncertainSend)
                            Button("Allow Retry", action: controller.acknowledgeUncertainSend)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.system(size: QuickChatComposer.secondaryFontSize))
                .padding(.horizontal, QuickChatComposer.headerHorizontalInset)
                .padding(.top, QuickChatComposer.errorTopInset)
                .padding(.bottom, QuickChatComposer.errorBottomInset)
                .frame(height: controller.statusFooterHeight, alignment: .topLeading)
            }
        }
        .frame(width: QuickChatComposer.cardWidth, alignment: .topLeading)
        .onAppear {
            controller.prepareForDrops()
        }
        .onChange(of: controller.draft) { _, _ in
            controller.syncPanelSize()
        }
        .onChange(of: controller.textChip) { _, _ in
            controller.syncPanelSize()
        }
        .onChange(of: controller.attachments) { _, _ in
            controller.syncPanelSize()
        }
        .onChange(of: controller.sendFailed) { _, _ in
            controller.syncPanelSize()
        }
        .onChange(of: controller.statusFooterHeight) { _, _ in
            controller.syncPanelSize()
        }
    }

    private var hasItems: Bool {
        controller.textChip != nil || !controller.attachments.isEmpty
    }

    private var composerRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(
                    width: QuickChatComposer.leadingIconSide,
                    height: QuickChatComposer.leadingIconSide
                )
                .padding(
                    .top,
                    QuickChatComposer.accessoryTopInset(
                        side: QuickChatComposer.leadingIconSide,
                        for: controller.draft
                    )
                )

            QuickChatComposerField(
                text: $controller.draft,
                fontSize: expanded ? QuickChatComposer.longFontSize : QuickChatComposer.shortFontSize,
                focusGeneration: controller.composerFocusGeneration,
                controller: controller,
                showsVerticalScroller: QuickChatComposer.needsVerticalScroller(controller.draft),
                onSubmit: controller.send
            )
            .frame(height: QuickChatComposer.fieldHeight(for: controller.draft), alignment: .top)
            .padding(.leading, QuickChatComposer.leadingIconSpacing)

            Button(action: controller.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: QuickChatComposer.sendSide, height: QuickChatComposer.sendSide)
                    .background(Circle().fill(Color(nsColor: .labelColor)))
            }
            .buttonStyle(.plain)
            .opacity(controller.canSend ? 1 : 0.28)
            .disabled(!controller.canSend)
            .help("Send")
            .padding(.leading, QuickChatComposer.sendSpacing)
            .padding(
                .top,
                QuickChatComposer.accessoryTopInset(
                    side: QuickChatComposer.sendSide,
                    for: controller.draft
                )
            )
        }
        .padding(.horizontal, QuickChatComposer.headerHorizontalInset)
        .padding(.vertical, QuickChatComposer.headerVerticalInset)
    }

    private var itemList: some View {
        let count = controller.stagedItemCount
        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                if controller.textChip != nil {
                    QuickChatItemRow(
                        title: controller.textChipPreview,
                        subtitle: QuickChatAttachment.textRowSubtitle(
                            copiedAt: controller.textChipCopiedAt
                        ),
                        location: nil,
                        image: nil,
                        thumbnailURL: nil,
                        icon: NSWorkspace.shared.icon(for: .plainText),
                        badgeIcon: nil,
                        titleTruncation: .tail,
                        onPreview: { controller.previewTextChip() },
                        onRemove: { controller.removeTextChip() }
                    )
                }
                ForEach(controller.attachments) { item in
                    QuickChatItemRow(
                        title: item.attachment.rowTitle,
                        subtitle: item.attachment.rowMetaLine(),
                        location: item.attachment.rowLocation,
                        image: item.attachment.isImage ? item.attachment.thumbnail() : nil,
                        thumbnailURL: item.attachment.sourceURL,
                        icon: item.attachment.typeIcon,
                        badgeIcon: item.attachment.associatedApplicationIcon,
                        titleTruncation: .middle,
                        onPreview: { controller.previewAttachment(item.id) },
                        onRemove: { controller.removeAttachment(item.id) }
                    )
                }
            }
            .padding(.top, QuickChatComposer.listTopInset)
            .padding(.bottom, QuickChatComposer.listBottomInset)
        }
        .scrollIndicators(count > QuickChatComposer.maxVisibleRows ? .automatic : .hidden)
        .frame(height: QuickChatComposer.itemListViewportHeight(itemCount: count))
    }
}

private struct QuickChatItemRow: View {
    var title: String
    var subtitle: String
    var location: QuickChatRowLocation?
    var image: NSImage?
    var thumbnailURL: URL?
    var icon: NSImage
    var badgeIcon: NSImage?
    var titleTruncation: Text.TruncationMode
    var onPreview: () -> Void
    var onRemove: () -> Void

    @State private var hovering = false
    @State private var removeHovering = false
    @State private var fileThumbnail: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: QuickChatComposer.rowIconSpacing) {
            Button(action: onPreview) {
                HStack(alignment: .center, spacing: QuickChatComposer.rowIconSpacing) {
                    leadingArt
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                            .truncationMode(titleTruncation)
                        subtitleLine
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick Look")
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(removeHovering ? Color.primary : Color.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.primary.opacity(removeHovering ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .onHover { removeHovering = $0 }
            .help("Remove")
        }
        .padding(.horizontal, QuickChatComposer.rowContentHorizontalInset)
        .frame(height: QuickChatComposer.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: QuickChatComposer.rowHoverCornerRadius, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.10) : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.10), value: hovering)
        .animation(.easeOut(duration: 0.10), value: removeHovering)
        .onAppear(perform: loadFileThumbnail)
        .onChange(of: thumbnailURL) { _, _ in
            fileThumbnail = nil
            loadFileThumbnail()
        }
    }

    private var subtitleLine: some View {
        HStack(spacing: 4) {
            Text(subtitle)
            if let location {
                Text("·")
                switch location {
                case .folder(let name):
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .regular))
                    Text(name)
                case .clipboard:
                    Text("Clipboard")
                }
            }
        }
        .font(.system(size: 15))
        // Hierarchical, not a flattened label colour: the glass recolours
        // `.secondary` when the card sits over dark content, and it left a
        // pre-resolved `labelColor.withAlphaComponent` as near-black.
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    @ViewBuilder
    private var leadingArt: some View {
        if let preview = image ?? fileThumbnail {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: QuickChatComposer.rowArtWidth,
                        height: QuickChatComposer.rowArtHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                if image != nil, let badgeIcon {
                    Image(nsImage: badgeIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.24), radius: 1, y: 0.5)
                        .offset(x: 2, y: 2)
                }
            }
            .frame(
                width: QuickChatComposer.rowArtWidth,
                height: QuickChatComposer.rowArtHeight
            )
        } else {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: QuickChatComposer.rowArtWidth,
                    height: QuickChatComposer.rowArtWidth
                )
                .frame(height: QuickChatComposer.rowArtHeight)
        }
    }

    private func loadFileThumbnail() {
        guard image == nil, fileThumbnail == nil, let thumbnailURL else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: thumbnailURL,
            size: CGSize(
                width: QuickChatComposer.rowArtWidth,
                height: QuickChatComposer.rowArtHeight
            ),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        request.iconMode = true
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation else { return }
            DispatchQueue.main.async {
                guard self.thumbnailURL == thumbnailURL else { return }
                self.fileThumbnail = representation.nsImage
            }
        }
    }
}

/// AppKit composer. SwiftUI `TextField` uses a field editor that only exists
/// once focused, so first open cannot become first responder, and a focused
/// field editor inserts POSIX paths on Finder drops.
final class QuickChatNSTextView: NSTextView {
    weak var controller: QuickChatController?
    var onSubmit: (() -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticTextCompletionEnabled = false
        focusRingType = .none
        insertionPointColor = .controlAccentColor
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff,
            .pdf,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        needsDisplay = true
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        needsDisplay = true
        return ok
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        QuickChatDropHost.canAccept(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard QuickChatDropHost.canAccept(sender.draggingPasteboard) else { return false }
        let before = controller?.attachments.count ?? 0
        controller?.addDroppedPasteboard(sender.draggingPasteboard)
        return (controller?.attachments.count ?? 0) > before
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if QuickChatDropHost.canAccept(pboard) {
            controller?.addDroppedPasteboard(pboard)
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            super.insertNewline(sender)
            return
        }
        onSubmit?()
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if QuickChatDropHost.canAccept(pasteboard) {
            controller?.addDroppedPasteboard(pasteboard)
            return
        }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let font = self.font ?? NSFont.systemFont(ofSize: QuickChatComposer.shortFontSize)
        let placeholder = NSAttributedString(
            string: "Ask Grok…",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.40)
            ]
        )
        placeholder.draw(at: textContainerOrigin)
    }
}

struct QuickChatComposerField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var focusGeneration: Int
    var controller: QuickChatController
    var showsVerticalScroller: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = showsVerticalScroller
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: 1_000_000))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = QuickChatNSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.controller = controller
        textView.onSubmit = onSubmit
        textView.string = text
        applyFont(fontSize, to: textView)
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: 1_000_000)
        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastFocusGeneration = -1
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? QuickChatNSTextView else { return }
        textView.controller = controller
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
        }
        applyFont(fontSize, to: textView)
        scroll.hasVerticalScroller = showsVerticalScroller
        if let width = textView.enclosingScrollView?.contentSize.width, width > 0 {
            textView.textContainer?.containerSize = NSSize(width: width, height: 1_000_000)
        }
        if showsVerticalScroller {
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        } else if scroll.contentView.bounds.origin != .zero {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            DispatchQueue.main.async {
                textView.window?.makeKeyAndOrderFront(nil)
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyFont(_ size: CGFloat, to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: size)
        if textView.font?.pointSize != size {
            textView.font = font
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: QuickChatNSTextView?
        var lastFocusGeneration = -1

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
            view.needsDisplay = true
        }
    }
}
