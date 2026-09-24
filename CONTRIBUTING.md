# Contributing

Thanks for looking. Grock is small on purpose, so the best contributions are small too.

## Bugs first

grok.com changes every week, and when it does, a bridge usually breaks: downloads, focus, the New Chat click, the Dock badge. Those reports are gold. [Open an issue](https://github.com/jaredatch/grock/issues/new/choose) with your Grock and macOS versions and what you were doing. Please leave out private conversation URLs and screenshots of your chats.

## What a good pull request looks like here

- It fixes one thing.
- It edits an existing file when it can.
- It comes with a test that fails without the fix. Web bridges get an executable fixture that exercises the interaction, including cancellation and failure. Asserting that a script contains a selector doesn't count.

Please read [AGENTS.md](AGENTS.md) before you start. It's the brief, and it's short. Then run both checks before you push:

```
./script/build_and_run.sh --headless
./script/test.sh
```

CI runs those two on macOS 26 with Xcode 26.6, then builds a sandboxed Release app with `./script/release.sh --local`. Run that one too if you touched entitlements, `project.yml`, or anything in `script/`.

## What we'll say no to

Grock wraps grok.com. It doesn't rebuild it. So, kindly, not these:

- A native rewrite of the chat surface
- An Electron port, or any web framework for the shell
- Anything that needs an xAI API key for ordinary chat
- A multi-model router
- A feature that sends a message without the user pressing Return
- Drive-by architecture changes

If you're not sure an idea fits, open an issue and ask. It's cheaper than a PR nobody merges.

## Releases and security

Building a signed, sandboxed release is covered in [docs/RELEASING.md](docs/RELEASING.md). Vulnerabilities go through [SECURITY.md](SECURITY.md), not the public tracker.
