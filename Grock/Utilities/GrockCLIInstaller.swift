import Foundation

/// Symlink the bundled `grock` tool onto PATH (DEC-053).
enum GrockCLIInstaller {
    static let toolName = "grock"

    enum Status: Equatable {
        case notInstalled
        case installed(URL)
        case foreign(URL)
    }

    enum InstallError: LocalizedError, Equatable {
        case missingBundledTool
        case occupied(URL)
        case changedInstall(URL)

        var errorDescription: String? {
            switch self {
            case .missingBundledTool:
                return "The grock tool is missing from this Grock.app."
            case .occupied(let url):
                return "A file or link already exists at \(url.path). Grock won't replace it. Move or remove it in Terminal, then try again."
            case .changedInstall(let url):
                return "\(url.path) no longer links to this Grock.app. Nothing was changed."
            }
        }
    }

    struct Command: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let text: String
        let destination: URL
    }

    static let bundledRelativePath = "Contents/SharedSupport/grock"

    static func bundledToolURL(in bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.appendingPathComponent(bundledRelativePath)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    static var candidateDirectories: [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        ]
    }

    static func preferredInstallDirectory() -> URL {
        let homebrew = candidateDirectories[0]
        if FileManager.default.fileExists(atPath: homebrew.path) {
            return homebrew
        }
        return candidateDirectories[1]
    }

    static func status(bundled: URL? = bundledToolURL(), directories: [URL] = candidateDirectories) -> Status {
        guard let bundled else { return .notInstalled }
        for directory in directories {
            let url = directory.appendingPathComponent(toolName)
            guard pathExists(url) else { continue }
            return isOurInstall(at: url, bundled: bundled) ? .installed(url) : .foreign(url)
        }
        return .notInstalled
    }

    static func isOurInstall(at url: URL, bundled: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
            && resolvedURL(url).path == bundled.standardizedFileURL.path
    }

    /// The user runs this command in Terminal. Grock never executes an installer
    /// shell or requests administrator privileges from inside the sandbox.
    static func installCommand(
        bundled: URL? = bundledToolURL(),
        directory: URL? = nil,
        requiresAdministrator: Bool = true
    ) throws -> Command {
        guard let bundled else { throw InstallError.missingBundledTool }
        let directory = directory ?? preferredInstallDirectory()
        let destination = directory.appendingPathComponent(toolName)
        guard !pathExists(destination) else { throw InstallError.occupied(destination) }
        let target = shQuote(destination.path)
        let script = """
        if [ -e \(target) ] || [ -L \(target) ]; then
          /bin/echo 'A grock file or link already exists here. Nothing was changed.' >&2
          exit 1
        fi
        /bin/mkdir -p \(shQuote(directory.path)) && /bin/ln -sh \(shQuote(bundled.path)) \(target)
        """
        return Command(title: "Install CLI", text: shellCommand(script, requiresAdministrator: requiresAdministrator), destination: destination)
    }

    static func uninstallCommand(
        at destination: URL,
        bundled: URL? = bundledToolURL(),
        requiresAdministrator: Bool = true
    ) throws -> Command {
        guard let bundled else { throw InstallError.missingBundledTool }
        guard isOurInstall(at: destination, bundled: bundled),
              let expected = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        else { throw InstallError.changedInstall(destination) }
        let target = shQuote(destination.path)
        let script = """
        if [ -L \(target) ] && [ "$(/usr/bin/readlink \(target))" = \(shQuote(expected)) ]; then
          /bin/rm \(target)
        else
          /bin/echo 'This path no longer links to the expected Grock tool. Nothing was changed.' >&2
          exit 1
        fi
        """
        return Command(title: "Uninstall CLI", text: shellCommand(script, requiresAdministrator: requiresAdministrator), destination: destination)
    }

    static func resolvedURL(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        var seen = Set<String>()
        while true {
            let path = current.path
            if seen.contains(path) { break }
            seen.insert(path)
            guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                break
            }
            if dest.hasPrefix("/") {
                current = URL(fileURLWithPath: dest).standardizedFileURL
            } else {
                current = current.deletingLastPathComponent().appendingPathComponent(dest).standardizedFileURL
            }
        }
        return current
    }

    private static func shQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func pathExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func shellCommand(_ script: String, requiresAdministrator: Bool) -> String {
        (requiresAdministrator ? "/usr/bin/sudo " : "") + "/bin/sh -c " + shQuote(script)
    }
}
