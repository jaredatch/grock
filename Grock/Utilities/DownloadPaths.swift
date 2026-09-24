import Darwin
import Foundation

/// Download names are untrusted page/server input. All writes reserve a new file
/// relative to an opened Downloads directory, without following a leaf symlink.
enum DownloadPaths {
    static func safeFilename(_ filename: String) -> String {
        let leaf = filename.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let disallowed = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: ":"))
        var name = leaf.components(separatedBy: disallowed).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { return "download" }
        // Leave room for collision suffixes under NAME_MAX (UTF-8 bytes).
        if name.utf8.count > 200 {
            let ext = (name as NSString).pathExtension
            let suffix = ext.utf8.count <= 20 && !ext.isEmpty ? "." + ext : ""
            var stem = suffix.isEmpty ? name : (name as NSString).deletingPathExtension
            while stem.utf8.count > 200 - suffix.utf8.count { stem.removeLast() }
            name = stem + suffix
        }
        return name
    }

    static func uniqueDestination(filename: String, in directory: URL, fileExists: (String) -> Bool = {
        // attributesOfItem sees dangling symlinks too; fileExists alone does not.
        (try? FileManager.default.attributesOfItem(atPath: $0)) != nil
    }) -> URL {
        let name = safeFilename(filename)
        var counter = 0
        while true {
            let destination = directory.appendingPathComponent(candidate(name, counter: counter))
            if !fileExists(destination.path) { return destination }
            counter += 1
        }
    }

    private static func candidate(_ name: String, counter: Int) -> String {
        guard counter > 0 else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return ext.isEmpty ? "\(name) (\(counter))" : "\(base) (\(counter)).\(ext)"
    }

    /// O_EXCL makes collision handling atomic across concurrent saves, and the
    /// open directory descriptor prevents a renamed parent from redirecting writes.
    static func write(_ data: Data, suggestedName: String, in directory: URL = downloadsDirectory) throws -> URL {
        try reserve(suggestedName: suggestedName, in: directory) { descriptor in
            try writeAll(data, to: descriptor)
        }
    }

    private static func reserve(suggestedName: String, in directory: URL,
                                writer: (Int32) throws -> Void) throws -> URL {
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directoryFD >= 0 else { throw posixError() }
        defer { close(directoryFD) }
        let name = safeFilename(suggestedName)
        var counter = 0
        var descriptor: Int32 = -1
        var filename = name
        while descriptor < 0 {
            filename = candidate(name, counter: counter)
            descriptor = openat(directoryFD, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            if descriptor < 0 {
                guard errno == EEXIST, counter < 10_000 else { throw posixError() }
                counter += 1
            }
        }
        var complete = false
        defer {
            close(descriptor)
            if !complete { unlinkat(directoryFD, filename, 0) }
        }
        try writer(descriptor)
        guard fsync(descriptor) == 0 else { throw posixError() }
        complete = true
        return directory.appendingPathComponent(filename)
    }

    /// WebKit requires a nonexistent destination. Give each download a private,
    /// unique staging directory, then atomically reserve its final name on finish.
    static func stagingDestination(in directory: URL = downloadsDirectory) throws -> URL {
        let staging = directory.appendingPathComponent(".grock-download-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return staging.appendingPathComponent("content")
    }

    static func finishStagedDownload(_ source: URL, suggestedName: String,
                                     in directory: URL = downloadsDirectory) throws -> URL {
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let sourceFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard sourceFD >= 0 else { throw posixError() }
        defer { close(sourceFD) }
        var status = stat()
        guard fstat(sourceFD, &status) == 0, status.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return try reserve(suggestedName: suggestedName, in: directory) { destinationFD in
            var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
            while true {
                let count = Darwin.read(sourceFD, &buffer, buffer.count)
                if count < 0, errno == EINTR { continue }
                guard count >= 0 else { throw posixError() }
                if count == 0 { break }
                try writeAll(Data(buffer.prefix(count)), to: destinationFD)
            }
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
