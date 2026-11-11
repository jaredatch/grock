<div align="center">

<img src="docs/assets/icon.png" width="160" height="160" alt="Grock icon">

# Grock

**Grok, one keystroke away, on a Mac that still feels like a Mac.**

[![Build](https://github.com/jaredatch/grock/actions/workflows/ci.yml/badge.svg)](https://github.com/jaredatch/grock/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jaredatch/grock?display_name=tag)](https://github.com/jaredatch/grock/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)
[![MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

</div>

Grock is a native macOS launcher for [grok.com](https://grok.com). Press ⌥Space, type, drop in a file, hit Return, and the answer streams into a window that gets out of your way when you're done. It uses the Grok account you already have. No API key, no Electron, no rebuilt chat UI. The conversation is grok.com; Grock is the Mac around it.

Unofficial. Not affiliated with xAI or SpaceX.

## Install

Download the latest `Grock-x.y.z-arm64.zip` from [Releases](https://github.com/jaredatch/grock/releases/latest), unzip it, and drag Grock to Applications. It's signed and notarized, so Gatekeeper won't complain. From then on it checks for updates by itself and asks before installing one.

You need macOS 26 or later on Apple silicon, plus a grok.com account (free or SuperGrok). The first launch opens grok.com's own sign-in page inside the app.

## What it does

**Quick Chat.** ⌥Space opens a small native card. Type, paste, or drop in files, then press Return. Grock starts a fresh conversation on grok.com, attaches everything, sends it once, and brings up the overlay with the answer already streaming. Anything you copied in the last minute is already on the card, unless your password manager marked it confidential. Esc, or clicking anywhere else, throws the card away.

**Hand Grok a file from anywhere.** Drop it on the Dock icon or the menu bar icon, use Open With, or run `open -a Grock notes.pdf`, and it lands on a Quick Chat card. Finder's Services → Ask Grok opens a New Chat in the overlay instead. Either way the file is attached and nothing goes anywhere until you press Return.

**An overlay that behaves.** It comes to the Space you're on and the display under your cursor. Show Grock always brings it forward and never hides it, so a covered window doesn't vanish when you reach for it. Esc or the close button hides it and hands focus back to whatever you were doing. Citations and other outside links open in your browser instead of trapping you in the overlay.

**A badge when the answer lands.** Ask something heavy and go back to work. If you aren't looking when Grok finishes, the Dock icon gets a `1` and the menu bar icon changes. Click the Dock icon or use Show Grock, and you're scrolled straight to the answer.

**A titlebar, not a browser frame.** The sidebar toggle, the chat title, New Chat, Private, and Search sit in a native toolbar over the page. Inside a conversation you also get More (pin, add to a project, archive) and Share. grok.com's sidebar starts hidden, and while it is, clicking the title copies the chat link, Option-click opens it in your browser, and the chevron beside it jumps to Imagine, Projects, History, and the rest. Appearance settings hide the parts of grok.com you don't use, like Projects, Plugins, or voice mode.

**Four hotkeys, all yours to rebind.** Quick Chat (⌥Space out of the box), New Chat, Show Grock, and Voice Chat. The last three stay unset until you pick a shortcut. They're registered through Carbon, so Grock never asks for Accessibility access.

**A login item that stays quiet.** Launch at Login starts Grock in the background. Opening it from the Dock or Spotlight shows the window. Turn on Hide from Dock and it lives in the menu bar.

**Downloads that work.** Generated images and files land in `~/Downloads`, including the ones grok.com's CDN refuses to hand a WebView. A footer tells you when a download finished or failed, with a Show in Finder button.

## Automate it

Anything on your Mac can open Grock with a URL. Nothing in these links sends on its own, so you always get the last word.

```
grock://                                   show the window
grock://new                                empty New Chat, prompt focused
grock://new?text=Summarize%20this          New Chat with that text staged
grock://ask?text=Summarize%20this          Quick Chat with that text staged
grock://imagine?generate=a%20red%20bicycle Imagine with the prompt filled in
```

`new` and `ask` also take `file=/absolute/path`, as many times as you like. A path on its own doesn't give Grock permission to read the file, though. If macOS says no, Grock keeps your prompt and shows a Choose File… button so you can pick it yourself, or Continue Without Them to drop the files it couldn't read.

There's a `grock` command too. Settings → Advanced → Install CLI… shows a command to paste into Terminal, which links `grock` into `/opt/homebrew/bin` (or `/usr/local/bin`) and may ask for your password.

```
grock                          # show the window
grock ask "summarize this"     # Quick Chat
grock new -f notes.pdf         # New Chat, file attached
pbpaste | grock ask            # stdin is the prompt
grock imagine a red bicycle
```

Files passed with `-f` work from anywhere your shell can read. The CLI hands Grock temporary access to each one, so you won't see a file picker or need Full Disk Access. Whichever way they arrive, Quick Chat takes up to 20 files, 12 MB each and 24 MB in total.

Raycast, Alfred, and Shortcuts can call the CLI for files or use the URL scheme for text. Native apps can hand over file access with bookmarks; [File handoff](docs/ARCHITECTURE.md#file-handoff) has the details.

## FAQ

**Why macOS 26 only?** Quick Chat is built on Liquid Glass, and there's no fallback material we'd want to ship. Supporting releases we don't test is a promise we'd end up breaking.

**Is my login safe?** You sign in on grok.com's own page and your provider's (X, Apple, Google, or GitHub), all inside Grock, and the session lives in Grock's WebKit cookie store inside its sandbox, separate from Safari's. Grock has no server and no telemetry. Apart from the pages you load, the only place it contacts is GitHub, to check for updates.

**Why is installing the CLI a Terminal step?** Grock is sandboxed and can't write to `/usr/local/bin` or `/opt/homebrew/bin` by itself. It shows you the exact command instead and notices when you come back.

**Signing in with X got stuck.** Settings → Account → Clear Web Data… signs you out and wipes Grock's cookies and site data. Sign in again from there.

**Why not the App Store?** Maybe later. Direct download keeps the release loop short while grok.com changes every week.

**Why not an API key?** Because you already have Grok. Grock exists to make the account you use every day feel at home on a Mac.

**How do I uninstall it?** In Settings, turn off Launch at Login and, if you installed it, remove the CLI under Advanced. Then quit Grock and drag it to the Trash. Your sign-in and settings live in `~/Library/Containers/com.jaredatch.Grock`, so delete that folder too if you want a clean slate.

## Build from source

You need macOS 26, Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
./script/build_and_run.sh            # build and launch
./script/build_and_run.sh --headless # compile check
./script/test.sh
```

If you plan to change code, read [AGENTS.md](AGENTS.md) first; it's short. [ARCHITECTURE](docs/ARCHITECTURE.md) covers how the app fits together, [DECISIONS](docs/DECISIONS.md) covers why, and [RELEASING](docs/RELEASING.md) covers shipping a build.

## Credits

[macos-grok-overlay](https://github.com/tchlux/macos-grok-overlay) is where the summon-and-dismiss flow comes from. [grokk](https://github.com/senor-artemisio/grokk) is how we learned that image downloads inside a WebView need a native fallback. Their code isn't in this tree, but their ideas are.

Updates use [Sparkle](https://sparkle-project.org), the only third-party dependency.

## License

[MIT](LICENSE). Grok is a product of xAI. Grock is a fan-made shell around it.
