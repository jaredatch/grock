# Changelog

## 1.0.3 (2026-11-11)

grok.com shipped a new design, and a lot of Grock stopped lining up with it. This release catches up.

- The sidebar hides again, and grok.com's own sidebar and Search buttons no longer sit under the traffic lights.
- More and Share are back in the titlebar on a chat. grok.com replaced Delete with Archive and renamed Move to Project, so the More menu now reads Pin, Add to Project, Toggle Right Pane, and Archive.
- Search in the titlebar opens grok.com's search again.
- `grock imagine` and `grock://imagine` work again. Imagine is now a mode of the main composer, so the prompt lands in a new chat with Imagine switched on.
- Plugins in the title menu opens Connect Apps, where grok.com moved it.
- Hiding Grok Bot no longer hides Billing, Usage, and Data Controls in grok.com's Settings.
- New Chat no longer shows grok.com's subscription card in the corner (it came back with the redesign).
- Chat text sits where grok.com puts it. Grock used to add its own gap under the titlebar, which the new layout doesn't need.
- The window background matches grok.com's new off-white, and near-black in dark mode.
- Showing Grock for an unread answer scrolls to the start of that answer, not its footer.
- The image viewer in Library and in chats starts below the titlebar. Its Copy, Save, and Close buttons were hidden under Grock's, so there was no way to close it.
- Upload files in Library and Upload a file in the composer open a file picker. Neither ever did.
- Signing in with X, Apple, Google, or GitHub stays inside Grock. grok.com's new Log in window sent you to your browser, where signing in couldn't reach the app.
- After signing in, the page fills the window. A blank band was left along the bottom until you resized it.
- Web Inspector always opens in its own window. Docked inside Grock it came up blank.
- Signed out, the page shows Sign in and nothing else from grok.com's header: no logo, Settings, Sign up, or Google's one-tap card. The cookie notice stays. The title menu only offers New Chat until you're signed in.
- In Quick Chat, the detail line under an attached file is readable when the card sits over something dark.

## 1.0.2 (2026-11-04)

- Search, and See all under Chats, open fully on screen again. grok.com moved its search window, and Grock was still nudging it down for the old layout, which pushed it halfway off the bottom.
- New Chat no longer shows grok.com's subscription card in the corner.

## 1.0.1 (2026-11-04)

Maintenance release. Updates are now built, signed, and published automatically, and this is the first one shipped that way. If Grock 1.0.0 offered you this version and installed it, the updater works end to end. Nothing else in the app changes.

## 1.0.0 (2026-10-01)

First public release. Grock is a native macOS launcher for grok.com, and this is everything it does on day one:

- Quick Chat on ⌥Space: a small card for text, a recent copy, and files, which sends once and opens the overlay mid-answer.
- An overlay that comes to your current Space and the display under your cursor, and hides instead of quitting.
- Files from the Dock, the menu bar icon, Open With, `open -a`, and Finder's Services → Ask Grok.
- The `grock://` URL scheme and a bundled `grock` command. Neither ever sends on its own.
- A Dock badge when an answer lands while you're looking elsewhere.
- Downloads that work even when grok.com's CDN refuses a WebView.
- Four rebindable hotkeys: Quick Chat, New Chat, Show Grock, and Voice Chat.
- A native titlebar over the page, plus Appearance settings for hiding the parts of grok.com you don't use.
- Updates through Sparkle.

Requires macOS 26 on Apple silicon. Signed, notarized, and sandboxed. Unofficial and not affiliated with xAI or SpaceX.
