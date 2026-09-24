#!/usr/bin/env bash
# Canonical test runner. Agents must use this, not raw xcodebuild test.
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
  echo "usage: $0 [--filter TEST_IDENTIFIER]" >&2
}

FILTER_ARGS=()
case "${1:-}" in
  "")
    ;;
  --filter)
    if [ "$#" -ne 2 ]; then
      usage
      exit 64
    fi
    filter="$2"
    case "$filter" in
      */*)
        ;;
      *)
        filter="GrockTests/$filter"
        ;;
    esac
    FILTER_ARGS=(-only-testing "$filter")
    ;;
  *)
    usage
    exit 64
    ;;
esac

if [ "${1:-}" != "--filter" ] && [ "$#" -ne 0 ]; then
  usage
  exit 64
fi

cd "$REPO"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "test: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

xcodegen generate
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$XDG_CACHE_HOME"

log="$(mktemp "${TMPDIR:-/tmp}/grock-test.XXXXXX")"
status=0
set +e
xcodebuild test \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" \
  SWIFT_MODULE_CACHE_PATH="$SWIFT_MODULE_CACHE_PATH" \
  ${FILTER_ARGS[@]+"${FILTER_ARGS[@]}"} 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
set -e

count="$(sed -nE 's/.*Executed ([0-9]+) tests?, with [0-9]+ failures?.*/\1/p' "$log" | tail -1)"
rm -f "$log"

if [ -z "$count" ]; then
  count=0
fi

printf 'GROCK_TEST_COUNT=%s\n' "$count"
if [ "$status" -eq 0 ] && [ "${1:-}" != "--filter" ]; then
  python3 "$REPO/script/test_file_access.py"
fi
exit "$status"
