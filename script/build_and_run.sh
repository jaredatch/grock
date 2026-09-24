#!/usr/bin/env bash
# Canonical build (+ optional launch). Agents must use this, not raw xcodebuild.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="platform=macOS,arch=arm64"
DERIVED_DATA="$REPO/DerivedData"
export CLANG_MODULE_CACHE_PATH="$DERIVED_DATA/ModuleCache.noindex"
export SWIFT_MODULE_CACHE_PATH="$DERIVED_DATA/ModuleCache.noindex"
export SWIFTPM_MODULECACHE_OVERRIDE="$DERIVED_DATA/ModuleCache.noindex"
export XDG_CACHE_HOME="$DERIVED_DATA/XDGCache"
SCHEME="Grock"

usage() {
  echo "usage: $0 [--headless] [--clean]" >&2
}

HEADLESS=0
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --headless) HEADLESS=1 ;;
    --clean) CLEAN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

cd "$REPO"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "build_and_run: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

if [ "$CLEAN" -eq 1 ]; then
  rm -rf "$DERIVED_DATA"
fi

xcodegen generate
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME"

xcodebuild build \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
  SWIFT_MODULE_CACHE_PATH="$SWIFT_MODULE_CACHE_PATH"

if [ "$HEADLESS" -eq 1 ]; then
  echo "SMOKE OK"
  exit 0
fi

settings="$(xcodebuild \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -showBuildSettings \
  CODE_SIGNING_ALLOWED=NO)"
target_build_dir="$(printf '%s\n' "$settings" | awk -F' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }')"
full_product_name="$(printf '%s\n' "$settings" | awk -F' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }')"

if [ -z "$target_build_dir" ] || [ -z "$full_product_name" ]; then
  echo "build_and_run: could not resolve built app path" >&2
  exit 1
fi

app_path="$target_build_dir/$full_product_name"
echo "Launching $app_path"
open "$app_path"
