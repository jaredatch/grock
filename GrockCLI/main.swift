import Darwin
import Foundation

func grockWrite(_ string: String, to handle: FileHandle) {
    handle.write(Data(string.utf8))
}

let args = Array(CommandLine.arguments.dropFirst())
let stdin: String?
if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    stdin = String(data: data, encoding: .utf8)
} else {
    stdin = nil
}

switch GrockCommand.parse(args, stdin: stdin) {
case .help:
    grockWrite(GrockCommand.helpText, to: FileHandle.standardOutput)
    exit(0)
case .failure(let message):
    grockWrite("grock: \(message)\nTry grock help\n", to: FileHandle.standardError)
    exit(2)
case .open(let command):
    let url: URL
    do { url = try command.authorizedHref() }
    catch {
        grockWrite("grock: \(error.localizedDescription)\n", to: FileHandle.standardError)
        exit(1)
    }
    guard let executable = Bundle.main.executableURL else {
        grockWrite("grock: couldn't locate the bundled command. Reinstall it from Grock Settings.\n", to: FileHandle.standardError)
        exit(1)
    }
    let app = executable.resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard Bundle(url: app)?.bundleIdentifier == "com.jaredatch.Grock" else {
        grockWrite("grock: keep this command inside Grock.app. Reinstall it from Grock Settings.\n", to: FileHandle.standardError)
        exit(1)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // Hand access to the app this CLI belongs to, even if another app claims
    // the same URL scheme or another Grock build is registered on this Mac.
    process.arguments = ["-a", app.path, url.absoluteString]
    // open may print the URL on failure. Bookmark parameters carry file access.
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            grockWrite("grock: couldn't open Grock. Open the app once, then try again.\n", to: FileHandle.standardError)
        }
        exit(process.terminationStatus)
    } catch {
        grockWrite("grock: \(error.localizedDescription)\n", to: FileHandle.standardError)
        exit(1)
    }
}
