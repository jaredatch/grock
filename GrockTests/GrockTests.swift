import AppKit
import Carbon
import CoreGraphics
import WebKit
import XCTest
@testable import Grock

final class GrockTests: XCTestCase {
    @MainActor
    func testFreshSessionScriptPrefersInPageNewChat() {
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("New Chat"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("Create New Chat"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("already-fresh"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("if (startPath()) return 'already-fresh'"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("findCreateNewChat"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("findHeaderNewChat"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("findChatHome"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("findProjectNewChat"))
        XCTAssertFalse(WebViewStore.freshSessionScript.contains("function findSearch"))
        XCTAssertFalse(WebViewStore.freshSessionScript.contains("composerEmpty(composer())"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("clicked"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("missing"))
        XCTAssertTrue(WebViewStore.freshSessionScript.contains("[data-sidebar]"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("Imagine"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("/imagine"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("clicked"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("navigated"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("isImagineHome"))
        XCTAssertTrue(WebViewStore.clickImagineHomeScript.contains("already-home"))
        XCTAssertFalse(WebViewStore.clickImagineHomeScript.contains("indexOf('/imagine/')"))
        XCTAssertTrue(WebViewStore.newGenerationScript.contains("New Generation"))
        XCTAssertTrue(WebViewStore.newGenerationScript.contains("already-home"))
        let already = WebViewStore.newGenerationScript.range(
            of: "if (imagineHome()) return 'already-home'"
        )
        let find = WebViewStore.newGenerationScript.range(of: "findNewGeneration")
        XCTAssertNotNil(already)
        XCTAssertNotNil(find)
        XCTAssertLessThan(already!.lowerBound, find!.lowerBound)
        XCTAssertTrue(WebViewStore.isImagineHome(URL(string: "https://grok.com/imagine")))
        XCTAssertTrue(WebViewStore.isImagineHome(URL(string: "https://grok.com/imagine/")))
        XCTAssertFalse(WebViewStore.isImagineHome(URL(string: "https://grok.com/imagine/saved")))
        XCTAssertFalse(WebViewStore.isImagineHome(URL(string: "https://grok.com")))
        let ready = WebViewStore.composerReadyScript(pathBefore: "/c/abc")
        XCTAssertTrue(ready.contains("/c/abc"))
        XCTAssertTrue(ready.contains("oldPath"))
    }

    func testAppearancePreferenceTitles() {
        XCTAssertEqual(AppearancePreference.system.title, "Auto")
        XCTAssertEqual(AppearancePreference.light.title, "Light")
        XCTAssertEqual(AppearancePreference.dark.title, "Dark")
    }

    func testChromeCollapseDefaultsOnWhenUnset() {
        let defaults = UserDefaults.standard
        let prior = ChromePreference.allKeys.map { ($0, defaults.object(forKey: $0)) }
        for key in ChromePreference.allKeys { defaults.removeObject(forKey: key) }
        defer {
            for (key, value) in prior {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        XCTAssertTrue(ChromePreference.current.collapseSidebar)
        XCTAssertTrue(ChromePreference.current.sidebarHidden)
        XCTAssertTrue(ChromePreference.current.hideGrokBot)
        XCTAssertTrue(ChromePreference.current.hidePrivate)
        XCTAssertFalse(ChromePreference.current.hideImagine)
        XCTAssertFalse(ChromePreference.current.hideLibrary)
        XCTAssertFalse(ChromePreference.current.hideVoice)
    }

    func testHideSidebarOnLaunchOverridesLastSession() {
        let defaults = UserDefaults.standard
        let launchKey = ChromePreference.hideSidebarOnLaunchKey
        let hiddenKey = ChromePreference.sidebarHiddenKey
        let priorLaunch = defaults.object(forKey: launchKey)
        let priorHidden = defaults.object(forKey: hiddenKey)
        defer {
            for (key, value) in [(launchKey, priorLaunch), (hiddenKey, priorHidden)] {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(true, forKey: launchKey)
        defaults.set(false, forKey: hiddenKey)
        ChromePreference.applyLaunchSidebarPolicy()
        XCTAssertTrue(ChromePreference.current.sidebarHidden)
    }

    func testUncheckedHideSidebarOnLaunchKeepsLastSession() {
        let defaults = UserDefaults.standard
        let launchKey = ChromePreference.hideSidebarOnLaunchKey
        let hiddenKey = ChromePreference.sidebarHiddenKey
        let priorLaunch = defaults.object(forKey: launchKey)
        let priorHidden = defaults.object(forKey: hiddenKey)
        defer {
            for (key, value) in [(launchKey, priorLaunch), (hiddenKey, priorHidden)] {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(false, forKey: launchKey)
        defaults.set(false, forKey: hiddenKey)
        ChromePreference.applyLaunchSidebarPolicy()
        XCTAssertFalse(ChromePreference.current.sidebarHidden)
    }

    func testSettingsResetRestoresChromeAndThemeDefaults() {
        let defaults = UserDefaults.standard
        let keys = ChromePreference.allKeys + [
            AppearancePreference.defaultsKey,
            WebViewStore.webInspectorKey,
            AppDelegate.hideFromDockKey,
            AppDelegate.windowFrameKey
        ]
        let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in prior {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(AppearancePreference.dark.rawValue, forKey: AppearancePreference.defaultsKey)
        defaults.set(false, forKey: ChromePreference.collapseSidebarKey)
        defaults.set(false, forKey: ChromePreference.sidebarHiddenKey)
        defaults.set(true, forKey: ChromePreference.hideImagineKey)
        defaults.set(true, forKey: ChromePreference.hideLibraryKey)
        defaults.set(false, forKey: ChromePreference.hideGrokBotKey)
        defaults.set(false, forKey: ChromePreference.hidePrivateKey)
        defaults.set(true, forKey: WebViewStore.webInspectorKey)
        defaults.set(true, forKey: AppDelegate.hideFromDockKey)
        defaults.set(["x": 10.0, "y": 20.0, "w": 400.0, "h": 300.0], forKey: AppDelegate.windowFrameKey)

        SettingsReset.restorePreferenceDefaults()

        XCTAssertEqual(AppearancePreference.current, .system)
        XCTAssertTrue(ChromePreference.current.collapseSidebar)
        XCTAssertTrue(ChromePreference.current.sidebarHidden)
        XCTAssertTrue(ChromePreference.current.hideGrokBot)
        XCTAssertTrue(ChromePreference.current.hidePrivate)
        XCTAssertFalse(ChromePreference.current.hideImagine)
        XCTAssertFalse(ChromePreference.current.hideLibrary)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: WebViewStore.webInspectorKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppDelegate.hideFromDockKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: AppDelegate.windowFrameKey))
    }

    func testPanelGeometryDefaultAndMinSizes() {
        XCTAssertEqual(PanelGeometry.defaultContentSize, NSSize(width: 920, height: 680))
        XCTAssertEqual(PanelGeometry.minContentSize, NSSize(width: 720, height: 520))
    }

    func testPanelGeometryKeepsOnscreenFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 100, y: 80, width: 920, height: 680)
        let result = PanelGeometry.constrainedFrame(
            frame,
            visibleScreens: [screen],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result, frame)
    }

    func testPanelGeometryNudgesPartialOverflow() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 1200, y: 700, width: 920, height: 680)
        let result = PanelGeometry.constrainedFrame(
            frame,
            visibleScreens: [screen],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result.origin.x, 520, accuracy: 0.5)
        XCTAssertEqual(result.origin.y, 220, accuracy: 0.5)
        XCTAssertEqual(result.size, NSSize(width: 920, height: 680))
    }

    func testPanelGeometryRecentersFullyOffscreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 5000, y: 4000, width: 920, height: 680)
        let result = PanelGeometry.constrainedFrame(
            frame,
            visibleScreens: [screen],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result.origin.x, (1440 - 920) / 2, accuracy: 0.5)
        XCTAssertEqual(result.origin.y, (900 - 680) / 2, accuracy: 0.5)
    }

    func testPanelGeometryEnforcesMinSize() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: 40, y: 40, width: 200, height: 200)
        let result = PanelGeometry.constrainedFrame(
            frame,
            visibleScreens: [screen],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result.size, PanelGeometry.minContentSize)
        XCTAssertGreaterThanOrEqual(result.minX, screen.minX)
        XCTAssertGreaterThanOrEqual(result.minY, screen.minY)
        XCTAssertLessThanOrEqual(result.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(result.maxY, screen.maxY)
    }

    func testSummonFrameLeavesSameScreenAlone() {
        let laptop = PanelGeometry.Screen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visible: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let frame = NSRect(x: 100, y: 80, width: 920, height: 680)
        let result = PanelGeometry.summonFrame(
            current: frame,
            cursor: CGPoint(x: 200, y: 200),
            screens: [laptop],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result, frame)
    }

    func testSummonFrameMovesToCursorScreen() {
        let laptop = PanelGeometry.Screen(
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visible: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let cinema = PanelGeometry.Screen(
            frame: NSRect(x: 1440, y: 0, width: 2560, height: 1440),
            visible: NSRect(x: 1440, y: 0, width: 2560, height: 1440)
        )
        let frame = NSRect(x: 100, y: 80, width: 920, height: 680)
        let result = PanelGeometry.summonFrame(
            current: frame,
            cursor: CGPoint(x: 2000, y: 400),
            screens: [laptop, cinema],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertEqual(result.origin.x, 1540, accuracy: 0.5)
        XCTAssertEqual(result.origin.y, 80, accuracy: 0.5)
        XCTAssertEqual(result.size, frame.size)
    }

    func testSummonFrameClampsOntoSmallerCursorScreen() {
        let cinema = PanelGeometry.Screen(
            frame: NSRect(x: 0, y: 0, width: 2560, height: 1440),
            visible: NSRect(x: 0, y: 0, width: 2560, height: 1440)
        )
        let laptop = PanelGeometry.Screen(
            frame: NSRect(x: 2560, y: 0, width: 1440, height: 900),
            visible: NSRect(x: 2560, y: 0, width: 1440, height: 900)
        )
        let frame = NSRect(x: 1500, y: 100, width: 920, height: 680)
        let result = PanelGeometry.summonFrame(
            current: frame,
            cursor: CGPoint(x: 2800, y: 200),
            screens: [cinema, laptop],
            minSize: PanelGeometry.minContentSize
        )
        XCTAssertGreaterThanOrEqual(result.minX, laptop.visible.minX)
        XCTAssertLessThanOrEqual(result.maxX, laptop.visible.maxX)
        XCTAssertEqual(result.size, frame.size)
    }

    func testPageTitleFallsBackForGrokAndEmpty() {
        XCTAssertEqual(PageTitle.display(nil), "Grok")
        XCTAssertEqual(PageTitle.display(""), "Grok")
        XCTAssertEqual(PageTitle.display("   "), "Grok")
        XCTAssertEqual(PageTitle.display("Grok"), "Grok")
        XCTAssertEqual(PageTitle.display("grok"), "Grok")
        XCTAssertEqual(PageTitle.display("How to cook a steak"), "How to cook a steak")
        XCTAssertEqual(PageTitle.display("Steak | Grok"), "Steak")
        XCTAssertEqual(PageTitle.display("Steak - Grok"), "Steak")
        XCTAssertEqual(PageTitle.display("Privacy Preference Center"), "Grok")
        XCTAssertEqual(
            PageTitle.display("Privacy Preference Center", url: URL(string: "https://grok.com/c/abc")),
            "Grok"
        )
        XCTAssertTrue(PageTitle.isJunk("Privacy Preference Center"))
    }

    func testPageTitleUsesPlaceFromURL() {
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com")), "Grok")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/imagine")), "Imagine")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/library")), "Library")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/library/abc")), "Library")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/files")), "Library")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/files/abc")), "Library")
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/automations")), "Automations")
        XCTAssertEqual(
            PageTitle.display("Grok", url: URL(string: "https://grok.com/skills-and-connectors")),
            "Plugins"
        )
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/project/abc")), "Projects")
        XCTAssertEqual(
            PageTitle.display("Steak recipe", url: URL(string: "https://grok.com/c/abc")),
            "Steak recipe"
        )
        XCTAssertEqual(PageTitle.display("Grok", url: URL(string: "https://grok.com/c/abc")), "Grok")
        XCTAssertNil(PageTitle.placeName(for: URL(string: "https://grok.com/c/abc")))
        XCTAssertEqual(PageTitle.placeName(for: URL(string: "https://grok.com")), "Grok")
    }

    func testChromeSnapshotJSONHasExpectedKeys() {
        let json = ChromePreference.Snapshot(
            collapseSidebar: true,
            sidebarHidden: true,
            hideImagine: true,
            hideLibrary: false,
            hideAutomations: false,
            hideProjects: false,
            hidePlugins: true,
            hideGrokBot: true,
            hidePrivate: true,
            hideDictation: false,
            hideVoice: true
        ).jsonString
        XCTAssertTrue(json.contains("\"collapseSidebar\":true"))
        XCTAssertTrue(json.contains("\"sidebarHidden\":true"))
        XCTAssertTrue(json.contains("\"hideImagine\":true"))
        XCTAssertTrue(json.contains("\"hideLibrary\":false"))
        XCTAssertTrue(json.contains("\"hideAutomations\":false"))
        XCTAssertTrue(json.contains("\"hidePlugins\":true"))
        XCTAssertFalse(json.contains("hideSkills"))
        XCTAssertTrue(json.contains("\"hideGrokBot\":true"))
        XCTAssertTrue(json.contains("\"hidePrivate\":true"))
        XCTAssertTrue(json.contains("\"hideVoice\":true"))
    }

    func testEdgeFixFlattensSafariScrollShells() {
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("grock-edge-fix"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("background-color:transparent"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("data-grock-edge-shell"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains(".overflow-scroll"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("setProperty"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("__grockEdgeFix"))
        XCTAssertFalse(WebViewStore.edgeFixScript.contains("attributeFilter"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("childList: true"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("nodeType === 1"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains("el.textContent !== css") || WebViewStore.edgeFixScript.contains("textContent !== css"))
        XCTAssertTrue(WebViewStore.edgeFixScript.contains(":not([data-grock-edge-shell])"))
    }

    func testReplyMonitorMarksUnreadWhenNotWatching() {
        var reply = ReplyMonitor()
        XCTAssertFalse(reply.hasUnread)
        reply.noteGenerating(true)
        XCTAssertTrue(reply.isGenerating)
        XCTAssertFalse(reply.noteLanded(userIsWatching: true))
        XCTAssertFalse(reply.hasUnread)
        reply.noteGenerating(true)
        XCTAssertTrue(reply.noteLanded(userIsWatching: false))
        XCTAssertTrue(reply.hasUnread)
        XCTAssertFalse(reply.isGenerating)
        XCTAssertFalse(reply.noteLanded(userIsWatching: false))
        XCTAssertTrue(reply.hasUnread)
        XCTAssertTrue(reply.clearUnread())
        XCTAssertFalse(reply.hasUnread)
        XCTAssertFalse(reply.clearUnread())
        XCTAssertEqual(ReplyMonitor.dockBadgeLabel(unread: true), "1")
        XCTAssertNil(ReplyMonitor.dockBadgeLabel(unread: false))
    }

    func testReplyObserverWiresPageHook() {
        let script = WebViewStore.replyObserverScript
        XCTAssertTrue(script.contains("window.__grockReply"))
        XCTAssertTrue(script.contains("grockReply"))
        XCTAssertTrue(script.contains("stop generating"))
        XCTAssertTrue(script.contains("post('landed')"))
        XCTAssertFalse(script.contains("exit voice"))
        XCTAssertFalse(script.contains("isVoiceExit"))
        XCTAssertTrue(script.contains("scrollToAnswer"))
        XCTAssertTrue(script.contains("attributeFilter: ['aria-label', 'title', 'disabled']"))
        XCTAssertFalse(script.contains("attributeFilter: ['style'"))
        XCTAssertFalse(script.contains("s === 'cancel'"))
        XCTAssertFalse(script.contains("requestAnimationFrame"))
    }

    @MainActor
    func testReplyObserverSeesStopThenLanded() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <form>
            <textarea></textarea>
            <button type="submit" aria-label="Submit" id="send" style="width:24px;height:24px">S</button>
          </form>
        </body>
        </html>
        """
        let idle = try await evaluateReplyState(html: html)
        XCTAssertEqual(idle["busy"], false)
        XCTAssertEqual(idle["generating"], false)

        let generating = try await evaluateReplyScript(
            html: html,
            script: """
            (function () {
              var btn = document.getElementById('send');
              btn.setAttribute('aria-label', 'Stop generating');
              window.__grockReply.tick();
              return window.__grockReply.state();
            })()
            """
        )
        XCTAssertEqual(generating["busy"], true)
        XCTAssertEqual(generating["generating"], true)

        let landed = try await evaluateReplyScript(
            html: html,
            script: """
            (function () {
              var btn = document.getElementById('send');
              btn.setAttribute('aria-label', 'Stop generating');
              window.__grockReply.tick();
              btn.setAttribute('aria-label', 'Submit');
              window.__grockReply.tick();
              return window.__grockReply.state();
            })()
            """
        )
        XCTAssertEqual(landed["busy"], false)
        XCTAssertEqual(landed["generating"], false)
    }

    @MainActor
    func testReplyObserverIgnoresCookieCancel() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <button aria-label="Submit" style="width:24px;height:24px">S</button>
          <button aria-label="Cancel" style="width:24px;height:24px">Cancel</button>
        </body>
        </html>
        """
        let state = try await evaluateReplyState(html: html)
        XCTAssertEqual(state["busy"], false)
    }

    @MainActor
    func testReplyObserverIgnoresVoiceExit() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <button aria-label="Submit" style="width:24px;height:24px">S</button>
          <button aria-label="Exit voice mode" style="width:24px;height:24px">X</button>
        </body>
        </html>
        """
        let state = try await evaluateReplyState(html: html)
        XCTAssertEqual(state["busy"], false)
    }

    @MainActor
    func testReplyObserverScrollsToLastCopy() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <main id="grok-content-area">
            <div id="thread" style="height:160px;overflow:auto;width:320px">
              <div style="height:400px">pad</div>
              <article id="answer">
                <p>Hello from Grok</p>
                <button aria-label="Copy" style="width:24px;height:24px">Copy</button>
              </article>
            </div>
            <form>
              <textarea></textarea>
              <button aria-label="Submit" style="width:24px;height:24px">S</button>
            </form>
          </main>
        </body>
        </html>
        """
        let outcome = try await evaluateReplyString(
            html: html,
            script: "window.__grockReply.scrollToAnswer()"
        )
        XCTAssertEqual(outcome, "scrolled")
    }

    @MainActor
    func testChromeScriptWiresPageHook() {
        XCTAssertTrue(WebViewStore.chromeScript.contains("window.__grockChrome"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-hide"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("'Plugins'"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("{ key: 'hideImagine', text: 'Imagine', href: '/imagine', group: false }"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("{ key: 'hideLibrary', text: 'Library', href: '/library', group: false }"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("{ key: 'hidePlugins', text: 'Plugins', href: '', group: false }"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("{ key: 'hideProjects', text: 'Projects', href: '/project', group: true }"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("Skills and Connectors"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("hideSkills"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("Enter voice mode"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("div.h-10.w-10"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markComposerControl"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("sidebarShowsFullLabels"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("collapseIfExpanded"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("expandIfCollapsed"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("sidebarHidden: true"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("hidePrivate: true"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("hideGrokBot: true"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markHeaderControl"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-sidebar-hidden"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markSidebarShell"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("sidebarChromeCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[data-sidebar=\"header\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[data-sidebar=\"rail\"],[data-sidebar=\"resize-handle\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[data-slot=\"sidebar-rail\"],[data-slot=\"sidebar-resize-handle\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-rail"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("muteCollapseRails"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("blockRailEvent"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("stopImmediatePropagation"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("pointer-events:none"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("-end-[5px]"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("w-[10px]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("keepSidebarExpanded"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("sidebarIsIconCollapsed"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("var wasHidden = root.hasAttribute('data-grock-sidebar-hidden')"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function expandIfCollapsed() {"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("keepSidebarExpanded();"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("attributeFilter: ['data-state', 'disabled', 'aria-disabled', 'aria-busy', 'aria-pressed', 'aria-hidden']"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("titlebarInsetCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("grok-content-area"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("div[data-sidebar=\"sidebar\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("padding-top:var(--grock-titlebar)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("--grock-titlebar:52px"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("findContentInsetTarget"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isViewportShell"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isPromptLike"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isRealScroller"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function bestScrollingDescendant"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function scrollerFillsContentTop"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function restoreScrollerOverflow"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-scroll-restore"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("pinnedSidebarHidden"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("insetTargetIsStable"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("pinnedInsetTarget"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isComposerTree"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("TITLEBAR_SPACER_PX"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (full && !config.sidebarHidden) keepSidebarExpanded"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (insetChanged) chaseContentInset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("applyContentInset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isImaginePage"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isImaginePath"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isImagineAgentPath"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isLibraryPath"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function isAutomationsPath"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function usesShellInset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("clearImagineOverlayChrome"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (isImaginePage())"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (usesShellInset())"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("return isImagineAgentPath();"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("grockImagineOverlaySpecialCase"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("p.indexOf('/imagine/') === 0"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("p === '/imagine/agent' || p.indexOf('/imagine/agent/') === 0"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("p === '/library' || p.indexOf('/library/') === 0"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("p === '/automations' || p.indexOf('/automations/') === 0"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-imagine-path"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("imagineStickyCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[data-composer-hero].sticky"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(".sticky.top-0.z-30.h-16"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("calc(76px + var(--grock-titlebar))"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("position:sticky;top:0;z-index:50"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html[data-grock-imagine-path]:not([data-grock-imagine]) #grok-content-area"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html[data-grock-imagine-path] #grock-titlebar-fade{display:none"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("imagineShellInsetCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("libraryFillCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html[data-grock-shell-inset]:not([data-grock-imagine]) #grok-content-area"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html[data-grock-shell-inset]:not([data-grock-imagine]) #grok-content-area [class*=\"from-surface-base\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html[data-grock-imagine] #grok-content-area[data-grock-imagine-inset=\"pad\"],"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("applyImagineShellInset"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("html:not([data-grock-imagine]) [role=\"dialog\"]:has("))
        XCTAssertFalse(WebViewStore.chromeScript.contains("html:not([data-grock-imagine]) [data-grock-plugins-dialog]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("50% + (var(--grock-titlebar) / 2)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("100dvh - var(--grock-titlebar) - 32px"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("pluginsDialogInsetCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-plugins-dialog"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-plugins-overlay"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markPluginsDialog"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("group-label"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markProjectSection"))
        XCTAssertTrue(WebViewStore.focusInputScript.contains("[contenteditable]"))
        XCTAssertTrue(WebViewStore.focusInputScript.contains("attempt(tries"))
        XCTAssertTrue(WebViewStore.openPluginsScript.contains("Plugins"))
        XCTAssertTrue(WebViewStore.openPluginsScript.contains("already-open"))
        XCTAssertTrue(WebViewStore.openPluginsScript.contains("New Connector"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-imagine"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-shell-inset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-imagine-inset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("#grok-content-area[data-grock-imagine-inset=\"shift\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("#grok-content-area[data-grock-imagine-inset=\"pad\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("calc(100dvh - var(--grock-titlebar))!important"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-imagine-vh"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function markImagineViewportHeights"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function restoreImagineShellInline"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(".h-dvh,"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("top:var(--grock-titlebar)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-content-inset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-home-inset"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isCenteredHomeColumn"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("applyInsetMark"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("contentInsetCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("]::before"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("flex:0 0 var(--grock-titlebar)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("composerBackdropCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("chat-input-backdrop"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("background-color:transparent!important"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("removeAttribute('data-grock-pad-base')"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("CONTENT_PAD_BASE"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("setAttribute('data-grock-pad-base'"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("calc("))
        XCTAssertFalse(WebViewStore.chromeScript.contains("main#grok-content-area,div[data-sidebar"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("titlebarFadeCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("grock-titlebar-fade"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("ensureTitlebarFade"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("linear-gradient"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("position:absolute"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("position === 'static'"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("left:16rem"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("position:fixed;top:0"))
        XCTAssertEqual(Int(PanelGeometry.titlebarFadeExtra), 28)
        XCTAssertTrue(WebViewStore.chromeScript.contains("+ 28px"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markPageTopBar"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function findLoggedOutSignIn"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function markLoggedOutHeaderChrome"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function shouldHidePageTopBar"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("var hideBar = shouldHidePageTopBar(root)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (!full || !hideBar) return"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("pageHeaderCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("el.textContent !== css"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("paint(false)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("paintTimer"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(", 200)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("addedNodes"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("from-surface-base"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(".absolute.top-0.z-10.h-16"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(".absolute.top-0.z-10.h-14"))
        XCTAssertTrue(WebViewStore.chromeScript.contains(".absolute.inset-x-0.top-0.z-10"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("artifactStickyCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("html:not([data-grock-imagine-path])"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("html[data-grock-page-header-hidden] #grok-content-area .sticky.top-0.z-10"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("html[data-grock-page-header-hidden] #grok-content-area .sticky.top-0.h-14"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (c.offsetHeight < 8) continue;"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("if (el.offsetHeight < 8) return false;"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("dumpLayout"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("set: apply"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("dumpLayout: dumpLayout"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("session: sessionSnapshot"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("clickSession: clickSession"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("inspectSessionMenu: inspectSessionMenu"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("z-index:100"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("z-index:40"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-page-header-hidden"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("document.getElementById('grok-app-root')"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("#grok-app-root>:not(#grok-content-area)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[style*=\"--sidebar-width\"]"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("--sidebar-width:0px"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("--sidebar-width:3rem"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("lockSidebar"))
        XCTAssertTrue(WebViewStore.toggleSearchScript.contains("Search"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function markPromos"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function markGrokBotPromo"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("looksLikePromoToast"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("composerUpsellCard"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("forbiddenPromoText"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isProtectedPromoHost"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("Never click Dismiss"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markPromos();"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("function promoHideCSS"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("mt-2.px-2.cursor-pointer:has(button)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("fixed.z-50:has(button[aria-label=\"Dismiss\"])"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("requestAnimationFrame(refreshChromeFrame)"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("[role=\"dialog\"], [role=\"alertdialog\"]"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("function dismissPromo"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("clickDismiss"))
        XCTAssertTrue(WebViewStore.toggleSearchScript.contains("closed"))
        XCTAssertTrue(WebViewStore.openSearchScript.contains("already-open"))
        XCTAssertEqual(TitleDestination.history.href, "/history")
        XCTAssertEqual(TitleDestination.library.href, "/library")
        XCTAssertEqual(TitleDestination.library.title, "Library")
        XCTAssertNil(TitleDestination.plugins.href)
        XCTAssertEqual(TitleDestination.plugins.title, "Plugins")
        XCTAssertNil(TitleDestination.projects.href)
        XCTAssertEqual(TitleDestination.imagine.href, "/imagine")
        XCTAssertTrue(WebViewStore.openAllProjectsScript.contains("All projects"))
        XCTAssertTrue(WebViewStore.openAllProjectsScript.contains("clicked"))
        XCTAssertTrue(WebViewStore.openAllProjectsScript.contains("missing"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("['Chat', 'Imagine', 'Library', 'Automations']"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("['New Chat', 'History', 'Search']"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("historyProbeCSS"))
        XCTAssertFalse(WebViewStore.chromeScript.contains("data-grock-history-probe"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("chaseContentInset"))
        let clickImagine = WebViewStore.clickSidebarItemScript(label: "Imagine", href: "/imagine")
        XCTAssertTrue(clickImagine.contains("Imagine"))
        XCTAssertTrue(clickImagine.contains("/imagine"))
        XCTAssertTrue(clickImagine.contains("clicked"))
        XCTAssertTrue(clickImagine.contains("navigated"))
        let clickHistory = WebViewStore.clickSidebarItemScript(label: "History", href: nil)
        XCTAssertTrue(clickHistory.contains("History"))
        XCTAssertTrue(clickHistory.contains("href = null"))
        XCTAssertTrue(WebViewStore.privateChatScript.contains("Private"))
        XCTAssertTrue(WebViewStore.privateChatScript.contains("already-private"))
        XCTAssertTrue(WebViewStore.privateChatScript.contains("new-private"))
        XCTAssertTrue(WebViewStore.privateChatScript.contains("Create New Chat"))
        XCTAssertFalse(WebViewStore.privateChatScript.contains("label === 'Chat'"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("Imagine"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("Library"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("/library"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("/files"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("return 'Grok'"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("privacy preference"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("onetrust"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("conversationKey"))
        XCTAssertTrue(WebViewStore.placeTitleScript.contains("/c/"))
        XCTAssertFalse(WebViewStore.placeTitleScript.contains("h1, h2"))
        XCTAssertFalse(WebViewStore.placeTitleScript.contains("querySelectorAll('h1"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("markSessionCluster"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-session-cluster"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-session-more"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-session-share"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-session-panel"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("data-grock-picking-menu"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("clickSession"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("inspectSessionMenu"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("session: sessionSnapshot"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("isConversationPath"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("delete chat"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("handlers.grockSession"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("authenticationStateFromDom"))
        XCTAssertTrue(WebViewStore.chromeScript.contains("authenticated: authenticationStateFromDom()"))
        XCTAssertEqual(SessionActionsBridge.channelName, "grockSession")
    }

    @MainActor
    func testPlaceTitleUsesSidebarConversationNotReplyHeading() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Grok</title></head>
        <body>
          <div data-sidebar="sidebar" style="display:none">
            <a href="/c/abc">Fastest Native macOS UI Prototyping</a>
            <a href="/c/other">Chat on 8/27/2026</a>
          </div>
          <main id="grok-content-area">
            <h2>Fastest: Keynote (start today)</h2>
            <h2>What I would actually do</h2>
          </main>
        </body>
        </html>
        """
        let title = try await evaluatePlaceTitle(
            html: html,
            url: "https://grok.com/c/abc"
        )
        XCTAssertEqual(title, "Fastest Native macOS UI Prototyping")
    }

    @MainActor
    func testPlaceTitleIgnoresReplyHeadingWhenDocumentTitleIsTheThread() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Fastest Native macOS UI Prototyping | Grok</title></head>
        <body>
          <main id="grok-content-area">
            <h2>Fastest: Keynote (start today)</h2>
          </main>
        </body>
        </html>
        """
        let title = try await evaluatePlaceTitle(
            html: html,
            url: "https://grok.com/c/abc"
        )
        XCTAssertEqual(title, "Fastest Native macOS UI Prototyping | Grok")
    }

    @MainActor
    func testPanelUsesActivatingSystemTitlebar() {
        let panel = FloatingPanel()
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .normal)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.toolbarStyle, .unified)
        XCTAssertNotNil(panel.toolbar)
        XCTAssertEqual(panel.toolbar?.displayMode, .iconOnly)
        XCTAssertEqual(panel.toolbar?.showsBaselineSeparator, false)
        XCTAssertNil(panel.toolbar?.centeredItemIdentifier)
        let ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertTrue(ids.contains(.grockSearch))
        XCTAssertTrue(ids.contains(.grockTitle))
        XCTAssertTrue(ids.contains(.grockNewChat))
        XCTAssertTrue(ids.contains(.grockPrivate))
        XCTAssertTrue(ids.contains(.flexibleSpace))
        XCTAssertEqual(ids.last, .grockSearch)
        if let titleIndex = ids.firstIndex(of: .grockTitle),
           let spaceIndex = ids.firstIndex(of: .flexibleSpace) {
            XCTAssertEqual(spaceIndex, titleIndex + 1)
        }
        if let newChatIndex = ids.firstIndex(of: .grockNewChat),
           let privateIndex = ids.firstIndex(of: .grockPrivate),
           let searchIndex = ids.firstIndex(of: .grockSearch) {
            XCTAssertEqual(privateIndex, newChatIndex + 1)
            XCTAssertEqual(searchIndex, privateIndex + 1)
        }
        if ChromePreference.current.sidebarHidden {
            if let sidebarIndex = ids.firstIndex(of: .grockSidebar),
               let titleIndex = ids.firstIndex(of: .grockTitle) {
                XCTAssertEqual(titleIndex, sidebarIndex + 1)
            }
        }
        XCTAssertEqual(panel.toolbar?.items.first { $0.itemIdentifier == .grockSearch }?.isNavigational, false)
        if ChromePreference.current.sidebarHidden {
            XCTAssertTrue(ids.contains(.grockSidebar))
            XCTAssertEqual(panel.toolbar?.items.first { $0.itemIdentifier == .grockSidebar }?.isNavigational, true)
            XCTAssertEqual(
                panel.toolbar?.items.first { $0.itemIdentifier == .grockSidebar }?.toolTip,
                "Show Sidebar"
            )
        }
        XCTAssertEqual(
            panel.toolbar?.items.first { $0.itemIdentifier == .grockNewChat }?.toolTip,
            "New Chat"
        )
        XCTAssertEqual(
            panel.toolbar?.items.first { $0.itemIdentifier == .grockPrivate }?.toolTip,
            "New Private Chat"
        )
        XCTAssertEqual(
            panel.toolbar?.items.first { $0.itemIdentifier == .grockSearch }?.toolTip,
            "Search"
        )
        XCTAssertTrue(
            panel.toolbar?.items.first { $0.itemIdentifier == .grockSearch } is NSToolbarItemGroup
        )
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertEqual(panel.animationBehavior, .none)
        XCTAssertEqual(panel.title, "Grok")
        let titleItem = panel.toolbar?.items.first { $0.itemIdentifier == .grockTitle }
        XCTAssertFalse(titleItem is NSToolbarItemGroup)
        if ChromePreference.current.sidebarHidden {
            let menuItem = titleItem as? NSMenuToolbarItem
            XCTAssertNotNil(menuItem)
            XCTAssertEqual(menuItem?.title, "Grok")
            XCTAssertEqual(menuItem?.showsIndicator, true)
            XCTAssertEqual(menuItem?.isBordered, true)
            XCTAssertNotNil(menuItem?.action)
            XCTAssertEqual(
                menuItem?.toolTip,
                "Grok\nCopy Link. Option-click opens in your browser."
            )
        } else {
            XCTAssertFalse(titleItem is NSMenuToolbarItem)
            XCTAssertEqual(titleItem?.isBordered, false)
            XCTAssertTrue(titleItem?.view is TitleLabelField)
            XCTAssertEqual(titleItem?.toolTip, "Grok")
            XCTAssertEqual((titleItem?.view as? TitleLabelField)?.toolTip, "Grok")
        }
    }

    func testTitleDestinationsFollowAppearanceHides() {
        let pref = ChromePreference.Snapshot(
            collapseSidebar: true,
            sidebarHidden: true,
            hideImagine: true,
            hideLibrary: true,
            hideAutomations: false,
            hideProjects: false,
            hidePlugins: true,
            hideGrokBot: true,
            hidePrivate: true,
            hideDictation: false,
            hideVoice: true
        )
        let titles = TitleDestination.available(in: pref).map(\.title)
        XCTAssertEqual(
            titles,
            ["New Chat", "Automations", "Projects", "History"]
        )
        XCTAssertFalse(titles.contains("Search"))
        XCTAssertFalse(titles.contains("Imagine"))
        XCTAssertFalse(titles.contains("Library"))
        XCTAssertFalse(titles.contains("Plugins"))
        XCTAssertFalse(titles.contains("Skills and Connectors"))
        XCTAssertFalse(titles.contains("New Generation"))
        XCTAssertFalse(titles.contains("Add Project"))

        let shownWithImagine = TitleDestination.available(in: ChromePreference.Snapshot(
            collapseSidebar: true,
            sidebarHidden: true,
            hideImagine: false,
            hideLibrary: false,
            hideAutomations: false,
            hideProjects: false,
            hidePlugins: false,
            hideGrokBot: true,
            hidePrivate: true,
            hideDictation: false,
            hideVoice: false
        )).map(\.title)
        XCTAssertTrue(shownWithImagine.contains("Imagine"))
        XCTAssertTrue(shownWithImagine.contains("New Chat"))
        XCTAssertTrue(shownWithImagine.contains("Library"))
        XCTAssertTrue(shownWithImagine.contains("Plugins"))
        XCTAssertFalse(shownWithImagine.contains("New Generation"))

        let menu = NSMenu()
        TitleDestination.rebuildMenu(
            menu,
            pref: pref,
            target: NSObject(),
            action: #selector(NSObject.description)
        )
        let shown = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(shown.first, "New Chat")
        XCTAssertEqual(shown, ["New Chat", "Automations", "Projects", "History"])
        XCTAssertTrue(menu.items.contains(where: \.isSeparatorItem))
        XCTAssertFalse(shown.contains("Plugins"))

        let pluginsMenu = NSMenu()
        TitleDestination.rebuildMenu(
            pluginsMenu,
            pref: ChromePreference.Snapshot(
                collapseSidebar: true,
                sidebarHidden: true,
                hideImagine: false,
                hideLibrary: false,
                hideAutomations: false,
                hideProjects: false,
                hidePlugins: false,
                hideGrokBot: true,
                hidePrivate: true,
                hideDictation: false,
                hideVoice: false
            ),
            target: NSObject(),
            action: #selector(NSObject.description)
        )
        let pluginsShown = pluginsMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(
            pluginsShown,
            ["New Chat", "Imagine", "Library", "Automations", "Projects", "History", "Plugins"]
        )
        XCTAssertEqual(pluginsShown.last, "Plugins")
        let imagineIndex = pluginsMenu.items.firstIndex { $0.title == "Imagine" }
        let libraryIndex = pluginsMenu.items.firstIndex { $0.title == "Library" }
        let automationsIndex = pluginsMenu.items.firstIndex { $0.title == "Automations" }
        XCTAssertNotNil(imagineIndex)
        XCTAssertNotNil(libraryIndex)
        XCTAssertNotNil(automationsIndex)
        if let imagineIndex, let libraryIndex, let automationsIndex {
            XCTAssertEqual(libraryIndex, imagineIndex + 1)
            XCTAssertEqual(automationsIndex, libraryIndex + 1)
        }
        let pluginIndex = pluginsMenu.items.firstIndex { $0.title == "Plugins" }
        let historyIndex = pluginsMenu.items.firstIndex { $0.title == "History" }
        let projectsIndex = pluginsMenu.items.firstIndex { $0.title == "Projects" }
        XCTAssertNotNil(pluginIndex)
        XCTAssertNotNil(historyIndex)
        XCTAssertNotNil(projectsIndex)
        if let pluginIndex, let historyIndex {
            XCTAssertGreaterThan(pluginIndex, historyIndex)
            XCTAssertTrue(pluginsMenu.items[pluginIndex - 1].isSeparatorItem)
        }
        if let projectsIndex, let historyIndex {
            XCTAssertGreaterThan(historyIndex, projectsIndex)
            XCTAssertTrue(pluginsMenu.items[historyIndex - 1].isSeparatorItem)
        }
        XCTAssertFalse(pluginsShown.contains("New Generation"))
        XCTAssertFalse(pluginsShown.contains("Add Project"))
    }

    func testGrockWebAppFollowsImagineURL() {
        XCTAssertEqual(GrockWebApp.from(url: nil), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/c/abc")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/automations")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/files")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/library")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/skills-and-connectors")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/project")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/history")), .chat)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/imagine")), .imagine)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/imagine/saved")), .imagine)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/imagine/agent")), .imagine)
        XCTAssertEqual(GrockWebApp.from(url: URL(string: "https://grok.com/imagine/post/1")), .imagine)
        XCTAssertTrue(GrockWebApp.isImaginePath("/imagine"))
        XCTAssertTrue(GrockWebApp.isImaginePath("/imagine/saved"))
        XCTAssertTrue(GrockWebApp.isImaginePath("/imagine/agent"))
        XCTAssertFalse(GrockWebApp.isImaginePath("/images"))
        XCTAssertFalse(GrockWebApp.isImaginePath("/c/abc"))
    }

    @MainActor
    func testHideImagineDropsImagineFromTitleMenuNotToolbar() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        let defaults = UserDefaults.standard
        let prior = defaults.object(forKey: ChromePreference.hideImagineKey)
        let previousHidden = ChromePreference.current.sidebarHidden
        defer {
            if let prior {
                defaults.set(prior, forKey: ChromePreference.hideImagineKey)
            } else {
                defaults.removeObject(forKey: ChromePreference.hideImagineKey)
            }
            ChromePreference.setSidebarHidden(previousHidden)
            panel.syncToolbar()
        }
        ChromePreference.setSidebarHidden(true)
        defaults.set(false, forKey: ChromePreference.hideImagineKey)
        panel.syncToolbar()
        let shown = TitleDestination.available(in: ChromePreference.current).map(\.title)
        XCTAssertTrue(shown.contains("Imagine"))
        XCTAssertTrue(panel.toolbar?.items.contains { $0.itemIdentifier == .grockNewChat } == true)
        XCTAssertTrue(panel.toolbar?.items.contains { $0.itemIdentifier == .grockPrivate } == true)

        defaults.set(true, forKey: ChromePreference.hideImagineKey)
        panel.syncToolbar()
        let hidden = TitleDestination.available(in: ChromePreference.current).map(\.title)
        XCTAssertFalse(hidden.contains("Imagine"))
        XCTAssertTrue(panel.toolbar?.items.contains { $0.itemIdentifier == .grockNewChat } == true)
        XCTAssertTrue(panel.toolbar?.items.contains { $0.itemIdentifier == .grockPrivate } == true)
        if ChromePreference.current.sidebarHidden {
            XCTAssertFalse(panel.toolbar?.items.contains { $0.itemIdentifier == .grockRailIndent } == true)
        }
    }

    @MainActor
    func testTitleParksAfterRailWhenSidebarOpen() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        panel.setFrame(NSRect(x: 80, y: 80, width: 920, height: 680), display: false)
        let previousHidden = ChromePreference.current.sidebarHidden
        defer {
            ChromePreference.setSidebarHidden(previousHidden)
            panel.syncToolbar()
        }
        ChromePreference.setSidebarHidden(false)
        panel.syncToolbar()
        let openIds = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertTrue(openIds.contains(.grockRailIndent))
        XCTAssertNil(openIds.firstIndex(of: .grockSidebar))
        if let indent = openIds.firstIndex(of: .grockRailIndent),
           let title = openIds.firstIndex(of: .grockTitle) {
            XCTAssertEqual(title, indent + 1)
        }
        XCTAssertTrue(openIds.contains(.grockNewChat))
        XCTAssertTrue(openIds.contains(.grockPrivate))
        XCTAssertEqual(openIds.last, .grockSearch)
        let indentView = panel.toolbar?.items.first { $0.itemIdentifier == .grockRailIndent }?.view as? ToolbarRailIndentView
        XCTAssertGreaterThan(indentView?.width ?? 0, 40)
        XCTAssertLessThan(indentView?.width ?? 999, PanelGeometry.grokSidebarWidth)

        ChromePreference.setSidebarHidden(true)
        panel.syncToolbar()
        let closedIds = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertFalse(closedIds.contains(.grockRailIndent))
        XCTAssertTrue(closedIds.contains(.grockSidebar))
        XCTAssertTrue(closedIds.contains(.grockNewChat))
        XCTAssertTrue(closedIds.contains(.grockPrivate))
        if let sidebar = closedIds.firstIndex(of: .grockSidebar),
           let title = closedIds.firstIndex(of: .grockTitle) {
            XCTAssertEqual(title, sidebar + 1)
        }
    }

    @MainActor
    func testTitleSitsLeadingNotCentered() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        XCTAssertNil(panel.toolbar?.centeredItemIdentifier)

        let previousHidden = ChromePreference.current.sidebarHidden
        defer {
            ChromePreference.setSidebarHidden(previousHidden)
            panel.syncToolbar()
        }

        ChromePreference.setSidebarHidden(true)
        panel.syncToolbar()
        var ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertEqual(ids.first, .grockSidebar)
        XCTAssertFalse(ids.contains(.grockRailIndent))
        if let sidebar = ids.firstIndex(of: .grockSidebar),
           let title = ids.firstIndex(of: .grockTitle),
           let space = ids.firstIndex(of: .flexibleSpace) {
            XCTAssertEqual(title, sidebar + 1)
            XCTAssertEqual(space, title + 1)
        } else {
            XCTFail("closed sidebar should be Sidebar, title, then space")
        }
        XCTAssertTrue(ids.contains(.grockNewChat))
        XCTAssertTrue(ids.contains(.grockPrivate))
        XCTAssertEqual(ids.last, .grockSearch)

        ChromePreference.setSidebarHidden(false)
        panel.syncToolbar()
        ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertEqual(ids.first, .grockRailIndent)
        if let indent = ids.firstIndex(of: .grockRailIndent),
           let title = ids.firstIndex(of: .grockTitle) {
            XCTAssertEqual(title, indent + 1)
        } else {
            XCTFail("open sidebar should be indent then title")
        }
        XCTAssertTrue(ids.contains(.grockNewChat))
        XCTAssertTrue(ids.contains(.grockPrivate))
        XCTAssertEqual(ids.last, .grockSearch)
    }

    @MainActor
    func testSessionActionsToolbarSitsLeftOfNewChat() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        let previous = WebViewStore.shared.sessionActions
        defer {
            WebViewStore.shared.applySessionActions(previous)
            panel.syncToolbar()
        }

        WebViewStore.shared.applySessionActions(SessionActions())
        panel.syncToolbar()
        var ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertFalse(ids.contains(.grockSessionMore))
        XCTAssertEqual(ids.last, .grockSearch)

        WebViewStore.shared.applySessionActions(SessionActions(more: true, share: true, panel: true))
        panel.syncToolbar()
        ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        if let more = ids.firstIndex(of: .grockSessionMore),
           let share = ids.firstIndex(of: .grockSessionShare),
           let gap = ids.firstIndex(of: .space),
           let newChat = ids.firstIndex(of: .grockNewChat),
           let privateChat = ids.firstIndex(of: .grockPrivate) {
            XCTAssertEqual(share, more + 1)
            XCTAssertEqual(gap, share + 1)
            XCTAssertEqual(newChat, gap + 1)
            XCTAssertEqual(privateChat, newChat + 1)
        } else {
            XCTFail("More / Share should sit immediately left of New Chat")
        }
        XCTAssertEqual(ids.last, .grockSearch)
        let sessionItems = panel.toolbar?.items.filter {
            [.grockSessionMore, .grockSessionShare].contains($0.itemIdentifier)
        } ?? []
        XCTAssertEqual(sessionItems.map(\.toolTip), ["More", "Share"])
        XCTAssertEqual(sessionItems.map(\.isEnabled), [true, true])
        for item in sessionItems {
            XCTAssertFalse(item is NSToolbarItemGroup)
            XCTAssertTrue(item.isBordered)
            XCTAssertFalse(item.autovalidates)
            XCTAssertTrue(item.target === panel)
            XCTAssertNotNil(item.action)
        }
        XCTAssertNotEqual(sessionItems.first?.action, sessionItems.last?.action)
        panel.sessionPinned = false
        panel.rebuildSessionMoreMenu()
        XCTAssertEqual(
            panel.sessionMoreMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Pin", "Toggle Right Panel", "Delete Chat"]
        )
        panel.sessionPinned = true
        panel.rebuildSessionMoreMenu()
        XCTAssertEqual(
            panel.sessionMoreMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Unpin", "Toggle Right Panel", "Delete Chat"]
        )

        WebViewStore.shared.applySessionActions(SessionActions(more: true, share: false, panel: true))
        panel.syncToolbar()
        XCTAssertEqual(sessionItems.map(\.isEnabled), [true, false])

        WebViewStore.shared.applySessionActions(SessionActions())
        panel.syncToolbar()
        ids = panel.toolbar?.items.map(\.itemIdentifier) ?? []
        XCTAssertFalse(ids.contains(.grockSessionMore))
        XCTAssertFalse(ids.contains(.grockSessionShare))
        XCTAssertFalse(ids.contains(.space))
    }

    @MainActor
    func testSessionMenuStartsBelowItsToolbarButton() {
        let bounds = NSRect(x: 2, y: 3, width: 32, height: 32)
        let normal = FloatingPanel.sessionMenuOrigin(bounds: bounds, flipped: false)
        XCTAssertEqual(normal.x, bounds.minX)
        XCTAssertLessThan(normal.y, bounds.minY)
        let flipped = FloatingPanel.sessionMenuOrigin(bounds: bounds, flipped: true)
        XCTAssertEqual(flipped.x, bounds.minX)
        XCTAssertGreaterThan(flipped.y, bounds.maxY)
    }

    func testSessionActionsParseAndToolbarFlags() {
        let empty = SessionActions.from([:])
        XCTAssertFalse(empty.showsToolbar)
        XCTAssertFalse(empty.showsMore)
        let all = SessionActions.from(["more": true, "share": true, "panel": true])
        XCTAssertTrue(all.showsToolbar)
        XCTAssertTrue(all.showsMore)
        let panelOnly = SessionActions.from(["panel": true])
        XCTAssertTrue(panelOnly.showsToolbar)
        XCTAssertTrue(panelOnly.showsMore)
        XCTAssertFalse(panelOnly.share)
        let shareOnly = SessionActions(more: false, share: true, panel: false)
        XCTAssertTrue(shareOnly.showsToolbar)
        XCTAssertFalse(shareOnly.showsMore)
    }

    @MainActor
    func testAuthenticatedToolbarItemsUseNativeDisabledState() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        let previousSignedIn = WebViewStore.shared.isSignedIn
        let previousSidebarHidden = ChromePreference.current.sidebarHidden
        defer {
            WebViewStore.shared.applySignedInState(previousSignedIn)
            ChromePreference.setSidebarHidden(previousSidebarHidden)
            panel.syncToolbar()
        }

        ChromePreference.setSidebarHidden(true)
        WebViewStore.shared.applySignedInState(false)
        panel.syncToolbar()

        let protected: Set<NSToolbarItem.Identifier> = [
            .grockSidebar, .grockNewChat, .grockPrivate, .grockSearch
        ]
        let disabledItems = panel.toolbar?.items.filter {
            protected.contains($0.itemIdentifier)
        } ?? []
        XCTAssertEqual(Set(disabledItems.map(\.itemIdentifier)), protected)
        XCTAssertTrue(disabledItems.allSatisfy { !$0.isEnabled })
        let search = disabledItems.first { $0.itemIdentifier == .grockSearch } as? NSToolbarItemGroup
        XCTAssertEqual(search?.subitems.map(\.isEnabled), [false])

        WebViewStore.shared.applySignedInState(true)
        panel.syncToolbar()
        XCTAssertTrue(disabledItems.allSatisfy(\.isEnabled))
        XCTAssertEqual(search?.subitems.map(\.isEnabled), [true])

        ChromePreference.setSidebarHidden(false)
        WebViewStore.shared.applySignedInState(false)
        panel.syncToolbar()
        let railButton = panel.contentView?.subviews.compactMap { $0 as? SidebarRailButton }.first
        XCTAssertEqual(railButton?.isEnabled, false)
    }

    @MainActor
    func testPanelInstallsSharedWebView() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        XCTAssertTrue(WebViewStore.shared.webView.isDescendant(of: panel.contentView ?? NSView()))
        XCTAssertFalse(panel.contentView === WebViewStore.shared.webView)
        XCTAssertTrue(
            (panel.contentView?.subviews.contains { $0 is SidebarRailButton }) == true
        )
    }

    @MainActor
    func testPanelInsetsAuthViewportAndRestoresGrokLayout() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(
            WKUserScript(source: WebViewStore.edgeFixScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: WebViewStore.chromeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        let panel = FloatingPanel()
        defer { panel.orderOut(nil) }

        // Load before installation too: rehosting an existing account page
        // must receive the same inset as navigating to it in an open panel.
        for (index, address) in [
            "https://accounts.x.ai/sign-in",
            "https://grok.com/",
            "https://auth.x.ai/continue",
            "https://appleid.apple.com/auth/authorize",
            "https://grok.com/c/fixture"
        ].enumerated() {
            let loaded = expectation(description: "panel-viewport-\(index)")
            let loader = PlaceTitleHTMLLoader(expectation: loaded)
            webView.navigationDelegate = loader
            webView.loadHTMLString("""
                <html><body style="margin:0">
                  <main style="height:900px">Sign in</main>
                  <header id="header" style="position:fixed;top:0;height:56px">Account</header>
                  <footer id="footer" style="position:fixed;bottom:0;height:30px">Terms</footer>
                </body></html>
                """, baseURL: URL(string: address))
            await fulfillment(of: [loaded], timeout: 4)
            if index == 0 { panel.installWebView(webView) }
            await Task.yield()

            for size in [PanelGeometry.defaultContentSize, PanelGeometry.minContentSize] {
                panel.setFrame(NSRect(origin: .zero, size: size), display: false)
                let host = try XCTUnwrap(panel.contentView)
                host.layoutSubtreeIfNeeded()
                let isAuth = !address.contains("https://grok.com/")
                let inset = isAuth ? PanelGeometry.titlebarInset(in: panel) : 0
                XCTAssertEqual(host.bounds.maxY - webView.frame.maxY, inset, accuracy: 0.5, address)
                XCTAssertEqual(webView.frame.minY, host.bounds.minY, accuracy: 0.5, address)
                XCTAssertEqual(webView.frame.width, host.bounds.width, accuracy: 0.5, address)

                let layout = try await callSessionJavaScript(webView, """
                    // AppKit lays out synchronously; WebKit receives the new viewport asynchronously.
                    var deadline = performance.now() + 1000;
                    while (Math.abs(innerHeight - \(webView.bounds.height)) > 1 && performance.now() < deadline) {
                      await new Promise(resolve => setTimeout(resolve, 10));
                    }
                    return {
                      height: innerHeight,
                      headerTop: document.getElementById('header').getBoundingClientRect().top,
                      footerBottom: document.getElementById('footer').getBoundingClientRect().bottom,
                      chrome: !!window.__grockChrome,
                      edgeFix: !!window.__grockEdgeFix,
                      overflow: getComputedStyle(document.documentElement).overflowY
                    };
                    """) as? [String: Any]
                XCTAssertEqual(try XCTUnwrap(layout?["headerTop"] as? Double), 0, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(layout?["height"] as? Double), webView.bounds.height, accuracy: 1)
                XCTAssertEqual(try XCTUnwrap(layout?["footerBottom"] as? Double), webView.bounds.height, accuracy: 1)
                XCTAssertEqual(layout?["chrome"] as? Bool, !isAuth)
                XCTAssertEqual(layout?["edgeFix"] as? Bool, !isAuth)
                if isAuth { XCTAssertNotEqual(layout?["overflow"] as? String, "hidden") }
            }
        }
    }

    @MainActor
    func testTitlebarEmptySpaceDragsWindow() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        panel.setFrame(NSRect(x: 80, y: 80, width: 920, height: 680), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let host = panel.contentView else {
            return XCTFail("missing host content view")
        }

        guard let drag = host.subviews.first(where: { $0 is TitlebarDragRegion }) else {
            return XCTFail("missing titlebar drag region")
        }
        XCTAssertGreaterThan(drag.bounds.width, 100)
        XCTAssertGreaterThan(drag.bounds.height, 8)
        var local = NSPoint(x: drag.bounds.midX, y: drag.bounds.midY)
        for control in host.subviews where control is SidebarRailButton || control is NSButton {
            let frame = drag.convert(control.bounds, from: control)
            if frame.contains(local) { local.x = frame.maxX + 24 }
        }
        let topHit = host.hitTest(host.convert(local, from: drag))
        XCTAssertTrue(topHit is TitlebarDragRegion)
        XCTAssertTrue(topHit?.mouseDownCanMoveWindow ?? false)
        XCTAssertFalse(topHit === WebViewStore.shared.webView)

        let bodyLocal = NSPoint(x: host.bounds.midX, y: host.bounds.maxY - 90)
        let bodyHit = host.hitTest(host.convert(bodyLocal, to: host.superview))
        XCTAssertFalse(bodyHit is TitlebarDragRegion)
        let inset = PanelGeometry.titlebarInset(in: panel)
        XCTAssertGreaterThan(inset, 8)
        XCTAssertLessThan(inset, 120)
    }

    @MainActor
    func testTitleGroupUsesMailStyleChevronMenu() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        let previous = ChromePreference.current.sidebarHidden
        ChromePreference.setSidebarHidden(true)
        panel.syncToolbar()
        let item = panel.toolbar?.items.first { $0.itemIdentifier == .grockTitle } as? NSMenuToolbarItem
        XCTAssertNotNil(item)
        XCTAssertNotNil(item?.menu)
        item?.menu.delegate?.menuNeedsUpdate?(item?.menu ?? NSMenu())
        let shown = (item?.menu.items ?? []).filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(shown.first, "New Chat")
        XCTAssertTrue(shown.contains("History"))
        XCTAssertFalse(shown.contains("Search"))
        if !ChromePreference.current.hideImagine {
            XCTAssertTrue(shown.contains("Imagine"))
        }
        XCTAssertFalse(shown.contains("New Generation"))
        XCTAssertEqual(item?.title, "Grok")
        XCTAssertEqual(item?.showsIndicator, true)
        XCTAssertNotNil(item?.action)
        XCTAssertEqual(
            item?.toolTip,
            "Grok\nCopy Link. Option-click opens in your browser."
        )
        XCTAssertEqual(
            panel.toolbar?.items.first { $0.itemIdentifier == .grockSidebar }?.toolTip,
            "Show Sidebar"
        )

        ChromePreference.setSidebarHidden(false)
        panel.syncToolbar()
        let label = panel.toolbar?.items.first { $0.itemIdentifier == .grockTitle }
        XCTAssertFalse(label is NSMenuToolbarItem)
        XCTAssertEqual(label?.isBordered, false)
        let field = label?.view as? TitleLabelField
        XCTAssertNotNil(field)
        XCTAssertEqual(field?.stringValue, "Grok")
        XCTAssertEqual(field?.font, TitleLabelField.titleFont)
        XCTAssertEqual(TitleLabelField.leadingPadding, PanelGeometry.appSwitchRailGap)
        XCTAssertGreaterThan(
            field?.intrinsicContentSize.width ?? 0,
            ("Grok" as NSString).size(withAttributes: [.font: TitleLabelField.titleFont]).width
        )
        XCTAssertEqual(label?.toolTip, "Grok")
        XCTAssertEqual(field?.toolTip, "Grok")
        let rail = panel.contentView?.subviews.compactMap { $0 as? SidebarRailButton }.first
        XCTAssertEqual(rail?.toolTip, "Hide Sidebar")
        XCTAssertNil(panel.toolbar?.items.first { $0.itemIdentifier == .grockSidebar })
        XCTAssertNotNil(panel.toolbar?.items.first { $0.itemIdentifier == .grockRailIndent })
        XCTAssertNotNil(panel.toolbar?.items.first { $0.itemIdentifier == .grockNewChat })
        XCTAssertNotNil(panel.toolbar?.items.first { $0.itemIdentifier == .grockPrivate })

        ChromePreference.setSidebarHidden(previous)
        panel.syncToolbar()
    }

    @MainActor
    func testConfirmCopiedLinkFlashesTitle() {
        let previous = ChromePreference.current.sidebarHidden
        ChromePreference.setSidebarHidden(true)
        let panel = FloatingPanel()
        panel.confirmCopiedLink()
        let item = panel.toolbar?.items.first { $0.itemIdentifier == .grockTitle } as? NSMenuToolbarItem
        XCTAssertEqual(item?.title, "URL Copied")
        ChromePreference.setSidebarHidden(previous)
    }

    @MainActor
    func testSettingsHasToolbarPanes() {
        let tabs = SettingsTabController.make()
        XCTAssertEqual(tabs.tabStyle, .toolbar)
        XCTAssertEqual(
            tabs.tabViewItems.map(\.label),
            ["General", "Appearance", "Account", "Advanced"]
        )
        XCTAssertEqual(
            tabs.tabViewItems.map { $0.viewController?.title },
            ["General", "Appearance", "Account", "Advanced"]
        )
        XCTAssertTrue(tabs.select(.appearance))
        XCTAssertEqual(tabs.tabViewItems[tabs.selectedTabViewItemIndex].label, "Appearance")
        XCTAssertEqual(SettingsPane.notificationKey, "pane")
    }

    func testWebInspectorDefaultsOff() {
        XCTAssertEqual(WebViewStore.webInspectorKey, "app.webInspector")
    }

    func testLaunchLoadingBeadStartsAtTop() {
        let p = LaunchLoadingLayout.beadCenter(at: 0)
        XCTAssertEqual(p.x, 0, accuracy: 0.0001)
        XCTAssertEqual(p.y, LaunchLoadingLayout.orbitRadius, accuracy: 0.0001)
    }

    func testLaunchLoadingBeadStaysOnRail() {
        for step in 0..<8 {
            let t = LaunchLoadingLayout.period * TimeInterval(step) / 8
            let p = LaunchLoadingLayout.beadCenter(at: t)
            XCTAssertEqual(hypot(p.x, p.y), LaunchLoadingLayout.orbitRadius, accuracy: 0.0001)
        }
        let a = LaunchLoadingLayout.beadCenter(at: 0)
        let b = LaunchLoadingLayout.beadCenter(at: LaunchLoadingLayout.period)
        XCTAssertEqual(a.x, b.x, accuracy: 0.0001)
        XCTAssertEqual(a.y, b.y, accuracy: 0.0001)
    }

    func testLaunchLoadingBeadClearsPlanet() {
        XCTAssertGreaterThan(
            LaunchLoadingLayout.orbitRadius - LaunchLoadingLayout.beadRadius,
            LaunchLoadingLayout.planetRadius + LaunchLoadingLayout.railStroke
        )
    }

    func testLaunchLoadingAngleWrapsOverPeriod() {
        XCTAssertEqual(LaunchLoadingLayout.angle(period: 10, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(LaunchLoadingLayout.angle(period: 10, at: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(LaunchLoadingLayout.angle(period: 8, at: 2), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(
            LaunchLoadingLayout.angle(period: 8, at: 2, phase: 0.5),
            .pi / 2 + 0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(LaunchLoadingLayout.period, 1.3, accuracy: 0.01)
    }

    @MainActor
    func testLaunchLoadingCoversWebViewWhileWaiting() {
        let store = WebViewStore.shared
        XCTAssertEqual(store.showsLaunchLoading, store.awaitingFirstPaint)
        if store.awaitingFirstPaint {
            XCTAssertEqual(store.webView.alphaValue, 0, accuracy: 0.01)
        }
    }

    @MainActor
    func testPanelCanShowLaunchLoading() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        panel.setLaunchLoadingVisible(true, animated: false)
        XCTAssertTrue(panel.isLaunchLoadingVisible)
        panel.setLaunchLoadingVisible(false, animated: false)
        XCTAssertFalse(panel.isLaunchLoadingVisible)
    }

    @MainActor
    func testOverlayHostDoesNotStealFileDrops() {
        let panel = FloatingPanel()
        panel.installWebView(WebViewStore.shared.webView)
        XCTAssertFalse(panel.contentView is FileDropCatcher)
    }

    func testAccountHelpExplainsGrokLogin() {
        XCTAssertTrue(AccountHelp.footer.contains("grok.com login"))
        XCTAssertTrue(AccountHelp.footer.contains("your browser"))
        XCTAssertTrue(AccountHelp.footer.contains("clear web data"))
    }

    func testInteractiveLaunchShowsWindow() {
        XCTAssertTrue(
            LaunchReason.shouldShowMainWindow(appleEvent: nil, isHidden: false)
        )
        XCTAssertTrue(
            LaunchReason.shouldShowMainWindow(
                appleEvent: Self.openApplicationEvent(loginItem: false),
                isHidden: false
            )
        )
    }

    func testLoginItemLaunchStaysInBackground() {
        XCTAssertFalse(
            LaunchReason.shouldShowMainWindow(appleEvent: nil, isHidden: true)
        )
        XCTAssertFalse(
            LaunchReason.shouldShowMainWindow(
                appleEvent: Self.openApplicationEvent(loginItem: true),
                isHidden: false
            )
        )
    }

    func testLaunchReasonReadsGetURLEvent() {
        let event = Self.getURLEvent("grock://ask?text=hi")
        XCTAssertEqual(LaunchReason.url(from: event)?.absoluteString, "grock://ask?text=hi")
        XCTAssertNil(LaunchReason.url(from: Self.openApplicationEvent(loginItem: false)))
        XCTAssertNil(LaunchReason.url(from: nil))
    }

    func testGrockURLSchemeIsRegistered() {
        let bundle = Bundle(for: AppDelegate.self)
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] } ?? []
        XCTAssertTrue(schemes.contains("grock"))
        XCTAssertFalse(schemes.contains("http"))
        XCTAssertFalse(schemes.contains("https"))
    }

    func testGrockURLParse() {
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://new")!),
            .new(text: nil, files: [])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock:///new")!),
            .new(text: nil, files: [])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://new?text=hello%20world")!),
            .new(text: "hello world", files: [])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://new?text=hi&file=/tmp/note.pdf")!),
            .new(text: "hi", files: [URL(fileURLWithPath: "/tmp/note.pdf")])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://ask?text=hello%20world")!),
            .ask(text: "hello world", files: [])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://ask?text=hello+world")!),
            .ask(text: "hello world", files: [])
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://ask?text=&file=/tmp/note.pdf")!),
            .ask(text: nil, files: [URL(fileURLWithPath: "/tmp/note.pdf")])
        )
        XCTAssertEqual(
            GrockURL.parse(
                URL(string: "grock://ask?text=hi&file=/tmp/a.pdf&file=/tmp/b.pdf")!
            ),
            .ask(
                text: "hi",
                files: [
                    URL(fileURLWithPath: "/tmp/a.pdf"),
                    URL(fileURLWithPath: "/tmp/b.pdf")
                ]
            )
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://imagine?generate=a%20red%20bike")!),
            .imagine(prompt: "a red bike")
        )
        XCTAssertEqual(
            GrockURL.parse(URL(string: "grock://imagine?text=fallback")!),
            .imagine(prompt: "fallback")
        )
        XCTAssertEqual(GrockURL.parse(URL(string: "grock://")!), .summon)
        XCTAssertEqual(GrockURL.parse(URL(string: "grock://open")!), .summon)
        XCTAssertEqual(
            GrockURL.parse(URL(string: "GROCK://NEW")!),
            .new(text: nil, files: [])
        )
        XCTAssertNil(GrockURL.parse(URL(string: "https://grok.com")!))
        XCTAssertNil(GrockURL.parse(URL(string: "file:///tmp/note.pdf")!))
    }

    func testGrockURLHrefRoundTrip() {
        XCTAssertEqual(GrockURL.summon.href()?.absoluteString, "grock://")
        XCTAssertEqual(GrockURL.parse(GrockURL.summon.href()!), .summon)

        let newText = GrockURL.new(text: "hello world", files: [])
        XCTAssertEqual(newText.href()?.absoluteString, "grock://new?text=hello%20world")
        XCTAssertEqual(GrockURL.parse(newText.href()!), newText)

        let plus = GrockURL.ask(text: "hello+world", files: [])
        XCTAssertEqual(plus.href()?.absoluteString, "grock://ask?text=hello%2Bworld")
        XCTAssertEqual(GrockURL.parse(plus.href()!), plus)

        let file = URL(fileURLWithPath: "/tmp/My File.pdf")
        let withFile = GrockURL.new(text: "hi", files: [file])
        XCTAssertEqual(GrockURL.parse(withFile.href()!), withFile)

        let imagine = GrockURL.imagine(prompt: "a red bicycle")
        XCTAssertEqual(imagine.href()?.absoluteString, "grock://imagine?generate=a%20red%20bicycle")
        XCTAssertEqual(GrockURL.parse(imagine.href()!), imagine)

        XCTAssertEqual(
            GrockURL.new(text: nil, files: []).href()?.absoluteString,
            "grock://new"
        )
    }

    func testGrockCommandParse() throws {
        XCTAssertEqual(GrockCommand.parse([]), .open(.summon))
        XCTAssertEqual(GrockCommand.parse(["open"]), .open(.summon))
        XCTAssertEqual(GrockCommand.parse(["new"]), .open(.new(text: nil, files: [])))
        XCTAssertEqual(
            GrockCommand.parse(["ask", "summarize", "this"]),
            .open(.ask(text: "summarize this", files: []))
        )
        XCTAssertEqual(
            GrockCommand.parse(["imagine", "a", "red", "bicycle"]),
            .open(.imagine(prompt: "a red bicycle"))
        )
        XCTAssertEqual(GrockCommand.parse(["help"]), .help)
        XCTAssertEqual(GrockCommand.parse(["-h"]), .help)
        XCTAssertEqual(GrockCommand.parse(["--help"]), .help)
        XCTAssertEqual(
            GrockCommand.parse(["ask"], stdin: "from stdin\n"),
            .open(.ask(text: "from stdin", files: []))
        )
        XCTAssertEqual(
            GrockCommand.parse(["ask", "args"], stdin: "ignored"),
            .open(.ask(text: "args", files: []))
        )
        XCTAssertEqual(
            GrockCommand.parse(["ask", "--", "-f", "looks-like-flag"]),
            .open(.ask(text: "-f looks-like-flag", files: []))
        )

        switch GrockCommand.parse(["ask", "--nope"]) {
        case .failure(let message):
            XCTAssertTrue(message.contains("unknown option"))
        default:
            XCTFail("expected unknown option")
        }
        switch GrockCommand.parse(["summarize", "this"]) {
        case .failure(let message):
            XCTAssertTrue(message.contains("try grock ask"))
        default:
            XCTFail("expected missing command")
        }
        switch GrockCommand.parse(["open", "hi"]) {
        case .failure(let message):
            XCTAssertTrue(message.contains("open does not take"))
        default:
            XCTFail("expected open error")
        }
        switch GrockCommand.parse(["imagine", "-f", "/tmp/x.pdf"]) {
        case .failure(let message):
            XCTAssertTrue(message.contains("imagine does not take files"))
        default:
            XCTFail("expected imagine file error")
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "grock-cli-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appendingPathComponent("notes.pdf")
        try Data("%PDF".utf8).write(to: note)

        XCTAssertEqual(
            GrockCommand.parse(["new", "-f", note.path, "summarize"]),
            .open(.new(text: "summarize", files: [note.standardizedFileURL]))
        )
        XCTAssertEqual(
            GrockCommand.parse(["ask", "--file", "notes.pdf"], cwd: dir),
            .open(.ask(text: nil, files: [note.standardizedFileURL]))
        )
        switch GrockCommand.parse(["new", "-f", dir.path]) {
        case .failure(let message):
            XCTAssertTrue(message.contains("not a file"))
        default:
            XCTFail("expected directory error")
        }
        switch GrockCommand.parse(["ask", "-f", "missing.pdf"], cwd: dir) {
        case .failure(let message):
            XCTAssertTrue(message.contains("file not found"))
        default:
            XCTFail("expected missing file")
        }
    }

    func testGrockCLIIsEmbeddedAndHelpWorks() throws {
        let cli = Bundle(for: AppDelegate.self).bundleURL
            .appendingPathComponent(GrockCLIInstaller.bundledRelativePath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: cli.path), cli.path)

        let process = Process()
        process.executableURL = cli
        process.arguments = ["help"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(output, GrockCommand.helpText)
        XCTAssertTrue(output.contains("grock ask"))
        XCTAssertTrue(output.contains("nothing sends") || output.contains("Nothing here sends"))
    }

    func testGrockCLIInstallerRecognizesOurSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "grock-cli-install-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bundled = dir.appendingPathComponent("bundled-grock")
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)

        let ours = dir.appendingPathComponent("grock")
        try FileManager.default.createSymbolicLink(atPath: ours.path, withDestinationPath: bundled.path)
        XCTAssertTrue(GrockCLIInstaller.isOurInstall(at: ours, bundled: bundled))

        let foreign = dir.appendingPathComponent("other")
        try Data("other".utf8).write(to: foreign)
        let foreignLink = dir.appendingPathComponent("foreign-grock")
        try FileManager.default.createSymbolicLink(atPath: foreignLink.path, withDestinationPath: foreign.path)
        XCTAssertFalse(GrockCLIInstaller.isOurInstall(at: foreignLink, bundled: bundled))
        XCTAssertEqual(GrockCLIInstaller.resolvedURL(ours).path, bundled.standardizedFileURL.path)
    }

    func testFileIntakePartition() {
        let grock = URL(string: "grock://ask?text=hi")!
        let file = URL(fileURLWithPath: "/tmp/note.pdf")
        let https = URL(string: "https://grok.com")!
        let split = FileIntake.partition([grock, file, https])
        XCTAssertEqual(split.commands, [.ask(text: "hi", files: [])])
        XCTAssertEqual(split.files, [file])
    }

    func testFileIntakeSkipsDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "grock-intake-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.pdf")
        try Data("%PDF".utf8).write(to: file)
        XCTAssertFalse(FileIntake.isReadableFile(dir))
        XCTAssertTrue(FileIntake.isReadableFile(file))
        XCTAssertFalse(FileIntake.isReadableFile(URL(fileURLWithPath: "/tmp/grock-missing-\(UUID().uuidString)")))
    }

    func testDocumentTypesAreRegistered() {
        let bundle = Bundle(for: AppDelegate.self)
        let types = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
        let roles = types?.compactMap { $0["CFBundleTypeRole"] as? String } ?? []
        XCTAssertTrue(roles.contains("Viewer"))
        let ranks = types?.compactMap { $0["LSHandlerRank"] as? String } ?? []
        XCTAssertTrue(ranks.contains("Alternate"))
        let utis = types?.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] } ?? []
        XCTAssertTrue(utis.contains("public.data"))
        XCTAssertTrue(utis.contains("public.content"))
    }

    func testAskGrokServiceIsRegisteredForFilesNotText() {
        let bundle = Bundle(for: AppDelegate.self)
        let services = bundle.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]]
        XCTAssertEqual(services?.count, 1)
        let service = services?.first
        XCTAssertEqual(service?["NSMessage"] as? String, "askGrok")
        XCTAssertEqual(service?["NSPortName"] as? String, "Grock")
        let menu = service?["NSMenuItem"] as? [String: String]
        XCTAssertEqual(menu?["default"], "Ask Grok")
        let fileTypes = service?["NSSendFileTypes"] as? [String] ?? []
        XCTAssertTrue(fileTypes.contains("public.data"))
        XCTAssertTrue(fileTypes.contains("public.content"))
        let sendTypes = service?["NSSendTypes"] as? [String] ?? []
        XCTAssertEqual(sendTypes, ["public.file-url"])
        XCTAssertFalse(sendTypes.contains("public.utf8-plain-text"))
        XCTAssertFalse(sendTypes.contains("NSStringPboardType"))
        let context = service?["NSRequiredContext"] as? [String: String]
        XCTAssertEqual(context?["NSTextContent"], "FilePath")
    }

    func testFileIntakeReadsServicePasteboard() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ask-grok.pdf"
        )
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))
        XCTAssertEqual(FileIntake.fileURLs(from: pasteboard), [url])
    }

    func testFileIntakeServicePasteboardSkipsDirectoriesAndText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ask-grok-dir-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = NSPasteboard.withUniqueName()
        files.clearContents()
        XCTAssertTrue(files.writeObjects([dir as NSURL]))
        XCTAssertTrue(FileIntake.fileURLs(from: files).isEmpty)

        let text = NSPasteboard.withUniqueName()
        text.clearContents()
        text.setString("summarize this", forType: .string)
        XCTAssertTrue(FileIntake.fileURLs(from: text).isEmpty)
    }

    @MainActor
    func testIngestOSFilesDoesNotGatherClipboard() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("os-hand.pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = QuickChatController()
        controller.draft = "keep?"
        controller.textChip = "clipboard"
        XCTAssertEqual(controller.ingestOSFiles([url]), 1)
        XCTAssertTrue(controller.draft.isEmpty)
        XCTAssertNil(controller.textChip)
        XCTAssertEqual(controller.attachments.count, 1)
        XCTAssertEqual(controller.attachments.first?.attachment.filename, "os-hand.pdf")
        XCTAssertFalse(controller.isPresented)
    }

    @MainActor
    func testIngestOSFilesAppendsWhenPresented() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("os-hand-2.pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = QuickChatController()
        controller.draft = "hello"
        controller.textChip = "clip"
        controller.isPresented = true
        XCTAssertEqual(controller.ingestOSFiles([url]), 1)
        XCTAssertEqual(controller.draft, "hello")
        XCTAssertEqual(controller.textChip, "clip")
        XCTAssertEqual(controller.attachments.count, 1)
    }

    @MainActor
    func testIngestOSFilesSkipsDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "grock-os-dir-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let controller = QuickChatController()
        XCTAssertEqual(controller.ingestOSFiles([dir]), 0)
        XCTAssertTrue(controller.attachments.isEmpty)
    }

    func testLaunchReasonReadsOpenDocuments() {
        let file = URL(fileURLWithPath: "/tmp/note.pdf")
        let event = Self.openDocumentsEvent(urls: [file])
        XCTAssertEqual(LaunchReason.fileURLs(from: event), [file])
        XCTAssertTrue(LaunchReason.fileURLs(from: Self.openApplicationEvent(loginItem: false)).isEmpty)
        XCTAssertTrue(LaunchReason.fileURLs(from: Self.getURLEvent("grock://ask?text=hi")).isEmpty)
        XCTAssertTrue(LaunchReason.fileURLs(from: nil).isEmpty)
    }

    func testFillComposerScriptDoesNotSend() {
        XCTAssertTrue(WebViewStore.fillComposerScript.contains("insertText"))
        XCTAssertTrue(WebViewStore.fillComposerScript.contains("no-composer"))
        XCTAssertTrue(WebViewStore.fillComposerScript.contains("filled"))
        XCTAssertTrue(WebViewStore.fillComposerScript.contains("grockAttach"))
        XCTAssertFalse(WebViewStore.fillComposerScript.contains("grockFindSend"))
        XCTAssertTrue(WebViewStore.submitPayloadScript.contains("insertText"))
        XCTAssertTrue(WebViewStore.submitPayloadScript.contains("grockFindSend"))
    }

    private static func getURLEvent(_ url: String) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(string: url),
            forKeyword: keyDirectObject
        )
        return event
    }

    private static func openDocumentsEvent(urls: [URL]) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        let list = NSAppleEventDescriptor.list()
        for (index, url) in urls.enumerated() {
            list.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1)
        }
        event.setParam(list, forKeyword: keyDirectObject)
        return event
    }

    private static func openApplicationEvent(loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if loginItem {
            event.setParam(
                NSAppleEventDescriptor(boolean: true),
                forKeyword: LaunchReason.loginItemKeyword
            )
        }
        return event
    }

    @MainActor
    func testWebViewReportsNoSafeArea() {
        XCTAssertEqual(WebViewStore.shared.webView.safeAreaInsets.top, 0)
        XCTAssertEqual(WebViewStore.shared.webView.safeAreaInsets.left, 0)
        XCTAssertEqual(WebViewStore.shared.webView.safeAreaInsets.bottom, 0)
        XCTAssertEqual(WebViewStore.shared.webView.safeAreaInsets.right, 0)
    }

    func testQuickChatPayloadHasContent() {
        XCTAssertFalse(QuickChatPayload(text: "  ", attachments: []).hasContent)
        XCTAssertTrue(QuickChatPayload(text: "hello", attachments: []).hasContent)
        let png = QuickChatAttachment(filename: "x.png", mimeType: "image/png", data: Data([0x89, 0x50]))
        XCTAssertTrue(QuickChatPayload(text: "", attachments: [png]).hasContent)
        XCTAssertEqual(QuickChatPayload(text: "  hi  ", attachments: []).trimmedText, "hi")
        XCTAssertEqual(
            QuickChatPayload(text: "", attachments: [png]).promptForSubmit,
            QuickChatPayload.singleAttachmentPrompt
        )
        XCTAssertEqual(
            QuickChatPayload(text: "", attachments: [png, png]).promptForSubmit,
            QuickChatPayload.multipleAttachmentPrompt
        )
        XCTAssertEqual(
            QuickChatPayload(text: "  hello  ", attachments: [png]).promptForSubmit,
            "hello"
        )
        XCTAssertEqual(QuickChatPayload(text: "", attachments: []).promptForSubmit, "")
    }

    func testPasteboardMonitorIgnoresStaleChanges() {
        let monitor = PasteboardMonitor()
        var now = Date(timeIntervalSince1970: 1_000)
        monitor.now = { now }
        XCTAssertFalse(monitor.isRecent())
        monitor.markChanged(at: now)
        XCTAssertTrue(monitor.isRecent())
        now = now.addingTimeInterval(PasteboardMonitor.recency + 1)
        XCTAssertFalse(monitor.isRecent())
    }

    @MainActor
    func testQuickChatPayloadJoinsTypedTextAndChip() {
        let controller = QuickChatController()
        controller.draft = "  typed  "
        controller.textChip = "clipboard"
        let png = QuickChatAttachment(filename: "x.png", mimeType: "image/png", data: Data([0x89]))
        controller.attachments = [StagedAttachment(attachment: png)]
        let payload = controller.makePayload()
        XCTAssertEqual(payload.text, "typed\n\nclipboard")
        XCTAssertEqual(payload.attachments.count, 1)
        XCTAssertTrue(controller.canSend)
        XCTAssertEqual(
            QuickChatAttachment.combinedText(draft: "  hi  ", clipboardText: " clip "),
            "hi\n\nclip"
        )
        XCTAssertEqual(
            QuickChatAttachment.combinedText(draft: "only", clipboardText: nil),
            "only"
        )
        XCTAssertEqual(
            QuickChatAttachment.combinedText(draft: "  ", clipboardText: "clip"),
            "clip"
        )
    }

    @MainActor
    func testQuickChatURLChipSkipsClipboardGather() {
        let controller = QuickChatController()
        controller.draft = "old draft"
        controller.textChip = "clipboard leftover"
        controller.present(chip: "  from url  ", files: [])
        XCTAssertEqual(controller.draft, "")
        XCTAssertEqual(controller.textChip, "from url")
        XCTAssertTrue(controller.isPresented)
        XCTAssertTrue(controller.canSend)
        controller.dismiss()
        XCTAssertFalse(controller.isPresented)
    }

    @MainActor
    func testQuickChatURLChipAttachesReadableFile() async throws {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("grock-url-chip.txt")
        try Data("hello".utf8).write(to: file)
        let controller = QuickChatController()
        controller.present(chip: "caption", files: [file])
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.textChip, "caption")
        XCTAssertEqual(controller.attachments.count, 1)
        XCTAssertEqual(controller.attachments.first?.attachment.filename, "grock-url-chip.txt")
        controller.dismiss()
    }

    @MainActor
    func testQuickChatPayloadFallsBackToTextChip() {
        let controller = QuickChatController()
        controller.draft = "   "
        controller.textChip = "from clipboard"
        XCTAssertEqual(controller.makePayload().text, "from clipboard")
        controller.removeTextChip()
        XCTAssertFalse(controller.canSend)
    }

    @MainActor
    func testQuickChatPanelIsKeyableHUD() {
        let panel = QuickChatPanel(controller: QuickChatController.shared)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel is FloatingPanel)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.hasShadow)
        let glass = panel.contentView as? NSGlassEffectView
        XCTAssertNotNil(glass)
        XCTAssertTrue(glass?.contentView is QuickChatDropHost)
        XCTAssertEqual(glass?.style, .regular)
        XCTAssertEqual(glass?.cornerRadius, QuickChatComposer.cardCornerRadius)
        XCTAssertTrue(glass?.clipsToBounds ?? false)
        XCTAssertEqual(glass?.layer?.cornerRadius, QuickChatComposer.cardCornerRadius)
        XCTAssertTrue(glass?.layer?.masksToBounds ?? false)
        XCTAssertGreaterThan(QuickChatComposer.minHeight, 50)
        XCTAssertLessThan(
            QuickChatComposer.minHeight,
            QuickChatComposer.cardHeight(text: "a\nb", itemCount: 0, hasError: false)
        )
    }

    @MainActor
    func testQuickChatPanelExpandCollapseLayout() {
        let controller = QuickChatController()
        let panel = QuickChatPanel(controller: controller)
        let glass = panel.contentView as! NSGlassEffectView
        let drop = glass.contentView!
        let host = drop.subviews[0]
        let top = panel.frame.maxY

        func assertLayout(height: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.maxY, top, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(panel.contentLayoutRect.height, height, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(glass.bounds.size, panel.contentLayoutRect.size, file: file, line: line)
            XCTAssertEqual(drop.frame, glass.bounds, file: file, line: line)
            XCTAssertEqual(host.frame, drop.bounds, file: file, line: line)
            XCTAssertEqual(host.intrinsicContentSize.height, height, accuracy: 0.5, file: file, line: line)
        }

        assertLayout(height: QuickChatComposer.minHeight)
        controller.draft = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen"
        panel.relayout()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assertLayout(
            height: QuickChatComposer.cardHeight(
                text: controller.draft,
                itemCount: 0,
                hasError: false
            )
        )
        controller.draft = "short"
        panel.relayout()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assertLayout(height: QuickChatComposer.minHeight)
    }

    func testQuickChatComposerFieldIsRealFirstResponder() {
        let view = QuickChatNSTextView(frame: .zero, textContainer: nil)
        XCTAssertTrue(view.acceptsFirstResponder)
        XCTAssertFalse(view.importsGraphics)
        XCTAssertFalse(view.isRichText)
        XCTAssertEqual(view.focusRingType, .none)
    }

    func testQuickChatDropHostStealsFinderDragAfterHotkey() {
        XCTAssertTrue(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 1,
                eventType: .keyDown,
                eventIsInPanel: true,
                isLeftoverDrag: false
            )
        )
        XCTAssertTrue(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 1,
                eventType: .leftMouseDragged,
                eventIsInPanel: true,
                isLeftoverDrag: false
            ),
            "Finder drag over a focused field must still attach"
        )
        XCTAssertTrue(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 1,
                eventType: nil,
                eventIsInPanel: false,
                isLeftoverDrag: false
            )
        )
        XCTAssertFalse(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 1,
                eventType: .leftMouseDown,
                eventIsInPanel: true,
                isLeftoverDrag: false
            )
        )
        XCTAssertFalse(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 1,
                eventType: .leftMouseDragged,
                eventIsInPanel: true,
                isLeftoverDrag: true
            ),
            "Leftover drag pasteboard must not steal text selection"
        )
        XCTAssertFalse(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: true,
                pressedButtons: 0,
                eventType: .keyDown,
                eventIsInPanel: true,
                isLeftoverDrag: false
            )
        )
        XCTAssertFalse(
            QuickChatDropHost.shouldStealFileDrag(
                hasFiles: false,
                pressedButtons: 1,
                eventType: .keyDown,
                eventIsInPanel: false,
                isLeftoverDrag: false
            )
        )
    }

    func testQuickChatComposerOpensFiveLineViewportAfterWrapping() {
        XCTAssertFalse(QuickChatComposer.isExpanded(""))
        XCTAssertFalse(QuickChatComposer.isExpanded("Hi"))
        XCTAssertTrue(QuickChatComposer.isExpanded("a\nb"))
        XCTAssertTrue(QuickChatComposer.isExpanded("a\nb\nc"))
        let paste = String(repeating: "something ", count: 40)
        XCTAssertTrue(QuickChatComposer.isExpanded(paste))
        XCTAssertEqual(QuickChatComposer.visibleFieldLines(""), 1)
        XCTAssertEqual(QuickChatComposer.visibleFieldLines("Hi"), 1)
        XCTAssertEqual(QuickChatComposer.visibleFieldLines("a\nb"), 5)
        XCTAssertEqual(QuickChatComposer.visibleFieldLines("a\nb\nc\nd\ne\nf"), 5)
        XCTAssertFalse(QuickChatComposer.needsVerticalScroller("a\nb\nc\nd\ne"))
        XCTAssertTrue(QuickChatComposer.needsVerticalScroller("a\nb\nc\nd\ne\nf"))
        XCTAssertGreaterThan(
            QuickChatComposer.fieldHeight(for: "a\nb"),
            QuickChatComposer.fieldHeight(for: "Hi")
        )
        XCTAssertEqual(
            QuickChatComposer.fieldHeight(for: "a\nb"),
            QuickChatComposer.fieldHeight(for: "a\nb\nc\nd\ne")
        )
        XCTAssertEqual(
            QuickChatComposer.fieldHeight(for: "a\nb\nc\nd\ne\nf"),
            QuickChatComposer.fieldHeight(for: "a\nb\nc\nd\ne")
        )
        XCTAssertGreaterThan(
            QuickChatComposer.cardHeight(text: "a\nb", itemCount: 0, hasError: false),
            QuickChatComposer.cardHeight(text: "", itemCount: 0, hasError: false)
        )
        XCTAssertGreaterThan(
            QuickChatComposer.cardHeight(text: "", itemCount: 1, hasError: false),
            QuickChatComposer.cardHeight(text: "", itemCount: 0, hasError: false)
        )
        let seven = QuickChatComposer.cardHeight(text: "", itemCount: 7, hasError: false)
        let eight = QuickChatComposer.cardHeight(text: "", itemCount: 8, hasError: false)
        XCTAssertEqual(seven, eight)
        XCTAssertEqual(QuickChatComposer.stagedItemCount(textChip: nil, attachments: []), 0)
        let png = QuickChatAttachment(filename: "shot.png", mimeType: "image/png", data: Data([0x89]))
        XCTAssertEqual(QuickChatComposer.stagedItemCount(textChip: nil, attachments: [png]), 1)
        XCTAssertEqual(QuickChatComposer.stagedItemCount(textChip: "hi", attachments: [png]), 2)
        XCTAssertEqual(
            QuickChatComposer.itemListHeight(itemCount: 1),
            QuickChatComposer.dividerHeight
                + QuickChatComposer.listTopInset
                + QuickChatComposer.rowHeight
                + QuickChatComposer.listBottomInset
        )
        XCTAssertEqual(
            QuickChatComposer.itemListViewportHeight(itemCount: 1),
            QuickChatComposer.listTopInset
                + QuickChatComposer.rowHeight
                + QuickChatComposer.listBottomInset
        )
        XCTAssertEqual(
            QuickChatComposer.itemListHeight(itemCount: 8),
            QuickChatComposer.dividerHeight
                + QuickChatComposer.listTopInset
                + CGFloat(QuickChatComposer.maxVisibleRows) * QuickChatComposer.rowHeight
                + QuickChatComposer.listBottomInset
        )
        XCTAssertEqual(QuickChatComposer.itemListHeight(itemCount: 0), 0)
        XCTAssertEqual(QuickChatComposer.itemListViewportHeight(itemCount: 0), 0)
    }

    func testQuickChatRowMetadata() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let disk = QuickChatAttachment(
            filename: "shot.png",
            mimeType: "image/png",
            data: Data(count: 1800),
            source: .disk,
            folderName: "Desktop",
            modifiedAt: yesterday
        )
        XCTAssertEqual(disk.rowTitle, "shot.png")
        let diskSub = disk.rowSubtitle(now: now)
        XCTAssertTrue(diskSub.contains("Desktop"))
        XCTAssertTrue(diskSub.contains("Yesterday"))
        XCTAssertTrue(diskSub.contains(" · "))
        XCTAssertFalse(diskSub.contains("Clipboard"))

        let clipFile = QuickChatAttachment(
            filename: "quote.pdf",
            mimeType: "application/pdf",
            data: Data(count: 4096),
            source: .clipboard,
            folderName: "Documents",
            modifiedAt: yesterday,
            copiedAt: now
        )
        let clipSub = clipFile.rowSubtitle(now: now)
        XCTAssertTrue(clipSub.contains("Clipboard"))
        XCTAssertFalse(clipSub.contains("Documents"))

        let clipboardImage = QuickChatAttachment(
            filename: "clipboard.png",
            mimeType: "image/png",
            data: Data(count: 80),
            source: .clipboard,
            copiedAt: now
        )
        XCTAssertEqual(clipboardImage.rowTitle, clipboardImage.localizedTypeName)
        XCTAssertTrue(clipboardImage.rowSubtitle(now: now).hasSuffix("Clipboard"))

        XCTAssertEqual(
            QuickChatAttachment.textRowSubtitle(copiedAt: nil, now: now),
            "Text"
        )
        let copied = QuickChatAttachment.textRowSubtitle(copiedAt: now.addingTimeInterval(-120), now: now)
        XCTAssertTrue(copied.hasPrefix("Text · Copied "))
        XCTAssertEqual(
            QuickChatAttachment.collapsedSnippet("one   two\nthree", limit: 80),
            "one two three"
        )
        XCTAssertTrue(QuickChatAttachment.collapsedSnippet(String(repeating: "a", count: 90)).hasSuffix("…"))
        XCTAssertEqual(QuickChatAttachment.spotlightDate(yesterday, now: now).hasPrefix("Yesterday,"), true)
        XCTAssertTrue(QuickChatAttachment.spotlightDate(now, now: now).hasPrefix("Today,"))
        XCTAssertEqual(
            QuickChatAttachment(filename: "Agenda.xlsx", mimeType: "application/octet-stream", data: Data()).localizedTypeName,
            "Excel spreadsheet"
        )
        XCTAssertEqual(
            QuickChatAttachment(filename: "notes.docx", mimeType: "application/octet-stream", data: Data()).localizedTypeName,
            "Word document"
        )
        XCTAssertEqual(
            QuickChatAttachment(filename: "data.csv", mimeType: "text/csv", data: Data()).localizedTypeName,
            "CSV"
        )
        XCTAssertEqual(
            QuickChatAttachment(filename: "shot.png", mimeType: "image/png", data: Data()).localizedTypeName,
            "PNG image"
        )
        XCTAssertEqual(disk.rowLocation, .folder("Desktop"))
        XCTAssertEqual(clipFile.rowLocation, .clipboard)
        XCTAssertFalse(disk.rowMetaLine(now: now).contains("Desktop"))
    }

    func testQuickChatAttachmentFromFileCapturesFolder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grock-row-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("note.pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: dir) }

        let attachment = try XCTUnwrap(QuickChatAttachment.fromFile(url: url))
        XCTAssertEqual(attachment.filename, "note.pdf")
        XCTAssertEqual(attachment.source, .disk)
        XCTAssertEqual(attachment.folderName, dir.lastPathComponent)
        XCTAssertNotNil(attachment.modifiedAt)
        XCTAssertTrue(attachment.rowSubtitle().contains(dir.lastPathComponent))

        let clip = try XCTUnwrap(
            QuickChatAttachment.fromFile(url: url, source: .clipboard, copiedAt: Date())
        )
        XCTAssertEqual(clip.source, .clipboard)
        XCTAssertNil(clip.folderName)
        XCTAssertTrue(clip.rowSubtitle().contains("Clipboard"))
    }

    func testQuickChatAttachmentFromImage() {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let attachment = QuickChatAttachment.fromImage(image)
        XCTAssertEqual(attachment?.mimeType, "image/png")
        XCTAssertEqual(attachment?.filename, "clipboard.png")
        XCTAssertGreaterThan(attachment?.data.count ?? 0, 8)
        XCTAssertFalse(attachment?.isOversize ?? true)
        XCTAssertTrue(attachment?.isImage ?? false)
        let thumb = attachment?.thumbnail(maxPixel: 64)
        XCTAssertNotNil(thumb)
        XCTAssertGreaterThan(thumb?.size.width ?? 0, 0)
        XCTAssertLessThanOrEqual(thumb?.size.width ?? 1_000, 64)
        XCTAssertLessThanOrEqual(thumb?.size.height ?? 1_000, 64)
    }

    func testQuickChatAttachmentTypeIconUsesExtension() {
        let pdf = QuickChatAttachment(
            filename: "quote.pdf",
            mimeType: "application/octet-stream",
            data: Data([0x25])
        )
        let md = QuickChatAttachment(
            filename: "notes.md",
            mimeType: "text/plain",
            data: Data("hi".utf8)
        )
        let bin = QuickChatAttachment(
            filename: "blob.bin",
            mimeType: "application/octet-stream",
            data: Data([0x00])
        )
        XCTAssertFalse(pdf.isImage)
        XCTAssertGreaterThan(pdf.typeIcon.size.width, 0)
        XCTAssertGreaterThan(md.typeIcon.size.width, 0)
        XCTAssertNotEqual(pdf.typeIcon.tiffRepresentation, bin.typeIcon.tiffRepresentation)
        XCTAssertNotEqual(pdf.typeIcon.tiffRepresentation, md.typeIcon.tiffRepresentation)
        XCTAssertNil(bin.thumbnail())
    }

    @MainActor
    func testQuickChatDropPasteboardBecomesAttachment() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-test.pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))

        let controller = QuickChatController()
        controller.addDroppedPasteboard(pasteboard)
        await controller.waitForPendingIntake()
        XCTAssertEqual(controller.attachments.count, 1)
        XCTAssertEqual(controller.attachments.first?.attachment.filename, "drop-test.pdf")
        XCTAssertEqual(controller.attachments.first?.attachment.mimeType, "application/pdf")
        XCTAssertEqual(controller.attachments.first?.attachment.source, .disk)
        XCTAssertEqual(
            controller.attachments.first?.attachment.folderName,
            url.deletingLastPathComponent().lastPathComponent
        )
        XCTAssertTrue(controller.draft.isEmpty)
        XCTAssertNil(controller.textChip)
    }

    func testQuickChatDropPasteboardIgnoresBarePathString() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("/tmp/shot.png", forType: .string)
        XCTAssertTrue(QuickChatAttachment.fromPasteboard(pasteboard).isEmpty)
    }

    func testQuickChatResolvedFileURLAcceptsPathOnly() {
        let path = URL(fileURLWithPath: "/tmp/shot.png")
        XCTAssertEqual(QuickChatAttachment.resolvedFileURL(path), path)
        let loose = URL(string: "/tmp/shot.png")
        XCTAssertEqual(
            QuickChatAttachment.resolvedFileURL(loose ?? path).path,
            "/tmp/shot.png"
        )
    }

    func testQuickChatAttachmentSkipsOversize() {
        let huge = QuickChatAttachment(
            filename: "big.bin",
            mimeType: "application/octet-stream",
            data: Data(count: QuickChatPayload.maxAttachmentBytes + 1)
        )
        XCTAssertTrue(huge.isOversize)
    }

    func testSubmitPayloadScriptProbesComposerAndSend() {
        let js = WebViewStore.submitPayloadScript
        XCTAssertTrue(js.contains("textarea"))
        XCTAssertTrue(js.contains("contenteditable"))
        XCTAssertTrue(js.contains("role=\"textbox\""))
        XCTAssertTrue(js.contains("insertText"))
        XCTAssertTrue(js.contains("DataTransfer"))
        XCTAssertTrue(js.contains("input[type=\"file\"]"))
        XCTAssertTrue(js.contains("promptText"))
        XCTAssertTrue(js.contains("refer to the following content"))
        XCTAssertTrue(js.contains("grockClearText"))
        XCTAssertTrue(WebViewStore.composerPresentScript.contains("textbox"))
    }

    @MainActor
    func testChromeScriptHidesPromoShapesAndSkipsAccountChrome() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <div id="query-bar" class="query-bar">
            <div contenteditable="true">Ask anything</div>
          </div>
          <div id="finance-promo">
            <p>Finance</p>
            <p>Connect accounts to manage your finances in chat</p>
            <button type="button">Dismiss</button>
            <button type="button">Add</button>
          </div>
          <div id="imagine-promo" style="position:fixed;left:24px;bottom:24px;width:360px;height:280px">
            <button type="button" aria-label="Dismiss">X</button>
            <video src="https://example.com/a.mp4"></video>
            <span>Now with References</span>
            <button type="button">Try References</button>
          </div>
          <div id="tos-dialog" role="dialog" style="position:fixed;left:200px;top:80px;width:400px;height:280px">
            <button type="button" aria-label="Close">X</button>
            <p>We've updated our Terms of Service</p>
            <button type="button">I agree</button>
          </div>
          <div id="billing-toast" style="position:fixed;left:24px;bottom:24px;width:360px;height:220px">
            <button type="button" aria-label="Dismiss">X</button>
            <img src="https://example.com/a.png" width="360" height="80" alt="">
            <p>Update your payment method</p>
            <button type="button">Try SuperGrok</button>
          </div>
          <div id="x-connect">
            <p>Connect your X account</p>
            <button type="button">Dismiss</button>
            <button type="button">Add</button>
          </div>
          <div id="grok-bot-promo" role="dialog" style="position:fixed;left:0;top:0;width:320px;height:340px">
            <div aria-hidden="true" style="height:140px"></div>
            <section>
              <h2>Meet Grok Bot</h2>
              <p>AI teammates you can give real work to. Bots can sign in to your tools, use them just like you do, and come back with finished work.</p>
              <button type="button">Dismiss</button>
            </section>
          </div>
          <div id="build-mode-promo" data-radix-popper-content-wrapper style="position:fixed;right:84px;bottom:0">
            <div role="dialog" aria-label="Introducing Build Mode" data-state="open">
              <div style="width:320px;height:300px;visibility:visible">
                <video></video><p>Introducing Build Mode</p>
                <p>Use Build Mode to create websites, games, apps, and interactive dashboards.</p>
                <button onclick="window.promoClicked = true">Try now</button>
                <button onclick="window.promoClicked = true">Dismiss</button>
              </div>
              <span data-radix-popper-arrow></span>
            </div>
          </div>
          <div id="build-mode-dialog" data-radix-popper-content-wrapper>
            <div role="dialog" aria-label="Introducing Build Mode" aria-modal="true">
              <p>Build Mode settings</p><button>Close</button>
            </div>
          </div>
          <div id="other-popover" data-radix-popper-content-wrapper>
            <div role="dialog" aria-label="Account notice"><p>Sign in</p><button>Dismiss</button></div>
          </div>
          <div id="unify-card" role="region" aria-label="Unlock the ultimate AI subscription"
               style="position:fixed;right:16px;bottom:16px;width:428px;height:80px">
            <div><p>Unlock the ultimate AI subscription</p><p>Get benefits in Grok, Cursor and X</p></div>
            <span aria-hidden="true">See plans</span>
            <a href="https://accounts.x.ai/unify?redirect=grok-com&amp;src=grok_web_new_chat_card" aria-label="See plans"
               style="position:absolute;inset:0"></a>
            <span><button type="button" aria-label="Dismiss">x</button></span>
          </div>
          <div id="unify-elsewhere" role="region" aria-label="Plans">
            <p>Manage your plan</p>
            <a href="https://accounts.x.ai/unify?redirect=grok-com&amp;src=grok_web_settings_billing_banner">See plans</a>
          </div>
        </body>
        </html>
        """
        let marks = try await evaluatePromoMarks(html: html)
        XCTAssertEqual(marks["finance"], true)
        XCTAssertEqual(marks["imagine"], true)
        XCTAssertEqual(marks["tos"], false)
        XCTAssertEqual(marks["billing"], false)
        XCTAssertEqual(marks["xConnect"], false)
        XCTAssertEqual(marks["grokBot"], true)
        XCTAssertEqual(marks["buildMode"], true)
        XCTAssertEqual(marks["buildModeDialog"], false)
        XCTAssertEqual(marks["otherPopover"], false)
        XCTAssertEqual(marks["unifyCard"], true)
        XCTAssertEqual(marks["unifyElsewhere"], false)
        XCTAssertEqual(marks["noPromoClick"], true)
    }

    /// Search, and See all under Chats, open grok.com's command menu. It used
    /// to be a centered dialog that grew under the titlebar; now it's anchored
    /// at 18vh. Only the centered form may move.
    @MainActor
    func testCommandMenuInsetMovesOnlyTheCenteredDialog() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <div id="anchored" role="dialog" class="fixed top-[18vh] translate-y-0"
               style="position:fixed;left:50%;top:18vh;transform:translateX(-50%);width:600px;height:400px">
            <div cmdk-root><input cmdk-input><div cmdk-list></div></div>
          </div>
          <div id="centered" role="dialog" class="fixed top-[50%] translate-y-[-50%]"
               style="position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:600px;height:900px">
            <div cmdk-root><input cmdk-input><div cmdk-list></div></div>
          </div>
        </body>
        </html>
        """
        let result = try await evaluateChromeFixture(html: html, url: "https://grok.com/", script: """
        (function () {
          if (window.__grockChrome && window.__grockChrome.set) window.__grockChrome.set();
          function edges(id) {
            var r = document.getElementById(id).getBoundingClientRect();
            return [r.top, r.bottom];
          }
          return { anchored: edges('anchored'), centered: edges('centered'), height: window.innerHeight };
        })()
        """)
        func edges(_ key: String) -> [Double] {
            (result[key] as? [NSNumber])?.map(\.doubleValue) ?? []
        }
        let height = (result["height"] as? NSNumber)?.doubleValue ?? 0
        XCTAssertEqual(height, 600, accuracy: 1)
        // grok.com's own placement, untouched.
        XCTAssertEqual(edges("anchored").first ?? -1, 0.18 * height, accuracy: 1)
        XCTAssertEqual(edges("anchored").last ?? -1, 0.18 * height + 400, accuracy: 1)
        // Shifted and capped: 16px below the 52px titlebar, 16px above the bottom.
        XCTAssertGreaterThanOrEqual(edges("centered").first ?? -1, 52 + 16 - 1)
        XCTAssertLessThanOrEqual(edges("centered").last ?? .infinity, height - 16 + 1)
    }

    /// Session column, not New Chat home: collapsed in-page nav (height 0,
    /// scrollHeight from the absolute h-14) must not win the titlebar spacer.
    @MainActor
    func testContentInsetSkipsCollapsedNavAndLeavesComposerOnScreen() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <main id="grok-content-area" style="height:600px;width:800px;overflow:hidden">
            <div style="height:600px;width:800px;overflow:hidden;position:relative">
              <div style="height:600px;width:800px;position:relative">
                <div id="nav" style="height:0;width:800px;overflow:visible;position:relative">
                  <div style="height:51px;width:800px">Grok Bot</div>
                </div>
                <div id="col" style="height:600px;width:800px;display:flex;flex-direction:column;position:relative">
                  <div id="thread" style="height:600px;width:800px;overflow-y:auto">
                    <div style="height:1800px;padding-top:80px">
                      <p id="top-msg">hello thread</p>
                      <div id="code-toolbar" class="sticky top-0" style="position:sticky;top:0;height:28px">Copy</div>
                    </div>
                  </div>
                  <div id="composer" style="position:absolute;left:0;right:0;bottom:0;height:88px">
                    <form><textarea>ask</textarea></form>
                  </div>
                </div>
              </div>
            </div>
          </main>
        </body>
        </html>
        """
        let layout = try await evaluateContentInsetLayout(html: html)
        XCTAssertEqual(layout["threadInset"] as? Bool, true)
        XCTAssertEqual(layout["navInset"] as? Bool, false)
        XCTAssertEqual(layout["colInset"] as? Bool, false)
        XCTAssertEqual(layout["composerOnScreen"] as? Bool, true)
        XCTAssertEqual(layout["toolbarRelative"] as? Bool, true)
        XCTAssertEqual(layout["navHeight"] as? Int, 0)
    }

    @MainActor
    func testSessionClusterIsHiddenOnConversationPages() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <main id="grok-content-area" style="position:relative;height:600px;width:800px">
            <div class="absolute inset-x-0 top-0 z-10 flex h-14" style="position:absolute;top:0;right:0;left:0;height:56px;display:flex;justify-content:flex-end">
              <div id="cluster" class="flex flex-row items-center" style="display:flex;flex-direction:row;align-items:center;gap:6px">
                <button type="button" aria-label="More" style="width:32px;height:32px"></button>
                <button type="button" aria-label="Share" style="width:32px;height:32px"></button>
                <button type="button" aria-label="Toggle panel" style="width:32px;height:32px"></button>
              </div>
            </div>
          </main>
        </body>
        </html>
        """
        let marked = try await evaluateSessionCluster(html: html, url: "https://grok.com/c/fixture")
        XCTAssertEqual(marked["cluster"], true)
        XCTAssertEqual(marked["more"], true)
        XCTAssertEqual(marked["share"], true)
        XCTAssertEqual(marked["panel"], true)
        XCTAssertEqual(marked["hidden"], true)
        XCTAssertEqual(marked["sessionMore"], true)
        XCTAssertEqual(marked["sessionShare"], true)
        XCTAssertEqual(marked["sessionPanel"], true)
    }

    @MainActor
    func testSessionActionsSurvivePanelOpenCloseAndHeaderRemount() async throws {
        let html = """
        <!DOCTYPE html><html><body style="margin:0">
          <div id="grok-app-root" style="position:relative;height:600px;width:800px">
            <div id="sidebar" data-collapsible="" data-side="left" data-state="expanded"></div>
            <main id="grok-content-area" style="height:600px;width:500px">
              <div id="decoy"><button aria-label="Expand"></button><button aria-label="Files"></button></div>
              <div id="header" class="absolute inset-x-0 top-0 z-10 h-14">
                <div id="cluster">
                  <button id="more" aria-label="More" aria-haspopup="menu"></button>
                  <button id="share" aria-label="Create share link"></button>
                  <button id="toggle" aria-label="Toggle Right Panel" aria-pressed="false"></button>
                </div>
              </div>
              <div id="response"><button aria-label="Create share link"></button><button aria-label="More actions"></button></div>
            </main>
          </div>
          <script>
            var app = document.getElementById('grok-app-root');
            var cluster = document.getElementById('cluster');
            var toggle = document.getElementById('toggle');
            var placeholder = document.createElement('div');
            placeholder.className = 'h-8 shrink-0 overflow-hidden pointer-events-none';
            var panel = document.createElement('div');
            panel.id = 'panel';
            panel.className = 'h-dvh overflow-hidden flex absolute inset-y-0';
            panel.setAttribute('aria-hidden', 'false');
            panel.style.cssText = 'position:absolute;top:0;right:0;height:600px;width:300px';
            var controls = document.createElement('div');
            controls.id = 'controls';
            controls.style.cssText = 'position:absolute;top:15px;right:15px;height:32px';
            controls.innerHTML = '<button aria-label="Expand"></button>';
            toggle.addEventListener('click', function () {
              var opening = toggle.getAttribute('aria-pressed') !== 'true';
              toggle.setAttribute('aria-pressed', String(opening));
              if (opening) {
                toggle.replaceWith(placeholder);
                controls.appendChild(toggle);
                app.append(panel, controls);
              } else {
                placeholder.replaceWith(toggle);
                panel.remove();
                controls.remove();
              }
            });
          </script>
        </body></html>
        """
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/c/fixture")
        let opened = try await callSessionJavaScript(webView, """
          var result = await window.__grockChrome.clickSession('panel');
          // Flush DOM observers, not a frame: source hiding and panel geometry
          // must already be correct before paint, including in occluded views.
          await Promise.resolve();
          var state = window.__grockChrome.session();
          return {
            result: result, more: state.more, share: state.share, panel: state.panel,
            hidden: getComputedStyle(cluster).display === 'none',
            panelTop: panel.getBoundingClientRect().top,
            panelBottom: panel.getBoundingClientRect().bottom,
            controlsTop: controls.getBoundingClientRect().top,
            toggleMarked: toggle.hasAttribute('data-grock-session-panel'),
            sidebarHidden: getComputedStyle(document.getElementById('sidebar')).display === 'none',
            decoyMarked: !!document.querySelector('#decoy [data-grock-session-more], #response [data-grock-session-share]')
          };
        """) as? [String: Any]
        XCTAssertEqual(opened?["result"] as? String, "clicked")
        for key in ["more", "share", "panel", "hidden", "toggleMarked", "sidebarHidden"] {
            XCTAssertEqual(opened?[key] as? Bool, true, key)
        }
        XCTAssertEqual(opened?["panelTop"] as? Int, 52)
        XCTAssertEqual(opened?["panelBottom"] as? Int, 600)
        XCTAssertEqual(opened?["controlsTop"] as? Int, 67)
        XCTAssertEqual(opened?["decoyMarked"] as? Bool, false)

        // Re-enter a conversation with the panel already open. No marker or
        // DOM reference from the old header may be required for discovery.
        let remounted = try await callSessionJavaScript(webView, """
          var header = document.getElementById('header');
          var replacement = header.cloneNode(true);
          [replacement].concat(Array.from(replacement.querySelectorAll('*'))).forEach(function (el) {
            Array.from(el.attributes).forEach(function (attr) {
              if (attr.name.startsWith('data-grock-')) el.removeAttribute(attr.name);
            });
          });
          header.replaceWith(replacement);
          cluster = document.getElementById('cluster');
          placeholder = cluster.lastElementChild;
          await Promise.resolve();
          var state = window.__grockChrome.session();
          return { more: state.more, share: state.share, panel: state.panel,
            hidden: getComputedStyle(cluster).display === 'none' };
        """) as? [String: Bool]
        for key in ["more", "share", "panel", "hidden"] {
            XCTAssertEqual(remounted?[key], true, key)
        }
        let closed = try await callSessionJavaScript(webView, """
          var result = await window.__grockChrome.clickSession('panel');
          await Promise.resolve();
          return { result: result, removed: !panel.isConnected,
            more: window.__grockChrome.session().more,
            hidden: getComputedStyle(cluster).display === 'none' };
        """) as? [String: Any]
        XCTAssertEqual(closed?["result"] as? String, "clicked")
        XCTAssertEqual(closed?["removed"] as? Bool, true)
        XCTAssertEqual(closed?["more"] as? Bool, true)
        XCTAssertEqual(closed?["hidden"] as? Bool, true)
    }

    @MainActor
    func testSessionShareLoadingKeepsSourceHiddenAndNativeMoreAvailable() async throws {
        let html = """
        <!DOCTYPE html><html><body>
          <main id="grok-content-area">
            <div class="absolute inset-x-0 top-0 z-10 h-14">
              <div id="cluster"><button aria-label="More"></button><button id="share" aria-label="Create share link"></button></div>
            </div>
          </main>
        </body></html>
        """
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/c/fixture")
        let loading = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          var share = document.getElementById('share');
          var spinner = document.createElement('div');
          spinner.setAttribute('role', 'status');
          share.replaceWith(spinner);
          await Promise.resolve();
          var cluster = document.getElementById('cluster');
          var hiddenBeforeSnapshot = getComputedStyle(cluster).display === 'none';
          var state = window.__grockChrome.session();
          return { more: state.more, share: state.share, hidden: hiddenBeforeSnapshot,
            result: await window.__grockChrome.clickSession('share') };
        """) as? [String: Any]
        XCTAssertEqual(loading?["more"] as? Bool, true)
        XCTAssertEqual(loading?["share"] as? Bool, false)
        XCTAssertEqual(loading?["hidden"] as? Bool, true)
        XCTAssertEqual(loading?["result"] as? String, "missing")

        let finished = try await callSessionJavaScript(webView, """
          var replacement = document.createElement('button');
          replacement.setAttribute('aria-label', 'Create share link');
          replacement.addEventListener('click', function () { document.body.dataset.shared = 'true'; });
          document.querySelector('[role=status]').replaceWith(replacement);
          await Promise.resolve();
          replacement.disabled = true;
          await Promise.resolve();
          var disabled = window.__grockChrome.session().share;
          var blocked = await window.__grockChrome.clickSession('share');
          replacement.disabled = false;
          await Promise.resolve();
          var enabled = window.__grockChrome.session().share;
          var result = await window.__grockChrome.clickSession('share');
          return { disabled: disabled, blocked: blocked, enabled: enabled,
            result: result, shared: document.body.dataset.shared,
            hidden: getComputedStyle(document.getElementById('cluster')).display === 'none' };
        """) as? [String: Any]
        XCTAssertEqual(finished?["disabled"] as? Bool, false)
        XCTAssertEqual(finished?["blocked"] as? String, "unavailable")
        XCTAssertEqual(finished?["enabled"] as? Bool, true)
        XCTAssertEqual(finished?["result"] as? String, "clicked")
        XCTAssertEqual(finished?["shared"] as? String, "true")
        XCTAssertEqual(finished?["hidden"] as? Bool, true)
    }

    @MainActor
    func testUnchangedChromeRefreshDoesNotMoveStylesheetOrRewriteSessionMarks() async throws {
        let webView = try await loadSessionFixture(html: Self.chromePerformanceFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          var observer = new MutationObserver(function () {});
          observer.observe(document.documentElement, {childList:true, subtree:true, attributes:true});
          for (var i = 0; i < 20; i++) window.__grockChrome.set();
          var records = observer.takeRecords();
          observer.disconnect();
          return {
            styleMoves: records.filter(r => Array.from(r.removedNodes).some(n => n.id === 'grock-chrome-style')).length,
            sessionWrites: records.filter(r => r.attributeName && /^data-grock-(session|right-panel|panel-controls)/.test(r.attributeName)).length,
            railWrites: records.filter(r => r.attributeName === 'data-grock-rail').length,
            sheets: document.querySelectorAll('#grock-chrome-style').length,
            hidden: getComputedStyle(document.getElementById('cluster')).display === 'none'
          };
        """) as? [String: Any]
        XCTAssertEqual(result?["styleMoves"] as? Int, 0)
        XCTAssertEqual(result?["sessionWrites"] as? Int, 0)
        XCTAssertEqual(result?["railWrites"] as? Int, 0)
        XCTAssertEqual(result?["sheets"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
    }

    @MainActor
    func testChromeStylesheetRecoversPrecedenceWithoutFollowingUnrelatedHeadNodes() async throws {
        let webView = try await loadSessionFixture(html: Self.chromePerformanceFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          var sheet = document.getElementById('grock-chrome-style');
          var observer = new MutationObserver(function () {});
          observer.observe(document.head, {childList:true});
          var later = document.createElement('style');
          later.textContent = '[data-grock-session-cluster]{display:block!important}';
          document.head.appendChild(later);
          window.__grockChrome.set();
          var recovered = getComputedStyle(document.getElementById('cluster')).display === 'none';
          var moved = observer.takeRecords().filter(r => Array.from(r.removedNodes).includes(sheet)).length;
          document.head.appendChild(document.createElement('meta'));
          window.__grockChrome.set();
          var unrelatedMoves = observer.takeRecords().filter(r => Array.from(r.removedNodes).includes(sheet)).length;
          sheet.remove();
          window.__grockChrome.set();
          observer.disconnect();
          return {recovered:recovered, moved:moved, unrelatedMoves:unrelatedMoves,
            recreated:document.getElementById('grock-chrome-style') !== sheet,
            sheets:document.querySelectorAll('#grock-chrome-style').length,
            hidden:getComputedStyle(document.getElementById('cluster')).display === 'none'};
        """) as? [String: Any]
        XCTAssertEqual(result?["recovered"] as? Bool, true)
        XCTAssertEqual(result?["moved"] as? Int, 1)
        XCTAssertEqual(result?["unrelatedMoves"] as? Int, 0)
        XCTAssertEqual(result?["recreated"] as? Bool, true)
        XCTAssertEqual(result?["sheets"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
    }

    @MainActor
    func testChromeMutationBurstBatchesFramesAndDefersUnrelatedScans() async throws {
        let webView = try await loadSessionFixture(html: Self.chromePerformanceFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          await new Promise(resolve => setTimeout(resolve, 350));
          var raf = window.requestAnimationFrame, cancel = window.cancelAnimationFrame;
          var query = Document.prototype.querySelectorAll;
          var pending = new Map(), serial = 0, sessionScans = 0, promoScans = 0, cancelled = 0;
          window.requestAnimationFrame = function (cb) { pending.set(++serial, cb); return serial; };
          window.cancelAnimationFrame = function (id) { if (pending.delete(id)) cancelled++; };
          Document.prototype.querySelectorAll = function (selector) {
            if (selector.indexOf('[data-grock-session-cluster]') === 0) sessionScans++;
            if (selector === 'button, [role="button"]') promoScans++;
            return query.apply(this, arguments);
          };
          try {
            var response = document.getElementById('response');
            for (var i = 0; i < 50; i++) {
              response.appendChild(document.createElement('span'));
              await Promise.resolve();
            }
            await Promise.resolve();
            var queued = pending.size, immediateSession = sessionScans, immediatePromo = promoScans;
            var callbacks = Array.from(pending.values());
            pending.clear();
            callbacks.forEach(cb => cb(performance.now()));
            var deferredPromo = promoScans;
            response.appendChild(document.createElement('span'));
            await Promise.resolve();
            var nextFrame = pending.size;
            window.__grockChrome.set();
            return {queued:queued, immediateSession:immediateSession, immediatePromo:immediatePromo,
              deferredPromo:deferredPromo, nextFrame:nextFrame, cancelled:cancelled};
          } finally {
            window.requestAnimationFrame = raf;
            window.cancelAnimationFrame = cancel;
            Document.prototype.querySelectorAll = query;
            pending.clear();
          }
        """) as? [String: Any]
        XCTAssertEqual(result?["queued"] as? Int, 1)
        XCTAssertEqual(result?["immediateSession"] as? Int, 0)
        XCTAssertEqual(result?["immediatePromo"] as? Int, 0)
        XCTAssertGreaterThan(result?["deferredPromo"] as? Int ?? 0, 0)
        XCTAssertEqual(result?["nextFrame"] as? Int, 1)
        XCTAssertGreaterThan(result?["cancelled"] as? Int ?? 0, 0)
    }

    @MainActor
    func testChromeTimerDrainsDeferredWorkWhenAnimationFramesStop() async throws {
        let webView = try await loadSessionFixture(html: Self.chromePerformanceFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          await new Promise(resolve => setTimeout(resolve, 350));
          var raf = window.requestAnimationFrame, cancel = window.cancelAnimationFrame;
          var pending = new Map(), serial = 0, cancelled = 0;
          window.requestAnimationFrame = function (cb) { pending.set(++serial, cb); return serial; };
          window.cancelAnimationFrame = function (id) { if (pending.delete(id)) cancelled++; };
          try {
            var response = document.getElementById('response');
            response.insertAdjacentHTML('beforeend', '<div id="late-promo"><p>Finance</p><p>Connect accounts to manage your finances in chat</p><button>Dismiss</button><button>Add</button></div>');
            await Promise.resolve();
            var queued = pending.size;
            await new Promise(resolve => setTimeout(resolve, 350));
            var hidden = getComputedStyle(document.getElementById('late-promo')).display === 'none';
            var drained = cancelled;
            var callbacks = serial;
            await new Promise(resolve => setTimeout(resolve, 350));
            return {queued:queued, hidden:hidden, drained:drained, idle:serial === callbacks};
          } finally {
            window.requestAnimationFrame = raf;
            window.cancelAnimationFrame = cancel;
            window.__grockChrome.set();
          }
        """) as? [String: Any]
        XCTAssertEqual(result?["queued"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
        XCTAssertEqual(result?["drained"] as? Int, 1)
        XCTAssertEqual(result?["idle"] as? Bool, true)
    }

    @MainActor
    func testSessionRemountAndPanelStateRefreshBeforeAnyAnimationFrame() async throws {
        let bridge = SessionActionsBridge()
        let disabledShare = expectation(description: "disabled-share-without-frame")
        var watchShare = false
        bridge.handler = { _, body in
            if watchShare, body["more"] as? Bool == true, body["share"] as? Bool == false {
                watchShare = false
                disabledShare.fulfill()
            }
        }
        let webView = try await loadSessionFixture(
            html: Self.chromePerformanceFixture, url: "https://grok.com/c/fixture", sessionBridge: bridge
        )
        watchShare = true
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          await new Promise(resolve => setTimeout(resolve, 350));
          var raf = window.requestAnimationFrame, cancel = window.cancelAnimationFrame;
          var handler = window.webkit.messageHandlers.grockSession, post = handler.postMessage;
          var posted = null;
          handler.postMessage = function (body) { posted = body; post.call(handler, body); };
          window.requestAnimationFrame = function () { return 12345; };
          window.cancelAnimationFrame = function () {};
          try {
            // The first mutation is unrelated; it must not conceal a later
            // header replacement in the same observer delivery.
            document.getElementById('response').appendChild(document.createElement('span'));
            var old = document.getElementById('header'), replacement = old.cloneNode(true);
            [replacement].concat(Array.from(replacement.querySelectorAll('*'))).forEach(el => {
              Array.from(el.attributes).forEach(a => { if (a.name.startsWith('data-grock-')) el.removeAttribute(a.name); });
            });
            old.replaceWith(replacement);
            await Promise.resolve();
            var hidden = getComputedStyle(document.getElementById('cluster')).display === 'none';
            var moreMarked = replacement.querySelector('[aria-label="More"]').hasAttribute('data-grock-session-more');
            var panel = document.createElement('div');
            panel.className = 'h-dvh absolute';
            panel.setAttribute('aria-hidden', 'false');
            document.getElementById('grok-app-root').appendChild(panel);
            await Promise.resolve();
            var panelMarked = panel.hasAttribute('data-grock-right-panel');
            panel.setAttribute('aria-hidden', 'true');
            await Promise.resolve();
            var panelCleared = !panel.hasAttribute('data-grock-right-panel');
            replacement.querySelector('[aria-label="Create share link"]').disabled = true;
            await Promise.resolve();
            var disabledPosted = posted && posted.more === true && posted.share === false;
            return {hidden:hidden, moreMarked:moreMarked, panelMarked:panelMarked, panelCleared:panelCleared,
              disabledPosted:!!disabledPosted};
          } finally {
            handler.postMessage = post;
            window.requestAnimationFrame = raf;
            window.cancelAnimationFrame = cancel;
            window.__grockChrome.set();
          }
        """) as? [String: Bool]
        for key in ["hidden", "moreMarked", "panelMarked", "panelCleared", "disabledPosted"] {
            XCTAssertEqual(result?[key], true, key)
        }
        await fulfillment(of: [disabledShare], timeout: 4)
    }

    private static let chromePerformanceFixture = """
    <!DOCTYPE html><html><body>
      <div id="grok-app-root">
        <aside data-sidebar="sidebar"><button data-sidebar="rail"></button></aside>
        <main id="grok-content-area" style="height:600px">
          <div id="header" class="absolute inset-x-0 top-0 z-10 h-14">
            <div id="cluster"><button aria-label="More"></button><button aria-label="Create share link"></button></div>
          </div>
          <div id="response" style="height:600px;overflow:auto"><p>Fixture response</p></div>
        </main>
      </div>
    </body></html>
    """

    @MainActor
    func testSessionClusterStaysOnHome() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <main id="grok-content-area" style="position:relative;height:600px;width:800px">
            <div class="absolute inset-x-0 top-0 z-10 flex h-14" style="position:absolute;top:0;right:0;left:0;height:56px;display:flex;justify-content:flex-end">
              <div id="cluster" class="flex flex-row items-center" style="display:flex;flex-direction:row;align-items:center;gap:6px">
                <button type="button" aria-label="More" style="width:32px;height:32px"></button>
                <button type="button" aria-label="Share" style="width:32px;height:32px"></button>
              </div>
            </div>
          </main>
        </body>
        </html>
        """
        let marked = try await evaluateSessionCluster(html: html, url: "https://grok.com/")
        XCTAssertEqual(marked["cluster"], false)
        XCTAssertEqual(marked["hidden"], false)
        XCTAssertEqual(marked["sessionMore"], false)
        XCTAssertEqual(marked["sessionShare"], false)
    }

    @MainActor
    func testHeaderVisibilityPreservesNewChatLayout() async throws {
        // Cover both an in-flow row and the site's absolute header. The row
        // gets its height from its controls, so hiding either control must
        // leave the heading/composer geometry and the other control intact.
        for absoluteHeader in [false, true] {
            let html = """
            <!DOCTYPE html><html><head><style>
              html, body { margin:0; height:100%; }
              main { position:relative; display:flex; flex-direction:column; height:100vh; }
              #header { display:flex; justify-content:flex-end; flex-shrink:0; width:100%;
                padding:8px; box-sizing:border-box; position:\(absoluteHeader ? "absolute" : "relative"); }
              #header button { height:40px; }
              #home { display:flex; flex-direction:column; justify-content:center;
                align-items:center; flex:1; min-height:0; gap:24px; }
              h1 { margin:0; }
              form { width:80%; }
              textarea { width:100%; height:100px; box-sizing:border-box; }
            </style></head><body>
              <main id="grok-content-area">
                <div id="header" class="\(absoluteHeader ? "absolute inset-x-0 top-0 z-10 h-14" : "")">
                  <button id="bot">Grok Bot</button><button id="private">Private</button>
                </div>
                <div id="home"><h1>What should we explore?</h1>
                  <form><textarea id="prompt" aria-label="Ask Grok anything"></textarea></form>
                </div>
              </main>
            </body></html>
            """
            let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
            let window = try XCTUnwrap(webView.window)
            defer { window.orderOut(nil) }

            for size in [NSSize(width: 920, height: 680), NSSize(width: 720, height: 520)] {
                window.setContentSize(size)
                let result = try await callSessionJavaScript(webView, """
                await new Promise(resolve => setTimeout(resolve, 250));
                const states = [];
                for (const [bot, priv] of [[false,false], [true,false], [false,true], [true,true], [false,false]]) {
                  window.__grockChrome.set({ hideGrokBot:bot, hidePrivate:priv });
                  // Also check a React-style header replacement while the
                  // controls are hidden, after the coalesced observer runs.
                  if (bot && priv) {
                    const header = document.getElementById('header');
                    const replacement = header.cloneNode(true);
                    for (const el of [replacement, ...replacement.querySelectorAll('[data-grock-hide]')]) {
                      el.removeAttribute('data-grock-hide');
                    }
                    header.replaceWith(replacement);
                    await new Promise(resolve => setTimeout(resolve, 400));
                  }
                  function hidden(id) {
                    const el = document.getElementById(id);
                    const style = getComputedStyle(el);
                    return style.visibility === 'hidden' || !el.getClientRects().length;
                  }
                  document.getElementById('prompt').focus();
                  document.getElementById('bot').focus();
                  const botFocused = document.activeElement.id === 'bot';
                  document.getElementById('prompt').focus();
                  document.getElementById('private').focus();
                  const privateFocused = document.activeElement.id === 'private';
                  const heading = document.querySelector('h1').getBoundingClientRect();
                  const prompt = document.getElementById('prompt').getBoundingClientRect();
                  states.push({ botHidden:hidden('bot'), privateHidden:hidden('private'),
                    botFocused, privateFocused, headingTop:heading.top, promptTop:prompt.top,
                    promptBottom:prompt.bottom, headerHeight:document.getElementById('header').offsetHeight });
                }
                return states;
                """)
                let states = try XCTUnwrap(result as? [[String: Any]])
                XCTAssertEqual(states.count, 5)
                let baseline = try XCTUnwrap(states.first)
                for (state, flags) in zip(states, [(false, false), (true, false), (false, true), (true, true), (false, false)]) {
                    let context = "absolute=\(absoluteHeader), size=\(size), hidden=\(flags)"
                    XCTAssertEqual(state["botHidden"] as? Bool, flags.0, context)
                    XCTAssertEqual(state["privateHidden"] as? Bool, flags.1, context)
                    XCTAssertEqual(state["botFocused"] as? Bool, !flags.0, context)
                    XCTAssertEqual(state["privateFocused"] as? Bool, !flags.1, context)
                    for key in ["headingTop", "promptTop", "headerHeight"] {
                        XCTAssertEqual(try XCTUnwrap(state[key] as? Double),
                                       try XCTUnwrap(baseline[key] as? Double), accuracy: 1, "\(key): \(context)")
                    }
                    XCTAssertGreaterThan(try XCTUnwrap(state["headingTop"] as? Double), 52, context)
                    XCTAssertLessThanOrEqual(try XCTUnwrap(state["promptBottom"] as? Double), size.height, context)
                }
            }
        }
    }

    @MainActor
    func testLoggedOutHomeKeepsOnlySignInInWebHeader() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <main id="grok-content-area" style="position:relative;height:600px;width:800px">
            <div id="auth-header" class="absolute inset-x-0 top-0 z-10 flex h-14" style="position:absolute;top:0;right:0;left:0;height:56px;display:flex;justify-content:flex-end">
              <a id="home" href="/" aria-label="Home page">Grok</a>
              <a id="imagine" href="/imagine">Imagine</a>
              <button id="settings" type="button" aria-label="Settings"></button>
              <button id="signin" type="button">Sign in</button>
              <button id="signup" type="button">Sign up</button>
            </div>
          </main>
        </body>
        </html>
        """
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(
            webView,
            """
            function hidden(id) {
              var el = document.getElementById(id);
              while (el) {
                var style = getComputedStyle(el);
                if (style.display === 'none' || style.visibility === 'hidden') return true;
                el = el.parentElement;
              }
              return false;
            }
            var header = document.getElementById('auth-header');
            return {
              pageHeaderHidden: document.documentElement.hasAttribute('data-grock-page-header-hidden'),
              headerHidden: hidden('auth-header'),
              signInHidden: hidden('signin'),
              homeHidden: hidden('home'),
              imagineHidden: hidden('imagine'),
              settingsHidden: hidden('settings'),
              signUpHidden: hidden('signup'),
              headerTop: getComputedStyle(header).top,
              authenticated: window.__grockChrome.session().authenticated
            };
            """
        ) as? [String: Any]
        XCTAssertEqual(result?["pageHeaderHidden"] as? Bool, false)
        XCTAssertEqual(result?["headerHidden"] as? Bool, false)
        XCTAssertEqual(result?["signInHidden"] as? Bool, false)
        XCTAssertEqual(result?["homeHidden"] as? Bool, true)
        XCTAssertEqual(result?["imagineHidden"] as? Bool, true)
        XCTAssertEqual(result?["settingsHidden"] as? Bool, true)
        XCTAssertEqual(result?["signUpHidden"] as? Bool, true)
        XCTAssertEqual(result?["headerTop"] as? String, "52px")
        XCTAssertEqual(result?["authenticated"] as? Bool, false)

        let signedIn = try await callSessionJavaScript(
            webView,
            """
            document.getElementById('signin').remove();
            window.__grockChrome.set();
            var header = document.getElementById('auth-header');
            return {
              headerHidden: getComputedStyle(header).display === 'none'
                || header.hasAttribute('data-grock-hide'),
              authenticated: window.__grockChrome.session().authenticated
            };
            """
        ) as? [String: Any]
        XCTAssertEqual(signedIn?["headerHidden"] as? Bool, true)
        XCTAssertEqual(signedIn?["authenticated"] as? Bool, true)
    }

    @MainActor
    func testSignedInHomePostsAuthenticatedStateWithoutSessionActions() async throws {
        let bridge = SessionActionsBridge()
        let reported = expectation(description: "signed-in-home-session-state")
        var authenticatedState: [String: Any]?
        bridge.handler = { _, body in
            guard body["authenticated"] as? Bool == true else { return }
            authenticatedState = body
            reported.fulfill()
        }

        _ = try await loadSessionFixture(
            html: "<html><body><main id=\"grok-content-area\"></main></body></html>",
            url: "https://grok.com/",
            sessionBridge: bridge
        )
        await fulfillment(of: [reported], timeout: 4)

        XCTAssertEqual(authenticatedState?["authenticated"] as? Bool, true)
        XCTAssertEqual(authenticatedState?["more"] as? Bool, false)
        XCTAssertEqual(authenticatedState?["share"] as? Bool, false)
        XCTAssertEqual(authenticatedState?["panel"] as? Bool, false)
    }

    @MainActor
    func testNonGrokPageDisablesNativeActionsWithoutInjectingChrome() async throws {
        let bridge = SessionActionsBridge()
        let reported = expectation(description: "non-grok-session-state")
        var authenticationState: [String: Any]?
        bridge.handler = { _, body in
            guard body["authenticated"] as? Bool == false else { return }
            authenticationState = body
            reported.fulfill()
        }

        let webView = try await loadSessionFixture(
            html: "<html><body><main id=\"account-page\"></main></body></html>",
            url: "https://accounts.x.ai/sign-in",
            sessionBridge: bridge
        )
        await fulfillment(of: [reported], timeout: 4)
        let injected = try await callSessionJavaScript(
            webView,
            """
            return {
              api: !!window.__grockChrome,
              style: !!document.getElementById('grock-chrome-style'),
              hidden: document.documentElement.hasAttribute('data-grock-page-header-hidden')
            };
            """
        ) as? [String: Any]

        XCTAssertEqual(authenticationState?["authenticated"] as? Bool, false)
        XCTAssertEqual(authenticationState?["more"] as? Bool, false)
        XCTAssertEqual(authenticationState?["share"] as? Bool, false)
        XCTAssertEqual(authenticationState?["panel"] as? Bool, false)
        XCTAssertEqual(injected?["api"] as? Bool, false)
        XCTAssertEqual(injected?["style"] as? Bool, false)
        XCTAssertEqual(injected?["hidden"] as? Bool, false)
    }

    @MainActor
    func testSessionMenuInspectionAndCommandsUseTheCurrentWebMenu() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <div role="menu" aria-labelledby="another-trigger" data-state="open">
            <button role="menuitem" onclick="document.body.dataset.wrongMenu='true'">Pin</button>
            <button role="menuitem" onclick="document.body.dataset.wrongMenu='true'">Delete Chat</button>
          </div>
          <div id="grok-app-root">
          <main id="grok-content-area" style="position:relative;height:600px;width:800px">
            <div class="absolute inset-x-0 top-0 z-10 flex h-14" style="position:absolute;top:0;right:0;left:0;height:56px;display:flex;justify-content:flex-end">
              <div id="cluster" class="flex flex-row items-center" style="display:flex;gap:6px">
                <button id="more" type="button" aria-label="More" aria-haspopup="menu" aria-expanded="false"></button>
                <button id="share" type="button" aria-label="Create share link"></button>
                <div class="h-8 shrink-0 overflow-hidden pointer-events-none"></div>
              </div>
            </div>
          </main>
          <div class="h-dvh absolute" aria-hidden="false"></div>
          <div>
            <button aria-label="Expand"></button>
            <button aria-label="Toggle Right Panel" aria-pressed="true" onclick="document.body.dataset.panelClicked='true'"></button>
          </div>
          </div>
          <script>
            var pinned = true;
            var popup = null;
            function closeMenu() {
              if (popup) popup.dataset.state = 'closed';
              document.getElementById('more').setAttribute('aria-expanded', 'false');
            }
            document.addEventListener('keydown', function (event) {
              if (event.key === 'Escape') closeMenu();
            });
            document.getElementById('more').addEventListener('pointerdown', function () {
              if (popup && popup.dataset.state === 'open') { closeMenu(); return; }
              if (popup) popup.remove();
              popup = document.createElement('div');
              popup.setAttribute('role', 'menu');
              popup.setAttribute('aria-labelledby', 'more');
              popup.dataset.state = 'open';
              document.getElementById('more').setAttribute('aria-expanded', 'true');
              function item(text, action) {
                var button = document.createElement('button');
                button.setAttribute('role', 'menuitem');
                button.textContent = text;
                button.addEventListener('click', action);
                popup.appendChild(button);
              }
              item(pinned ? 'Unpin' : 'Pin', function () {
                pinned = !pinned;
                document.body.dataset.pinned = String(pinned);
                closeMenu();
              });
              item('Toggle Right Panel', function () {
                document.body.dataset.panelClicked = 'true';
                closeMenu();
              });
              item('Delete Chat', function () {
                document.body.dataset.deleted = 'true';
                closeMenu();
                var confirmation = document.createElement('div');
                confirmation.id = 'confirm-delete';
                confirmation.setAttribute('role', 'alertdialog');
                confirmation.tabIndex = -1;
                confirmation.textContent = 'Confirm deletion';
                document.body.appendChild(confirmation);
                confirmation.focus();
              });
              document.body.appendChild(popup);
            });
          </script>
        </body>
        </html>
        """
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/c/fixture")

        let first = try await callSessionJavaScript(
            webView,
            "return await window.__grockChrome.inspectSessionMenu();"
        ) as? [String: Any]
        XCTAssertEqual(first?["pin"] as? String, "unpin")
        XCTAssertEqual(first?["panel"] as? Bool, true)
        let sourceMenuOpen = try await callSessionJavaScript(
            webView,
            "return !!document.querySelector('[role=menu][aria-labelledby=more][data-state=open]');"
        ) as? Bool
        XCTAssertEqual(sourceMenuOpen, false)

        let replacementShare = try await callSessionJavaScript(webView, """
          var old = document.getElementById('share');
          var replacement = document.createElement('button');
          replacement.id = 'share';
          replacement.setAttribute('aria-label', 'Create share link');
          replacement.addEventListener('click', function () {
            document.body.dataset.shared = 'true';
          });
          old.replaceWith(replacement);
          var result = await window.__grockChrome.clickSession('share');
          return result + ':' + document.body.dataset.shared;
        """) as? String
        XCTAssertEqual(replacementShare, "clicked:true")

        let pinResult = try await callSessionJavaScript(
            webView,
            "return await window.__grockChrome.clickSession('pin');"
        ) as? String
        XCTAssertEqual(pinResult, "clicked")
        let pinned = try await callSessionJavaScript(
            webView,
            "return document.body.dataset.pinned;"
        ) as? String
        XCTAssertEqual(pinned, "false")
        let second = try await callSessionJavaScript(
            webView,
            "return await window.__grockChrome.inspectSessionMenu();"
        ) as? [String: Any]
        XCTAssertEqual(second?["pin"] as? String, "pin")

        let panelResult = try await callSessionJavaScript(
            webView,
            "return await window.__grockChrome.clickSession('panel');"
        ) as? String
        XCTAssertEqual(panelResult, "clicked")
        let panelClicked = try await callSessionJavaScript(
            webView,
            "return document.body.dataset.panelClicked;"
        ) as? String
        XCTAssertEqual(panelClicked, "true")
        let deleteResult = try await callSessionJavaScript(
            webView,
            "return await window.__grockChrome.clickSession('delete');"
        ) as? String
        XCTAssertEqual(deleteResult, "clicked")
        let deleted = try await callSessionJavaScript(
            webView,
            "return document.body.dataset.deleted;"
        ) as? String
        XCTAssertEqual(deleted, "true")
        let cleanup = try await callSessionJavaScript(webView, """
          return {
            hidden: document.documentElement.hasAttribute('data-grock-picking-menu'),
            focus: document.activeElement.id,
            wrongMenu: document.body.dataset.wrongMenu || 'false'
          };
        """) as? [String: Any]
        XCTAssertEqual(cleanup?["hidden"] as? Bool, false)
        XCTAssertEqual(cleanup?["focus"] as? String, "confirm-delete")
        XCTAssertEqual(cleanup?["wrongMenu"] as? String, "false")

        // A remounted trigger with no handler must not reuse the closed source
        // menu, choose the unrelated menu, or leave the page's menus hidden.
        let failed = try await callSessionJavaScript(webView, """
          document.getElementById('confirm-delete').remove();
          var more = document.getElementById('more');
          more.replaceWith(more.cloneNode(true));
          var state = await window.__grockChrome.inspectSessionMenu();
          return {
            pin: state.pin,
            hidden: document.documentElement.hasAttribute('data-grock-picking-menu')
          };
        """) as? [String: Any]
        XCTAssertEqual(failed?["pin"] as? String, "missing")
        XCTAssertEqual(failed?["hidden"] as? Bool, false)
    }

    @MainActor
    private func evaluateSessionCluster(html: String, url: String) async throws -> [String: Bool] {
        let webView = try await loadSessionFixture(html: html, url: url)
        let script = """
        (function () {
          if (window.__grockChrome && window.__grockChrome.set) window.__grockChrome.set();
          var cluster = document.getElementById('cluster');
          var more = cluster && cluster.querySelector('[aria-label="More"]');
          var share = cluster && cluster.querySelector('[aria-label="Share"]');
          var panel = cluster && cluster.querySelector('[aria-label="Toggle panel"]');
          var state = window.__grockChrome && window.__grockChrome.session
            ? window.__grockChrome.session()
            : { more: false, share: false, panel: false };
          var hidden = false;
          if (cluster) {
            var cs = window.getComputedStyle(cluster);
            hidden = cs.display === 'none'
              || cluster.hasAttribute('data-grock-session-cluster')
              || !!(cluster.closest && cluster.closest('[data-grock-session-cluster]'));
          }
          return {
            cluster: !!(cluster && cluster.hasAttribute('data-grock-session-cluster')),
            more: !!(more && more.hasAttribute('data-grock-session-more')),
            share: !!(share && share.hasAttribute('data-grock-session-share')),
            panel: !!(panel && panel.hasAttribute('data-grock-session-panel')),
            hidden: hidden,
            sessionMore: !!state.more,
            sessionShare: !!state.share,
            sessionPanel: !!state.panel
          };
        })()
        """
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let dict = result as? [String: Any] else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GrockTests",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "session cluster was not a dictionary"]
                        )
                    )
                    return
                }
                func flag(_ key: String) -> Bool {
                    if let value = dict[key] as? Bool { return value }
                    if let value = dict[key] as? NSNumber { return value.boolValue }
                    return false
                }
                continuation.resume(returning: [
                    "cluster": flag("cluster"),
                    "more": flag("more"),
                    "share": flag("share"),
                    "panel": flag("panel"),
                    "hidden": flag("hidden"),
                    "sessionMore": flag("sessionMore"),
                    "sessionShare": flag("sessionShare"),
                    "sessionPanel": flag("sessionPanel")
                ])
            }
        }
    }

    @MainActor
    private func loadSessionFixture(
        html: String,
        url: String,
        sessionBridge: SessionActionsBridge? = nil
    ) async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        if let sessionBridge {
            config.userContentController.addScriptMessageHandler(
                SessionFixtureBridge(bridge: sessionBridge),
                contentWorld: .page,
                name: SessionActionsBridge.channelName
            )
        }
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebViewStore.chromeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFront(nil)
        webView.layoutSubtreeIfNeeded()
        let loaded = expectation(description: "session-cluster-html")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: url))
        await fulfillment(of: [loaded], timeout: 4)
        return webView
    }

    @MainActor
    private func callSessionJavaScript(_ webView: WKWebView, _ script: String) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result.map(Optional.some))
            }
        }
    }

    @MainActor
    private func evaluateContentInsetLayout(html: String) async throws -> [String: Any] {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebViewStore.chromeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFront(nil)
        webView.layoutSubtreeIfNeeded()
        let loaded = expectation(description: "inset-html")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: "https://grok.com/c/fixture"))
        await fulfillment(of: [loaded], timeout: 4)
        let script = """
        (function () {
          if (window.__grockChrome && window.__grockChrome.set) window.__grockChrome.set();
          function marked(id, attr) {
            var el = document.getElementById(id);
            return !!(el && el.getAttribute(attr));
          }
          var composer = document.getElementById('composer');
          var toolbar = document.getElementById('code-toolbar');
          var nav = document.getElementById('nav');
          var cbox = composer ? composer.getBoundingClientRect() : null;
          var tstyle = toolbar ? window.getComputedStyle(toolbar).position : '';
          return {
            threadInset: marked('thread', 'data-grock-content-inset'),
            navInset: marked('nav', 'data-grock-content-inset') || marked('nav', 'data-grock-home-inset'),
            colInset: marked('col', 'data-grock-content-inset') || marked('col', 'data-grock-home-inset'),
            composerOnScreen: !!(cbox && cbox.bottom <= (window.innerHeight + 1) && cbox.height >= 80),
            toolbarRelative: tstyle === 'relative',
            navHeight: nav ? nav.offsetHeight : -1
          };
        })()
        """
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let dict = result as? [String: Any] else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GrockTests",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "inset layout was not a dictionary"]
                        )
                    )
                    return
                }
                func flag(_ key: String) -> Bool {
                    if let value = dict[key] as? Bool { return value }
                    if let value = dict[key] as? NSNumber { return value.boolValue }
                    return false
                }
                func intVal(_ key: String) -> Int {
                    if let value = dict[key] as? Int { return value }
                    if let value = dict[key] as? NSNumber { return value.intValue }
                    return -1
                }
                continuation.resume(returning: [
                    "threadInset": flag("threadInset"),
                    "navInset": flag("navInset"),
                    "colInset": flag("colInset"),
                    "composerOnScreen": flag("composerOnScreen"),
                    "toolbarRelative": flag("toolbarRelative"),
                    "navHeight": intVal("navHeight")
                ])
            }
        }
    }

    @MainActor
    private func evaluatePromoMarks(html: String) async throws -> [String: Bool] {
        let script = """
        (function () {
          if (window.__grockChrome && window.__grockChrome.set) window.__grockChrome.set();
          function hidden(id) {
            var el = document.getElementById(id);
            if (!el) return false;
            return !!(el.hasAttribute('data-grock-hide')
              || el.querySelector('[data-grock-hide]')
              || el.closest('[data-grock-hide]'));
          }
          function undrawn(id) {
            return getComputedStyle(document.getElementById(id)).display === 'none';
          }
          return {
            finance: hidden('finance-promo'),
            imagine: hidden('imagine-promo'),
            tos: hidden('tos-dialog'),
            billing: hidden('billing-toast'),
            xConnect: hidden('x-connect'),
            grokBot: hidden('grok-bot-promo'),
            buildMode: undrawn('build-mode-promo'),
            buildModeDialog: undrawn('build-mode-dialog'),
            otherPopover: undrawn('other-popover'),
            unifyCard: undrawn('unify-card'),
            unifyElsewhere: undrawn('unify-elsewhere'),
            noPromoClick: window.promoClicked !== true
          };
        })()
        """
        let result = try await evaluateChromeFixture(html: html, url: "https://grok.com/", script: script)
        return result.mapValues { ($0 as? NSNumber)?.boolValue ?? false }
    }

    /// Loads `html` at `url` with the production chrome script in an 800×600
    /// window and returns what `script` evaluates to.
    @MainActor
    private func evaluateChromeFixture(html: String, url: String, script: String) async throws -> [String: Any] {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebViewStore.chromeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFront(nil)
        webView.layoutSubtreeIfNeeded()
        let loaded = expectation(description: "chrome-fixture")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: url))
        await fulfillment(of: [loaded], timeout: 4)
        _ = window
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let dict = result as? [String: Any] {
                    continuation.resume(returning: dict)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GrockTests",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "fixture script did not return a dictionary"]
                        )
                    )
                }
            }
        }
    }

    @MainActor
    private func evaluateReplyState(html: String) async throws -> [String: Bool] {
        try await evaluateReplyScript(
            html: html,
            script: "window.__grockReply.state()"
        )
    }

    @MainActor
    private func evaluateReplyString(html: String, script: String) async throws -> String {
        let (webView, window) = try await loadReplyObserver(html: html)
        _ = window
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (result as? String) ?? "")
                }
            }
        }
    }

    @MainActor
    private func evaluateReplyScript(html: String, script: String) async throws -> [String: Bool] {
        let (webView, window) = try await loadReplyObserver(html: html)
        _ = window
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let dict = result as? [String: Any] else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GrockTests",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "reply state was not a dictionary"]
                        )
                    )
                    return
                }
                func flag(_ key: String) -> Bool {
                    if let value = dict[key] as? Bool { return value }
                    if let value = dict[key] as? NSNumber { return value.boolValue }
                    return false
                }
                continuation.resume(returning: [
                    "busy": flag("busy"),
                    "generating": flag("generating")
                ])
            }
        }
    }

    @MainActor
    private func loadReplyObserver(html: String) async throws -> (WKWebView, NSWindow) {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(
                source: WebViewStore.replyObserverScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFront(nil)
        webView.layoutSubtreeIfNeeded()
        let loaded = expectation(description: "reply-html")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: "https://grok.com/"))
        await fulfillment(of: [loaded], timeout: 4)
        return (webView, window)
    }

    @MainActor
    private func evaluatePlaceTitle(html: String, url: String) async throws -> String {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        let loaded = expectation(description: "place-title-html")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: url))
        await fulfillment(of: [loaded], timeout: 4)
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(WebViewStore.placeTitleScript) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (result as? String) ?? "")
                }
            }
        }
    }
}

private final class PlaceTitleHTMLLoader: NSObject, WKNavigationDelegate {
    private let loaded: XCTestExpectation
    private var didFulfill = false

    init(expectation: XCTestExpectation) {
        loaded = expectation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish()
    }

    private func finish() {
        guard !didFulfill else { return }
        didFulfill = true
        loaded.fulfill()
    }
}

/// These fixtures exercise page-script state reporting with loadHTMLString's
/// synthetic origin. Native production sender authorization is tested separately.
private final class SessionFixtureBridge: NSObject, WKScriptMessageHandlerWithReply {
    let bridge: SessionActionsBridge
    init(bridge: SessionActionsBridge) { self.bridge = bridge }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @Sendable (Any?, String?) -> Void) {
        let body = message.body as? [String: Any] ?? [:]
        DispatchQueue.main.async { [bridge] in bridge.handler?(message.webView, body) }
        replyHandler(["ok": true], nil)
    }
}
