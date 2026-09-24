import AppKit
import Darwin
import ImageIO
import UniformTypeIdentifiers

/// OS-handed files: Dock, Open With, `open -a`, status-item drops (DEC-050).
/// Finder Ask Grok is a file Service (DEC-051). Overlay drops stay with grok.com.
enum FileIntake {
    enum IntakeError: LocalizedError, Equatable {
        case unreadable(String)
        case permissionDenied(URL)
        case missing(String)
        case notRegularFile(String)
        case empty(String)
        case oversized(String)
        case totalSize
        case tooManyFiles

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn't read \(name). Try choosing the file again."
            case .permissionDenied(let url): return "Choose \(url.lastPathComponent) to give Grock access."
            case .missing(let name): return "\(name) couldn't be found. Check its location and try again."
            case .notRegularFile(let name): return "\(name) isn't a regular file."
            case .empty(let name): return "\(name) is empty."
            case .oversized(let name): return "\(name) exceeds the 12 MB file limit."
            case .totalSize: return "The files together exceed the 24 MB limit."
            case .tooManyFiles: return "Add up to \(QuickChatPayload.maxAttachmentCount) files at a time."
            }
        }
    }

    /// An atomic addition. Cancellation propagates to the worker; security-scoped
    /// access stays open until all metadata checks and bounded reads finish.
    static func load(
        _ urls: [URL],
        source: QuickChatSource = .disk,
        copiedAt: Date? = nil,
        existingBytes: Int = 0,
        existingCount: Int = 0
    ) async throws -> [QuickChatAttachment] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try loadSynchronously(
                urls, source: source, copiedAt: copiedAt,
                existingBytes: existingBytes, existingCount: existingCount
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    static func loadImage(_ data: Data, source: QuickChatSource, copiedAt: Date?) async throws -> [QuickChatAttachment] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard data.count <= QuickChatPayload.maxAttachmentBytes else {
                throw IntakeError.oversized("Clipboard image")
            }
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 64_000_000 / height else {
                throw IntakeError.unreadable("Clipboard image")
            }
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
                throw IntakeError.unreadable("Clipboard image")
            }
            CGImageDestinationAddImageFromSource(destination, imageSource, 0, nil)
            guard CGImageDestinationFinalize(destination) else { throw IntakeError.unreadable("Clipboard image") }
            try Task.checkCancellation()
            guard bytes.length <= QuickChatPayload.maxAttachmentBytes else { throw IntakeError.oversized("Clipboard image") }
            return [QuickChatAttachment(filename: "clipboard.png", mimeType: "image/png", data: bytes as Data,
                                        source: source, copiedAt: copiedAt)]
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    /// Synchronous core is also used by small isolated tests and compatibility
    /// helpers. Interactive entrypoints call `load`.
    static func loadSynchronously(
        _ urls: [URL],
        source: QuickChatSource = .disk,
        copiedAt: Date? = nil,
        existingBytes: Int = 0,
        existingCount: Int = 0
    ) throws -> [QuickChatAttachment] {
        guard existingCount >= 0,
              urls.count <= QuickChatPayload.maxAttachmentCount - existingCount else {
            throw IntakeError.tooManyFiles
        }
        guard existingBytes >= 0, existingBytes <= QuickChatPayload.maxTotalAttachmentBytes else {
            throw IntakeError.totalSize
        }
        let files = urls.map(QuickChatAttachment.resolvedFileURL)
        var accessed: [URL] = []
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        var advertisedTotal = existingBytes
        for url in files {
            try Task.checkCancellation()
            let name = url.lastPathComponent
            guard url.isFileURL else { throw IntakeError.notRegularFile(name) }
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            } catch { throw readFailure(error, at: url) }
            guard values.isRegularFile == true else { throw IntakeError.notRegularFile(name) }
            guard let size = values.fileSize else { throw IntakeError.unreadable(name) }
            guard size > 0 else { throw IntakeError.empty(name) }
            guard size <= QuickChatPayload.maxAttachmentBytes else { throw IntakeError.oversized(name) }
            advertisedTotal += size
            guard advertisedTotal <= QuickChatPayload.maxTotalAttachmentBytes else {
                throw IntakeError.totalSize
            }
        }
        var total = existingBytes
        var attachments: [QuickChatAttachment] = []
        for url in files {
            let data = try boundedRead(url)
            total += data.count
            guard total <= QuickChatPayload.maxTotalAttachmentBytes else { throw IntakeError.totalSize }
            attachments.append(.fromLoadedFile(url: url, data: data, source: source, copiedAt: copiedAt))
        }
        return attachments
    }

    private static func boundedRead(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        let name = url.lastPathComponent
        // O_NONBLOCK and fstat close the metadata/open race: a file replaced by a
        // pipe or device must never make the launcher wait on a special file.
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else {
            throw readFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)), at: url)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw IntakeError.unreadable(name) }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw IntakeError.notRegularFile(name)
        }
        guard info.st_size <= Int64(QuickChatPayload.maxAttachmentBytes) else { throw IntakeError.oversized(name) }
        var data = Data()
        do {
            while true {
                try Task.checkCancellation()
                // The extra byte detects growth after the metadata check without
                // ever allocating the rest of a newly enlarged file.
                let remaining = QuickChatPayload.maxAttachmentBytes - data.count + 1
                guard let chunk = try handle.read(upToCount: min(256_000, remaining)), !chunk.isEmpty else { break }
                data.append(chunk)
                guard data.count <= QuickChatPayload.maxAttachmentBytes else { throw IntakeError.oversized(name) }
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as IntakeError { throw error }
        catch { throw readFailure(error, at: url) }
        guard !data.isEmpty else { throw IntakeError.empty(name) }
        return data
    }

    static func readFailure(_ error: Error, at url: URL) -> IntakeError {
        let error = error as NSError
        if (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileReadNoPermission.rawValue)
            || (error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code)) {
            return .permissionDenied(url)
        }
        if (error.domain == NSCocoaErrorDomain && [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(error.code))
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)) {
            return .missing(url.lastPathComponent)
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return readFailure(underlying, at: url)
        }
        return .unreadable(url.lastPathComponent)
    }

    /// The picker grants access only after the user selects a file. URL requests
    /// merely suggest its starting folder; they cannot authorize their own path.
    @MainActor
    static func chooseFile(_ requested: URL, completion: @escaping (URL?) -> Void) -> NSOpenPanel? {
        let picker = NSOpenPanel()
        picker.title = "Attach File"
        picker.message = "Choose \(requested.lastPathComponent) to attach it to Grock."
        picker.prompt = "Attach"
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.canCreateDirectories = false
        picker.allowsMultipleSelection = false
        picker.resolvesAliases = false
        picker.directoryURL = requested.deletingLastPathComponent()
        picker.begin { response in completion(response == .OK ? picker.url : nil) }
        return picker
    }

    static let draggedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .png,
        .tiff,
        .pdf,
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]

    /// Finder / Services pasteboard. Files only; directories and plain text drop out.
    static func fileURLs(from pasteboard: NSPasteboard, validate: Bool = true) -> [URL] {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        var urls: [URL] = []
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileOptions
        ) as? [URL] {
            urls.append(contentsOf: objects)
        }
        if urls.isEmpty,
           let paths = pasteboard.propertyList(
               forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
           ) as? [String] {
            urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        }
        return validate ? urls.filter { isReadableFile($0) } : urls.filter(\.isFileURL)
    }

    static func partition(_ urls: [URL]) -> (commands: [GrockURL], files: [URL]) {
        var commands: [GrockURL] = []
        var files: [URL] = []
        for url in urls {
            if let command = GrockURL.parse(url) {
                commands.append(command)
            } else if url.isFileURL {
                files.append(url)
            }
        }
        return (commands, files)
    }

    static func isReadableFile(_ url: URL) -> Bool {
        let fileURL = QuickChatAttachment.resolvedFileURL(url)
        guard fileURL.isFileURL else { return false }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { fileURL.stopAccessingSecurityScopedResource() }
        }
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        return values?.isRegularFile == true && values?.isReadable == true
    }
}
