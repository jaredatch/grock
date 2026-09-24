#!/usr/bin/env bash
# Build a signed, sandboxed Release app. Publication is a separate step.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY=""
PROFILE=""
LOCAL=0
SIGN_ONLY=0
usage() {
  cat <<'USAGE'
usage: ./script/release.sh --local
       ./script/release.sh --identity 'Developer ID Application: …' --sign-only
       ./script/release.sh --identity 'Developer ID Application: …' --notary-profile PROFILE

--local signs ad hoc for sandbox testing; its output is not distributable.
--sign-only verifies a Developer ID build without uploading it to Apple.
The full workflow notarizes and staples the app, then creates a ZIP, a checksum, and the Sparkle appcast.
Credentials stay in the named notarytool Keychain profile.
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --local) LOCAL=1; shift ;;
    --sign-only) SIGN_ONLY=1; shift ;;
    --identity|--notary-profile)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { usage >&2; exit 64; }
      case "$1" in
        --identity) IDENTITY="$2" ;;
        --notary-profile) PROFILE="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done
if [ "$LOCAL" -eq 1 ]; then
  [ -z "$IDENTITY$PROFILE" ] && [ "$SIGN_ONLY" -eq 0 ] || { usage >&2; exit 64; }
  IDENTITY="-"
else
  case "$IDENTITY" in
    'Developer ID Application: '*) ;;
    *) echo 'release: provide a Developer ID Application identity, or use --local' >&2; exit 64 ;;
  esac
  if [ "$SIGN_ONLY" -eq 1 ]; then
    [ -z "$PROFILE" ] || { usage >&2; exit 64; }
  else
    [ -n "$PROFILE" ] || { echo 'release: --notary-profile is required (or use --sign-only)' >&2; exit 64; }
  fi
fi

command -v xcodegen >/dev/null || { echo 'release: install XcodeGen first' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'release: python3 is required for verification' >&2; exit 1; }
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[ "${SDK_VERSION%%.*}" -ge 26 ] || { echo 'release: Xcode with the macOS 26 SDK or newer is required' >&2; exit 1; }
if [ -n "$PROFILE" ]; then
  # Validate the stored profile before spending time on the build. No credential output.
  xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
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

UPLOAD="$OUTPUT/notary-upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait \
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
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
rm "$UPLOAD"

# Appcast. generate_appcast signs the ZIP with the Grock EdDSA key in Keychain
# and merges the entry into the published appcast so older items survive.
GENERATE_APPCAST="$(find "$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin" -name generate_appcast -type f | head -n 1)"
[ -n "$GENERATE_APPCAST" ] || { echo 'release: could not find Sparkle generate_appcast' >&2; exit 1; }
APPCAST_DIR="$OUTPUT/appcast"
mkdir -p "$APPCAST_DIR"
ln "$ZIP" "$APPCAST_DIR/$(basename "$ZIP")"
[ -f "$REPO/appcast.xml" ] && cp "$REPO/appcast.xml" "$APPCAST_DIR/appcast.xml"
"$GENERATE_APPCAST" --account Grock \
  --download-url-prefix "https://github.com/jaredatch/grock/releases/download/v$VERSION/" \
  --link "https://github.com/jaredatch/grock" \
  "$APPCAST_DIR"
cp "$APPCAST_DIR/appcast.xml" "$REPO/appcast.xml"
echo "VERIFIED RELEASE: $ZIP"
echo "APPCAST UPDATED: $REPO/appcast.xml (commit it after the GitHub Release is up)"
