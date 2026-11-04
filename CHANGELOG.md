# Changelog

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
