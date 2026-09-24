import AppKit

/// Test-only receiver. Compile with the real parser and loader, then sign with
/// App Sandbox so an unsigned XCTest host cannot mask a missing file grant.
@main
struct FileAccessProbe {
    static func main() throws {
        if CommandLine.arguments.dropFirst().first == "make" {
            guard case .open(let command) = GrockCommand.parse(Array(CommandLine.arguments.dropFirst(2))) else {
                throw GrockURL.RequestError.invalidFile
            }
            // The runner captures this capability in memory and never logs it.
            print(try command.authorizedHref().absoluteString)
            return
        }
        let app = NSApplication.shared
        let delegate = Receiver()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class Receiver: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { NSApp.terminate(nil) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for incoming in urls {
            guard var parts = URLComponents(url: incoming, resolvingAgainstBaseURL: false) else { continue }
            let items = parts.queryItems ?? []
            if items.contains(where: { $0.name == "quit" }) { NSApp.terminate(nil); return }
            guard let label = items.first(where: { $0.name == "case" })?.value,
                  !label.isEmpty, label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { continue }
            parts.scheme = GrockURL.scheme
            guard let url = parts.url else { continue }
            Task { @MainActor in
                var report: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
                var files: [URL] = []
                do {
                    switch GrockURL.parse(url) {
                    case .ask(let text, let urls):
                        files = urls; report["command"] = "ask"; report["text"] = text ?? ""
                    case .new(let text, let urls):
                        files = urls; report["command"] = "new"; report["text"] = text ?? ""
                    case .invalid(_, let reason):
                        report["invalid"] = true
                        throw NSError(domain: "FileAccessProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
                    default: throw GrockURL.RequestError.invalidFile
                    }
                    report["readBefore"] = files.map(Self.canReadWithoutScope)
                    let attachments = try await FileIntake.load(files)
                    report["success"] = true
                    report["names"] = attachments.map(\.filename)
                    report["contents"] = attachments.map { String(decoding: $0.data, as: UTF8.self) }
                } catch {
                    report["success"] = false
                    report["error"] = error.localizedDescription
                    if case .permissionDenied = error as? FileIntake.IntakeError { report["permissionDenied"] = true }
                }
                report["readAfter"] = files.map(Self.canReadWithoutScope)
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                try data.write(to: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(label + ".json"), options: .atomic)
            }
        }
    }

    private static func canReadWithoutScope(_ url: URL) -> Bool {
        (try? Data(contentsOf: URL(fileURLWithPath: url.path))) != nil
    }
}
