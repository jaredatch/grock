import AppKit
import XCTest
@testable import Grock

final class FileHandoffTests: XCTestCase {
    func testCLIBookmarksPreserveCommandPromptFileOrderAndContents() async throws {
        let files = try fixtures(["café + report.txt", "second file.txt "])
        for action in [GrockURL.ask(text: "Summarize + compare & explain", files: files),
                       .new(text: "Summarize + compare & explain", files: files)] {
            let url = try action.authorizedHref()
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.filter { $0.name == "bookmark" }.count, 2)
            XCTAssertFalse(items.contains { $0.name == "file" })
            let parsed = try XCTUnwrap(GrockURL.parse(url))
            let urls: [URL]
            switch (action, parsed) {
            case (.ask, .ask(let text, let files)), (.new, .new(let text, let files)):
                XCTAssertEqual(text, "Summarize + compare & explain")
                urls = files
            default: XCTFail("The handoff changed its destination"); return
            }
            let loaded = try await FileIntake.load(urls)
            XCTAssertEqual(loaded.map(\.data), [Data("fixture 0".utf8), Data("fixture 1".utf8)])
        }
    }

    func testPlainFilePathsPreserveTrailingWhitespaceAndEncodedPlus() throws {
        let file = URL(fileURLWithPath: "/tmp/report + final.txt ")
        let action = GrockURL.ask(text: "hello", files: [file])
        XCTAssertEqual(GrockURL.parse(try XCTUnwrap(action.href())), action)
    }

    func testBadAttachmentRejectsEntireURLAndKeepsPrompt() throws {
        let invalidItems = ["file=relative.txt", "file=", "file=file://remote/tmp/note.txt", "file=/tmp/note%00.txt",
                            "bookmark=not-base64", "bookmark=bm90IGEgYm9va21hcms="]
        for invalid in invalidItems {
            let url = try XCTUnwrap(URL(string: "grock://ask?text=keep+me&file=/tmp/good.txt&" + invalid))
            guard case .invalid(let text, let reason) = GrockURL.parse(url) else {
                XCTFail("An invalid attachment was silently omitted: \(invalid)"); continue
            }
            XCTAssertEqual(text, "keep me")
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testRequestBoundsAndUnsupportedFileRoutesFailExplicitly() throws {
        let oversizedBookmark = String(repeating: "A", count: GrockURL.maximumBookmarkBytes * 2)
        let excessiveFiles = Array(repeating: "file=/tmp/note.txt", count: GrockURL.maximumFileCount + 1).joined(separator: "&")
        for string in ["grock://ask?" + excessiveFiles, "grock://new?bookmark=" + oversizedBookmark,
                       "grock://ask?text=" + String(repeating: "x", count: GrockURL.maximumURLBytes),
                       "grock://?file=/tmp/note.txt", "grock://imagine?file=/tmp/note.txt"] {
            guard case .invalid = GrockURL.parse(try XCTUnwrap(URL(string: string))) else {
                XCTFail("Expected a visible request error"); continue
            }
        }
        XCTAssertEqual(GrockURL.parse(try XCTUnwrap(URL(string: "grock://"))), .summon)
        XCTAssertThrowsError(try GrockURL.ask(text: nil, files: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 21)).authorizedHref())
    }

    func testReadErrorsDistinguishPermissionMissingAndOtherFailures() {
        let file = URL(fileURLWithPath: "/tmp/report.txt")
        XCTAssertEqual(FileIntake.readFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)), at: file), .permissionDenied(file))
        XCTAssertEqual(FileIntake.readFailure(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue), at: file), .permissionDenied(file))
        XCTAssertEqual(FileIntake.readFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT)), at: file), .missing("report.txt"))
        XCTAssertEqual(FileIntake.readFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)), at: file), .unreadable("report.txt"))
    }

    @MainActor
    func testCancelAndWrongSelectionPreserveDraftAndBlockPartialSend() async throws {
        let files = try fixtures(["requested.txt", "other.txt"])
        var selection: ((URL?) -> Void)?
        let controller = QuickChatController { requested, completion in
            XCTAssertEqual(requested, files[0]); selection = completion; return nil
        }
        controller.fileLoader = { urls, _, _, _, _ in throw FileIntake.IntakeError.permissionDenied(urls[0]) }
        controller.draft = "keep this draft"
        controller.addFiles([files[0]])
        await controller.waitForPendingIntake()
        XCTAssertTrue(controller.canChooseFile)
        controller.chooseDeniedFile()
        XCTAssertTrue(controller.isChoosingFile)
        controller.handleResignKey()
        selection?(nil)
        XCTAssertFalse(controller.isChoosingFile)
        XCTAssertEqual(controller.draft, "keep this draft")
        XCTAssertFalse(controller.canSend)
        controller.chooseDeniedFile()
        selection?(files[1])
        XCTAssertTrue(controller.attachments.isEmpty)
        XCTAssertTrue(controller.canChooseFile)
        XCTAssertFalse(controller.canSend)
        controller.discardFailedAddition()
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testRecoveryRetriesWholeBatchAndRequiresEveryFile() async throws {
        let files = try fixtures(["first.txt", "second.txt"])
        var selection: ((URL?) -> Void)?
        var allowed: Set<URL> = []
        let controller = QuickChatController { _, completion in selection = completion; return nil }
        controller.fileLoader = { urls, source, date, bytes, count in
            if let denied = urls.first(where: { !allowed.contains($0) }) { throw FileIntake.IntakeError.permissionDenied(denied) }
            return try await FileIntake.load(urls, source: source, copiedAt: date, existingBytes: bytes, existingCount: count)
        }
        controller.draft = "summarize both"
        controller.addFiles(files)
        await controller.waitForPendingIntake()
        for file in files {
            XCTAssertTrue(controller.attachments.isEmpty)
            XCTAssertFalse(controller.canSend)
            controller.chooseDeniedFile()
            allowed.insert(file)
            selection?(file)
            await controller.waitForPendingIntake()
        }
        XCTAssertEqual(controller.attachments.map(\.attachment.data), [Data("fixture 0".utf8), Data("fixture 1".utf8)])
        XCTAssertEqual(controller.draft, "summarize both")
        XCTAssertNil(controller.intakeError)
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testLatePickerCallbackCannotAttachToReplacementPackage() async throws {
        let file = try XCTUnwrap(fixtures(["report.txt"]).first)
        var selection: ((URL?) -> Void)?
        let controller = QuickChatController { _, completion in selection = completion; return nil }
        controller.fileLoader = { urls, _, _, _, _ in throw FileIntake.IntakeError.permissionDenied(urls[0]) }
        controller.addFiles([file])
        await controller.waitForPendingIntake()
        controller.chooseDeniedFile()
        controller.dismiss()
        controller.draft = "new draft"
        selection?(file)
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.draft, "new draft")
        XCTAssertTrue(controller.attachments.isEmpty)
        XCTAssertNil(controller.intakeError)
        XCTAssertFalse(controller.isChoosingFile)
    }

    @MainActor
    func testMultipleFailedAdditionsRemainBlockedUntilEachIsHandled() async throws {
        let files = try fixtures(["first.txt", "second.txt"])
        let controller = QuickChatController()
        controller.fileLoader = { urls, _, _, _, _ in throw FileIntake.IntakeError.permissionDenied(urls[0]) }
        controller.draft = "keep me"
        controller.addFiles([files[0]])
        controller.addFiles([files[1]])
        await controller.waitForPendingIntake()
        controller.discardFailedAddition()
        XCTAssertNotNil(controller.intakeError)
        XCTAssertFalse(controller.canSend)
        controller.discardFailedAddition()
        XCTAssertTrue(controller.canSend)
    }

    @MainActor
    func testNewChatRecoveryReturnsStagedPayloadWithoutSending() async throws {
        let file = try XCTUnwrap(fixtures(["report.txt"]).first)
        var selection: ((URL?) -> Void)?
        var recovered: [QuickChatPayload] = []
        let controller = QuickChatController { _, completion in selection = completion; return nil }
        controller.present(chip: "original prompt")
        defer { controller.dismiss() }
        controller.presentIntakeError(FileIntake.IntakeError.permissionDenied(file), retrying: [file]) { recovered.append($0) }
        controller.draft = "additional instruction"
        controller.chooseDeniedFile()
        selection?(nil)
        XCTAssertTrue(recovered.isEmpty)
        controller.chooseDeniedFile()
        selection?(file)
        await controller.waitForPendingIntake()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.text, "additional instruction\n\noriginal prompt")
        XCTAssertEqual(recovered.first?.attachments.first?.data, Data("fixture 0".utf8))
        XCTAssertFalse(controller.isPresented)
        XCTAssertFalse(controller.sendFailed)
    }

    @MainActor
    func testDroppingFailedNewChatAdditionReturnsPromptWithoutFiles() {
        let controller = QuickChatController()
        var recovered: QuickChatPayload?
        controller.present(chip: "keep this prompt")
        defer { controller.dismiss() }
        controller.presentIntakeError(FileIntake.IntakeError.missing("report.txt")) { recovered = $0 }
        XCTAssertFalse(controller.canChooseFile)
        XCTAssertFalse(controller.canSend)
        controller.discardFailedAddition()
        XCTAssertEqual(recovered?.text, "keep this prompt")
        XCTAssertEqual(recovered?.attachments, [])
        XCTAssertFalse(controller.isPresented)
    }

    private func fixtures(_ names: [String]) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grock-handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try names.enumerated().map { index, name in
            let url = directory.appendingPathComponent(name)
            try Data("fixture \(index)".utf8).write(to: url)
            return url
        }
    }
}
