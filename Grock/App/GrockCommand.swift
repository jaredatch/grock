import Foundation

/// `grock` argv → `grock://` (DEC-053). Never auto-sends.
enum GrockCommand {
    enum Outcome: Equatable {
        case open(GrockURL)
        case help
        case failure(String)
    }

    static let helpText = """
    grock: open Grock from the terminal

    Nothing here sends on its own. Grock opens, the text or file lands, you hit Return.

    Usage:
      grock                    Show the window
      grock open               Same as grock
      grock new [text]         New Chat in the overlay
      grock ask [text]         Quick Chat
      grock imagine [text]     Imagine, prompt filled
      grock help

      -f, --file PATH          Attach a file (repeatable; new and ask only)

    Examples:
      grock ask "summarize this"
      grock new -f notes.pdf
      pbpaste | grock ask
      grock imagine a red bicycle

    """

    static func parse(
        _ args: [String],
        stdin: String? = nil,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> Outcome {
        var command: String?
        var files: [String] = []
        var textParts: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]
            if arg == "--" {
                textParts.append(contentsOf: args[(index + 1)...])
                break
            }
            if arg == "-h" || arg == "--help" {
                return .help
            }
            if arg == "-f" || arg == "--file" {
                index += 1
                guard index < args.count else {
                    return .failure("\(arg) needs a path")
                }
                files.append(args[index])
                index += 1
                continue
            }
            if arg.hasPrefix("-") && arg != "-" {
                return .failure("unknown option \(arg)")
            }
            if command == nil {
                switch arg.lowercased() {
                case "help":
                    return .help
                case "new", "ask", "imagine", "open":
                    command = arg.lowercased()
                    index += 1
                    continue
                default:
                    break
                }
            }
            textParts.append(arg)
            index += 1
        }

        let argText = joinedText(textParts)
        let stdinText = joinedText(stdin.map { [$0] } ?? [])
        let text = argText ?? stdinText

        if let command, command == "open" {
            if text != nil || !files.isEmpty {
                return .failure("open does not take text or files")
            }
            return .open(.summon)
        }

        if command == nil {
            if text != nil || !files.isEmpty {
                return .failure("try grock ask, grock new, or grock imagine")
            }
            return .open(.summon)
        }

        if command == "imagine" && !files.isEmpty {
            return .failure("imagine does not take files")
        }

        var resolved: [URL] = []
        guard files.count <= GrockURL.maximumFileCount else {
            return .failure(GrockURL.RequestError.tooManyFiles.localizedDescription)
        }
        for path in files {
            let url: URL
            if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path).standardizedFileURL
            } else {
                url = URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .failure("file not found: \(path)")
            }
            if isDirectory.boolValue {
                return .failure("not a file: \(path)")
            }
            resolved.append(url)
        }

        switch command {
        case "imagine":
            return .open(.imagine(prompt: text))
        case "new":
            return .open(.new(text: text, files: resolved))
        case "ask":
            return .open(.ask(text: text, files: resolved))
        default:
            return .failure("unknown command")
        }
    }

    private static func joinedText(_ parts: [String]) -> String? {
        let trimmed = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
