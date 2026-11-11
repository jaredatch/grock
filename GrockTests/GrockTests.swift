import AppKit
import Carbon
import CoreGraphics
import WebKit
import XCTest
@testable import Grock

final class GrockTests: XCTestCase {
    // MARK: - New chat, Search, Plugins, Private

    /// A conversation page whose New chat controls record which one was clicked.
    private static let freshSessionFixture = GrokShellFixture.page(
        header: GrokShellFixture.conversationHeader,
        outside: """
        <script>
          window.clicked = [];
          ['new-chat', 'chats-new-chat', 'project-new-chat'].forEach(function (id) {
            document.getElementById(id).addEventListener('click', function () { window.clicked.push(id); });
          });
        </script>
        """
    )

    @MainActor
    func testFreshSessionClicksTheSidebarNewChatRow() async throws {
        let run = try await runPageScripts(
            [WebViewStore.freshSessionScript],
            html: Self.freshSessionFixture,
            url: "https://grok.com/c/fixture",
            probe: "{ clicked: window.clicked, previousPath: window.__grockPreviousPath || '' }"
        )
        XCTAssertEqual(run.results, ["clicked"])
        // The row's text is "New chat" plus its shortcut hint; the label span decides.
        XCTAssertEqual(run.page["clicked"] as? [String], ["new-chat"])
        XCTAssertEqual(run.page["previousPath"] as? String, "/c/fixture")
    }

    @MainActor
    func testFreshSessionLeavesTheStartPageAlone() async throws {
        let run = try await runPageScripts(
            [WebViewStore.freshSessionScript],
            html: Self.freshSessionFixture,
            url: "https://grok.com/",
            probe: "{ clicked: window.clicked }"
        )
        XCTAssertEqual(run.results, ["already-fresh"])
        XCTAssertEqual(run.page["clicked"] as? [String], [])
    }

    @MainActor
    func testFreshSessionNeverUsesAProjectNewChatButton() async throws {
        let run = try await runPageScripts(
            [
                "document.getElementById('new-chat').remove(); 'removed'",
                WebViewStore.freshSessionScript,
                "document.getElementById('chats-new-chat').remove(); 'removed'",
                WebViewStore.freshSessionScript
            ],
            html: Self.freshSessionFixture,
            url: "https://grok.com/c/fixture",
            probe: "{ clicked: window.clicked }"
        )
        // Without the row, the Chats header's New chat button still counts.
        // "New chat in Untitled project" never does.
        XCTAssertEqual(run.results, ["removed", "clicked", "removed", "missing"])
        XCTAssertEqual(run.page["clicked"] as? [String], ["chats-new-chat"])
    }

    @MainActor
    func testFreshSessionDoesNothingOffGrok() async throws {
        let run = try await runPageScripts(
            [WebViewStore.freshSessionScript],
            html: Self.freshSessionFixture,
            url: "https://accounts.x.ai/c/fixture",
            probe: "{ clicked: window.clicked }"
        )
        XCTAssertEqual(run.results, ["missing"])
        XCTAssertEqual(run.page["clicked"] as? [String], [])
    }

    @MainActor
    func testImaginePathLandsOnTheStartPage() {
        XCTAssertEqual(WebViewStore.landingPath("/imagine"), "")
        XCTAssertEqual(WebViewStore.landingPath("/imagine/"), "")
        XCTAssertEqual(WebViewStore.landingPath("imagine"), "")
        XCTAssertEqual(WebViewStore.landingPath("/"), "")
        XCTAssertEqual(WebViewStore.landingPath("/c/abc"), "c/abc")
        XCTAssertEqual(WebViewStore.landingPath("/imagine/saved"), "imagine/saved")
    }

    /// grok.com's Search button sits in the leading chrome the titlebar hides.
    /// The right pane has a Search of its own, earlier in the document.
    private static func searchFixture(dialogs: String = "") -> String {
        """
        <!DOCTYPE html>
        <html>
        <body style="margin:0">
          <div id="grok-app-root">
            <div><aside id="app-sidebar" aria-label="App navigation"></aside></div>
            <section>
              <div id="grok-content-area" role="main"></div>
              <aside id="right-pane" aria-label="Right pane">
                <button id="pane-search" aria-label="Search" style="width:28px;height:28px"></button>
              </aside>
            </section>
            <span data-leading-chrome style="display:none">
              <button aria-label="Toggle sidebar" aria-controls="app-sidebar" aria-expanded="true"></button>
              <button id="search" aria-label="Search"></button>
            </span>
          </div>
          <div id="consent" role="dialog" aria-label="Privacy Preference Center" inert hidden>
            <input role="searchbox">
          </div>
          \(dialogs)
          <script>
            window.searchClicks = 0; window.paneClicks = 0; window.escapes = 0;
            document.getElementById('pane-search').addEventListener('click', function () { window.paneClicks++; });
            document.getElementById('search').addEventListener('click', function () {
              window.searchClicks++;
              var menu = document.createElement('div');
              menu.id = 'command-menu';
              menu.setAttribute('role', 'dialog');
              menu.setAttribute('data-analytics-name', 'command_menu');
              menu.setAttribute('data-open', '');
              menu.style.cssText = 'position:fixed;top:18vh;left:40px;width:720px;height:300px';
              menu.innerHTML = '<input role="combobox" aria-label="Search"><div role="listbox"></div>';
              document.body.appendChild(menu);
            });
            document.addEventListener('keydown', function (event) {
              if (event.key !== 'Escape') return;
              window.escapes++;
              var menu = document.getElementById('command-menu');
              if (menu) menu.remove();
            });
          </script>
        </body>
        </html>
        """
    }

    private static let searchProbe = """
    { searchClicks: window.searchClicks, paneClicks: window.paneClicks, escapes: window.escapes,
      menuOpen: !!document.getElementById('command-menu'), settingsOpen: !!document.getElementById('settings') }
    """

    @MainActor
    func testSearchScriptsOpenAndCloseTheCommandMenu() async throws {
        let run = try await runPageScripts(
            [
                WebViewStore.openSearchScript, WebViewStore.openSearchScript,
                WebViewStore.toggleSearchScript, WebViewStore.toggleSearchScript
            ],
            html: Self.searchFixture(),
            url: "https://grok.com/",
            probe: Self.searchProbe
        )
        XCTAssertEqual(run.results, ["opened", "already-open", "closed", "opened"])
        XCTAssertEqual(run.page["searchClicks"] as? Int, 2)
        XCTAssertEqual(run.page["paneClicks"] as? Int, 0)
        XCTAssertEqual(run.page["escapes"] as? Int, 1)
        XCTAssertEqual(run.page["menuOpen"] as? Bool, true)
    }

    @MainActor
    func testSettingsSearchFieldIsNotTheCommandMenu() async throws {
        let settings = """
        <div id="settings" role="dialog" data-open style="position:fixed;top:56px;left:40px;width:700px;height:400px">
          <h2>Settings</h2>
          <input type="search" aria-label="Search settings">
          <button>Account</button><button>Appearance</button>
        </div>
        """
        let run = try await runPageScripts(
            [WebViewStore.toggleSearchScript, WebViewStore.openSearchScript, WebViewStore.toggleSearchScript],
            html: Self.searchFixture(dialogs: settings),
            url: "https://grok.com/",
            probe: Self.searchProbe
        )
        // Settings up, Search closed: the toggle opens Search. It does not
        // read Settings as an open Search and press Escape on it.
        XCTAssertEqual(run.results, ["opened", "already-open", "closed"])
        XCTAssertEqual(run.page["searchClicks"] as? Int, 1)
        XCTAssertEqual(run.page["escapes"] as? Int, 1)
        XCTAssertEqual(run.page["menuOpen"] as? Bool, false)
        XCTAssertEqual(run.page["settingsOpen"] as? Bool, true)
    }

    @MainActor
    func testADialogBuiltAroundAComboboxCountsAsOpenSearch() async throws {
        let unnamed = """
        <div id="palette" role="dialog" data-open style="position:fixed;top:18vh;left:40px;width:720px;height:300px">
          <input role="combobox" aria-label="Search">
        </div>
        """
        let open = try await runPageScripts(
            [WebViewStore.openSearchScript],
            html: Self.searchFixture(dialogs: unnamed),
            url: "https://grok.com/",
            probe: Self.searchProbe
        )
        XCTAssertEqual(open.results, ["already-open"])
        XCTAssertEqual(open.page["searchClicks"] as? Int, 0)

        let bare = try await runPageScripts(
            [WebViewStore.openSearchScript, WebViewStore.toggleSearchScript],
            html: "<!DOCTYPE html><html><body><div id=\"grok-content-area\" role=\"main\"></div></body></html>",
            url: "https://grok.com/"
        )
        XCTAssertEqual(bare.results, ["missing", "missing"])
    }

    @MainActor
    func testPluginsOpensSettingsFromConnectApps() async throws {
        let html = GrokShellFixture.page(outside: """
        <script>
          window.connectClicks = 0;
          document.getElementById('connect').addEventListener('click', function () {
            window.connectClicks++;
            var settings = document.createElement('div');
            settings.setAttribute('role', 'dialog');
            settings.setAttribute('data-open', '');
            settings.style.cssText = 'position:fixed;top:56px;left:40px;width:700px;height:400px';
            settings.innerHTML = '<h2>Settings</h2><button>Connect Apps</button><button>Skills</button>';
            document.body.appendChild(settings);
          });
        </script>
        """)
        let run = try await runPageScripts(
            [WebViewStore.openPluginsScript, WebViewStore.openPluginsScript],
            html: html,
            url: "https://grok.com/",
            probe: "{ connectClicks: window.connectClicks }"
        )
        XCTAssertEqual(run.results, ["opened", "already-open"])
        XCTAssertEqual(run.page["connectClicks"] as? Int, 1)

        let missing = try await runPageScripts(
            ["document.getElementById('connect').remove(); 'removed'", WebViewStore.openPluginsScript],
            html: html,
            url: "https://grok.com/",
            probe: "{ connectClicks: window.connectClicks }"
        )
        XCTAssertEqual(missing.results, ["removed", "missing"])
        XCTAssertEqual(missing.page["connectClicks"] as? Int, 0)
    }

    @MainActor
    func testPrivateTogglesTheHeaderButtonInBothDirections() async throws {
        // A chat that happens to be called Private sits in the sidebar, ahead
        // of the real control in the document.
        let html = GrokShellFixture.page(outside: """
        <script>
          window.privateLabels = []; window.sidebarClicks = 0;
          var row = document.querySelector('#other-chat-row [data-sidebar-item-label]');
          row.textContent = 'Private';
          document.getElementById('other-chat-row').addEventListener('click', function () { window.sidebarClicks++; });
          var toggle = document.getElementById('private');
          toggle.addEventListener('click', function () {
            window.privateLabels.push(toggle.getAttribute('aria-label'));
            var entering = toggle.getAttribute('aria-pressed') !== 'true';
            toggle.setAttribute('aria-pressed', String(entering));
            toggle.setAttribute('aria-label', entering ? 'Exit Private Chat' : 'Switch to Private Chat');
            // Only the label says what the control is once it is pressed.
            toggle.textContent = entering ? '' : 'Private';
          });
        </script>
        """)
        let run = try await runPageScripts(
            [WebViewStore.privateChatScript, WebViewStore.privateChatScript],
            html: html,
            url: "https://grok.com/",
            probe: "{ labels: window.privateLabels, sidebarClicks: window.sidebarClicks }"
        )
        XCTAssertEqual(run.results, ["clicked", "clicked"])
        XCTAssertEqual(run.page["labels"] as? [String], ["Switch to Private Chat", "Exit Private Chat"])
        XCTAssertEqual(run.page["sidebarClicks"] as? Int, 0)

        let missing = try await runPageScripts(
            ["document.getElementById('private').remove(); 'removed'", WebViewStore.privateChatScript],
            html: html,
            url: "https://grok.com/",
            probe: "{ sidebarClicks: window.sidebarClicks }"
        )
        XCTAssertEqual(missing.results, ["removed", "missing"])
        XCTAssertEqual(missing.page["sidebarClicks"] as? Int, 0)
    }

    @MainActor
    func testPageBackdropMatchesGrokPageFill() throws {
        func backdrop(_ name: NSAppearance.Name) throws -> [Int] {
            var resolved: NSColor?
            try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                resolved = AppearancePreference.pageBackdrop.usingColorSpace(.sRGB)
            }
            let color = try XCTUnwrap(resolved)
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        // grok.com's --grok-chrome: #F9F8F7 light, #1E1D1D dark.
        XCTAssertEqual(try backdrop(.aqua), [0xF9, 0xF8, 0xF7, 255])
        XCTAssertEqual(try backdrop(.darkAqua), [0x1E, 0x1D, 0x1D, 255])
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

    /// grok.com swaps Voice mode, Send, and Stop through one composer slot.
    @MainActor
    func testReplyObserverPostsLandedWhenStopLeavesTheComposer() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body>
          <div id="grok-content-area" role="main">
            <form data-composer>
              <div contenteditable="true" role="textbox" aria-label="Message Grok" style="width:300px;height:24px"></div>
              <button id="action" type="button" aria-label="Voice mode" data-composer-action="voice"
                      style="width:32px;height:32px"></button>
            </form>
          </div>
        </body>
        </html>
        """
        let recorder = ReplyFixtureRecorder()
        let landed = expectation(description: "reply-landed")
        recorder.onMessage = { body in
            if body["kind"] as? String == "landed" { landed.fulfill() }
        }
        let (webView, window) = try await loadReplyObserver(html: html, recorder: recorder)
        _ = window
        let seen = try await callSessionJavaScript(webView, """
          var action = document.getElementById('action');
          var seen = [window.__grockReply.state().generating];
          action.setAttribute('aria-label', 'Stop');
          await new Promise(resolve => setTimeout(resolve, 50));
          seen.push(window.__grockReply.state().generating);
          action.setAttribute('aria-label', 'Voice mode');
          await new Promise(resolve => setTimeout(resolve, 50));
          seen.push(window.__grockReply.state().generating);
          return seen;
        """) as? [Bool]
        XCTAssertEqual(seen, [false, true, false])
        await fulfillment(of: [landed], timeout: 4)
        XCTAssertEqual(recorder.kinds, ["state:true", "state:false", "landed"])
    }

    /// The Copy button under an answer lives in a footer below it. Scrolling
    /// to that would show the end of the answer, not its start.
    @MainActor
    func testReplyObserverScrollsToTheStartOfTheLastAnswer() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <body style="margin:0;overflow:hidden">
          <div id="grok-content-area" role="main" style="height:300px;overflow:hidden">
            <div id="transcript" role="log" data-testid="chat-transcript-scroller"
                 style="height:300px;overflow-y:scroll">
              <div data-testid="user-message"><span data-bubble-text>First question</span></div>
              <div data-testid="assistant-message" style="height:500px">First answer</div>
              <div data-testid="response-footer-actions">
                <button aria-label="Copy response" style="width:20px;height:20px"></button>
              </div>
              <div data-testid="user-message"><span data-bubble-text>Second question</span></div>
              <div id="last-answer" data-testid="assistant-message" style="height:900px">Second answer</div>
              <div id="last-footer" data-testid="response-footer-actions">
                <button aria-label="Copy response" style="width:20px;height:20px"></button>
              </div>
            </div>
            <form data-composer>
              <button aria-label="Voice mode" style="width:32px;height:32px"></button>
            </form>
          </div>
        </body>
        </html>
        """
        let (webView, window) = try await loadReplyObserver(html: html)
        _ = window
        let result = try await callSessionJavaScript(webView, """
          var outcome = window.__grockReply.scrollToAnswer();
          var transcript = document.getElementById('transcript').getBoundingClientRect();
          var answer = document.getElementById('last-answer').getBoundingClientRect();
          return { outcome: outcome, offset: answer.top - transcript.top };
        """) as? [String: Any]
        XCTAssertEqual(result?["outcome"] as? String, "scrolled")
        // The answer starts just below the 52pt titlebar.
        XCTAssertEqual(try XCTUnwrap(result?["offset"] as? Double), 52, accuracy: 1)
    }

    @MainActor
    func testChromeScriptWiresPageHook() async throws {
        // Everything native calls on the page: applyChrome, probeSessionActions,
        // clickSessionAction, inspectSessionMenu.
        let surface = try await evaluateChromeFixture(
            html: "<!DOCTYPE html><html><body><div id=\"grok-content-area\" role=\"main\"></div></body></html>",
            url: "https://grok.com/",
            script: """
            (function () {
              var api = window.__grockChrome || {};
              return {
                set: typeof api.set, session: typeof api.session,
                clickSession: typeof api.clickSession, inspectSessionMenu: typeof api.inspectSessionMenu
              };
            })()
            """
        )
        for name in ["set", "session", "clickSession", "inspectSessionMenu"] {
            XCTAssertEqual(surface[name] as? String, "function", name)
        }
        // The page script and the panel agree on the titlebar's height.
        XCTAssertEqual(PanelGeometry.fallbackTitlebarInset, 52)
        XCTAssertTrue(WebViewStore.chromeScript.contains("--grock-titlebar:52px"))
        XCTAssertTrue(WebViewStore.focusInputScript.contains("[contenteditable]"))
        XCTAssertTrue(WebViewStore.focusInputScript.contains("attempt(tries"))
        XCTAssertEqual(TitleDestination.history.href, "/history")
        XCTAssertEqual(TitleDestination.library.href, "/library")
        XCTAssertEqual(TitleDestination.library.title, "Library")
        XCTAssertNil(TitleDestination.plugins.href)
        XCTAssertEqual(TitleDestination.plugins.title, "Plugins")
        XCTAssertNil(TitleDestination.projects.href)
        XCTAssertEqual(TitleDestination.imagine.href, "/imagine")
        XCTAssertEqual(SessionActionsBridge.channelName, "grockSession")
    }

    /// The name grok.com prints over the chat wins. Reply headings, the
    /// sidebar, and the tab title are fallbacks.
    @MainActor
    func testPlaceTitleUsesConversationHeadingNotReplyHeading() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Stale tab title - Grok</title></head>
        <body>
          <aside id="app-sidebar" style="display:none">
            <button aria-current="true"><span data-sidebar-item-label>Sidebar row title</span></button>
          </aside>
          <div id="grok-content-area" role="main">
            <header data-header-over-column>
              <div data-testid="conversation-title"><span data-sidebar-item-label>Example chat</span></div>
            </header>
            <h2>A heading inside the reply</h2>
          </div>
        </body>
        </html>
        """
        let title = try await evaluatePlaceTitle(
            html: html,
            url: "https://grok.com/c/abc"
        )
        XCTAssertEqual(title, "Example chat")
    }

    @MainActor
    func testPlaceTitleFallsBackToTheCurrentSidebarRow() async throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Grok</title></head>
        <body>
          <aside id="app-sidebar" style="display:none">
            <button><span data-sidebar-item-label>Another chat</span></button>
            <button aria-current="true"><span data-sidebar-item-label>Example chat</span><span>2h</span></button>
            <button aria-label="Actions for Example chat" aria-haspopup="menu"></button>
          </aside>
          <div id="grok-content-area" role="main">
            <h2>A heading inside the reply</h2>
          </div>
        </body>
        </html>
        """
        let title = try await evaluatePlaceTitle(
            html: html,
            url: "https://grok.com/c/abc"
        )
        XCTAssertEqual(title, "Example chat")
    }

    @MainActor
    func testPlaceTitleIgnoresReplyHeadingWhenDocumentTitleIsTheThread() async throws {
        func page(title: String) -> String {
            """
            <!DOCTYPE html>
            <html>
            <head><title>\(title)</title></head>
            <body>
              <div id="grok-content-area" role="main">
                <h2>A heading inside the reply</h2>
              </div>
            </body>
            </html>
            """
        }
        // Every grok.com page is titled "<name> - Grok".
        for (documentTitle, expected) in [
            ("Example chat - Grok", "Example chat"),
            ("Example chat | Grok", "Example chat"),
            ("Grok", ""),
            ("Privacy Preference Center - Grok", "")
        ] {
            let title = try await evaluatePlaceTitle(
                html: page(title: documentTitle),
                url: "https://grok.com/c/abc"
            )
            XCTAssertEqual(title, expected, documentTitle)
        }
    }

    @MainActor
    func testPlaceTitleNamesPlacesFromThePath() async throws {
        // A heading and a tab title are on the page; the path still decides.
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Example chat - Grok</title></head>
        <body>
          <div id="grok-content-area" role="main">
            <header data-header-over-column>
              <div data-testid="conversation-title"><span data-sidebar-item-label>Example chat</span></div>
            </header>
          </div>
        </body>
        </html>
        """
        for (address, expected) in [
            ("https://grok.com/", "Grok"),
            ("https://grok.com/library", "Library"),
            ("https://grok.com/files", "Library"),
            ("https://grok.com/files/abc", "Library"),
            ("https://grok.com/history", "History"),
            ("https://grok.com/project", "Projects"),
            ("https://grok.com/project/abc", "Example chat"),
            ("https://accounts.x.ai/c/abc", "")
        ] {
            let title = try await evaluatePlaceTitle(html: html, url: address)
            XCTAssertEqual(title, expected, address)
        }
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
        // Signed out, only New Chat can be chosen: the rest are sign-in walls.
        let signedOutMenu = NSMenu()
        TitleDestination.rebuildMenu(
            signedOutMenu,
            pref: pref,
            signedIn: false,
            target: NSObject(),
            action: #selector(NSObject.description)
        )
        let choosable = signedOutMenu.items.filter { !$0.isSeparatorItem && $0.isEnabled }.map(\.title)
        XCTAssertEqual(choosable, ["New Chat"])
        XCTAssertFalse(signedOutMenu.autoenablesItems)
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled))

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
            ["Pin", "Toggle Right Pane", "Archive"]
        )
        panel.sessionPinned = true
        panel.rebuildSessionMoreMenu()
        XCTAssertEqual(
            panel.sessionMoreMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Unpin", "Toggle Right Pane", "Archive"]
        )
        // Offered only once grok.com's own menu has been seen to offer it.
        panel.sessionProjectAvailable = true
        panel.rebuildSessionMoreMenu()
        XCTAssertEqual(
            panel.sessionMoreMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Unpin", "Add to Project…", "Toggle Right Pane", "Archive"]
        )
        panel.sessionProjectAvailable = false

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

    // MARK: - Page chrome (DEC-071)

    private static let homeFixture = GrokShellFixture.page(content: GrokShellFixture.hero)

    private static let conversationFixture = GrokShellFixture.page(
        header: GrokShellFixture.conversationHeader,
        content: GrokShellFixture.transcript + GrokShellFixture.composer,
        title: "Example chat - Grok"
    )

    /// Read-only helpers for fixture scripts. `gone` is display:none on the
    /// node or an ancestor; `blanked` keeps the box but cannot be seen or hit.
    private static let domProbes = """
    function node(id) { return document.getElementById(id); }
    function gone(id) { var el = node(id); return !el || el.getClientRects().length === 0; }
    function blanked(id) {
      if (gone(id)) return false;
      var style = getComputedStyle(node(id));
      return style.visibility === 'hidden' && style.pointerEvents === 'none';
    }
    function seen(id) { return !gone(id) && getComputedStyle(node(id)).visibility !== 'hidden'; }
    function sleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }

    """

    @MainActor
    func testSidebarIsShownInFullOrGoneAndLeadingChromeStaysHidden() async throws {
        let webView = try await loadSessionFixture(html: Self.homeFixture, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          return [true, false, true].map(function (hidden) {
            window.__grockChrome.set({ sidebarHidden: hidden });
            return {
              sidebarGone: gone('app-sidebar'), boxGone: gone('sidebar-box'),
              mainLeft: node('grok-content-area').getBoundingClientRect().left,
              leadingGone: gone('leading'), searchGone: gone('search'),
              resize: getComputedStyle(node('resize')).pointerEvents
            };
          });
        """) as? [[String: Any]]
        let states = try XCTUnwrap(result)
        XCTAssertEqual(states.count, 3)
        for (state, hidden) in zip(states, [true, false, true]) {
            let context = "sidebarHidden=\(hidden)"
            XCTAssertEqual(state["sidebarGone"] as? Bool, hidden, context)
            // The wrapper goes too, so the main column takes the width.
            XCTAssertEqual(state["boxGone"] as? Bool, hidden, context)
            XCTAssertEqual(try XCTUnwrap(state["mainLeft"] as? Double), hidden ? 0 : 254, accuracy: 1, context)
            // grok.com's own sidebar toggle and Search sit under the traffic lights.
            XCTAssertEqual(state["leadingGone"] as? Bool, true, context)
            XCTAssertEqual(state["searchGone"] as? Bool, true, context)
            XCTAssertEqual(state["resize"] as? String, "none", context)
        }
    }

    /// The media viewer's Copy, Save, and Close sit in the titlebar's corner,
    /// and Close is the only way out. Other full-window dialogs stay put.
    @MainActor
    func testMediaViewerStartsBelowTheTitlebar() async throws {
        let html = GrokShellFixture.page(content: GrokShellFixture.hero, outside: """
        <div id="viewer-box" role="presentation" style="position:fixed;inset:0">
          <div role="dialog" aria-label="example.png" style="position:absolute;inset:0">
            <div style="position:absolute;top:12px;right:12px">
              <button aria-label="Copy image"></button>
              <button aria-label="Save media"></button>
              <button id="viewer-close" aria-label="Close lightbox" style="width:24px;height:24px"></button>
            </div>
          </div>
        </div>
        <div id="other-box" role="presentation" style="position:fixed;inset:0">
          <div role="dialog" aria-label="Example"><button aria-label="Close">Close</button></div>
        </div>
        """)
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/library")
        let result = try await callSessionJavaScript(webView, """
          function top(id) { return document.getElementById(id).getBoundingClientRect().top; }
          return { viewer: top('viewer-box'), close: top('viewer-close'), other: top('other-box') };
        """) as? [String: Any]
        let tops = try XCTUnwrap(result)
        XCTAssertEqual(try XCTUnwrap(tops["viewer"] as? Double), 52, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(tops["close"] as? Double), 64, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(tops["other"] as? Double), 0, accuracy: 0.5)
    }

    /// grok.com's sidebar is open or collapsed to nothing. When the titlebar
    /// says shown, the script opens it, and reopens it if grok.com closes it.
    @MainActor
    func testShownSidebarKeepsGrokSidebarExpanded() async throws {
        let html = GrokShellFixture.page(content: GrokShellFixture.hero, outside: """
        <script>
          window.toggleClicks = 0; window.stuck = false;
          var sidebarToggle = document.getElementById('sidebar-toggle');
          sidebarToggle.setAttribute('aria-expanded', 'false');
          sidebarToggle.addEventListener('click', function () {
            window.toggleClicks++;
            if (window.stuck) return;
            var open = sidebarToggle.getAttribute('aria-expanded') === 'true';
            sidebarToggle.setAttribute('aria-expanded', String(!open));
          });
        </script>
        """)
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var toggle = node('sidebar-toggle');
          await sleep(300);
          window.__grockChrome.set({ sidebarHidden: true });
          var whileHidden = window.toggleClicks;
          window.__grockChrome.set({ sidebarHidden: false });
          var shown = window.toggleClicks, expanded = toggle.getAttribute('aria-expanded');
          window.__grockChrome.set({ sidebarHidden: false });
          var repeated = window.toggleClicks;
          // grok.com closes it on its own (its shortcut).
          await sleep(450);
          toggle.setAttribute('aria-expanded', 'false');
          await sleep(350);
          var reopened = window.toggleClicks, expandedAgain = toggle.getAttribute('aria-expanded');
          // A toggle that has not caught up yet must not be clicked twice.
          await sleep(450);
          window.stuck = true;
          toggle.setAttribute('aria-expanded', 'false');
          window.__grockChrome.set({ sidebarHidden: false });
          window.__grockChrome.set({ sidebarHidden: false });
          var slow = window.toggleClicks;
          return { whileHidden: whileHidden, shown: shown, expanded: expanded, repeated: repeated,
            reopened: reopened, expandedAgain: expandedAgain, slow: slow };
        """) as? [String: Any]
        XCTAssertEqual(result?["whileHidden"] as? Int, 0)
        XCTAssertEqual(result?["shown"] as? Int, 1)
        XCTAssertEqual(result?["expanded"] as? String, "true")
        XCTAssertEqual(result?["repeated"] as? Int, 1)
        XCTAssertEqual(result?["reopened"] as? Int, 2)
        XCTAssertEqual(result?["expandedAgain"] as? String, "true")
        XCTAssertEqual(result?["slow"] as? Int, 3)
    }

    @MainActor
    func testAppearancePreferencesHideTheirGrokControls() async throws {
        let targets = [
            "hideGrokBot": "bots", "hideProjects": "projects", "hideLibrary": "library",
            "hidePlugins": "connect", "hideDictation": "dictate", "hideVoice": "voice"
        ]
        let webView = try await loadSessionFixture(html: Self.homeFixture, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var prefs = Object.keys(targets).sort();
          var off = { sidebarHidden: false, hidePrivate: false };
          prefs.forEach(function (pref) { off[pref] = false; });
          window.__grockChrome.set(off);
          var out = {};
          prefs.forEach(function (pref) {
            var allSeen = prefs.every(function (other) { return seen(targets[other]); });
            var next = {};
            next[pref] = true;
            window.__grockChrome.set(next);
            var hidden = prefs.filter(function (other) { return gone(targets[other]); })
              .map(function (other) { return targets[other]; });
            next[pref] = false;
            window.__grockChrome.set(next);
            out[pref] = { allSeen: allSeen, hidden: hidden, restored: seen(targets[pref]) };
          });
          return out;
        """, arguments: ["targets": targets]) as? [String: [String: Any]]
        let outcomes = try XCTUnwrap(result)
        XCTAssertEqual(Set(outcomes.keys), Set(targets.keys))
        for (pref, target) in targets {
            XCTAssertEqual(outcomes[pref]?["allSeen"] as? Bool, true, pref)
            XCTAssertEqual(outcomes[pref]?["hidden"] as? [String], [target], pref)
            XCTAssertEqual(outcomes[pref]?["restored"] as? Bool, true, pref)
        }
    }

    /// Send and Stop take Voice mode's place in the composer. Hiding Voice
    /// must never hide them.
    @MainActor
    func testHidingVoiceKeepsSendInTheSameSlot() async throws {
        let webView = try await loadSessionFixture(html: Self.homeFixture, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          window.__grockChrome.set({ hideVoice: true, hideDictation: true });
          var voiceGone = gone('voice');
          var slot = node('voice');
          slot.setAttribute('aria-label', 'Send');
          slot.setAttribute('data-composer-action', 'send');
          var sendSeen = seen('voice');
          slot.setAttribute('aria-label', 'Stop');
          slot.setAttribute('data-composer-action', 'stop');
          return { voiceGone: voiceGone, sendSeen: sendSeen, stopSeen: seen('voice'), attachSeen: seen('attach') };
        """) as? [String: Bool]
        XCTAssertEqual(result, ["voiceGone": true, "sendSeen": true, "stopSeen": true, "attachSeen": true])
    }

    /// Settings lists Bots, Data Controls, Billing, and Usage as tabs. The
    /// sidebar preferences are about the sidebar and stop at its edge.
    @MainActor
    func testSidebarPreferencesLeaveDialogsAndNamesakesAlone() async throws {
        let html = GrokShellFixture.page(content: GrokShellFixture.hero, outside: """
        <div id="settings" role="dialog" data-open style="position:fixed;top:56px;left:40px;width:700px;height:400px">
          <h2>Settings</h2>
          <input type="search" aria-label="Search settings">
          <button id="tab-library"><span data-sidebar-item-label>Library</span></button>
          <button id="tab-connect" aria-label="Connect apps">Connect Apps</button>
          <button id="tab-bots">Bots</button>
          <button id="tab-data">Data Controls</button>
          <button id="tab-billing">Billing</button>
          <button id="tab-usage">Usage</button>
        </div>
        """)
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          // A project that happens to be called Library is not the Library row.
          node('project-row').querySelector('[data-sidebar-item-label]').textContent = 'Library';
          window.__grockChrome.set({ sidebarHidden: false, hideGrokBot: true, hideLibrary: true, hidePlugins: true });
          var tabs = ['tab-library', 'tab-connect', 'tab-bots', 'tab-data', 'tab-billing', 'tab-usage'];
          return {
            botsGone: gone('bots'), libraryGone: gone('library'), connectGone: gone('connect'),
            tabsSeen: tabs.filter(seen),
            dialogMarks: node('settings').querySelectorAll('[data-grock-hide]').length,
            namesakeSeen: seen('project-row')
          };
        """) as? [String: Any]
        XCTAssertEqual(result?["botsGone"] as? Bool, true)
        XCTAssertEqual(result?["libraryGone"] as? Bool, true)
        XCTAssertEqual(result?["connectGone"] as? Bool, true)
        XCTAssertEqual(
            result?["tabsSeen"] as? [String],
            ["tab-library", "tab-connect", "tab-bots", "tab-data", "tab-billing", "tab-usage"]
        )
        XCTAssertEqual(result?["dialogMarks"] as? Int, 0)
        XCTAssertEqual(result?["namesakeSeen"] as? Bool, true)
    }

    /// Private is the only control in the New Chat band. Hidden, the band
    /// keeps its box; shown, it drops below the titlebar. Neither moves the page.
    @MainActor
    func testPrivatePreferenceHidesOrShiftsTheHeaderWithoutMovingTheComposer() async throws {
        let webView = try await loadSessionFixture(html: Self.homeFixture, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var states = [];
          for (var hidden of [true, false, true]) {
            window.__grockChrome.set({ hidePrivate: hidden });
            if (hidden && states.length) {
              // grok.com remounts the band while it is hidden.
              var header = node('page-header');
              header.replaceWith(header.cloneNode(true));
            }
            node('composer').focus();
            node('private').focus();
            states.push({
              flagged: document.documentElement.hasAttribute('data-grock-page-header-hidden'),
              headerBlanked: blanked('page-header'), privateBlanked: blanked('private'),
              privateFocused: document.activeElement.id === 'private',
              headerTop: node('page-header').getBoundingClientRect().top,
              headerHeight: node('page-header').offsetHeight,
              heroTop: node('hero').getBoundingClientRect().top,
              composerTop: node('composer').getBoundingClientRect().top
            });
          }
          return states;
        """) as? [[String: Any]]
        let states = try XCTUnwrap(result)
        XCTAssertEqual(states.count, 3)
        let baseline = try XCTUnwrap(states.first)
        for (state, hidden) in zip(states, [true, false, true]) {
            let context = "hidePrivate=\(hidden)"
            XCTAssertEqual(state["flagged"] as? Bool, hidden, context)
            XCTAssertEqual(state["headerBlanked"] as? Bool, hidden, context)
            XCTAssertEqual(state["privateBlanked"] as? Bool, hidden, context)
            XCTAssertEqual(state["privateFocused"] as? Bool, !hidden, context)
            XCTAssertEqual(try XCTUnwrap(state["headerTop"] as? Double), hidden ? 0 : 52, accuracy: 0.5, context)
            for key in ["headerHeight", "heroTop", "composerTop"] {
                XCTAssertEqual(
                    try XCTUnwrap(state[key] as? Double),
                    try XCTUnwrap(baseline[key] as? Double),
                    accuracy: 0.5, "\(key): \(context)"
                )
            }
        }
    }

    @MainActor
    func testConversationTitleAndActionsBelongToTheTitlebar() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          function snapshot() {
            return {
              titleBlanked: blanked('title'), actionsBlanked: blanked('actions'),
              titleWidth: node('title').getBoundingClientRect().width,
              actionsWidth: node('actions').getBoundingClientRect().width,
              headerBlanked: blanked('page-header'),
              headerTop: node('page-header').getBoundingClientRect().top,
              paneToggleBlanked: blanked('pane-toggle'),
              leadingGone: gone('leading')
            };
          }
          window.__grockChrome.set({ hidePrivate: false });
          var shifted = snapshot();
          window.__grockChrome.set({ hidePrivate: true });
          return { shifted: shifted, hidden: snapshot() };
        """) as? [String: [String: Any]]
        for (name, headerHidden) in [("shifted", false), ("hidden", true)] {
            let state = try XCTUnwrap(result?[name], name)
            // Hidden, not removed: the menu the trigger opens still has an anchor.
            XCTAssertEqual(state["titleBlanked"] as? Bool, true, name)
            XCTAssertEqual(state["actionsBlanked"] as? Bool, true, name)
            XCTAssertGreaterThan(try XCTUnwrap(state["titleWidth"] as? Double), 0, name)
            XCTAssertGreaterThan(try XCTUnwrap(state["actionsWidth"] as? Double), 0, name)
            XCTAssertEqual(state["headerBlanked"] as? Bool, headerHidden, name)
            XCTAssertEqual(try XCTUnwrap(state["headerTop"] as? Double), headerHidden ? 0 : 52, accuracy: 0.5, name)
            XCTAssertEqual(state["paneToggleBlanked"] as? Bool, true, name)
            XCTAssertEqual(state["leadingGone"] as? Bool, true, name)
        }
    }

    @MainActor
    func testConversationPageOffersMoreShareAndPanel() async throws {
        let state = try await evaluateSessionState(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        XCTAssertEqual(state, ["more": true, "share": true, "panel": true, "authenticated": true])
    }

    /// The same controls on any other path are not a conversation's.
    @MainActor
    func testSessionActionsStayOffOutsideConversations() async throws {
        for address in ["https://grok.com/", "https://grok.com/project/fixture", "https://grok.com/library"] {
            let state = try await evaluateSessionState(html: Self.conversationFixture, url: address)
            XCTAssertEqual(state, ["more": false, "share": false, "panel": false, "authenticated": true], address)
        }
    }

    /// The right pane's script, as far as the titlebar cares: closed, it is
    /// inert with its Hide button inside and a floating toggle outside.
    private static let rightPaneFixture = GrokShellFixture.page(
        header: GrokShellFixture.conversationHeader,
        content: GrokShellFixture.transcript + GrokShellFixture.composer,
        outside: """
        <script>
          (function () {
            var pane = document.getElementById('right-pane');
            var box = document.getElementById('pane-yield');
            var toggle = document.getElementById('pane-toggle');
            window.paneClicks = [];
            function setOpen(open) {
              if (open) {
                pane.removeAttribute('inert');
                pane.setAttribute('aria-hidden', 'false');
                pane.style.width = '300px';
                toggle.remove();
              } else {
                pane.setAttribute('inert', '');
                pane.setAttribute('aria-hidden', 'true');
                pane.style.width = '0';
                box.appendChild(toggle);
              }
            }
            toggle.addEventListener('click', function () { window.paneClicks.push('toggle'); setOpen(true); });
            document.getElementById('hide-pane').addEventListener('click', function () {
              window.paneClicks.push('hide');
              setOpen(false);
            });
          })();
        </script>
        """
    )

    @MainActor
    func testPanelActionUsesWhicheverPaneToggleIsLive() async throws {
        let webView = try await loadSessionFixture(html: Self.rightPaneFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var chrome = window.__grockChrome;
          var closed = chrome.session().panel;
          var opened = await chrome.clickSession('panel');
          var open = chrome.session().panel;
          var paneOpen = !node('right-pane').hasAttribute('inert');
          var paneTop = getComputedStyle(node('right-pane')).paddingTop;
          var shut = await chrome.clickSession('panel');
          var toggle = node('pane-toggle');
          toggle.setAttribute('aria-disabled', 'true');
          var disabled = await chrome.clickSession('panel');
          toggle.removeAttribute('aria-disabled');
          toggle.style.display = 'none';
          var undrawn = chrome.session().panel;
          // Only the closed pane's inert Hide button is left.
          toggle.remove();
          var inertOnly = chrome.session().panel;
          var missing = await chrome.clickSession('panel');
          return { closed: closed, opened: opened, open: open, paneOpen: paneOpen, paneTop: paneTop, shut: shut,
            disabled: disabled, undrawn: undrawn, inertOnly: inertOnly, missing: missing, clicks: window.paneClicks };
        """) as? [String: Any]
        XCTAssertEqual(result?["closed"] as? Bool, true)
        XCTAssertEqual(result?["opened"] as? String, "clicked")
        XCTAssertEqual(result?["open"] as? Bool, true)
        XCTAssertEqual(result?["paneOpen"] as? Bool, true)
        // An open pane has a toolbar of its own, so it starts below the titlebar.
        XCTAssertEqual(result?["paneTop"] as? String, "52px")
        XCTAssertEqual(result?["shut"] as? String, "clicked")
        XCTAssertEqual(result?["disabled"] as? String, "unavailable")
        XCTAssertEqual(result?["undrawn"] as? Bool, false)
        XCTAssertEqual(result?["inertOnly"] as? Bool, false)
        XCTAssertEqual(result?["missing"] as? String, "missing")
        XCTAssertEqual(result?["clicks"] as? [String], ["toggle", "hide"])
    }

    /// Share is an item in Conversation Actions now, so both follow that one
    /// trigger: through a remount, without its test id, and while it is busy.
    @MainActor
    func testMoreAndShareFollowTheConversationActionsTrigger() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var chrome = window.__grockChrome;
          function flags() { var state = chrome.session(); return [state.more, state.share]; }
          var out = { initial: flags() };
          var header = node('page-header');
          header.replaceWith(header.cloneNode(true));
          out.remounted = flags();
          out.remountBlanked = blanked('actions');
          node('actions').removeAttribute('data-testid');
          out.byLabel = flags();
          node('actions').setAttribute('aria-busy', 'true');
          out.busy = flags();
          out.busyShare = await chrome.clickSession('share');
          node('actions').removeAttribute('aria-busy');
          node('actions').disabled = true;
          out.disabled = flags();
          node('actions').disabled = false;
          out.ready = flags();
          node('actions').remove();
          out.removed = flags();
          return out;
        """) as? [String: Any]
        XCTAssertEqual(result?["initial"] as? [Bool], [true, true])
        XCTAssertEqual(result?["remounted"] as? [Bool], [true, true])
        XCTAssertEqual(result?["remountBlanked"] as? Bool, true)
        XCTAssertEqual(result?["byLabel"] as? [Bool], [true, true])
        XCTAssertEqual(result?["busy"] as? [Bool], [false, false])
        XCTAssertEqual(result?["busyShare"] as? String, "missing")
        XCTAssertEqual(result?["disabled"] as? [Bool], [false, false])
        XCTAssertEqual(result?["ready"] as? [Bool], [true, true])
        XCTAssertEqual(result?["removed"] as? [Bool], [false, false])
    }

    @MainActor
    func testUnchangedChromeRefreshWritesNothingToThePage() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          window.__grockChrome.set();
          var observer = new MutationObserver(function () {});
          observer.observe(document.documentElement, {
            childList: true, subtree: true, attributes: true, characterData: true
          });
          for (var i = 0; i < 20; i++) window.__grockChrome.set();
          var records = observer.takeRecords();
          observer.disconnect();
          return {
            writes: records.length,
            sheets: document.querySelectorAll('#grock-chrome-style').length,
            hidden: blanked('title')
          };
        """) as? [String: Any]
        XCTAssertEqual(result?["writes"] as? Int, 0)
        XCTAssertEqual(result?["sheets"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
    }

    @MainActor
    func testChromeStylesheetRecoversPrecedenceWithoutFollowingUnrelatedHeadNodes() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          window.__grockChrome.set();
          var sheet = document.getElementById('grock-chrome-style');
          var observer = new MutationObserver(function () {});
          observer.observe(document.head, {childList:true});
          var later = document.createElement('style');
          later.textContent = '[data-leading-chrome]{display:inline-block!important}';
          document.head.appendChild(later);
          var overridden = !gone('leading');
          window.__grockChrome.set();
          var recovered = gone('leading');
          var moved = observer.takeRecords().filter(r => Array.from(r.removedNodes).includes(sheet)).length;
          document.head.appendChild(document.createElement('meta'));
          window.__grockChrome.set();
          var unrelatedMoves = observer.takeRecords().filter(r => Array.from(r.removedNodes).includes(sheet)).length;
          sheet.remove();
          window.__grockChrome.set();
          observer.disconnect();
          return {overridden:overridden, recovered:recovered, moved:moved, unrelatedMoves:unrelatedMoves,
            recreated:document.getElementById('grock-chrome-style') !== sheet,
            sheets:document.querySelectorAll('#grock-chrome-style').length,
            hidden:gone('leading')};
        """) as? [String: Any]
        XCTAssertEqual(result?["overridden"] as? Bool, true)
        XCTAssertEqual(result?["recovered"] as? Bool, true)
        XCTAssertEqual(result?["moved"] as? Int, 1)
        XCTAssertEqual(result?["unrelatedMoves"] as? Int, 0)
        XCTAssertEqual(result?["recreated"] as? Bool, true)
        XCTAssertEqual(result?["sheets"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
    }

    /// Lets the load settle, then replaces rAF with a queue the test drains and
    /// counts the document-wide button scan that only a repaint makes (the
    /// promo pass).
    private static let frameStubs = """
    window.__grockChrome.set();
    await sleep(350);
    var raf = window.requestAnimationFrame, cancel = window.cancelAnimationFrame;
    var query = Document.prototype.querySelectorAll;
    var pending = new Map(), serial = 0, cancelled = 0, repaints = 0;
    window.requestAnimationFrame = function (cb) { pending.set(++serial, cb); return serial; };
    window.cancelAnimationFrame = function (id) { if (pending.delete(id)) cancelled++; };
    Document.prototype.querySelectorAll = function (selector) {
      if (selector === 'button, [role="button"]') repaints++;
      return query.apply(this, arguments);
    };
    function restoreFrames() {
      window.requestAnimationFrame = raf;
      window.cancelAnimationFrame = cancel;
      Document.prototype.querySelectorAll = query;
      pending.clear();
    }

    """

    @MainActor
    func testChromeMutationBurstBatchesFramesAndRepaintsOnce() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + Self.frameStubs + """
          try {
            var column = node('main-column');
            for (var i = 0; i < 50; i++) {
              column.appendChild(document.createElement('span'));
              await Promise.resolve();
            }
            await Promise.resolve();
            var queued = pending.size, immediate = repaints;
            var callbacks = Array.from(pending.values());
            pending.clear();
            callbacks.forEach(cb => cb(performance.now()));
            var afterFrame = repaints;
            column.appendChild(document.createElement('span'));
            await Promise.resolve();
            var nextFrame = pending.size;
            await sleep(350);
            return {queued:queued, immediate:immediate, afterFrame:afterFrame, nextFrame:nextFrame,
              afterTimer:repaints, cancelled:cancelled, left:pending.size};
          } finally {
            restoreFrames();
          }
        """) as? [String: Any]
        XCTAssertEqual(result?["queued"] as? Int, 1)
        XCTAssertEqual(result?["immediate"] as? Int, 0)
        // A frame refreshes the header flag and the session state, nothing wider.
        XCTAssertEqual(result?["afterFrame"] as? Int, 0)
        XCTAssertEqual(result?["nextFrame"] as? Int, 1)
        // 51 mutations, one repaint, and it retires the frame it made redundant.
        XCTAssertEqual(result?["afterTimer"] as? Int, 1)
        XCTAssertEqual(result?["cancelled"] as? Int, 1)
        XCTAssertEqual(result?["left"] as? Int, 0)
    }

    /// A streaming answer and a draft being typed add nodes many times a
    /// second. Neither is chrome, so neither may wake the chrome script.
    @MainActor
    func testStreamingAnswerAndTypingDoNotScheduleChromeWork() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + Self.frameStubs + """
          try {
            for (var i = 0; i < 20; i++) {
              node('answer').appendChild(document.createElement('p'));
              node('composer').appendChild(document.createElement('br'));
              await Promise.resolve();
            }
            await Promise.resolve();
            var streaming = pending.size;
            await sleep(350);
            var streamingRepaints = repaints;
            // The same observer still hears chrome: a busy Conversation Actions.
            node('actions').setAttribute('aria-busy', 'true');
            await Promise.resolve();
            return {streaming:streaming, streamingRepaints:streamingRepaints, chrome:pending.size};
          } finally {
            restoreFrames();
            window.__grockChrome.set();
          }
        """) as? [String: Int]
        XCTAssertEqual(result, ["streaming": 0, "streamingRepaints": 0, "chrome": 1])
    }

    @MainActor
    func testChromeTimerDrainsDeferredWorkWhenAnimationFramesStop() async throws {
        let webView = try await loadSessionFixture(html: Self.conversationFixture, url: "https://grok.com/c/fixture")
        let result = try await callSessionJavaScript(webView, Self.domProbes + Self.frameStubs + """
          try {
            node('main-column').insertAdjacentHTML('beforeend', latePromo);
            await Promise.resolve();
            var queued = pending.size;
            await sleep(350);
            var hidden = gone('late-promo');
            var drained = cancelled;
            var callbacks = serial;
            await sleep(350);
            return {queued:queued, hidden:hidden, drained:drained, idle:serial === callbacks};
          } finally {
            restoreFrames();
            window.__grockChrome.set();
          }
        """, arguments: ["latePromo": Self.promoCard("late-promo", title: "Unlock the full experience")]) as? [String: Any]
        XCTAssertEqual(result?["queued"] as? Int, 1)
        XCTAssertEqual(result?["hidden"] as? Bool, true)
        XCTAssertEqual(result?["drained"] as? Int, 1)
        // Marking the card is our own write; it must not start another pass.
        XCTAssertEqual(result?["idle"] as? Bool, true)
    }

    /// An occluded WebView stops getting frames. A busy trigger still has to
    /// reach the titlebar, and a remounted header is hidden with no script at all.
    @MainActor
    func testHeaderRemountAndBusyTriggerNeedNoAnimationFrame() async throws {
        let bridge = SessionActionsBridge()
        let busyReported = expectation(description: "busy-trigger-without-frame")
        var watching = false
        bridge.handler = { _, body in
            if watching, body["more"] as? Bool == false, body["share"] as? Bool == false {
                watching = false
                busyReported.fulfill()
            }
        }
        let webView = try await loadSessionFixture(
            html: Self.conversationFixture, url: "https://grok.com/c/fixture", sessionBridge: bridge
        )
        watching = true
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          window.__grockChrome.set();
          await sleep(350);
          var raf = window.requestAnimationFrame, cancel = window.cancelAnimationFrame;
          window.requestAnimationFrame = function () { return 12345; };
          window.cancelAnimationFrame = function () {};
          try {
            // The first mutation is unrelated; it must not conceal the header
            // replacement that follows in the same observer delivery.
            node('main-column').appendChild(document.createElement('span'));
            var header = node('page-header');
            header.replaceWith(header.cloneNode(true));
            var hidden = blanked('title') && blanked('actions');
            node('actions').setAttribute('aria-busy', 'true');
            await sleep(350);
            return { hidden: hidden, more: window.__grockChrome.session().more };
          } finally {
            window.requestAnimationFrame = raf;
            window.cancelAnimationFrame = cancel;
          }
        """) as? [String: Bool]
        XCTAssertEqual(result, ["hidden": true, "more": false])
        await fulfillment(of: [busyReported], timeout: 4)
    }

    /// Logged out, the band is the way in: Sign in stays on screen, below the
    /// titlebar, whatever Appearance says about Private.
    @MainActor
    func testLoggedOutHeaderKeepsSignInAndReportsSignedOut() async throws {
        let header = """
        <nav id="page-header" aria-label="Top navigation">
          <a id="home" href="/" aria-label="Home page">Grok</a>
          <span id="band-controls">
            <button id="settings" type="button" aria-label="Settings"></button>
            <a id="signin" href="/sign-in">Sign in</a>
            <a id="signup" href="/sign-up">Sign up</a>
          </span>
        </nav>
        """
        let html = GrokShellFixture.page(header: header, content: GrokShellFixture.hero, signedIn: false)
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          var chrome = window.__grockChrome;
          chrome.set({ hidePrivate: true });
          var out = {
            flagged: document.documentElement.hasAttribute('data-grock-page-header-hidden'),
            headerSeen: seen('page-header'), signInSeen: seen('signin'),
            headerTop: node('page-header').getBoundingClientRect().top,
            homeGone: gone('home'), settingsGone: gone('settings'), signUpGone: gone('signup'),
            authenticated: chrome.session().authenticated
          };
          // Signing in swaps the links for Private and adds the account row.
          node('band-controls').innerHTML =
            '<button id="private" aria-pressed="false" aria-label="Switch to Private Chat">Private</button>';
          node('app-sidebar').insertAdjacentHTML('beforeend',
            '<button data-account-trigger aria-label="Account menu for Example User"></button>');
          chrome.set();
          out.signedInBlanked = blanked('page-header');
          out.signedInAuthenticated = chrome.session().authenticated;
          return out;
        """) as? [String: Any]
        XCTAssertEqual(result?["flagged"] as? Bool, false)
        XCTAssertEqual(result?["headerSeen"] as? Bool, true)
        XCTAssertEqual(result?["signInSeen"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(result?["headerTop"] as? Double), 52, accuracy: 0.5)
        // Signed out, Sign in is the only thing the band offers.
        XCTAssertEqual(result?["homeGone"] as? Bool, true)
        XCTAssertEqual(result?["settingsGone"] as? Bool, true)
        XCTAssertEqual(result?["signUpGone"] as? Bool, true)
        XCTAssertEqual(result?["authenticated"] as? Bool, false)
        XCTAssertEqual(result?["signedInBlanked"] as? Bool, true)
        XCTAssertEqual(result?["signedInAuthenticated"] as? Bool, true)
    }

    /// The signed-out band in the full shell: a header like the signed-in one,
    /// with the logo, Settings, Sign in, and Sign up. Google's one-tap card
    /// floats over the titlebar's corner; the cookie notice must stay.
    @MainActor
    func testSignedOutShellShowsOnlySignInAndTheCookieNotice() async throws {
        let header = """
        <header id="page-header">
          <a id="home" href="/" aria-label="Home page">Grok</a>
          <span data-context-tray-yield>
            <div>
              <span><button id="settings" type="button" aria-label="Settings" aria-haspopup="menu"></button></span>
              <a id="signin" href="/sign-in?return_to=%2F"><span>Sign in</span></a>
              <a id="signup" href="/sign-up?return_to=%2F"><span>Sign up</span></a>
            </div>
          </span>
        </header>
        """
        let outside = """
        <div id="credential_picker_container" style="position:fixed;top:20px;right:20px;width:390px;height:150px">
          <iframe title="Sign in with Google Dialog"></iframe>
        </div>
        <div id="cookies" role="dialog" aria-label="Cookie notice" data-cookie-banner="true"
             style="position:fixed;right:16px;bottom:16px;width:520px;height:150px">
          <p>We use essential cookies. See our Cookie Policy.</p>
          <button aria-label="Dismiss cookie notice">Close</button>
          <button>Reject All</button><button>Accept All Cookies</button>
        </div>
        """
        let html = GrokShellFixture.page(
            header: header, content: GrokShellFixture.hero, signedIn: false, outside: outside
        )
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, Self.domProbes + """
          window.__grockChrome.set({ hidePrivate: true });
          return {
            signInSeen: seen('signin'), headerTop: node('page-header').getBoundingClientRect().top,
            homeGone: gone('home'), settingsGone: gone('settings'), signUpGone: gone('signup'),
            oneTapGone: gone('credential_picker_container'), cookiesSeen: seen('cookies'),
            authenticated: window.__grockChrome.session().authenticated
          };
        """) as? [String: Any]
        XCTAssertEqual(result?["signInSeen"] as? Bool, true)
        XCTAssertEqual(try XCTUnwrap(result?["headerTop"] as? Double), 52, accuracy: 0.5)
        XCTAssertEqual(result?["homeGone"] as? Bool, true)
        XCTAssertEqual(result?["settingsGone"] as? Bool, true)
        XCTAssertEqual(result?["signUpGone"] as? Bool, true)
        XCTAssertEqual(result?["oneTapGone"] as? Bool, true)
        XCTAssertEqual(result?["cookiesSeen"] as? Bool, true)
        XCTAssertEqual(result?["authenticated"] as? Bool, false)
    }

    /// Sign in can also sit in the sidebar, with an ordinary band over the chat.
    @MainActor
    func testSignInAnywhereInTheShellReportsSignedOut() async throws {
        let html = GrokShellFixture.page(
            content: GrokShellFixture.hero,
            sidebar: "<button id=\"signin\">Sign in</button>",
            signedIn: false
        )
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, """
          var chrome = window.__grockChrome;
          var signedOut = chrome.session().authenticated;
          document.getElementById('signin').remove();
          document.getElementById('app-sidebar').insertAdjacentHTML('beforeend',
            '<button data-account-trigger aria-label="Account menu for Example User"></button>');
          return { signedOut: signedOut, signedIn: chrome.session().authenticated };
        """) as? [String: Bool]
        XCTAssertEqual(result, ["signedOut": false, "signedIn": true])
    }

    /// The sidebar lists the user's own chats, projects, and bots by name. A
    /// name is not a Sign in control, whatever it says.
    @MainActor
    func testSidebarRowsNamedSignInDoNotSignTheUserOut() async throws {
        let webView = try await loadSessionFixture(html: Self.homeFixture, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, """
          var chrome = window.__grockChrome;
          var before = chrome.session().authenticated;
          function rename(id, name) {
            document.getElementById(id).querySelector('[data-sidebar-item-label]').textContent = name;
          }
          rename('other-chat-row', 'Sign in page ideas');
          rename('project-row', 'Log in flow');
          chrome.set();
          return { before: before, after: chrome.session().authenticated };
        """) as? [String: Bool]
        XCTAssertEqual(result, ["before": true, "after": true])
    }

    // MARK: - Promo cards (DEC-047)

    /// grok.com's dismissible card: a region with a call to action and a
    /// Dismiss button, floating in a corner of the main column.
    private static func promoCard(
        _ id: String,
        title: String,
        action: String = "See plans",
        place: String = "right:12px;bottom:12px"
    ) -> String {
        """
        <div id="\(id)" role="region" data-slot="card" aria-label="\(title)"
             style="position:absolute;\(place);width:234px;height:144px">
          <span data-slot="card-body">
            <span data-slot="card-content"><span data-slot="card-title">\(title)</span></span>
            <button type="button" onclick="window.promoClicked = true"><span>\(action)</span></button>
          </span>
          <button type="button" aria-label="Dismiss" onclick="window.promoClicked = true"></button>
        </div>
        """
    }

    @MainActor
    func testChromeScriptHidesPromoCardsAndSkipsAccountNotices() async throws {
        let cards = [
            Self.promoCard("plans", title: "Unlock the full experience"),
            Self.promoCard("feature", title: "Now with example feature", action: "Try it", place: "right:12px;top:60px"),
            Self.promoCard("expired", title: "Your subscription expired"),
            Self.promoCard("limit", title: "You are close to your usage limit"),
            Self.promoCard("terms", title: "We've updated our Terms of Service", action: "Try again"),
            Self.promoCard("centered", title: "Unlock the full experience", place: "left:150px;top:220px"),
            Self.promoCard("notice", title: "Example notice", action: "Details")
        ].joined()
        let html = GrokShellFixture.page(
            content: GrokShellFixture.hero + cards,
            sidebar: Self.promoCard("in-sidebar", title: "Unlock the full experience", place: "left:8px;bottom:8px"),
            outside: """
            <div id="plans-dialog" role="dialog" data-open
                 style="position:fixed;right:0;bottom:0;width:260px;height:170px">
              \(Self.promoCard("in-dialog", title: "Unlock the full experience"))
            </div>
            """
        )
        let marks = try await evaluatePromoMarks(
            html: html,
            ids: ["plans", "feature", "expired", "limit", "terms", "centered", "notice", "in-dialog", "in-sidebar"]
        )
        XCTAssertEqual(marks["plans"], true)
        XCTAssertEqual(marks["feature"], true)
        // Money, limits, and legal notices are the account talking, not a campaign.
        XCTAssertEqual(marks["expired"], false)
        XCTAssertEqual(marks["limit"], false)
        XCTAssertEqual(marks["terms"], false)
        // Not in a corner, or nothing being sold.
        XCTAssertEqual(marks["centered"], false)
        XCTAssertEqual(marks["notice"], false)
        // Dialogs and the sidebar are grok.com's own surfaces.
        XCTAssertEqual(marks["in-dialog"], false)
        XCTAssertEqual(marks["in-sidebar"], false)
        XCTAssertEqual(marks["noPromoClick"], true)
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

    /// The titlebar's More and Share are native. They read and pick from
    /// grok.com's one Conversation Actions menu, opened out of sight.
    @MainActor
    func testConversationActionsRunThroughTheHiddenWebMenu() async throws {
        let html = GrokShellFixture.page(
            header: GrokShellFixture.conversationHeader,
            content: GrokShellFixture.transcript + GrokShellFixture.composer,
            outside: """
            <div role="presentation" data-open>
              <div role="menu" data-open aria-labelledby="another-trigger">
                <div role="menuitem" onclick="window.wrongMenu = true">Pin</div>
                <div role="menuitem" onclick="window.wrongMenu = true">Archive</div>
              </div>
            </div>
            """ + GrokShellFixture.conversationMenu(project: "submenu")
        )
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/c/fixture")

        let inspected = try await callSessionJavaScript(webView, """
          document.getElementById('composer').focus();
          var state = await window.__grockChrome.inspectSessionMenu();
          var fx = window.fixture;
          return {
            pin: state.pin, panel: state.panel, project: state.project, archive: state.archive,
            suppressedAtOpen: fx.suppressedAtOpen, markedAtClose: fx.markedAtClose, opacityAtClose: fx.opacityAtClose,
            menuOpen: !!document.getElementById('menu'), escapes: fx.menuEscapes, triggerClicks: fx.triggerClicks,
            stillSuppressed: document.documentElement.hasAttribute('data-grock-picking-menu'),
            focus: document.activeElement.id
          };
        """) as? [String: Any]
        XCTAssertEqual(inspected?["pin"] as? String, "pin")
        XCTAssertEqual(inspected?["panel"] as? Bool, true)
        XCTAssertEqual(inspected?["project"] as? Bool, true)
        XCTAssertEqual(inspected?["archive"] as? Bool, true)
        // Out of sight from the click that opens it until it closes.
        XCTAssertEqual(inspected?["suppressedAtOpen"] as? Bool, true)
        XCTAssertEqual(inspected?["markedAtClose"] as? Bool, true)
        XCTAssertEqual(inspected?["opacityAtClose"] as? String, "0")
        // Closed again before AppKit shows its copy, with the page as it was.
        XCTAssertEqual(inspected?["menuOpen"] as? Bool, false)
        XCTAssertEqual(inspected?["escapes"] as? Int, 1)
        XCTAssertEqual(inspected?["triggerClicks"] as? Int, 1)
        XCTAssertEqual(inspected?["stillSuppressed"] as? Bool, false)
        XCTAssertEqual(inspected?["focus"] as? String, "composer")

        let picked = try await callSessionJavaScript(webView, """
          var chrome = window.__grockChrome, fx = window.fixture;
          var out = {};
          out.pin = await chrome.clickSession('pin');
          out.pinned = fx.pinned;
          out.afterPin = (await chrome.inspectSessionMenu()).pin;
          // Two requests at once take turns; a second click would close the menu.
          var both = await Promise.all([chrome.inspectSessionMenu(), chrome.clickSession('pin')]);
          out.queuedPin = both[0].pin;
          out.unpin = both[1];
          out.unpinned = !fx.pinned;
          out.share = await chrome.clickSession('share');
          fx.shareDisabled = true;
          out.disabledShare = await chrome.clickSession('share');
          out.menuOpenAfterDisabled = !!document.getElementById('menu');
          var clicksBefore = fx.triggerClicks;
          out.deleted = await chrome.clickSession('delete');
          out.more = await chrome.clickSession('more');
          out.unknownOpenedMenu = fx.triggerClicks !== clicksBefore;
          out.clicked = fx.clicked;
          return out;
        """) as? [String: Any]
        XCTAssertEqual(picked?["pin"] as? String, "clicked")
        XCTAssertEqual(picked?["pinned"] as? Bool, true)
        XCTAssertEqual(picked?["afterPin"] as? String, "unpin")
        XCTAssertEqual(picked?["queuedPin"] as? String, "unpin")
        XCTAssertEqual(picked?["unpin"] as? String, "clicked")
        XCTAssertEqual(picked?["unpinned"] as? Bool, true)
        XCTAssertEqual(picked?["share"] as? String, "clicked")
        XCTAssertEqual(picked?["disabledShare"] as? String, "unavailable")
        XCTAssertEqual(picked?["menuOpenAfterDisabled"] as? Bool, false)
        // grok.com has no Delete any more, and More is not an action.
        XCTAssertEqual(picked?["deleted"] as? String, "unknown")
        XCTAssertEqual(picked?["more"] as? String, "unknown")
        XCTAssertEqual(picked?["unknownOpenedMenu"] as? Bool, false)
        XCTAssertEqual(picked?["clicked"] as? [String], ["Pin", "Unpin", "Share"])

        let archived = try await callSessionJavaScript(webView, """
          var fx = window.fixture;
          var escapesBefore = fx.documentEscapes;
          var result = await window.__grockChrome.clickSession('archive');
          return {
            result: result, clicked: fx.clicked[fx.clicked.length - 1],
            // Escape after the item closed its menu would dismiss the confirmation.
            strayEscapes: fx.documentEscapes - escapesBefore,
            confirming: !!document.getElementById('confirm-archive'),
            focus: document.activeElement.id,
            stillSuppressed: document.documentElement.hasAttribute('data-grock-picking-menu'),
            wrongMenu: window.wrongMenu === true
          };
        """) as? [String: Any]
        XCTAssertEqual(archived?["result"] as? String, "clicked")
        XCTAssertEqual(archived?["clicked"] as? String, "Archive")
        XCTAssertEqual(archived?["strayEscapes"] as? Int, 0)
        XCTAssertEqual(archived?["confirming"] as? Bool, true)
        XCTAssertEqual(archived?["focus"] as? String, "confirm-archive")
        XCTAssertEqual(archived?["stillSuppressed"] as? Bool, false)
        XCTAssertEqual(archived?["wrongMenu"] as? Bool, false)

        // A remounted trigger with no handler must not fall back to the
        // unrelated menu, or leave the page's menus hidden.
        let failed = try await callSessionJavaScript(webView, """
          document.getElementById('confirm-archive').remove();
          var trigger = document.getElementById('actions');
          trigger.replaceWith(trigger.cloneNode(true));
          var state = await window.__grockChrome.inspectSessionMenu();
          return {
            pin: state.pin, project: state.project, archive: state.archive,
            pinResult: await window.__grockChrome.clickSession('pin'),
            stillSuppressed: document.documentElement.hasAttribute('data-grock-picking-menu'),
            wrongMenu: window.wrongMenu === true
          };
        """) as? [String: Any]
        XCTAssertEqual(failed?["pin"] as? String, "missing")
        XCTAssertEqual(failed?["project"] as? Bool, false)
        XCTAssertEqual(failed?["archive"] as? Bool, false)
        XCTAssertEqual(failed?["pinResult"] as? String, "missing")
        XCTAssertEqual(failed?["stillSuppressed"] as? Bool, false)
        XCTAssertEqual(failed?["wrongMenu"] as? Bool, false)
    }

    /// What `window.__grockChrome.session()` reports for `html` loaded at `url`.
    @MainActor
    private func evaluateSessionState(html: String, url: String) async throws -> [String: Bool] {
        let webView = try await loadSessionFixture(html: html, url: url)
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set();
          var state = window.__grockChrome.session();
          return { more: state.more, share: state.share, panel: state.panel, authenticated: state.authenticated };
        """)
        return try XCTUnwrap(result as? [String: Bool], "session state was not a dictionary of flags")
    }

    /// Loads `html` at `url` with nothing injected, runs each source the way
    /// `evaluateJavaScript` runs a production script, and returns their
    /// results with whatever the `probe` expression reads back from the page.
    @MainActor
    private func runPageScripts(
        _ sources: [String],
        html: String,
        url: String,
        probe: String = "{}"
    ) async throws -> (results: [String], page: [String: Any]) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFront(nil)
        webView.layoutSubtreeIfNeeded()
        let loaded = expectation(description: "page-script-fixture")
        let loader = PlaceTitleHTMLLoader(expectation: loaded)
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: URL(string: url))
        await fulfillment(of: [loaded], timeout: 4)
        _ = window
        let value = try await callSessionJavaScript(webView, """
          var results = [];
          for (var i = 0; i < sources.length; i++) results.push(String((0, eval)(sources[i])));
          return { results: results, page: (0, eval)('(' + probe + ')') };
        """, arguments: ["sources": sources, "probe": probe])
        let body = try XCTUnwrap(value as? [String: Any], "page scripts did not return a dictionary")
        return (body["results"] as? [String] ?? [], body["page"] as? [String: Any] ?? [:])
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
    private func callSessionJavaScript(
        _ webView: WKWebView,
        _ script: String,
        arguments: [String: Any] = [:]
    ) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                continuation.resume(with: result.map(Optional.some))
            }
        }
    }

    /// Which of `ids` the chrome script took off the page, with the sidebar
    /// shown so a card inside it is only gone if it was marked.
    @MainActor
    private func evaluatePromoMarks(html: String, ids: [String]) async throws -> [String: Bool] {
        let webView = try await loadSessionFixture(html: html, url: "https://grok.com/")
        let result = try await callSessionJavaScript(webView, """
          window.__grockChrome.set({ sidebarHidden: false });
          var marks = { noPromoClick: window.promoClicked !== true };
          ids.forEach(function (id) {
            marks[id] = document.getElementById(id).getClientRects().length === 0;
          });
          return marks;
        """, arguments: ["ids": ids])
        return try XCTUnwrap(result as? [String: Bool], "promo marks were not a dictionary of flags")
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
    private func loadReplyObserver(
        html: String,
        recorder: ReplyFixtureRecorder? = nil
    ) async throws -> (WKWebView, NSWindow) {
        let config = WKWebViewConfiguration()
        if let recorder {
            config.userContentController.add(recorder, name: ReplyBridge.channelName)
        }
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

/// Records what the reply observer posts to native.
private final class ReplyFixtureRecorder: NSObject, WKScriptMessageHandler {
    private(set) var kinds: [String] = []
    var onMessage: (([String: Any]) -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any] ?? [:]
        var kind = body["kind"] as? String ?? ""
        if let generating = body["generating"] as? Bool { kind += ":\(generating)" }
        kinds.append(kind)
        onMessage?(body)
    }
}

/// grok.com's shell after the November 2026 redesign (DEC-071), cut down to
/// the ids, roles, labels, and `data-*` hooks the page scripts read. Every
/// name and title in it is made up.
enum GrokShellFixture {
    /// The band over a new chat: Private, and nothing else.
    static let homeHeader = """
    <header id="page-header">
      <span data-context-tray-yield>
        <button id="private" aria-pressed="false" aria-label="Switch to Private Chat">Private</button>
      </span>
      <span aria-hidden="true"></span>
    </header>
    """

    /// The band over a conversation: its title and the Conversation Actions menu.
    static let conversationHeader = """
    <header id="page-header" data-header-over-column>
      <div id="title" data-testid="conversation-title"><span data-sidebar-item-label>Example chat</span></div>
      <span data-context-tray-yield>
        <button id="actions" data-testid="conversation-actions-trigger" aria-label="Conversation Actions"
                aria-haspopup="menu" aria-expanded="false"></button>
      </span>
    </header>
    """

    static let composer = """
    <div role="presentation">
      <form id="composer-form" data-composer onsubmit="return false">
        <div data-composer-field>
          <div id="composer" contenteditable="true" role="textbox" aria-label="Message Grok"><p><br></p></div>
        </div>
        <button id="attach" type="button" data-testid="attach-button" aria-label="Add files, skills, and connectors"></button>
        <button id="dictate" type="button" aria-label="Dictate"></button>
        <button id="voice" type="button" aria-label="Voice mode" data-composer-action="voice"></button>
      </form>
    </div>
    """

    static let hero = """
    <div data-empty-chat-hero>
      <h1 id="hero">What should we explore?</h1>
      \(composer)
    </div>
    """

    static let transcript = """
    <div id="transcript" role="log" aria-label="Conversation" aria-busy="false"
         data-testid="chat-transcript-scroller">
      <div data-plane-row="row-1">
        <div data-user-message-row>
          <div role="article" data-testid="user-message"><span data-bubble-text>Example question</span></div>
        </div>
      </div>
      <div data-plane-row="row-2">
        <div id="answer" role="article" data-testid="assistant-message"><p>Example answer</p></div>
        <div data-testid="response-footer-actions">
          <div role="toolbar" aria-label="Response actions">
            <button type="button" aria-label="Copy response"></button>
          </div>
        </div>
      </div>
    </div>
    """

    /// `header` and `content` go in the main column, `sidebar` at the end of
    /// the sidebar, and `outside` after the shell, where grok.com portals its
    /// menus and dialogs.
    static func page(
        header: String = homeHeader,
        content: String = "",
        sidebar: String = "",
        signedIn: Bool = true,
        outside: String = "",
        title: String = "Grok"
    ) -> String {
        let account = signedIn ? """
        <button id="account" type="button" data-account-trigger aria-haspopup="menu"
                aria-label="Account menu for Example User"></button>
        """ : ""
        return """
        <!DOCTYPE html>
        <html>
        <head><title>\(title)</title><style>
          html, body { margin:0; height:100%; }
          button { min-width:24px; min-height:24px; }
          #grok-app-root { position:relative; display:flex; width:100vw; height:100vh; }
          #app-sidebar { position:relative; width:254px; height:100%; }
          section { position:relative; flex:1; min-width:0; height:100%; }
          #grok-content-area, #main-column { position:relative; height:100vh; }
          #page-header { position:absolute; top:0; left:0; right:0; height:56px; }
          [data-empty-chat-hero] { display:flex; flex-direction:column; justify-content:center;
            align-items:center; height:100%; }
          #composer { width:320px; min-height:24px; }
          #transcript { height:400px; overflow-y:scroll; }
          #pane-yield { position:absolute; top:14px; right:14px; }
          #right-pane { position:absolute; top:0; right:0; width:0; height:100%; overflow:hidden; }
          #leading-box { position:absolute; top:12px; left:12px; }
        </style></head>
        <body>
          <div id="grok-app-root" data-desktop-shell>
            <div id="sidebar-box">
              <aside id="app-sidebar" aria-label="App navigation">
                <header></header>
                <button id="new-chat" type="button" aria-keyshortcuts="Meta+J">
                  <span data-sidebar-item-label>New chat</span>
                  <span data-slot="sidebar-item-shortcut"><span aria-hidden="true">J</span></span>
                </button>
                <div data-slot="sidebar-scrolling-content">
                  <div id="library-box">
                    <button id="library" type="button"><span data-sidebar-item-label>Library</span></button>
                  </div>
                  <div id="bots" data-reorder-item="bots"><div data-open>
                    <button type="button" data-panel-open aria-expanded="true"><span>Bots</span></button>
                    <button type="button" aria-label="New bot"></button>
                    <div data-open>
                      <button id="bot-row" type="button"><span data-sidebar-item-label>Example bot</span></button>
                    </div>
                  </div></div>
                  <div id="projects" data-reorder-item="projects"><div data-open>
                    <button type="button" data-panel-open aria-expanded="true"><span>Projects</span></button>
                    <button type="button" aria-label="New project"></button>
                    <div data-open>
                      <div data-closed>
                        <button id="project-row" type="button" data-project-row="project-1">
                          <span data-sidebar-item-label>Untitled project</span>
                        </button>
                        <button id="project-new-chat" type="button" aria-label="New chat in Untitled project"></button>
                      </div>
                    </div>
                  </div></div>
                  <div id="recent" data-reorder-item="recent"><div data-open>
                    <button type="button" data-panel-open aria-expanded="true"><span>Chats</span></button>
                    <button id="chats-new-chat" type="button" aria-label="New chat"></button>
                    <div data-open>
                      <button id="chat-row" type="button"><span data-sidebar-item-label>Example chat</span></button>
                      <button type="button" aria-label="Actions for Example chat" aria-haspopup="menu"></button>
                      <button id="other-chat-row" type="button"><span data-sidebar-item-label>Another chat</span></button>
                    </div>
                  </div></div>
                </div>
                <footer>
                  \(account)
                  <button id="connect" type="button" aria-label="Connect apps" data-account-action></button>
                </footer>
                <div id="resize" role="separator" aria-controls="app-sidebar" aria-label="Resize sidebar"></div>
                \(sidebar)
              </aside>
            </div>
            <span hidden></span>
            <section>
              <div>
                <div id="grok-content-area" role="main">
                  <div id="main-column">
                    \(header)
                    \(content)
                  </div>
                </div>
              </div>
              <span id="pane-yield" data-context-tray-yield>
                <button id="pane-toggle" type="button" aria-label="Toggle right pane" aria-expanded="false"></button>
              </span>
              <aside id="right-pane" aria-label="Right pane" aria-hidden="true" inert tabindex="-1">
                <header>
                  <div role="toolbar" aria-label="Pane actions">
                    <button type="button" aria-label="New tab"></button>
                    <button id="hide-pane" type="button" aria-label="Hide pane" aria-controls="right-pane"
                            aria-expanded="true"></button>
                  </div>
                </header>
              </aside>
            </section>
            <span id="leading-box">
              <span id="leading" data-leading-chrome>
                <button id="sidebar-toggle" type="button" aria-label="Toggle sidebar" aria-controls="app-sidebar"
                        aria-expanded="true"></button>
                <button id="search" type="button" aria-label="Search"></button>
              </span>
            </span>
          </div>
          \(outside)
        </body>
        </html>
        """
    }

    /// Conversation Actions as grok.com builds it: a click on the trigger
    /// mounts `[role="menu"]` (labelled by the trigger) inside a
    /// `[role="presentation"]` positioner a moment later and gives it focus; a
    /// second click closes it; Escape on the menu, or picking an item,
    /// unmounts it and anything nested in it. `project` is how Add to Project
    /// behaves: "submenu" (ArrowRight opens a nested menu and the parent stays
    /// open), "dialog" (a click swaps the menu for a dialog), or "none".
    /// `window.fixture` records what happened.
    static func conversationMenu(project: String) -> String {
        """
        <script>
        (function () {
          var trigger = document.getElementById('actions');
          var projectKind = '\(project)';
          var fx = window.fixture = {
            pinned: false, shareDisabled: false, moved: false, clicked: [],
            triggerClicks: 0, menuEscapes: 0, pickerEscapes: 0, documentEscapes: 0,
            suppressedAtOpen: null, markedAtClose: null, opacityAtClose: null
          };
          document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') fx.documentEscapes++;
          });
          var opening = false;
          function menu() { return document.getElementById('menu'); }
          function closePicker() {
            var picker = document.getElementById('project-picker');
            if (!picker) return;
            if (picker.parentElement.getAttribute('role') === 'presentation') picker.parentElement.remove();
            else picker.remove();
          }
          function closeMenu() {
            opening = false;
            var el = menu();
            if (!el) return;
            fx.markedAtClose = el.hasAttribute('data-grock-session-menu');
            fx.opacityAtClose = getComputedStyle(el).opacity;
            var picker = document.getElementById('project-picker');
            if (picker && picker.hasAttribute('data-nested')) closePicker();
            el.parentElement.remove();
            document.getElementById('actions').setAttribute('aria-expanded', 'false');
          }
          function openPicker(nested) {
            var picker = document.createElement('div');
            picker.id = 'project-picker';
            picker.setAttribute('data-open', '');
            picker.setAttribute('role', nested ? 'menu' : 'dialog');
            if (nested) picker.setAttribute('data-nested', '');
            var field = document.createElement('input');
            field.id = 'project-search';
            field.setAttribute('role', 'combobox');
            field.setAttribute('aria-label', 'Search projects');
            var choice = document.createElement('div');
            choice.id = 'project-choice';
            choice.setAttribute('role', nested ? 'menuitem' : 'button');
            choice.textContent = 'Untitled project';
            choice.addEventListener('click', function () {
              fx.moved = true;
              closePicker();
              closeMenu();
            });
            picker.append(field, choice);
            picker.addEventListener('keydown', function (event) {
              if (event.key !== 'Escape') return;
              fx.pickerEscapes++;
              closePicker();
            });
            if (nested) {
              var positioner = document.createElement('div');
              positioner.id = 'projects-positioner';
              positioner.setAttribute('role', 'presentation');
              positioner.setAttribute('data-open', '');
              positioner.style.cssText = 'position:absolute;top:0;left:0;transform:translate(300px,20px)';
              positioner.appendChild(picker);
              document.body.appendChild(positioner);
            } else {
              closeMenu();
              document.body.appendChild(picker);
            }
            field.focus();
          }
          function item(label, onClick) {
            var el = document.createElement('div');
            el.setAttribute('role', 'menuitem');
            el.tabIndex = -1;
            el.textContent = label;
            el.addEventListener('click', function () {
              fx.clicked.push(label);
              onClick();
            });
            return el;
          }
          trigger.addEventListener('click', function () {
            fx.triggerClicks++;
            if (menu() || opening) { closeMenu(); return; }
            fx.suppressedAtOpen = document.documentElement.hasAttribute('data-grock-picking-menu');
            opening = true;
            setTimeout(function () {
              if (opening) mount();
            }, 10);
          });
          function mount() {
            opening = false;
            var positioner = document.createElement('div');
            positioner.setAttribute('role', 'presentation');
            positioner.setAttribute('data-open', '');
            positioner.style.cssText = 'position:absolute;top:0;left:0;transform:translate(520px,48px)';
            var el = document.createElement('div');
            el.id = 'menu';
            el.setAttribute('role', 'menu');
            el.setAttribute('data-open', '');
            el.setAttribute('aria-labelledby', trigger.id);
            el.tabIndex = -1;
            el.addEventListener('keydown', function (event) {
              if (event.key !== 'Escape') return;
              fx.menuEscapes++;
              closeMenu();
            });
            var share = item('Share', closeMenu);
            if (fx.shareDisabled) share.setAttribute('aria-disabled', 'true');
            el.appendChild(share);
            el.appendChild(item(fx.pinned ? 'Unpin' : 'Pin', function () {
              fx.pinned = !fx.pinned;
              closeMenu();
            }));
            el.appendChild(item('Rename', closeMenu));
            if (projectKind === 'submenu') {
              var submenu = item('Add to Project', function () {});
              submenu.id = 'add-to-project';
              submenu.setAttribute('aria-haspopup', 'menu');
              submenu.addEventListener('keydown', function (event) {
                if (event.key === 'ArrowRight') openPicker(true);
              });
              el.appendChild(submenu);
            } else if (projectKind === 'dialog') {
              var opener = item('Add to Project', function () { openPicker(false); });
              opener.id = 'add-to-project';
              el.appendChild(opener);
            }
            el.appendChild(item('Archive', function () {
              closeMenu();
              var confirm = document.createElement('div');
              confirm.id = 'confirm-archive';
              confirm.setAttribute('role', 'alertdialog');
              confirm.tabIndex = -1;
              confirm.textContent = 'Archive conversation?';
              document.body.appendChild(confirm);
              confirm.focus();
            }));
            positioner.appendChild(el);
            document.body.appendChild(positioner);
            trigger.setAttribute('aria-expanded', 'true');
            el.focus();
          }
        })();
        </script>
        """
    }
}
