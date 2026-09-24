import Foundation
import WebKit
import XCTest
@testable import Grock

final class WebBoundaryTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        // NSTemporaryDirectory honors the test host's sandbox when it is signed.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testUntrustedFilenamesStayInsideDownloads() throws {
        let directory = try temporaryDirectory()
        for name in ["../outside.txt", "/absolute.txt", "..\\outside.txt", ".", "..", "", "a\u{0000}b.txt"] {
            let destination = try DownloadPaths.write(Data("fixture".utf8), suggestedName: name, in: directory)
            XCTAssertEqual(destination.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
            XCTAssertFalse(destination.lastPathComponent.hasPrefix("."))
            XCTAssertEqual(try Data(contentsOf: destination), Data("fixture".utf8))
        }
        let longName = String(repeating: "🐈", count: 100) + ".png"
        let destination = try DownloadPaths.write(Data([1]), suggestedName: longName, in: directory)
        XCTAssertLessThanOrEqual(destination.lastPathComponent.utf8.count, 200)
        XCTAssertEqual(destination.pathExtension, "png")
    }

    func testExistingAndDanglingSymlinksAreNeverFollowedOrOverwritten() throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory().appendingPathComponent("outside.txt")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("image.png"), withDestinationURL: outside)
        let missing = outside.deletingLastPathComponent().appendingPathComponent("missing.txt")
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("image (1).png"), withDestinationURL: missing)
        let destination = try DownloadPaths.write(Data("image".utf8), suggestedName: "image.png", in: directory)
        XCTAssertEqual(destination.lastPathComponent, "image (2).png")
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testConcurrentDownloadsReserveDifferentNames() throws {
        let directory = try temporaryDirectory()
        let lock = NSLock()
        var destinations: [URL] = []
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            do {
                let destination = try DownloadPaths.write(Data("\(index)".utf8), suggestedName: "image.png", in: directory)
                lock.lock(); destinations.append(destination); lock.unlock()
            } catch {
                lock.lock(); errors.append(error); lock.unlock()
            }
        }
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(Set(destinations).count, 16)
        let contents = try Set(destinations.map { try String(contentsOf: $0, encoding: .utf8) })
        XCTAssertEqual(contents, Set((0..<16).map(String.init)))
    }

    func testWebKitStagingUsesSafeFinalNameAndCleansUp() throws {
        let directory = try temporaryDirectory()
        let staging = try DownloadPaths.stagingDestination(in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        try Data("download".utf8).write(to: staging)
        let destination = try DownloadPaths.finishStagedDownload(staging, suggestedName: "../../file.txt", in: directory)
        XCTAssertEqual(destination.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "download")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.deletingLastPathComponent().path))
    }

    func testWebKitStagingRejectsSymlinkSource() throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory().appendingPathComponent("outside.txt")
        try Data("private".utf8).write(to: outside)
        let staging = try DownloadPaths.stagingDestination(in: directory)
        try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: outside)
        XCTAssertThrowsError(try DownloadPaths.finishStagedDownload(staging, suggestedName: "copy.txt", in: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("copy.txt").path))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "private")
    }

    func testWriteFailureDoesNotReportSuccess() throws {
        let directory = try temporaryDirectory().appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(try DownloadPaths.write(Data([1]), suggestedName: "file.png", in: directory))
    }

    func testOnlyTheCurrentMainGrokOriginCanCallNativeBridgeOrRequestMedia() {
        let grok = URL(string: "https://grok.com/c/fixture")!
        func permits(expected: Bool = true, main: Bool = true, frame: URL? = nil,
                     current: URL? = nil, scheme: String = "https", host: String = "grok.com", port: Int = 443) -> Bool {
            DownloadRequestPolicy.permitsSender(isExpectedView: expected, isMainFrame: main,
                frameURL: frame ?? grok, currentURL: current ?? grok, originScheme: scheme,
                originHost: host, originPort: port)
        }
        XCTAssertTrue(permits())
        XCTAssertTrue(permits(port: 0))
        XCTAssertFalse(permits(expected: false))
        XCTAssertFalse(permits(main: false))
        XCTAssertFalse(permits(scheme: "http"))
        XCTAssertFalse(permits(host: "artifacts.grokusercontent.com"))
        XCTAssertFalse(permits(host: "assets.grok.com"))
        XCTAssertFalse(permits(port: 8443))
        XCTAssertFalse(permits(current: URL(string: "https://accounts.x.ai/sign-in")))
        XCTAssertFalse(permits(frame: URL(string: "https://grok.com.evil.example")))
        XCTAssertFalse(permits(frame: URL(string: "https://www.grok.com")))
    }

    func testNativeFetchAllowsOnlyExactHTTPSAssetHostsAndReadRequests() throws {
        for host in DownloadRequestPolicy.assetHosts {
            XCTAssertNoThrow(try DownloadRequestPolicy.request(url: URL(string: "https://\(host)/image.png")!))
        }
        for raw in ["http://assets.grok.com/image.png", "https://assets.grok.com:8443/image.png",
                    "https://assets.grok.com.evil.example/image.png", "https://evil.assets.grok.com/image.png",
                    "https://user:password@assets.grok.com/image.png", "http://127.0.0.1/private",
                    "file:///etc/hosts", "https://grok.com/rest/chat", "https://api.x.ai/v1/chat"] {
            XCTAssertThrowsError(try DownloadRequestPolicy.request(url: URL(string: raw)!))
        }
        let url = URL(string: "https://assets.grok.com/image.png")!
        XCTAssertThrowsError(try DownloadRequestPolicy.request(url: url, method: "POST"))
        XCTAssertThrowsError(try DownloadRequestPolicy.request(url: url, headers: [["Authorization", "Bearer fake"]]))
        XCTAssertThrowsError(try DownloadRequestPolicy.request(url: url, headers: [["Cookie", "fixture=fake"]]))
        for value in ["image/png\r\nHost: localhost", "image/png\r", "image/png\n", "image/png\u{0000}", "image/png\u{2028}"] {
            XCTAssertThrowsError(try DownloadRequestPolicy.request(url: url, headers: [["Accept", value]]))
        }
        let request = try DownloadRequestPolicy.request(url: url, headers: [["Accept", "image/*"]])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
    }

    func testDownloadHandoffRestoresSurvivingDocumentWithFreshAuthorization() throws {
        var authorization = DownloadDocumentAuthorization()
        let previousToken = try XCTUnwrap(authorization.documentCommitted(isGrok: true))
        let downloadNavigation = NSObject()
        authorization.navigationStarted(downloadNavigation)
        XCTAssertNil(authorization.token)

        let restoredToken = try XCTUnwrap(authorization.provisionalNavigationFailed(downloadNavigation))
        XCTAssertEqual(authorization.token, restoredToken)
        XCTAssertNotEqual(restoredToken, previousToken, "Canceled transfer replies must remain invalid")
        XCTAssertNil(authorization.provisionalNavigationFailed(downloadNavigation), "Only restore once")
    }

    func testSupersededNavigationCancellationCannotReauthorizeReplacement() throws {
        var authorization = DownloadDocumentAuthorization()
        _ = authorization.documentCommitted(isGrok: true)
        let oldNavigation = NSObject(), replacement = NSObject()
        authorization.navigationStarted(oldNavigation)
        authorization.navigationStarted(replacement)
        XCTAssertNil(authorization.provisionalNavigationFailed(oldNavigation))
        XCTAssertNil(authorization.token)
        XCTAssertNotNil(authorization.provisionalNavigationFailed(replacement))
    }

    func testFailedInitialLoadAuthCommitAndProcessTerminationCannotRestoreGrokAuthorization() {
        var authorization = DownloadDocumentAuthorization()
        let navigation = NSObject()
        authorization.navigationStarted(navigation)
        XCTAssertNil(authorization.provisionalNavigationFailed(navigation))

        _ = authorization.documentCommitted(isGrok: true)
        authorization.navigationStarted(navigation)
        _ = authorization.documentCommitted(isGrok: false)
        authorization.navigationStarted(navigation)
        XCTAssertNil(authorization.provisionalNavigationFailed(navigation))
        XCTAssertNil(authorization.token)

        _ = authorization.documentCommitted(isGrok: true)
        authorization.navigationStarted(navigation)
        authorization.invalidate()
        XCTAssertNil(authorization.provisionalNavigationFailed(navigation))
        XCTAssertNil(authorization.token)
    }

    func testAssetTransferReturnsSuccessfulBytes() async throws {
        let output = try await transfer(path: "ok")
        XCTAssertEqual(output.data, Data([1, 2, 3, 4]))
        XCTAssertEqual(output.response.statusCode, 200)
    }

    func testAssetTransferRejectsHTTPErrorAndEmptyResponse() async {
        for path in ["not-found", "empty"] {
            do { _ = try await transfer(path: path); XCTFail("Expected failure for \(path)") }
            catch { XCTAssertTrue(error is DownloadFailure) }
        }
    }

    func testAssetTransferBoundsDeclaredAndStreamedBytes() async {
        for path in ["declared-large", "streamed-large"] {
            do { _ = try await transfer(path: path); XCTFail("Expected size limit for \(path)") }
            catch {
                guard case DownloadFailure.tooLarge = error else { XCTFail("Unexpected error: \(error)"); continue }
            }
        }
    }

    func testRedirectCannotLeaveAllowlistOrCarryHeaders() {
        let transfer = AssetTransfer()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://assets.grok.com/image.png")!
        let task = session.dataTask(with: original)
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var forbidden = URLRequest(url: URL(string: "http://127.0.0.1/private")!)
        forbidden.setValue("fixture", forHTTPHeaderField: "Authorization")
        transfer.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: forbidden) {
            XCTAssertNil($0)
        }
        var allowed = URLRequest(url: URL(string: "https://imagine-public.x.ai/image.png")!)
        allowed.setValue("fixture", forHTTPHeaderField: "Authorization")
        transfer.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: allowed) {
            XCTAssertEqual($0?.url, allowed.url)
            XCTAssertNil($0?.value(forHTTPHeaderField: "Authorization"))
        }
    }

    private func transfer(path: String) async throws -> AssetTransfer.Output {
        let transfer = AssetTransfer(maximumBytes: 16)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssetFixtureProtocol.self]
        let request = try DownloadRequestPolicy.request(url: URL(string: "https://assets.grok.com/\(path)")!)
        return try await withCheckedThrowingContinuation { continuation in
            transfer.start(request, configuration: configuration) { continuation.resume(with: $0) }
        }
    }
}

private final class AssetFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "assets.grok.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.lastPathComponent
        var headers = ["Content-Type": "image/png"]
        if path == "declared-large" { headers["Content-Length"] = "1024" }
        let response = HTTPURLResponse(url: url, statusCode: path == "not-found" ? 404 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "streamed-large" {
            client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 10))
            client?.urlProtocol(self, didLoad: Data(repeating: 2, count: 10))
        } else if path != "empty" {
            client?.urlProtocol(self, didLoad: Data([1, 2, 3, 4]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
