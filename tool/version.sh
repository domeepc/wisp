#!/usr/bin/env bash
# Prints the app's version. On a tag (v1.2.0) it's the tag's; otherwise
# pubspec.yaml's major.minor and the number of commits, like 1.0.187, so
# each push to main shows a newer version. The count needs the full
# history (actions/checkout with fetch-depth: 0).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${GITHUB_REF_TYPE:-}" == tag ]]; then
  echo "${GITHUB_REF_NAME#v}"
else
  echo "$(sed -n 's/^version: *\([0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml).$(git rev-list --count HEAD)"
fi
