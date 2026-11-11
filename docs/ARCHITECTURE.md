# Architecture

## What we are

A native macOS shell around https://grok.com. One `WKWebView`, four global hotkeys, a launcher-style overlay, a native Quick Chat card, and a handful of bridges for downloads, focus, files, and permissions. We don't rebuild the chat UI.

## Why these calls

The full write-ups are in [DECISIONS.md](DECISIONS.md). The short version:

**One WebView**, because login and cookies live in it. Two instances would mean two sessions. The overlay and any future companion window share the same `WebViewStore` (DEC-003). X and Apple sign-in popups get short-lived WebViews that borrow its configuration, so they write to the same cookie jar.

**Overlay, not browser window.** Summon, chat, dismiss. It's a titled, activating window at normal z-order. An always-on-top panel was tried and made Settings unreachable (DEC-011). Show Grock brings it forward and never hides it (DEC-013). It comes to the Space you're on and the display under your cursor (DEC-024).

**Carbon hotkeys.** A sandboxed `CGEventTap` often looks installed and never sees keys from another app. `RegisterEventHotKey` talks to the window server and needs no Accessibility prompt (DEC-008).

**Quick Chat is native.** A small card gathers text, clipboard, and files, then touches grok.com once at Send and reveals the overlay already streaming (DEC-041). It waits for observable acceptance before it considers a send done (DEC-058). Clipboard capture is optional and skips confidential pasteboard markers (DEC-057).

**Nothing auto-sends.** `grock://` URLs, the CLI, Finder Services, and OS-handed files all stage a prompt. The user presses Return (DEC-049, DEC-053).

**Offsite links go to the browser.** The main frame stays on grok.com, except for sign-in: xAI's account pages, and the provider page grok.com's Log in window sends you to, recognized by its return address back to grok.com (DEC-032, DEC-072).

**Web content gets a short leash.** Native handlers accept messages only from the main grok.com frame, and the download fallback is GET-only to a short list of asset hosts (DEC-056).

## Layers

Dependencies mostly point downward. A few go the other way: the web layer reaches up for sign-in popups and panel geometry, and appearance preferences push straight into `WebViewStore`.

```
Views / App shell     Grock/Views, Grock/App     SwiftUI + AppKit (panel, status item, hotkeys, Quick Chat)
        │
        ▼
Web bridge            Grock/Web                  WKWebView owner, injected scripts, navigation, downloads, recovery
        │
        ▼
Utilities / settings  Grock/Utilities            AppInfo, preferences, download paths, CLI installer
```

`WebViewStore` owns the WebView, navigation, composer handoff, and recovery state, plus the page script that notices a reply finishing. `WebNavigation.swift` has `NavigationPolicy`, the navigation delegates, and the guarded download bridge. `GrokChromeScript.swift` adapts grok.com's page chrome (the controls the titlebar replaces, sidebar, hidden features, promo cards). `QuickChatPayload.swift` is the package Quick Chat hands the page, size limits included. `ReplyMonitor.swift` tracks the unread answer behind the Dock badge. `WebRecovery.swift` draws the native Retry, Open in Browser, and download footer. On the app side, `UpdaterController.swift` wraps Sparkle and `AuthPopupPresenter.swift` hosts sign-in popups.

Injected scripts follow two rules. First, they stay idle when grok.com is idle. The chrome script folds a burst of DOM changes into one animation frame plus one throttled 200 ms pass, and that second pass keeps things current when an occluded window stops getting frames. Second, they never observe attributes we wrote ourselves.

## Load-bearing boundaries

| Boundary | Rule |
|----------|------|
| One WebView | `WebViewStore` owns the WKWebView. Never a second one. Sign-in popups share its configuration and cookie store. |
| Offsite links | Main frame stays on grok.com, plus a sign-in chain once it starts: xAI's account pages, or X, Apple, Google, or GitHub when grok.com sends the page there with a `redirect_uri` back to grok.com. Everything else opens in the default browser. See `NavigationPolicy` in `WebNavigation.swift`. |
| Native handlers | Accept messages only from the main HTTPS grok.com frame. Navigation revokes download authorization. |
| Sending | No code path sends a message without the user pressing Return or Send. |
| XcodeGen | Edit `project.yml`, run `xcodegen generate`. Never hand-edit `Grock.xcodeproj`, `Info.plist`, or `Grock.entitlements`; all three are generated. |
| Scripts | Build and test through `script/build_and_run.sh` and `script/test.sh`. Release by pushing a version tag; `.github/workflows/release.yml` runs `script/release.sh` and publishes (see `docs/RELEASING.md`). |
| AppKit bridges | Panel, status item, hotkeys, and Quick Chat are AppKit. Keep them narrow. Settings panes are SwiftUI. |

## Presentation

The overlay is a titled window with a unified toolbar drawn over the WebView (`fullSizeContentView`). grok.com keeps a 56px band for its own chrome at the top of every view and fades a thread out beneath it, so the 52pt toolbar sits in that band and nothing has to be pushed down. The chrome script hides the controls the toolbar replaces (grok.com's sidebar toggle and Search, the chat title, Conversation Actions, the right pane toggle) and leaves the layout alone (DEC-071). It matches ids, roles, labels, and `data-` attributes, never class names: grok.com's classes are hashed and change with every build.

Toolbar, left to right: Sidebar toggle, the place or conversation title (a menu of destinations when the sidebar is hidden, a plain label when it's open), then More and Share on a conversation (DEC-055), then New Chat, Private, and Search. While the sidebar is hidden, clicking the title copies the chat URL and Option-click opens it in the browser.

Close means hide. Interactive launch shows the window; login-item launch stays quiet (DEC-018). A cold grok.com load is covered by a small native orbit animation until the page has a composer (DEC-042). The app menu is a normal Mac app menu, not a mini-browser (DEC-033). The status item is a system menu: Show Grock, New Chat, Settings, Quit. An unread answer badges the Dock (DEC-054).

Settings is an AppDelegate-owned toolbar-tab window: General (hotkeys, clipboard capture, Dock, login item), Appearance (theme, hide grok.com chrome), Account (open the current page in a browser, clear web data), Advanced (Web Inspector, CLI install, reset). About is the system About panel.

## Sandbox and entitlements

Sandboxed. `Grock/Grock.entitlements`, generated from `project.yml`:

- `app-sandbox`
- `network.client` (load grok.com)
- `files.downloads.read-write` (image and file downloads)
- `files.user-selected.read-only` (Quick Chat drops, Open With, Dock, Finder Services)
- `device.audio-input` and `device.camera` (grok.com voice and media; WebKit asks, never at launch)
- `temporary-exception.files.absolute-path.read-only` for `/usr/local/bin/` and `/opt/homebrew/bin/`, so Settings can tell whether the `grock` symlink is ours (DEC-061)
- `temporary-exception.mach-lookup.global-name` for the two service names Sparkle's installer uses (DEC-062)

No Accessibility. No `CGEventTap`. No privileged helper.

## File handoff

`grock ask -f` and `grock new -f` transfer temporary access using Apple's [bookmark handoff between processes](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox). The CLI opens its containing app bundle, so a different default handler for `grock://` doesn't get the grant.

Native callers can use repeatable `bookmark=` on `grock://ask` or `grock://new`. Create each file URL's bookmark with `bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)`, base64-encode the data, then percent-encode the query value (including `+`). The sender must already have file access. These bookmarks carry temporary access, so don't log them or save them for reuse. `.withSecurityScope` is for persistent app-scoped bookmarks and isn't the option for this handoff.

`GrockURL.parse` resolves bookmarks with `.withoutUI`, `.withoutMounting`, and `.withoutImplicitStartAccessing`. `FileIntake.load` keeps the original resolved URLs, starts access for its bounded reads, then releases it on success, error, or cancellation. A stale flag alone doesn't reject a one-use bookmark; the resolved file still has to pass every read check. Requests allow 20 files, 16 KiB per bookmark, and 128 KiB for the encoded URL. Malformed attachments reject the whole request.

Plain `file=` accepts absolute paths and local file URLs. It carries no authorization. On a permission failure, Quick Chat keeps the prompt and offers a native file picker for the requested file. Cancelling the picker leaves the package as it was. Recovery retries the whole addition, and Send stays disabled until every failed addition is resolved or dropped with Continue Without Them. A recovered `new` request returns to the overlay with its prompt and files staged. Nothing auto-sends (DEC-067).

## Layout and conventions

Swift 5.10, Xcode 26, macOS 26.0 or later, Apple silicon. Not Swift 6 strict concurrency yet. No force unwraps in production code, apart from one constant URL literal. `guard let` early returns over nested `if let`.

```
Grock/
  GrockApp.swift          # @main entry and menu commands
  App/                    # AppDelegate, panel, hotkeys, Quick Chat, file intake, URL scheme, updater
  Web/                    # WebViewStore, navigation and downloads, chrome script, payload, reply tracking, recovery
  Views/                  # SwiftUI (Settings panes, Quick Chat view)
  Utilities/              # AppInfo, preferences, download paths, CLI installer
  Grock.entitlements      # generated from project.yml
  Info.plist              # generated from project.yml
GrockCLI/                 # grock tool; shares GrockURL and GrockCommand with the app
GrockTests/               # XCTest, grouped by area (CorePolicyTests, WebBoundaryTests, …)
```

New files are named for their main type. A few older ones are named for a feature instead (`WebNavigation.swift`, `GrokChromeScript.swift`). Prefer editing an existing file over adding one. SwiftUI for Settings, AppKit where the platform requires it. `@Observable` for new stores, unless the store has to republish Combine values the way `UpdaterController` does for Sparkle.

`DerivedData/` lives under the repo and is ignored. Development builds pass `CODE_SIGNING_ALLOWED=NO`. `script/release.sh` builds and verifies a signed sandboxed artifact; see [RELEASING.md](RELEASING.md).

Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`). Default branch is `master`. No secrets, signing keys, or `.env` in the tree.

Comments explain why for non-obvious macOS and WebKit choices. They don't narrate obvious code.

No third-party dependency without a DECISIONS entry. Prefer Apple's APIs. The one dependency today is Sparkle, for updates (DEC-062).

## Influences

Shoulders, not copy-paste.

[grokk](https://github.com/senor-artemisio/grokk) showed that hide-instead-of-close, a single WebView store, and sandbox entitlements were the right shape, and that grok.com's image CDN fails CORS inside a WebView. Our download bridge is a from-scratch rewrite so the tree can honestly be MIT (DEC-015).

[macos-grok-overlay](https://github.com/tchlux/macos-grok-overlay) is the summon UX: show the panel, focus the prompt, hide yields focus. We kept the idea and replaced the `CGEventTap` and the borderless always-on-top panel (DEC-008, DEC-011).

## Out of scope for the shell

- Rebuilding the Grok chat UI
- Requiring an xAI API key
- Electron, or any web framework for the shell
- A computer-use agent mode
