import AppKit
import Darwin
import XCTest
@testable import Grock

final class ContextIntakeTests: XCTestCase {
    func testAutomaticClipboardCaptureSkipsEveryConfidentialAndTransientMarker() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let defaults = try isolatedDefaults()
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        for marker in PasteboardMonitor.excludedAutomaticTypes {
            pasteboard.clearContents()
            pasteboard.setString("fake private text", forType: .string)
            pasteboard.setData(Data(), forType: marker)
            monitor.markChanged()
            XCTAssertNil(monitor.snapshotIfRecent(pasteboard: pasteboard, defaults: defaults), marker.rawValue)
            // Filtering does not alter what an explicit Paste can retrieve.
            XCTAssertEqual(pasteboard.string(forType: .string), "fake private text")
        }
        pasteboard.clearContents()
        pasteboard.setString("ordinary copy", forType: .string)
        monitor.markChanged()
        XCTAssertEqual(monitor.snapshotIfRecent(pasteboard: pasteboard, defaults: defaults)?.text, "ordinary copy")
    }

    func testMarkerOnAnotherPasteboardItemBlocksTheWholeAutomaticCapture() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let ordinary = NSPasteboardItem()
        ordinary.setString("ordinary", forType: .string)
        let confidential = NSPasteboardItem()
        confidential.setString("fake secret", forType: .string)
        confidential.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(pasteboard.writeObjects([ordinary, confidential]))
        XCTAssertFalse(PasteboardMonitor.permitsAutomaticCapture(pasteboard))
    }

    func testClipboardPreferenceDisablesAutomaticCaptureAndResetRestoresDefault() throws {
        let defaults = try isolatedDefaults()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("ordinary", forType: .string)
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        monitor.markChanged()
        XCTAssertTrue(ClipboardPreference.autoInclude(defaults: defaults))
        defaults.set(false, forKey: ClipboardPreference.autoIncludeKey)
        XCTAssertNil(monitor.snapshotIfRecent(pasteboard: pasteboard, defaults: defaults))
        ClipboardPreference.reset(defaults: defaults)
        XCTAssertEqual(monitor.snapshotIfRecent(pasteboard: pasteboard, defaults: defaults)?.text, "ordinary")
    }

    func testClipboardMonitorOnlyWatchesWhileCaptureIsOn() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        defer { monitor.stop() }

        monitor.sync(enabled: false, pasteboard: pasteboard)
        XCTAssertFalse(monitor.isPolling)

        monitor.sync(enabled: true, pasteboard: pasteboard)
        XCTAssertTrue(monitor.isPolling)
        pasteboard.clearContents()
        pasteboard.setString("copied while on", forType: .string)
        monitor.poll(pasteboard)
        XCTAssertTrue(monitor.isRecent())

        monitor.sync(enabled: false, pasteboard: pasteboard)
        XCTAssertFalse(monitor.isPolling)
        XCTAssertFalse(monitor.isRecent(), "turning capture off forgets the last copy")

        pasteboard.clearContents()
        pasteboard.setString("copied while off", forType: .string)
        monitor.sync(enabled: true, pasteboard: pasteboard)
        monitor.poll(pasteboard)
        XCTAssertFalse(monitor.isRecent(), "a copy made while capture was off must not count")

        pasteboard.clearContents()
        pasteboard.setString("copied after", forType: .string)
        monitor.poll(pasteboard)
        XCTAssertTrue(monitor.isRecent())
    }

    func testAutomaticFileCaptureDefersFileReadsToTheLoader() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("large.pdf")
        try sparseFile(file, size: QuickChatPayload.maxAttachmentBytes + 1)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        let monitor = PasteboardMonitor(pasteboard: pasteboard)
        monitor.markChanged()
        let snapshot = try XCTUnwrap(monitor.snapshotIfRecent(pasteboard: pasteboard, defaults: isolatedDefaults()))
        XCTAssertEqual(snapshot.fileURLs, [file])
        XCTAssertTrue(snapshot.attachments.isEmpty)
    }

    func testAsyncFileLoadPreservesMetadataAndContents() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("note.txt")
        let bytes = Data("a useful note".utf8)
        try bytes.write(to: file)
        let copiedAt = Date(timeIntervalSince1970: 1_000)
        let attachments = try await FileIntake.load([file], source: .clipboard, copiedAt: copiedAt)
        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(attachment.data, bytes)
        XCTAssertEqual(attachment.filename, "note.txt")
        XCTAssertEqual(attachment.mimeType, "text/plain")
        XCTAssertEqual(attachment.sourceURL, file)
        XCTAssertEqual(attachment.source, .clipboard)
        XCTAssertEqual(attachment.copiedAt, copiedAt)
    }

    func testLoaderRejectsOversizeBatchAtomically() async throws {
        let directory = try temporaryDirectory()
        let good = directory.appendingPathComponent("good.txt")
        let huge = directory.appendingPathComponent("huge.pdf")
        try Data("good".utf8).write(to: good)
        try sparseFile(huge, size: QuickChatPayload.maxAttachmentBytes + 1)
        do {
            _ = try await FileIntake.load([good, huge])
            XCTFail("A rejected file must reject the whole addition")
        } catch {
            XCTAssertEqual(error as? FileIntake.IntakeError, .oversized("huge.pdf"))
        }
    }

    func testLoaderPreflightsAggregateSizeAndCountIncludingExistingPackage() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("medium.pdf")
        try sparseFile(file, size: 9_000_000)
        do {
            _ = try await FileIntake.load([file, file], existingBytes: 9_000_000)
            XCTFail("Existing staged bytes count toward the package limit")
        } catch { XCTAssertEqual(error as? FileIntake.IntakeError, .totalSize) }
        do {
            _ = try await FileIntake.load([file], existingCount: QuickChatPayload.maxAttachmentCount)
            XCTFail("Existing staged files count toward the count limit")
        } catch { XCTAssertEqual(error as? FileIntake.IntakeError, .tooManyFiles) }
    }

    func testLoaderRejectsEmptyMissingDirectoryAndNamedPipe() async throws {
        let directory = try temporaryDirectory()
        let empty = directory.appendingPathComponent("empty.txt")
        try Data().write(to: empty)
        let pipe = directory.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let cases: [(URL, FileIntake.IntakeError)] = [
            (empty, .empty("empty.txt")),
            (directory.appendingPathComponent("missing.txt"), .missing("missing.txt")),
            (directory, .notRegularFile(directory.lastPathComponent)),
            (pipe, .notRegularFile("pipe"))
        ]
        for (url, expected) in cases {
            do {
                _ = try await FileIntake.load([url])
                XCTFail("Expected rejection for \(url.lastPathComponent)")
            } catch { XCTAssertEqual(error as? FileIntake.IntakeError, expected) }
        }
    }

    func testCancelledLoadDoesNotReturnAttachments() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("note.txt")
        try Data("note".utf8).write(to: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileIntake.load([file])
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must reach callers")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    func testDismissedIntakeCannotResurrectAttachments() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("note.txt")
        try Data("note".utf8).write(to: file)
        let controller = QuickChatController()
        controller.addFiles([file])
        XCTAssertEqual(controller.pendingIntakeCount, 1)
        controller.dismiss()
        await controller.waitForPendingIntake()
        await Task.yield()
        XCTAssertEqual(controller.pendingIntakeCount, 0)
        XCTAssertTrue(controller.attachments.isEmpty)
        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.intakeError)
    }

    @MainActor
    func testReplacementPackageIgnoresCancelledEarlierAddition() async throws {
        let directory = try temporaryDirectory()
        let first = directory.appendingPathComponent("first.txt")
        let replacement = directory.appendingPathComponent("replacement.txt")
        try Data("first".utf8).write(to: first)
        try Data("replacement".utf8).write(to: replacement)
        let controller = QuickChatController()
        controller.addFiles([first])
        controller.dismiss()
        controller.addFiles([replacement])
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.attachments.map(\.attachment.filename), ["replacement.txt"])
        XCTAssertEqual(controller.pendingIntakeCount, 0)
    }

    @MainActor
    func testRejectedAdditionBlocksPartialSendUntilExplicitlyDiscarded() async throws {
        let directory = try temporaryDirectory()
        let good = directory.appendingPathComponent("good.txt")
        let empty = directory.appendingPathComponent("empty.txt")
        try Data("good".utf8).write(to: good)
        try Data().write(to: empty)
        let controller = QuickChatController()
        controller.draft = "summarize"
        controller.addFiles([good, empty])
        XCTAssertFalse(controller.canSend)
        await controller.waitForPendingIntake()
        XCTAssertTrue(controller.attachments.isEmpty)
        XCTAssertNotNil(controller.intakeError)
        XCTAssertFalse(controller.canSend)
        controller.discardFailedAddition()
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testConcurrentAdditionsRespectAggregateLimit() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("attachment.pdf")
        try sparseFile(file, size: 9_000_000)
        let controller = QuickChatController()
        controller.addFiles([file])
        controller.addFiles([file])
        controller.addFiles([file])
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.attachments.count, 2)
        XCTAssertNotNil(controller.intakeError)
        XCTAssertFalse(controller.canSend)
        controller.discardFailedAddition()
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testExplicitFilePasteCanIncludeConfidentialMarkedContent() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("deliberate.txt")
        try Data("fake private document".utf8).write(to: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertFalse(PasteboardMonitor.permitsAutomaticCapture(pasteboard))
        let controller = QuickChatController()
        XCTAssertTrue(controller.addDroppedPasteboard(pasteboard))
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.attachments.first?.attachment.filename, "deliberate.txt")
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testUncertainSendRequiresAcknowledgementBeforeRetry() {
        let controller = QuickChatController()
        controller.draft = "hello"
        controller.sendFailed = true
        controller.sendUncertain = true
        XCTAssertFalse(controller.canSend)
        XCTAssertTrue(controller.sendFailedMessage.contains("twice"))
        controller.acknowledgeUncertainSend()
        XCTAssertTrue(controller.canSend)
        XCTAssertFalse(controller.sendFailed)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "GrockContextIntakeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grock-intake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func sparseFile(_ url: URL, size: Int) throws {
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }
}
