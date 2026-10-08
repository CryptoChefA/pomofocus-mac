#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SOURCE_ICON="$PROJECT_DIR/Resources/AppIcon.svg"
ICON_RENDERER="$PROJECT_DIR/Scripts/render-icon.swift"
ICNS_BUILDER="$PROJECT_DIR/Scripts/build-icns.swift"
TASK_ICON_DIR=$(mktemp -d /tmp/pomofocus-icon.XXXXXX)
ICONSET_DIR="$TASK_ICON_DIR/AppIcon.iconset"
TEMP_ICNS_PATH="$TASK_ICON_DIR/AppIcon.icns"
MASTER_PNG="$PROJECT_DIR/outputs/Pomofocus-AppIcon.png"
ICNS_PATH="$PROJECT_DIR/Resources/AppIcon.icns"
MODULE_CACHE_DIR="$PROJECT_DIR/work/module-cache"

mkdir -p "$PROJECT_DIR/work" "$PROJECT_DIR/outputs" "$MODULE_CACHE_DIR/clang"
mkdir -p "$ICONSET_DIR"

cleanup() {
  rm -rf -- "$TASK_ICON_DIR"
}
trap cleanup EXIT

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang"
if test -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi

swift "$ICON_RENDERER" "$SOURCE_ICON" "$MASTER_PNG"

for specification in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  size=${specification%% *}
  filename=${specification#* }
  sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
done

swift "$ICNS_BUILDER" "$ICONSET_DIR" "$TEMP_ICNS_PATH"
cp "$TEMP_ICNS_PATH" "$ICNS_PATH"
/usr/bin/xattr -c "$ICNS_PATH" 2>/dev/null || true
echo "$ICNS_PATH"
