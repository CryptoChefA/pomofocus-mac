#!/bin/zsh
# After publishing a GitHub release, points the Homebrew cask at it.
# Usage: Scripts/update-homebrew.sh <version> <path to a clone of CryptoChefA/homebrew-tap>
# It downloads the release's Pomofocus.zip, writes its checksum and the version into
# Casks/pomofocus.rb, and commits. Push the tap afterwards.
set -euo pipefail
VERSION=${1:?version, like 0.22.9}
TAP=${2:?path to the homebrew-tap clone}
CASK="$TAP/Casks/pomofocus.rb"
URL="https://github.com/CryptoChefA/pomofocus-mac/releases/download/v$VERSION/Pomofocus.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/Pomofocus.zip" "$URL"
SHA=$(shasum -a 256 "$TMP/Pomofocus.zip" | awk '{print $1}')
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP" add Casks/pomofocus.rb
git -C "$TAP" commit -m "Pomofocus for Mac $VERSION"
echo "Cask now at $VERSION ($SHA). Push $TAP to publish it."
