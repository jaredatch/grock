#!/usr/bin/env bash
# Build a signed, sandboxed Release app. Publication is a separate step.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY=""
PROFILE=""
NOTARY_KEY=""
NOTARY_KEY_ID=""
NOTARY_ISSUER=""
SPARKLE_KEY=""
LOCAL=0
SIGN_ONLY=0
usage() {
  cat <<'USAGE'
usage: ./script/release.sh --local
       ./script/release.sh --identity 'Developer ID Application: …' --sign-only
       ./script/release.sh --identity 'Developer ID Application: …' --notary-profile PROFILE
       ./script/release.sh --identity 'Developer ID Application: …' \
         --notary-key AuthKey.p8 --notary-key-id KEY_ID --notary-issuer ISSUER_ID [--sparkle-key FILE]

--local signs ad hoc for sandbox testing; its output is not distributable.
--sign-only verifies a Developer ID build without uploading it to Apple.
The full workflow notarizes and staples the app, then creates a ZIP, a checksum, and the Sparkle appcast.
On a desktop Mac, credentials stay in a notarytool Keychain profile and the Sparkle key in Keychain.
The release workflow passes an App Store Connect API key and an exported Sparkle key as files instead.
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --local) LOCAL=1; shift ;;
    --sign-only) SIGN_ONLY=1; shift ;;
    --identity|--notary-profile|--notary-key|--notary-key-id|--notary-issuer|--sparkle-key)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { usage >&2; exit 64; }
      case "$1" in
        --identity) IDENTITY="$2" ;;
        --notary-profile) PROFILE="$2" ;;
        --notary-key) NOTARY_KEY="$2" ;;
        --notary-key-id) NOTARY_KEY_ID="$2" ;;
        --notary-issuer) NOTARY_ISSUER="$2" ;;
        --sparkle-key) SPARKLE_KEY="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done
NOTARY_API="$NOTARY_KEY$NOTARY_KEY_ID$NOTARY_ISSUER"
if [ -n "$NOTARY_API" ]; then
  [ -n "$NOTARY_KEY" ] && [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ] && [ -z "$PROFILE" ] \
    || { echo 'release: --notary-key, --notary-key-id, and --notary-issuer go together, in place of --notary-profile' >&2; exit 64; }
  [ -f "$NOTARY_KEY" ] || { echo "release: no notary key at $NOTARY_KEY" >&2; exit 64; }
  NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
elif [ -n "$PROFILE" ]; then
  NOTARY_AUTH=(--keychain-profile "$PROFILE")
fi
[ -z "$SPARKLE_KEY" ] || [ -f "$SPARKLE_KEY" ] || { echo "release: no Sparkle key at $SPARKLE_KEY" >&2; exit 64; }
if [ "$LOCAL" -eq 1 ]; then
  [ -z "$IDENTITY$PROFILE$NOTARY_API$SPARKLE_KEY" ] && [ "$SIGN_ONLY" -eq 0 ] || { usage >&2; exit 64; }
  IDENTITY="-"
else
  case "$IDENTITY" in
    'Developer ID Application: '*) ;;
    *) echo 'release: provide a Developer ID Application identity, or use --local' >&2; exit 64 ;;
  esac
  if [ "$SIGN_ONLY" -eq 1 ]; then
    [ -z "$PROFILE$NOTARY_API$SPARKLE_KEY" ] || { usage >&2; exit 64; }
  else
    [ -n "$PROFILE$NOTARY_API" ] || { echo 'release: notarizing needs --notary-profile or the --notary-key options (or use --sign-only)' >&2; exit 64; }
  fi
fi

command -v xcodegen >/dev/null || { echo 'release: install XcodeGen first' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'release: python3 is required for verification' >&2; exit 1; }
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[ "${SDK_VERSION%%.*}" -ge 26 ] || { echo 'release: Xcode with the macOS 26 SDK or newer is required' >&2; exit 1; }
if [ -n "$PROFILE$NOTARY_API" ]; then
  # Check the notary credentials before spending time on the build. No credential output.
  xcrun notarytool history "${NOTARY_AUTH[@]}" --output-format json >/dev/null
fi

cd "$REPO"
xcodegen generate
DERIVED="$REPO/DerivedData/ReleaseBuild"
mkdir -p "$REPO/DerivedData/ReleaseArtifacts"
OUTPUT="$(mktemp -d "$REPO/DerivedData/ReleaseArtifacts/run.XXXXXX")"
xcodebuild build -scheme Grock -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO

APP="$OUTPUT/Grock.app"
ditto "$DERIVED/Build/Products/Release/Grock.app" "$APP"
if [ "$LOCAL" -eq 0 ] && [ "$SIGN_ONLY" -eq 0 ] && [ -f "$REPO/appcast.xml" ]; then
  # Sparkle compares build numbers. A build that isn't above everything in
  # the feed is an update nobody gets.
  python3 - "$REPO/appcast.xml" "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys, xml.etree.ElementTree as ET
build = int(plistlib.load(open(sys.argv[2], 'rb'))['CFBundleVersion'])
shipped = [int(v.text) for v in ET.parse(sys.argv[1]).iter('{http://www.andymatuschak.org/xml-namespaces/sparkle}version')]
if shipped and build <= max(shipped):
    raise SystemExit(f'release: build {build} is not above build {max(shipped)} in appcast.xml; run script/bump.sh')
PY
fi
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime)
if [ "$LOCAL" -eq 1 ]; then
  SIGN_ARGS+=(--timestamp=none)
else
  SIGN_ARGS+=(--timestamp)
fi
# Sparkle ships pre-signed. Re-sign inside-out under our identity and keep the
# XPC services' own entitlements; the app sandbox talks to them by name (DEC-062).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$SPARKLE"
codesign "${SIGN_ARGS[@]}" --identifier com.jaredatch.Grock.cli "$APP/Contents/SharedSupport/grock"
codesign "${SIGN_ARGS[@]}" --entitlements "$REPO/Grock/Grock.entitlements" "$APP"
VERIFY_ARGS=("$APP")
if [ "$LOCAL" -eq 0 ]; then VERIFY_ARGS+=(--distribution); fi
python3 "$REPO/script/verify_release.py" "${VERIFY_ARGS[@]}"

if [ "$LOCAL" -eq 1 ] || [ "$SIGN_ONLY" -eq 1 ]; then
  echo "SIGNED TEST APP: $APP"
  echo 'Not notarized. Use this artifact for local verification only.'
  exit 0
fi

# No extended attributes in the archives. macOS stamps every file with
# com.apple.provenance, ditto stores that as ._ entries, and Archive Utility
# leaves the ones beside Sparkle's symlinks as real files. Gatekeeper then
# rejects the app for unsealed contents in the framework root.
ZIP_ARGS=(-c -k --norsrc --noextattr --noacl --keepParent)
UPLOAD="$OUTPUT/notary-upload.zip"
ditto "${ZIP_ARGS[@]}" "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" "${NOTARY_AUTH[@]}" --wait \
  --output-format json > "$OUTPUT/notarization.json"
python3 - "$OUTPUT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; inspect notarization.json and the Apple notary log.')
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
python3 "$REPO/script/verify_release.py" "$APP" --distribution --notarized
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$OUTPUT/Grock-$VERSION-arm64.zip"
ditto "${ZIP_ARGS[@]}" "$APP" "$ZIP"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
# Check the ZIP people download, not just the app it came from. Plain unzip
# writes any ._ entries as files, the same way Archive Utility does.
if zipinfo -1 "$ZIP" | grep -Eq '(^|/)\._|^__MACOSX/'; then
  echo 'release: the ZIP contains AppleDouble (._) entries' >&2; exit 1
fi
EXTRACTED="$(mktemp -d "$OUTPUT/extracted.XXXXXX")"
unzip -q "$ZIP" -d "$EXTRACTED"
python3 "$REPO/script/verify_release.py" "$EXTRACTED/Grock.app" --distribution --notarized
rm -rf "$EXTRACTED"
rm "$UPLOAD"

# Appcast. generate_appcast signs the ZIP with the Grock EdDSA key (Keychain, or
# --sparkle-key) and merges the entry into the published appcast so older items
# survive. Only this run's verified ZIP goes in the folder, so the key never
# signs anything else.
GENERATE_APPCAST="$(find "$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin" -name generate_appcast -type f | head -n 1)"
[ -n "$GENERATE_APPCAST" ] || { echo 'release: could not find Sparkle generate_appcast' >&2; exit 1; }
APPCAST_DIR="$OUTPUT/appcast"
mkdir -p "$APPCAST_DIR"
ln "$ZIP" "$APPCAST_DIR/$(basename "$ZIP")"
[ -f "$REPO/appcast.xml" ] && cp "$REPO/appcast.xml" "$APPCAST_DIR/appcast.xml"
SIGNING_KEY=(--account Grock)
[ -z "$SPARKLE_KEY" ] || SIGNING_KEY=(--ed-key-file "$SPARKLE_KEY")
"$GENERATE_APPCAST" "${SIGNING_KEY[@]}" \
  --download-url-prefix "https://github.com/jaredatch/grock/releases/download/v$VERSION/" \
  --link "https://github.com/jaredatch/grock" \
  "$APPCAST_DIR"
xcrun swift "$REPO/script/verify_update.swift" "$APPCAST_DIR/appcast.xml" "$ZIP" "$APP"
cp "$APPCAST_DIR/appcast.xml" "$REPO/appcast.xml"
echo "VERIFIED RELEASE: $ZIP"
echo "APPCAST UPDATED: $REPO/appcast.xml (commit it after the GitHub Release is up)"
