import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Package for one grok.com send. Native Quick Chat builds this; `WebViewStore` throws it.
struct QuickChatPayload: Equatable {
    var text: String
    var attachments: [QuickChatAttachment]

    var hasContent: Bool {
        !trimmedText.isEmpty || !attachments.isEmpty
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// grok.com will not send a file with an empty prompt. It fills
    /// "Refer to the following content:" which titles the thread and
    /// reads like a task. A short question gets an answer instead.
    static let singleAttachmentPrompt = "What's in this?"
    static let multipleAttachmentPrompt = "What's in these?"

    var promptForSubmit: String {
        if !trimmedText.isEmpty { return trimmedText }
        if attachments.isEmpty { return "" }
        return attachments.count == 1 ? Self.singleAttachmentPrompt : Self.multipleAttachmentPrompt
    }

    /// The page bridge expands attachments to base64. Bound the whole package as
    /// well as individual files before allocating or handing anything to WebKit.
    static let maxAttachmentBytes = 12_000_000
    static let maxTotalAttachmentBytes = 24_000_000
    static let maxAttachmentCount = GrockURL.maximumFileCount

    var validationError: String? {
        if attachments.count > Self.maxAttachmentCount {
            return "Add up to \(Self.maxAttachmentCount) files at a time."
        }
        var total = 0
        for attachment in attachments {
            if attachment.data.isEmpty { return "\(attachment.filename) is empty." }
            if attachment.isOversize { return "\(attachment.filename) exceeds the 12 MB file limit." }
            total += attachment.data.count
            if total > Self.maxTotalAttachmentBytes {
                return "The files together exceed the 24 MB limit."
            }
        }
        return nil
    }
}

enum QuickChatSource: Equatable {
    case disk
    case clipboard
}

enum QuickChatRowLocation: Equatable {
    case folder(String)
    case clipboard
}

struct QuickChatAttachment: Equatable {
    var filename: String
    var mimeType: String
    var data: Data
    var source: QuickChatSource = .disk
    var sourceURL: URL? = nil
    var folderName: String? = nil
    var modifiedAt: Date? = nil
    var copiedAt: Date? = nil

    var isOversize: Bool {
        data.count > QuickChatPayload.maxAttachmentBytes
    }

    var isImage: Bool {
        if mimeType.lowercased().hasPrefix("image/") { return true }
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    /// Spotlight-style title. Clipboard screenshots have no real name.
    var rowTitle: String {
        if source == .clipboard, filename == "clipboard.png" || filename.isEmpty {
            return localizedTypeName
        }
        return filename
    }

    /// Short names Spotlight uses. UTType's localizedDescription is often the
    /// long IANA/Office title ("Office Open XML spreadsheet").
    var localizedTypeName: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if let name = Self.shortTypeNames[ext] { return name }
        if !ext.isEmpty, let type = UTType(filenameExtension: ext),
           let name = type.localizedDescription, !name.isEmpty {
            return name
        }
        if let type = UTType(mimeType: mimeType),
           let name = type.localizedDescription, !name.isEmpty {
            return name
        }
        return "Document"
    }

    var rowLocation: QuickChatRowLocation? {
        if source == .clipboard { return .clipboard }
        if let folderName, !folderName.isEmpty { return .folder(folderName) }
        return nil
    }

    func rowMetaLine(now: Date = Date()) -> String {
        var parts: [String] = [localizedTypeName, Self.byteCountString(data.count)]
        if source == .clipboard {
            if let modifiedAt {
                parts.append(Self.spotlightDate(modifiedAt, now: now))
            } else if let copiedAt {
                parts.append(Self.spotlightDate(copiedAt, now: now))
            }
        } else if let modifiedAt {
            parts.append(Self.spotlightDate(modifiedAt, now: now))
        }
        return parts.joined(separator: " · ")
    }

    func rowSubtitle(now: Date = Date()) -> String {
        let line = rowMetaLine(now: now)
        switch rowLocation {
        case .folder(let name):
            return line + " · " + name
        case .clipboard:
            return line + " · Clipboard"
        case nil:
            return line
        }
    }

    static func collapsedSnippet(_ text: String, limit: Int = 80) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    static func textRowSubtitle(copiedAt: Date?, now: Date = Date()) -> String {
        guard let copiedAt else { return "Text" }
        return "Text · \(copiedLabel(copiedAt, now: now))"
    }

    static func spotlightDate(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today, \(timeFormatter.string(from: date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(timeFormatter.string(from: date))"
        }
        return shortDateTimeFormatter.string(from: date)
    }

    static func copiedLabel(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Copied \(timeFormatter.string(from: date))"
        }
        return "Copied \(spotlightDate(date, now: now))"
    }

    static func byteCountString(_ count: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(count))
    }

    static func combinedText(draft: String, clipboardText: String?) -> String {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if typed.isEmpty { return clip }
        if clip.isEmpty { return typed }
        return typed + "\n\n" + clip
    }

    private static let shortTypeNames: [String: String] = [
        "pdf": "PDF document",
        "png": "PNG image",
        "jpg": "JPEG image",
        "jpeg": "JPEG image",
        "gif": "GIF image",
        "webp": "WEBP image",
        "heic": "HEIC image",
        "tif": "TIFF image",
        "tiff": "TIFF image",
        "svg": "SVG image",
        "xlsx": "Excel spreadsheet",
        "xls": "Excel spreadsheet",
        "docx": "Word document",
        "doc": "Word document",
        "pptx": "PowerPoint presentation",
        "ppt": "PowerPoint presentation",
        "csv": "CSV",
        "html": "HTML text",
        "htm": "HTML text",
        "css": "CSS",
        "js": "JavaScript",
        "ts": "TypeScript",
        "json": "JSON",
        "md": "Markdown",
        "txt": "Plain text",
        "rtf": "Rich text",
        "zip": "Zip archive",
        "dmg": "Disk image",
        "mp4": "MPEG-4 movie",
        "mov": "QuickTime movie",
        "mp3": "MP3 audio",
        "wav": "WAVE audio",
        "php": "PHP source",
        "py": "Python source",
        "swift": "Swift source",
        "sh": "Shell script"
    ]

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// Downsampled preview for image rows. Nil if the bytes are not an image.
    func thumbnail(maxPixel: CGFloat = 128) -> NSImage? {
        guard isImage, !data.isEmpty else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    /// System icon from the filename extension, then MIME, then generic document.
    var typeIcon: NSImage {
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        if let type = UTType(mimeType: mimeType) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    /// Spotlight badges previews with the app that opens the file, not another
    /// copy of the file-type icon. Clipboard-only images have no source file.
    var associatedApplicationIcon: NSImage? {
        guard let sourceURL,
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: sourceURL)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    /// Finder / panel drops. File URLs win, then legacy path lists, then images.
    /// Never treat a POSIX path string as the prompt.
    static func fromPasteboard(
        _ pasteboard: NSPasteboard,
        source: QuickChatSource = .disk,
        copiedAt: Date? = nil
    ) -> [QuickChatAttachment] {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL] {
            let files = urls.compactMap { fromFile(url: $0, source: source, copiedAt: copiedAt) }
            if !files.isEmpty { return files }
        }
        if let paths = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            let files = paths.map { URL(fileURLWithPath: $0) }.compactMap {
                fromFile(url: $0, source: source, copiedAt: copiedAt)
            }
            if !files.isEmpty { return files }
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            return images.compactMap {
                fromImage($0, source: source, copiedAt: copiedAt)
            }
        }
        return []
    }

    static func fromFile(
        url: URL,
        source: QuickChatSource = .disk,
        copiedAt: Date? = nil
    ) -> QuickChatAttachment? {
        // Compatibility for synchronous callers. App intake uses FileIntake.load
        // so filesystem access and bounded reads run away from the main thread.
        try? FileIntake.loadSynchronously([url], source: source, copiedAt: copiedAt).first
    }

    static func fromLoadedFile(
        url fileURL: URL,
        data: Data,
        source: QuickChatSource,
        copiedAt: Date?
    ) -> QuickChatAttachment {
        let ext = fileURL.pathExtension
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType
            ?? "application/octet-stream"
        let name = fileURL.lastPathComponent.isEmpty ? "attachment" : fileURL.lastPathComponent
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        let folder = source == .disk && !parent.isEmpty && parent != "/" ? parent : nil
        return QuickChatAttachment(
            filename: name,
            mimeType: mime,
            data: data,
            source: source,
            sourceURL: fileURL,
            folderName: folder,
            modifiedAt: values?.contentModificationDate,
            copiedAt: copiedAt
        )
    }

    static func resolvedFileURL(_ url: URL) -> URL {
        if url.isFileURL { return url }
        if url.scheme == nil || url.scheme == "file" {
            let path = url.path.isEmpty ? url.absoluteString : url.path
            if !path.isEmpty { return URL(fileURLWithPath: path) }
        }
        return url
    }

    static func fromImage(
        _ image: NSImage,
        filename: String = "clipboard.png",
        source: QuickChatSource = .clipboard,
        copiedAt: Date? = nil
    ) -> QuickChatAttachment? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= QuickChatPayload.maxAttachmentBytes
        else { return nil }
        return QuickChatAttachment(
            filename: filename,
            mimeType: "image/png",
            data: png,
            source: source,
            copiedAt: copiedAt
        )
    }
}
