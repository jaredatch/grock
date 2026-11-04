# Decisions

The calls that shaped Grock, and what each one cost. Numbers come from the maintainers' full working log, so there are gaps. The missing entries are mostly selector churn, titlebar experiments, and small calls the entries here already cover, though you'll see a few of those numbers cited in code comments. Newest at the bottom.

Each one is short: the problem, the call, and what it costs us.

---

## DEC-003. The overlay is the app

Launcher DNA: summon, chat, dismiss. The default surface is an overlay, not a browser window with tabs and a URL bar. A regular "companion" window may come later, and when it does it will share the same WebView under different chrome.

That meant the early months went into panel, hotkey, and focus correctness instead of features. One WebView is a hard rule, because login and cookies live in it and two instances would mean two sessions.

## DEC-008. Global hotkey through Carbon

The first build used a `CGEventTap` with Accessibility permission, the pattern most overlay apps copy. Inside App Sandbox it often looks installed and still never sees a key from another app. Carbon's `RegisterEventHotKey` talks to the window server directly, consumes the combo, and needs no Accessibility prompt.

If registration fails, another app already owns that shortcut and all we can do is say so in Settings. There is no Accessibility entitlement in this app, and there won't be one for hotkeys.

## DEC-011. Summon brings it forward. It is not always on top

An always-floating, non-activating panel sat above every window, stole the sense of focus, and made Settings unreachable because Grock never became the active app. The overlay is now a titled window at normal level that activates when summoned. Hide-on-close and hotkey summon stay.

Other apps can cover Grock now. That is what Show Grock is for.

## DEC-013. The hotkey never hides

A toggle hotkey feels broken the moment Grock is open but covered: you press it to talk to Grok and the app disappears. Show Grock always shows and activates the window, then focuses the prompt, or scrolls to the answer if one landed while you were away. Dismissal is Esc or the close button.

The gotcha for anyone touching window logic: `isVisible` doesn't mean "in front."

## DEC-015. MIT, after rewriting the download bridge

Two earlier open-source wrappers taught us that grok.com's image CDN fails CORS inside `WKWebView`, and one of them is GPL-3. Our first download path was close enough to that code that MIT wouldn't have been honest. We rewrote the bridge from scratch (`WKDownload` first, a guarded native fetch fallback, native context-menu save) and licensed the tree MIT. Those projects are credited in the README as inspiration, not vendored.

Cost: the rewrite, and a standing rule to never paste the original back in.

## DEC-018. Opening the app means show the window

After first run, launching Grock from the Dock or Spotlight left the overlay hidden and you had to click again. Opening an app is a request to use it, so interactive launch shows the window. Login-item launch is the exception: it stays in the background until you summon it.

Telling the two apart means reading the launch Apple Event early, before it disappears. `LaunchReason` owns that check.

## DEC-024. The window comes to you

Summon used to raise the window on whatever display it last hid on, and joining every Space meant getting yanked to the wrong desktop. Now the overlay moves to the Space you're on and, if the cursor is on a different display, parks itself there at the same relative spot. Same display, it doesn't move.

The order matters: relocate the frame, then order front, then activate. Get it wrong and AppKit switches you to the old Space.

## DEC-032. Offsite links open in your browser

A citation, a Help link, or a tweet used to load inside the overlay, with no back button, and you were stuck off grok.com. The main frame now stays on grok.com. Anything else opens in the default browser. The one exception is xAI's own account and identity-provider flow (X, Apple), which has to stay in WebKit so the cookies land in the right jar.

Cost: a new login host on xAI's side means an explicit allowlist update in `NavigationPolicy`. We would rather maintain a short list than let the overlay become a browser.

## DEC-033. The menu bar is a Mac app's, not a mini-browser's

The Grock menu had Home, Reload, Copy Link, Open in Browser, and Clear Web Data, and View had Show Tab Bar. It looked like a wrapper. Now the Grock menu is About, Check for Updates, and Settings. File is New Chat, New Voice Chat, Quick Chat, and Close Window (which hides and keeps running). View is Customize Appearance and Reload, and Help points at the repo and its issues. Copy Link and Open in Browser moved to the title in the toolbar, which works as a control while grok.com's sidebar is hidden.

Some verbs are one click further away. Feeling like a Mac app is worth that.

## DEC-041. Quick Chat is native intake, not a second Grok

Stuffing the clipboard into New Chat was wrong: the pasteboard nearly always has something, often hours old. The real gesture is package-then-throw: a recent copy, a drop, a selection, or just typing. Fighting grok.com's composer for that would mean fighting their DOM all session. So Quick Chat is a small native card. Gather, type, Send. It touches grok.com once, at Send, then reveals the overlay already streaming.

What it deliberately lacks: a model picker, recents, a mic, a transcript. The overlay is the chat. Quick Chat is the front door.

## DEC-042. A native loading orbit instead of a blank page

The window appears instantly and grok.com takes a beat to paint, so the first thing you saw was white. A spinner would have worked. We drew a small orbit instead: a planet, a hairline ring, one bead, black on light and white on dark. It fades out when the page has a composer.

WKWebView's remote layer paints over sibling views, so the WebView has to be hidden while the orbit shows. We tried a busier 3D solar system first and cut it; the simple loop is the drawing.

## DEC-044. macOS 26 is the floor

Quick Chat wants Liquid Glass with no material fallback, and carrying older releases as a promise we don't test is noise. Deployment target is macOS 26.0.

Cost: no Sonoma or Sequoia users. In exchange, not a single `#available` check in the tree.

## DEC-045. ⌥Space is Quick Chat

Quick Chat shipped unbound so we wouldn't steal the shortcut until daily use said it was how you actually talk to Grok. It is. A fresh install binds ⌥Space to Quick Chat; New Chat, Show Grock, and Voice Chat stay unset until you assign them.

Installs that had ⌥Space on New Chat get migrated. Custom bindings are left alone.

## DEC-047. Hide grok.com's promo cards, never dismiss them

grok.com shows campaign strips, corner cards, toasts, and composer upsells, most with a Dismiss button. Clicking Dismiss writes their state, so the promo would also vanish in Safari, which isn't ours to decide. We hide the specific shapes we've seen, plus a couple of named announcements, and never click anything. Modal dialogs, sign-in, billing, rate-limit, and terms copy are never touched.

A new promo shape can slip through until we add it. We'd rather live with that than write a generic "hide anything with a Dismiss button" rule.

## DEC-049. `grock://`, and nothing auto-sends

Shortcuts, scripts, and a CLI need a way in that isn't a hotkey. `grock://new`, `new?text=`, `ask?text=`, and `imagine?generate=` open the right surface with the prompt staged. Repeatable `file=` attaches what the sandbox can read. None of them send. You press Return.

One more keypress for automation. In exchange, nothing ever fires by accident.

## DEC-050. Files the Mac hands us land on Quick Chat

Dropping a file on the Dock icon or the menu bar icon, choosing Open With, or running `open -a Grock notes.pdf` used to do nothing, because Grock never registered as a document app. Now it registers as an alternate viewer for any file, so it never becomes your default for anything, and those files open Quick Chat with the attachment staged. Nothing sends. Folders are skipped.

A drop on the open overlay is different. It goes to grok.com's composer, the same as it would in Safari.

Cost: Grock shows up in every file's Open With menu.

## DEC-051. Finder's Ask Grok opens a New Chat

Right-click a file in Finder and choose Services → Ask Grok. Quick Chat is the wrong landing for this one: the card dismisses when it loses focus, and a gesture that starts in Finder usually ends with another click in Finder. So the service opens a New Chat in the overlay, with the file in grok.com's composer and the prompt focused. It doesn't send.

Cost: Services sits one level down in Finder's menu, and macOS may not list the item until it has noticed the app. We decided against an Action extension just to appear in the Quick Actions row.

## DEC-052. We do not claim grok.com links

Opening a shared `grok.com/c/…` link in Grock would need Universal Links, and grok.com's association file lists xAI's official app, not us. The remaining hack would be registering as the default browser and bouncing everything else. No.

So a grok.com URL in Mail or Slack opens your browser. `grock://` is ours. https is theirs.

## DEC-053. The `grock` command wraps `grock://`

The CLI is a thin tool inside the app bundle that builds a `grock://` URL and runs `open`. Verbs are `open`, `new`, `ask`, and `imagine`, with repeatable `-f` and stdin as the text. It fetches no conversations and lists no sessions; that would need an API or a scrape.

One oddity: the binary lives in `Contents/SharedSupport`, because `Contents/MacOS/grock` collides with `Grock` on a case-insensitive disk. Installation is a symlink (DEC-061).

## DEC-054. An unread answer badges the Dock

Long answers finish after you have gone back to work, and then you guess. We watch for grok.com's Stop control to appear and then disappear; that edge is the honest "landed." If you weren't looking at that moment, the Dock tile gets a `1` and the menu bar icon changes. Show Grock or a Dock click scrolls you to the answer and clears it. So does ⌘Tab, if you left the overlay open behind another app.

There is no Notification Center banner, no sound, and the badge never counts past one. It is a single bit, on purpose.

## DEC-055. Conversation actions live in the titlebar

On a chat, grok.com puts More, Share, and a panel toggle in its own header, which ends up underneath Grock's toolbar. We hide that cluster without removing it, so clicks can still reach it, and add More and Share as ordinary toolbar buttons beside New Chat and Private. More opens a native menu with Pin or Unpin, Move to Project, Toggle Right Panel when grok.com offers one, and Delete Chat. Each item drives the matching entry in grok.com's own menu. Share clicks grok.com's Share button, which publishes a public link; clicking the title still copies the private one.

Cost: this is DOM work, so a grok.com redesign can break it until we adapt. And Delete does whatever grok.com does, which right now means deleting at once with a short Undo toast, not asking first.

## DEC-056. Web content gets a short leash

A message from the page crosses the sandbox boundary, so a download fallback must not become a general proxy or a file writer. Native handlers accept messages only from the main HTTPS grok.com frame. The fetch fallback is GET-only, to a short list of Grok asset hosts, with credentials stripped, redirects validated, and a 64 MiB cap. Navigation revokes download authorization.

A new asset host on xAI's side means a policy update and a release. We would rather ship that than a general bridge.

## DEC-057. Clipboard capture is optional and careful

Quick Chat can stage what you copied in the last minute. It is on by default and skips anything marked confidential, transient, or autogenerated, which covers the common password managers. Explicit Paste always works. File intake reads off the main thread with limits of 12 MB per file, 24 MB per package, and 20 files.

An unmarked secret is still a secret we can't recognize. The toggle is in General for exactly that reason, and turning it off stops Grock from watching the pasteboard at all.

## DEC-058. Send means Grok took it

Clicking Send doesn't prove grok.com received the package, and retrying an uncertain send can double-post. Quick Chat waits for every attachment to be acknowledged, clicks Send once, then requires the composer to clear and either a new turn or grok.com's Stop button to appear. If that doesn't happen, it keeps your package and asks you to look before trying again.

A grok.com change can now produce a visible "please check" instead of a silent partial send. We think that's the better failure.

## DEC-060. The release artifact gets verified, not trusted

Development builds disable signing, so a green build says nothing about running inside App Sandbox. `script/release.sh` builds a Release app, signs the CLI and the app, and runs a verifier that reads the actual signatures, entitlements, hardened runtime, architecture, and deployment target. Distribution mode notarizes, staples, zips with a checksum, then unzips that ZIP and verifies the copy, because a stray file from the archive is enough for Gatekeeper to refuse the app. CI runs the local variant on every push to `master` and every pull request.

Releases take a Terminal session with Keychain access. Nothing about signing lives in the repo.

## DEC-061. Installing the CLI is a Terminal step

The first CLI installer used a privileged AppleScript, which App Sandbox forbids. Settings → Advanced now shows the exact symlink command with a Copy button; you run it and Grock notices when you come back. Install refuses to overwrite anything that already exists. Uninstall checks that the symlink still points at our bundled tool.

Cost: one paste into Terminal, and moving Grock.app later means reinstalling the link. The app keeps read-only visibility into `/usr/local/bin` and `/opt/homebrew/bin` and gains no write access.

## DEC-062. Updates ship inside the first release

grok.com changes every week and every adaptation is a release. An app with no updater strands whoever installed it, and an app shipped without Sparkle can't later update itself to the version that has it. So Sparkle is in 1.0, the only third-party dependency in the tree. Check for Updates lives in the Grock menu, automatic checks are on by default with no first-launch alert, and inside App Sandbox the installer runs through Sparkle's XPC service with a narrow mach-lookup exception.

The feed is `appcast.xml` in this repo. The release script rewrites it, and it gets committed once the GitHub Release is live. The signing key lives in a Keychain, not here. Sparkle's update window is Sparkle's; we don't restyle it.

## DEC-067. File handoff carries temporary access

A path in a custom URL tells Grock where a file is; it doesn't let a sandboxed app read it. The CLI now includes an ephemeral URL bookmark for each attachment and opens its own app bundle. The receiving app starts access only around the file read and releases it afterward. We use Apple's interprocess bookmark support, with no new entitlements or saved folder permissions.

Integrations that only know a path can still use `file=`. If access fails, Grock keeps the draft and offers Choose File. Selecting the requested file retries the whole addition. Cancel keeps it pending, and Continue Without Them explicitly drops it. Missing files and size errors remain separate errors. A recovered `new` request stages in the overlay; `ask` stays in Quick Chat. Neither sends.

The cost is a picker for callers that can't transfer access, plus limits on bookmark and URL size. Bookmark data is a temporary file-access capability, so we keep it out of logs and persistent storage. A signed sandbox regression runs with the full test suite because an unsigned test host can't prove this works.

## DEC-069. A tag ships the release

Releases used to be built on one Mac's desktop, because signing and notarizing needed its Keychain prompts, and then published by hand in an order that's easy to get wrong. Now pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml` on a GitHub macOS runner. It signs with the Developer ID certificate from a throwaway keychain, notarizes with an App Store Connect API key, signs the update with the Sparkle key, and publishes the GitHub Release, then the feed, then the Homebrew cask. The secrets sit in a `release` environment that only `v*` tags can use. Before anything goes public, `script/verify_update.swift` checks the new feed entry against the public key inside the app, so a wrong key fails the run instead of every installed copy.

Cost: the Developer ID and Sparkle private keys now live in GitHub, and anyone who can push a tag can ship an update. The clean-Mac test list becomes optional: run it when a release touches login, permissions, or file access, ideally on a hand-built copy before tagging.
