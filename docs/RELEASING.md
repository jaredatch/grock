# Releasing

Push a version tag and GitHub Actions builds, signs, and notarizes Grock, then publishes the GitHub Release, the Sparkle update feed, and the Homebrew cask. Nobody has to be at a Mac to answer Keychain prompts.

For the checks below you need Xcode 26 or newer, XcodeGen 2.40 or newer, and Python 3. Releases are Apple silicon only; we don't verify Intel builds.

## Check the tree

Start with the development checks, the same ones CI runs on macOS 26 with Xcode 26.6:

```sh
./script/build_and_run.sh --headless   # SMOKE OK
./script/test.sh                       # GROCK_TEST_COUNT=N, then FILE ACCESS CHECK OK
./script/release.sh --local            # SIGNED APP CHECK OK (not a notarization check)
```

The app build and XCTest host run unsigned, so `test.sh` finishes with a small signed sandbox receiver that exercises the real URL parser and file loader: raw-path denial, temporary CLI access with the receiver running or closed, multiple files, and access cleanup.

`release.sh --local` builds an ad hoc signed Release app and checks its entitlements, hardened runtime, CLI signature, architecture, and deployment target. It prints the app's path under `DerivedData/ReleaseArtifacts/`. That build is for testing. It isn't notarized and Gatekeeper will reject it on another Mac.

## Cut a version

Sparkle decides whether an update is newer by comparing build numbers, so `CURRENT_PROJECT_VERSION` has to go up every release. The bump script takes care of that:

```sh
./script/bump.sh 1.0.1
```

It sets the new version in `project.yml`, `AppInfo.expectedMarketingVersion`, the version test in `CorePolicyTests`, and the bug report template, and adds one to the build number. It won't go backwards, and if any of those files look unexpected it stops before changing anything.

Then add a `## 1.0.1 (YYYY-MM-DD)` section to `CHANGELOG.md`. That section becomes the release notes, so write it for people deciding whether to update. Run the checks above, commit, push to `master`, and tag the commit:

```sh
git tag v1.0.1
git push origin v1.0.1
```

There's nothing else to do. The run shows up under the repository's Actions tab.

## What the release workflow does

`.github/workflows/release.yml` runs on any `v*` tag:

1. It checks that the tag matches the version in `project.yml`, that the commit is on `master`, and that `CHANGELOG.md` has a section for it. Any miss stops the run before it builds anything.
2. It reads the live `appcast.xml` from `master`, so the new feed keeps every entry already published.
3. It imports the Developer ID certificate into a throwaway keychain and runs `script/release.sh` with an App Store Connect API key and the Sparkle key. That builds, signs, notarizes, staples, and zips the app, then checks the stapled app and a fresh unzip of the ZIP (`RELEASE CHECK OK` twice). The script refuses a build number that isn't above every build in the feed. After signing the update, `script/verify_update.swift` checks the new feed entry against the public key inside the app, so a wrong key fails here instead of on every installed copy.
4. It creates the GitHub Release with `Grock-X.Y.Z-arm64.zip` and its `.sha256`.
5. It commits the new `appcast.xml` to `master`. Installed copies find the update there. Pull before your next change.
6. Once the repository is public, it writes `Casks/grock.rb` in [jaredatch/homebrew-tap](https://github.com/jaredatch/homebrew-tap).

The Release always goes up before the feed, because a feed entry that points at a missing ZIP is a broken update for everyone.

If the run fails before step 4, nothing was published. Fix the problem, then move the tag:

```sh
git tag -f v1.0.1 && git push -f origin v1.0.1
```

If it fails after the Release exists, rerun the failed job from the Actions tab. It replaces the Release assets and publishes the feed. That's safe because the feed doesn't point at those assets yet.

## One-time setup

The workflow takes its secrets from a `release` environment (Settings → Environments) that only `v*` tags can deploy to:

| Secret | What goes in it |
| --- | --- |
| `DEVELOPER_ID_P12` | The Developer ID Application certificate and private key, exported from Keychain Access as a `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set on that export |
| `NOTARY_API_KEY_P8` | An App Store Connect team API key (`AuthKey_KEY_ID.p8`). Developer access is enough. |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the key list in App Store Connect → Users and Access → Integrations |
| `SPARKLE_PRIVATE_KEY` | The Sparkle EdDSA private key, exported as described below |
| `HOMEBREW_TAP_TOKEN` | A fine-grained token with Contents read and write on the tap repository only |

`gh` sets each one, and prompts when you don't pipe in a value:

```sh
base64 -i developer-id.p12 | gh secret set DEVELOPER_ID_P12 --env release
gh secret set DEVELOPER_ID_P12_PASSWORD --env release
gh secret set NOTARY_API_KEY_P8 --env release < AuthKey_KEY_ID.p8
gh secret set NOTARY_KEY_ID --env release
gh secret set NOTARY_ISSUER_ID --env release
gh secret set HOMEBREW_TAP_TOKEN --env release
```

Export the certificate and the Sparkle key in a Terminal on the Mac's own desktop, not over SSH, so you can answer the Keychain prompts. Delete the exported files when you're done. Your password manager is where the backups belong.

### Sparkle signing key

Grock's EdDSA public key is already in `project.yml` as `SUPublicEDKey`. The private half lives in a Keychain under the account `Grock`, with a backup in a password manager. Export it for the workflow, upload it, and delete the file:

```sh
DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account Grock -x sparkle.key
gh secret set SPARKLE_PRIVATE_KEY --env release < sparkle.key
rm sparkle.key
```

The Sparkle tools show up under `DerivedData/SourcePackages/` after `build_and_run.sh` or `test.sh`.

Only ever generate this key once. A second key won't match the public key in copies people already have, and they'll reject every update signed with it. To put the key on another Mac, import the backup with `generate_keys -f grock-sparkle.key --account Grock`, then delete the file. Lose the key and shipped copies stop updating.

Shipping your own fork? Generate your own key with `generate_keys --account YourName`, export a backup with `-x`, and put the public key in `SUPublicEDKey`. Then change `SUFeedURL` in `project.yml`, the account and URLs in `script/release.sh`, and the repository names in `release.yml`.

## Test the downloaded app

The workflow's checks stop at signing, notarization, and the update signature. When a release touches login, permissions, file access, or the entry points, go through this list on a Mac or user account with no development settings:

- Fresh grok.com login, including OAuth popups and returning from the browser.
- Quick Chat, a file from Finder, a clipboard image, and an unread answer after dismissing.
- Image and file downloads, including a failed download.
- The microphone permission prompt the first time you use voice.
- Finder Services, URL entry points, and installing and removing the CLI.
- CLI `ask -f` and `new -f` with files outside Downloads, with Grock running and closed. Plain `file=` links should offer Choose File when access is missing. Try cancelling the picker, choosing each requested file, and Continue Without Them. The prompt has to survive every path, and nothing should send.
- Login-item launch staying quiet, hotkey conflicts, and summoning on another Space or display.
- Retry after a lost connection, and recovery after the web content process exits.
- Check for Updates… on a Mac running the previous version offers this one and installs it.

To check before anything ships, build by hand (below), test that ZIP, and tag once you're happy. Either way, write down which build you tested and anything still pending.

## Building by hand

`release.sh` also runs on a desktop Mac with credentials from Keychain. Store a notarization profile once:

```sh
xcrun notarytool store-credentials grock-notary \
  --key '/path/to/AuthKey_KEY_ID.p8' \
  --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID
```

Then build from a clean working tree:

```sh
./script/release.sh \
  --identity 'Developer ID Application: YOUR_ORGANIZATION (TEAM_ID)' \
  --notary-profile grock-notary
```

Everything lands in a fresh `DerivedData/ReleaseArtifacts/run.XXXXXX/` folder, next to Apple's `notarization.json`, and the script rewrites `appcast.xml` at the repo root. A good run ends with `UPDATE SIGNATURE OK`, `VERIFIED RELEASE`, and `APPCAST UPDATED`. Use `--sign-only` instead of `--notary-profile` to check a Developer ID build without sending it to Apple.

If `codesign` returns `errSecInternalComponent`, check that the signing Keychain is unlocked and that `codesign` can reach the identity's private key in your logged-in session. A certificate showing up in `security find-identity -v -p codesigning` doesn't prove that it can.

To publish a hand-built release, run `gh workflow disable release.yml` first so the tag doesn't start a second release. Then push the tag, create the Release with the ZIP and `.sha256` without renaming them, and only then commit `appcast.xml` to `master`. Turn the workflow back on with `gh workflow enable release.yml`.

Apple's [notarization guide](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) covers the rest. Passwords, private keys, and certificates never go in the repository.
