#!/usr/bin/env bash
# Set the marketing version and bump the build number everywhere they live.
# Sparkle compares build numbers, so every release needs a new one.
# The CHANGELOG entry is still yours to write.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
usage() {
  echo "usage: $0 X.Y.Z" >&2
}
[ "$#" -eq 1 ] || { usage; exit 64; }
NEW="$1"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { usage; exit 64; }

cd "$REPO"
OLD="$(sed -nE 's/^ *MARKETING_VERSION: "([0-9.]+)"$/\1/p' project.yml)"
BUILD="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: ([0-9]+)$/\1/p' project.yml)"
[ -n "$OLD" ] && [ -n "$BUILD" ] || { echo 'bump: could not read the current version from project.yml' >&2; exit 1; }
[ "$NEW" != "$OLD" ] || { echo "bump: already at $OLD" >&2; exit 1; }
[ "$(printf '%s\n%s\n' "$OLD" "$NEW" | sort -V | tail -n 1)" = "$NEW" ] || { echo "bump: $NEW is older than $OLD" >&2; exit 1; }
NEXT=$((BUILD + 1))

# file | current text | new text. Each current text must appear exactly once.
EDITS=(
  "project.yml|MARKETING_VERSION: \"$OLD\"|MARKETING_VERSION: \"$NEW\""
  "project.yml|CURRENT_PROJECT_VERSION: $BUILD|CURRENT_PROJECT_VERSION: $NEXT"
  "Grock/Utilities/AppInfo.swift|expectedMarketingVersion = \"$OLD\"|expectedMarketingVersion = \"$NEW\""
  "GrockTests/CorePolicyTests.swift|AppInfo.expectedMarketingVersion, \"$OLD\"|AppInfo.expectedMarketingVersion, \"$NEW\""
  ".github/ISSUE_TEMPLATE/bug.yml|placeholder: Grock $OLD,|placeholder: Grock $NEW,"
)

# Check everything before touching anything.
for edit in "${EDITS[@]}"; do
  IFS='|' read -r file from _ <<< "$edit"
  count="$(grep -cF -- "$from" "$file" || true)"
  [ "$count" = 1 ] || { echo "bump: expected one \"$from\" in $file, found $count" >&2; exit 1; }
done
for edit in "${EDITS[@]}"; do
  IFS='|' read -r file from to <<< "$edit"
  FROM="$from" TO="$to" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$file"
done

echo "Grock $OLD ($BUILD) -> $NEW ($NEXT)"
echo 'Next: add a dated CHANGELOG entry, then run the build and test scripts.'
