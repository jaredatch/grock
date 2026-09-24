import Foundation

/// `grock://` entry points (DEC-049). Never auto-sends.
enum GrockURL: Equatable {
    case new(text: String?, files: [URL])
    case ask(text: String?, files: [URL])
    case imagine(prompt: String?)
    case summon
    case invalid(text: String?, reason: String)

    static let scheme = "grock"
    static let maximumFileCount = 20
    static let maximumURLBytes = 128 * 1024
    static let maximumBookmarkBytes = 16 * 1024

    enum RequestError: LocalizedError {
        case invalidFile, invalidBookmark, tooManyFiles, tooLong, cannotShare(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Use an absolute path or a local file URL for each attachment."
            case .invalidBookmark: return "Couldn't open the supplied file access. Run the command again or choose the files in Grock."
            case .tooManyFiles: return "Add up to \(maximumFileCount) files at a time."
            case .tooLong: return "This request is too large. Use less text or fewer files."
            case .cannotShare(let name): return "Couldn't share access to \(name). Check that Terminal can read it, or choose it in Grock."
            }
        }
    }

    static func parse(_ url: URL) -> GrockURL? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.absoluteString.utf8.count <= maximumURLBytes else {
            return .invalid(text: nil, reason: RequestError.tooLong.localizedDescription)
        }
        // percentEncoded so `%2B` stays plus and a raw `+` can still mean space.
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        let text = queryValue(["text"], in: items)
        do {
            switch command(from: url) {
            case "new": return .new(text: text, files: try fileURLs(in: items))
            case "ask": return .ask(text: text, files: try fileURLs(in: items))
            case "imagine":
                guard !items.contains(where: isFileItem) else { throw RequestError.invalidFile }
                return .imagine(prompt: queryValue(["generate", "text"], in: items))
            default:
                guard !items.contains(where: isFileItem) else {
                    return .invalid(text: text, reason: "Use grock://ask or grock://new to attach files.")
                }
                return .summon
            }
        } catch {
            return .invalid(text: text, reason: error.localizedDescription)
        }
    }

    /// Plain-path links for callers that cannot transfer file access.
    func href() -> URL? {
        switch self {
        case .summon:
            return URL(string: "\(Self.scheme)://")
        case .invalid: return nil
        case .new(let text, let files):
            return Self.make(host: "new", textKey: "text", text: text, files: files)
        case .ask(let text, let files):
            return Self.make(host: "ask", textKey: "text", text: text, files: files)
        case .imagine(let prompt):
            return Self.make(host: "imagine", textKey: "generate", text: prompt, files: [])
        }
    }

    /// Transfer temporary access from a local caller (DEC-067). These bookmarks
    /// are capabilities: never log the resulting URL or persist its bookmark data.
    func authorizedHref() throws -> URL {
        let host: String
        let text: String?
        let files: [URL]
        switch self {
        case .ask(let prompt, let urls): (host, text, files) = ("ask", prompt, urls)
        case .new(let prompt, let urls): (host, text, files) = ("new", prompt, urls)
        default:
            guard let url = href(), url.absoluteString.utf8.count <= Self.maximumURLBytes else {
                throw RequestError.tooLong
            }
            return url
        }
        guard files.count <= Self.maximumFileCount else { throw RequestError.tooManyFiles }
        var parts: [String] = []
        if let text, !text.isEmpty { parts.append("text=\(Self.encodeQueryValue(text))") }
        for file in files {
            guard Self.isLocalFile(file) else { throw RequestError.invalidFile }
            let data: Data
            do {
                // [] embeds the ephemeral scope Apple supports for interprocess
                // handoff. .withSecurityScope is for persistent app-scoped access.
                data = try file.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch { throw RequestError.cannotShare(file.lastPathComponent) }
            guard data.count <= Self.maximumBookmarkBytes else { throw RequestError.tooLong }
            parts.append("bookmark=\(Self.encodeQueryValue(data.base64EncodedString()))")
        }
        let string = "\(Self.scheme)://\(host)" + (parts.isEmpty ? "" : "?" + parts.joined(separator: "&"))
        guard string.utf8.count <= Self.maximumURLBytes, let url = URL(string: string) else {
            throw RequestError.tooLong
        }
        return url
    }

    /// Host (`grock://ask`) or first path step (`grock:///ask`). Empty is summon.
    private static func command(from url: URL) -> String {
        if let host = url.host?.lowercased(), !host.isEmpty {
            return host
        }
        return url.path.split(separator: "/").first.map { String($0).lowercased() } ?? ""
    }

    private static func queryValue(_ names: [String], in items: [URLQueryItem]) -> String? {
        for name in names {
            guard let raw = items.first(where: { $0.name == name })?.value else { continue }
            let trimmed = decodeQueryValue(raw)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func isFileItem(_ item: URLQueryItem) -> Bool {
        ["file", "files", "bookmark"].contains(item.name)
    }

    private static func isLocalFile(_ url: URL) -> Bool {
        url.isFileURL && [nil, "", "localhost"].contains(url.host?.lowercased())
            && url.path.hasPrefix("/") && !url.path.contains("\0")
            && url.absoluteString.removingPercentEncoding?.contains("\0") == false
    }

    private static func fileURLs(in items: [URLQueryItem]) throws -> [URL] {
        let fileItems = items.filter(isFileItem)
        guard fileItems.count <= maximumFileCount else { throw RequestError.tooManyFiles }
        return try fileItems.map { item in
            guard let value = item.value, !value.isEmpty else { throw RequestError.invalidFile }
            let decoded = decodeQueryValue(value, trim: false)
            guard !decoded.contains("\0") else { throw RequestError.invalidFile }
            let url: URL
            if item.name == "bookmark" {
                guard decoded.utf8.count <= ((maximumBookmarkBytes + 2) / 3) * 4,
                      let data = Data(base64Encoded: decoded), data.count <= maximumBookmarkBytes else {
                    throw RequestError.invalidBookmark
                }
                var stale = false
                do {
                    url = try URL(resolvingBookmarkData: data,
                                  options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                } catch { throw RequestError.invalidBookmark }
                // One-use bookmarks can report stale after crossing the sandbox.
                // The resolved URL and the bounded read determine success.
            } else if decoded.hasPrefix("/") {
                url = URL(fileURLWithPath: decoded)
            } else if let parsed = URL(string: decoded), parsed.isFileURL {
                url = parsed
            } else { throw RequestError.invalidFile }
            guard isLocalFile(url) else { throw RequestError.invalidFile }
            return url
        }
    }

    /// Form `+` is a space. `%2B` is a plus. `%20` is a space.
    private static func decodeQueryValue(_ raw: String, trim: Bool = true) -> String {
        let plusAsSpace = raw.replacingOccurrences(of: "+", with: " ")
        let value = plusAsSpace.removingPercentEncoding ?? plusAsSpace
        return trim ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    private static func make(host: String, textKey: String, text: String?, files: [URL]) -> URL? {
        var parts: [String] = []
        if let text, !text.isEmpty {
            parts.append("\(textKey)=\(encodeQueryValue(text))")
        }
        for file in files {
            parts.append("file=\(encodeQueryValue(file.path))")
        }
        var string = "\(scheme)://\(host)"
        if !parts.isEmpty {
            string += "?" + parts.joined(separator: "&")
        }
        return URL(string: string)
    }

    /// Unreserved characters only, so `+` stays `%2B` and does not become a space.
    private static func encodeQueryValue(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
