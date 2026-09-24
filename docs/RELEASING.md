# Releasing

You need Xcode 26 or newer, XcodeGen 2.40 or newer, and Python 3. Releases are Apple silicon only; we don't verify Intel builds.

## Check the tree

Start with the development checks, the same ones CI runs on macOS 26 with Xcode 26.6:

```sh
./script/build_and_run.sh --headless   # SMOKE OK
./script/test.sh                       # GROCK_TEST_COUNT=N, then FILE ACCESS CHECK OK
./script/release.sh --local            # SIGNED APP CHECK OK (not a notarization check)
```

The app build and XCTest host run unsigned, so `test.sh` finishes with a small signed sandbox receiver that exercises the real URL parser and file loader: raw-path denial, temporary CLI access with the receiver running or closed, multiple files, and access cleanup.

`release.sh --local` builds an ad hoc signed Release app and checks its entitlements, hardened runtime, CLI signature, architecture, and deployment target. It prints the app's path under `DerivedData/ReleaseArtifacts/`. That build is for testing. It isn't notarized and Gatekeeper will reject it on another Mac.

## One-time setup

### Notarization profile

The Developer ID signing identity lives in Keychain. Set up a notarization profile once on the Mac you release from. With an App Store Connect team API key:

```sh
xcrun notarytool store-credentials grock-notary \
  --key '/path/to/AuthKey_KEY_ID.p8' \
  --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID
```

Or use your Apple ID, which prompts for an app-specific password:

```sh
xcrun notarytool store-credentials grock-notary \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Do this in a Terminal on the Mac's own desktop, not over SSH, so you can answer the Keychain prompts. Then check that the profile works (an empty history is fine):

```sh
xcrun notarytool history --keychain-profile grock-notary
```

### Sparkle signing key

Grock's EdDSA public key is already in `project.yml` as `SUPublicEDKey`. The private half lives in the release Mac's login Keychain under the account `Grock`, with a backup in a password manager, and the release script uses it to sign every update.

Only ever generate this key once. A second key won't match the public key in copies people already have, and they'll reject every update signed with it. To set up another release Mac, import the backup, then delete the file:

```sh
DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -f grock-sparkle.key --account Grock
```

The Sparkle tools show up under `DerivedData/SourcePackages/` after `build_and_run.sh` or `test.sh`, and under `DerivedData/ReleaseBuild/SourcePackages/` after a release build. Lose the key and shipped copies stop updating.

Shipping your own fork? Generate your own key with `generate_keys --account YourName`, export a backup with `-x`, put the public key in `SUPublicEDKey`, and change `SUFeedURL` in `project.yml` and the account and URLs in `script/release.sh` to match.

## Cut a version

Sparkle decides whether an update is newer by comparing build numbers, so `CURRENT_PROJECT_VERSION` has to go up every release. Ship a new version with the same build number and existing copies will never see it. The bump script takes care of that:

```sh
./script/bump.sh 1.0.1
```

It sets the new version in `project.yml`, `AppInfo.expectedMarketingVersion`, the version test in `CorePolicyTests`, and the bug report template, and adds one to the build number. It won't go backwards, and if any of those files look unexpected it stops before changing anything.

Then add a dated entry to `CHANGELOG.md`, run the checks above, commit, and push. Build the release from that commit with a clean working tree, so the binary matches the tag.

## Build the release

```sh
./script/release.sh \
  --identity 'Developer ID Application: YOUR_ORGANIZATION (TEAM_ID)' \
  --notary-profile grock-notary
```

The script signs Sparkle, the CLI, and the app, submits the package to Apple, checks acceptance, staples the app, and creates `Grock-X.Y.Z-arm64.zip` with a SHA-256 checksum. Everything lands in a fresh `DerivedData/ReleaseArtifacts/run.XXXXXX/` folder, next to Apple's `notarization.json`. It also signs the ZIP with the Sparkle key and rewrites `appcast.xml` at the repo root. A good run prints `RELEASE CHECK OK` after stapling, then `VERIFIED RELEASE` and `APPCAST UPDATED` at the end.

To check a Developer ID build without submitting it to Apple, use `--sign-only` instead of `--notary-profile`.

If `codesign` returns `errSecInternalComponent`, check that the signing Keychain is unlocked and that `codesign` can reach the identity's private key in your logged-in session. A certificate showing up in `security find-identity -v -p codesigning` doesn't prove that it can.

Apple's [notarization guide](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) covers the rest. Passwords, private keys, and certificates never go in the repository.

## Test the downloaded app

Apple accepting the upload isn't the same as the app working on a stranger's Mac. Before you publish, copy the finished ZIP to a Mac or user account with no development settings, install it in Applications, and check:

- Fresh grok.com login, including OAuth popups and returning from the browser.
- Quick Chat, a file from Finder, a clipboard image, and an unread answer after dismissing.
- Image and file downloads, including a failed download.
- The microphone permission prompt the first time you use voice.
- Finder Services, URL entry points, and installing and removing the CLI.
- CLI `ask -f` and `new -f` with files outside Downloads, with Grock running and closed. Plain `file=` links should offer Choose File when access is missing. Try cancelling the picker, choosing each requested file, and Continue Without Them. The prompt has to survive every path, and nothing should send.
- Login-item launch staying quiet, hotkey conflicts, and summoning on another Space or display.
- Retry after a lost connection, and recovery after the web content process exits.

Write down which artifact you tested and anything still pending. The automated tests don't cover fresh login, permission prompts, or Gatekeeper on a clean Mac, so this list is the release gate.

## Publish

The update feed builds download links as `…/releases/download/vX.Y.Z/Grock-X.Y.Z-arm64.zip`, so the tag and asset names have to match exactly.

1. Tag the commit you built from as `vX.Y.Z` and push the tag.
2. Create the GitHub Release from that tag and upload the ZIP and its `.sha256` without renaming them:

   ```sh
   gh release create vX.Y.Z \
     DerivedData/ReleaseArtifacts/run.XXXXXX/Grock-X.Y.Z-arm64.zip \
     DerivedData/ReleaseArtifacts/run.XXXXXX/Grock-X.Y.Z-arm64.zip.sha256 \
     --title "Grock X.Y.Z" --notes-file notes.md
   ```

3. Commit the updated `appcast.xml` and push it to `master`. Installed copies read the feed from there, so do this only once the Release and its assets are live. A feed entry that points at a missing ZIP is a broken update for everyone.
4. On a Mac running the previous version, choose Check for Updates… from the Grock menu. It should offer this version and install it.
