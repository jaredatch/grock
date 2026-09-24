# Working on Grock

The brief for anyone touching code, human or agent. Read it before your first change. `docs/ARCHITECTURE.md` has the shape; `docs/DECISIONS.md` has the reasoning.

## What this is

Grock is a native macOS app that wraps [grok.com](https://grok.com) in a launcher-style overlay and gives it Mac superpowers: a global hotkey, Quick Chat, file intake from Finder and the Dock, a `grock://` scheme, a `grock` command, and a Dock badge when an answer lands. Swift, AppKit where the platform demands it, SwiftUI for Settings. Sandboxed. Unofficial.

The conversation surface is grok.com. We do not rebuild it.

## Constitution

Break one of these and the project stops being Grock.

- **Wrapper, not clone.** Chat, models, image generation, voice, limits, and updates come from grok.com. We own the shell, the bridges, and the native extras.
- **Your subscription is the login.** Core chat works with an ordinary grok.com or SuperGrok account. Requiring an xAI API key would be a failure.
- **Native or nothing.** Real panels, activation policy, entitlements, menus, Carbon hotkeys. Not a skin that fights macOS. Not Electron.
- **Launcher first.** Hotkey, useful chat, dismiss. Everything else serves that loop.
- **Nothing sends on its own.** URLs, the CLI, Services, and file drops stage a prompt. The user presses Return.
- **Fidelity and reliability over novelty.** Downloads work, login is honest, the hotkey fires. When grok.com changes, we adapt.
- **Personality without cringe.** Light and professional in the chrome. Wit is allowed. A bit is not.
- **Small surface area.** Prefer editing an existing file. Singletons, NotificationCenter, and UserDefaults for cross-cutting state.

## Writing for strangers

This tree is public. Write like people you have never met will read it, because they will.

- No hostnames, machine names, paths into other projects, or notes about the state of someone's working tree.
- No secrets, tokens, or signing material. Ever.
- Public prose (README, CONTRIBUTING, CHANGELOG, `docs/`) is conversational, tight, and free of AI filler.
- Maintainer notes live in `private/`, which is gitignored. If that folder exists on your machine, read its `AGENTS.md` too. If it does not, nothing here depends on it.

## Operating rules

1. **Smallest change that moves the north star.**
2. **Verify with the scripts.** After a code change, run `./script/build_and_run.sh --headless` and `./script/test.sh`. Fix red before you say you are done.
3. **XcodeGen owns the project.** Edit `project.yml`, then let the scripts run `xcodegen generate`. Never hand-edit `Grock.xcodeproj`.
4. **Write down durable decisions** in `docs/DECISIONS.md` with a number, the context, and what it costs.
5. **No new dependency without a decision entry.** Prefer Apple's APIs.
6. **Do not weaken a check to go green.** Tests, sandbox verification, and release verification are the contract.

## Build and test

```
./script/build_and_run.sh            # build and launch
./script/build_and_run.sh --headless # compile check, prints SMOKE OK
./script/build_and_run.sh --clean
./script/test.sh                     # prints GROCK_TEST_COUNT=N, then FILE ACCESS CHECK OK
./script/test.sh --filter CorePolicyTests  # one class; skips the file access check
./script/release.sh --local          # ad hoc signed, sandboxed Release build
```

Swift 5.10, Xcode 26 (macOS 26 SDK), macOS 26 or later, Apple silicon, XcodeGen 2.40 or later. Development builds pass `CODE_SIGNING_ALLOWED=NO` and keep `DerivedData/` inside the repo. See `docs/RELEASING.md` for signed builds.

## Settled defaults

- Bundle ID `com.jaredatch.Grock`. MIT license. Sparkle is the only third-party dependency.
- Fresh install: Quick Chat is ⌥Space. New Chat, Show Grock, and Voice Chat are unset until the user assigns them. Show Grock never hides a window that is already up.
- One `WKWebView`, owned by `WebViewStore`. Cookies and login live there, so there is never a second instance. X and Apple sign-in popups borrow its configuration and cookie store.
- The overlay is a titled window at normal z-order. Close and Esc hide it. It comes to the current Space and, if needed, the display under the cursor.
- Interactive launch shows the window. Login-item launch stays quiet until summoned.
- `grock://` (show), `grock://new`, `grock://new?text=`, `grock://ask?text=`, `grock://imagine?generate=`, plus repeatable `file=` and `bookmark=` on `new` and `ask`. The `grock` CLI wraps those URLs and lives inside the app bundle.
- Files handed over by the OS (Dock, Open With, `open -a`, status item drop) land on Quick Chat. Finder → Services → Ask Grok lands on a New Chat in the overlay. Drops on the open window attach in grok.com.
- Unread answer badges the Dock. Showing the window scrolls to that answer.
- Settings: General (hotkeys, clipboard capture, Dock, login), Appearance (theme, hide grok.com chrome), Account (open the current page in a browser, clear web data), Advanced (Web Inspector, CLI install, reset).

## Patterns to follow

- Native talks to the page through a few injected user scripts (page chrome, downloads, reply watching, edge fixes) and three message handlers. Handlers accept messages only from the main grok.com frame.
- Downloads: `WKDownload` first, a guarded native fetch when the page hits CORS, context menu save through native.
- The main window never truly closes. Hide and re-show.
- Activation policy switches for menu-bar versus regular presence.
- Settings is an AppDelegate-owned toolbar-tab window. The SwiftUI `Settings` scene exists so `@main` has a scene.
- Injected scripts stay idle when grok.com is idle. Never observe attributes we wrote ourselves.

## Pitfalls we already hit

- Treating the WebView as a dumb browser, then wondering why downloads, auth, or focus break.
- A local event monitor or sandboxed `CGEventTap` for the global hotkey. It looks installed and never fires. Use Carbon.
- Forgetting that close means hide and must yield focus to the previous app.
- Calling `AVCaptureDevice.requestAccess` at launch. WebKit asks when voice is used.
- Duplicating something grok.com already does well.

## Never

- Require an xAI API key for core chat.
- Rebuild the Grok conversation UI in native controls.
- Ship Electron or a generic "AI browser box."
- Commit secrets, or bypass sandbox entitlements without a decision entry.
- Auto-send anything on the user's behalf.
