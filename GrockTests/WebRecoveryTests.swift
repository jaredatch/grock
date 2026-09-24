import AppKit
import XCTest
@testable import Grock

final class WebRecoveryTests: XCTestCase {
    func testReplacedLoadsAndDownloadHandOffDoNotShowRecovery() {
        XCTAssertNil(WebRecoveryState.navigation(URLError(.cancelled)))
        XCTAssertNil(WebRecoveryState.navigation(NSError(domain: "WebKitErrorDomain", code: 102)))
        XCTAssertNotNil(WebRecoveryState.navigation(URLError(.notConnectedToInternet)))
        XCTAssertNotNil(WebRecoveryState.navigation(URLError(.timedOut)))
    }

    @MainActor
    func testRecoveryActionsStayExplicitAndViewCanBeCleared() throws {
        let view = WebRecoveryView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        var retries = 0
        var browserOpens = 0
        view.onRetry = { retries += 1 }
        view.onOpenBrowser = { browserOpens += 1 }
        view.show(.processTerminated)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(retries, 0)
        XCTAssertEqual(browserOpens, 0)
        let retry = try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == "Retry" })
        retry.performClick(nil)
        XCTAssertEqual(retries, 1)
        XCTAssertEqual(browserOpens, 0)
        let browser = try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == "Open in Browser" })
        browser.performClick(nil)
        XCTAssertEqual(browserOpens, 1)
        view.show(nil)
        XCTAssertTrue(view.isHidden)
        XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.allSatisfy { $0.stringValue.isEmpty })
    }

    @MainActor
    func testFailedDownloadRemovesPreviouslyAvailableFinderAction() throws {
        let view = DownloadStatusView(frame: NSRect(x: 0, y: 0, width: 800, height: 44))
        let reveal = try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.title == "Show in Finder" })
        view.show(message: "Saved example.png", fileURL: URL(fileURLWithPath: "/tmp/example.png"))
        XCTAssertFalse(reveal.isHidden)
        view.show(message: "Download failed", fileURL: nil)
        XCTAssertTrue(reveal.isHidden)
        XCTAssertEqual(descendants(view).compactMap { $0 as? NSTextField }.first?.stringValue, "Download failed")
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
