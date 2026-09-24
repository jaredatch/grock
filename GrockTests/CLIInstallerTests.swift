import Foundation
import XCTest
@testable import Grock

final class CLIInstallerTests: XCTestCase {
    func testInstallAndUninstallCommandsWorkInAnIsolatedDirectory() throws {
        let root = try temporaryDirectory()
        let bundled = try tool(in: root)
        let directory = root.appendingPathComponent("bin")
        let command = try GrockCLIInstaller.installCommand(
            bundled: bundled, directory: directory, requiresAdministrator: false
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: command.destination.path))
        XCTAssertEqual(try run(command, in: root), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: command.destination.path), bundled.path)
        XCTAssertEqual(GrockCLIInstaller.status(bundled: bundled, directories: [directory]), .installed(command.destination))
        let removal = try GrockCLIInstaller.uninstallCommand(
            at: command.destination, bundled: bundled, requiresAdministrator: false
        )
        XCTAssertEqual(try run(removal, in: root), 0)
        XCTAssertEqual(GrockCLIInstaller.status(bundled: bundled, directories: [directory]), .notInstalled)
        XCTAssertEqual(try Data(contentsOf: bundled), Data("bundled tool".utf8))
    }

    func testInstallCommandQuotesShellMetacharactersAndNewlines() throws {
        let root = try temporaryDirectory()
        let bundled = try tool(in: root, name: "bundle ' $(touch INJECTED) `touch ALSO_INJECTED`\nfile")
        let directory = root.appendingPathComponent("bin ' \" $HOME $(touch THIRD_INJECTED)")
        let command = try GrockCLIInstaller.installCommand(
            bundled: bundled, directory: directory, requiresAdministrator: false
        )
        XCTAssertEqual(try run(command, in: root), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: command.destination.path), bundled.path)
        for name in ["INJECTED", "ALSO_INJECTED", "THIRD_INJECTED"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        let removal = try GrockCLIInstaller.uninstallCommand(
            at: command.destination, bundled: bundled, requiresAdministrator: false
        )
        XCTAssertEqual(try run(removal, in: root), 0)
    }

    func testInstallDoesNotOverwriteFilesDirectoriesOrDanglingLinksCreatedAfterPlanning() throws {
        for kind in ["file", "directory", "dangling link"] {
            let root = try temporaryDirectory()
            let bundled = try tool(in: root)
            let directory = root.appendingPathComponent("bin")
            let command = try GrockCLIInstaller.installCommand(
                bundled: bundled, directory: directory, requiresAdministrator: false
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            switch kind {
            case "file": try Data("foreign contents".utf8).write(to: command.destination)
            case "directory": try FileManager.default.createDirectory(at: command.destination, withIntermediateDirectories: false)
            default: try FileManager.default.createSymbolicLink(atPath: command.destination.path, withDestinationPath: "missing")
            }
            XCTAssertNotEqual(try run(command, in: root), 0, kind)
            switch kind {
            case "file": XCTAssertEqual(try Data(contentsOf: command.destination), Data("foreign contents".utf8))
            case "directory": XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: command.destination.path), [])
            default: XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: command.destination.path), "missing")
            }
            guard case .foreign(let occupied) = GrockCLIInstaller.status(bundled: bundled, directories: [directory]) else {
                return XCTFail("Existing \(kind) must be reported as foreign")
            }
            XCTAssertEqual(occupied.path, command.destination.path)
            XCTAssertThrowsError(try GrockCLIInstaller.installCommand(bundled: bundled, directory: directory)) {
                guard case .occupied(let occupied) = $0 as? GrockCLIInstaller.InstallError else {
                    return XCTFail("Expected an occupied-path error, got \($0)")
                }
                XCTAssertEqual(occupied.path, command.destination.path)
            }
        }
    }

    func testRepeatedInstallLeavesExistingLinkUntouched() throws {
        let root = try temporaryDirectory()
        let bundled = try tool(in: root)
        let command = try GrockCLIInstaller.installCommand(
            bundled: bundled, directory: root.appendingPathComponent("bin"), requiresAdministrator: false
        )
        XCTAssertEqual(try run(command, in: root), 0)
        XCTAssertNotEqual(try run(command, in: root), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: command.destination.path), bundled.path)
    }

    func testUninstallRefusesChangedSymlinkAndRegularFile() throws {
        for replacementIsLink in [true, false] {
            let root = try temporaryDirectory()
            let bundled = try tool(in: root)
            let destination = root.appendingPathComponent("grock")
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: bundled)
            let command = try GrockCLIInstaller.uninstallCommand(
                at: destination, bundled: bundled, requiresAdministrator: false
            )
            try FileManager.default.removeItem(at: destination)
            if replacementIsLink {
                try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "foreign-missing")
            } else {
                try Data("replacement".utf8).write(to: destination)
            }
            XCTAssertNotEqual(try run(command, in: root), 0)
            if replacementIsLink {
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), "foreign-missing")
            } else {
                XCTAssertEqual(try Data(contentsOf: destination), Data("replacement".utf8))
            }
            XCTAssertThrowsError(try GrockCLIInstaller.uninstallCommand(at: destination, bundled: bundled)) {
                XCTAssertEqual($0 as? GrockCLIInstaller.InstallError, .changedInstall(destination))
            }
        }
    }

    func testUninstallChecksExactRelativeLinkDestination() throws {
        let root = try temporaryDirectory()
        let bundled = try tool(in: root)
        let destination = root.appendingPathComponent("grock")
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: bundled.lastPathComponent)
        let command = try GrockCLIInstaller.uninstallCommand(
            at: destination, bundled: bundled, requiresAdministrator: false
        )
        // This still resolves to our binary, but it is no longer the link the
        // command was prepared to remove.
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: bundled.path)
        XCTAssertNotEqual(try run(command, in: root), 0)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), bundled.path)
    }

    func testForeignEarlierCandidateIsNotHiddenByOurLaterInstall() throws {
        let root = try temporaryDirectory()
        let bundled = try tool(in: root)
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let foreign = first.appendingPathComponent("grock")
        try FileManager.default.createSymbolicLink(atPath: foreign.path, withDestinationPath: "missing")
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent("grock"), withDestinationURL: bundled)
        XCTAssertEqual(GrockCLIInstaller.status(bundled: bundled, directories: [first, second]), .foreign(foreign))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grock-cli-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func tool(in root: URL, name: String = "bundled-grock") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("bundled tool".utf8).write(to: url)
        return url
    }

    /// Only generated commands with elevation disabled and paths in this test's
    /// temporary directory are executed. Real installation is never exercised.
    private func run(_ command: GrockCLIInstaller.Command, in root: URL) throws -> Int32 {
        XCTAssertTrue(command.destination.path.hasPrefix(root.path + "/"))
        XCTAssertFalse(command.text.hasPrefix("/usr/bin/sudo"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command.text]
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus
    }
}
