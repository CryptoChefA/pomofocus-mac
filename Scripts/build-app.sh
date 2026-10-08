#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
TASK_BUILD_DIR=$(mktemp -d /tmp/pomofocus-build.XXXXXX)
APP_DIR="$PROJECT_DIR/outputs/Pomofocus.app"
TEMP_APP_DIR="$TASK_BUILD_DIR/Pomofocus.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist")
ARCHIVE_PATH="$PROJECT_DIR/outputs/Pomofocus-$VERSION.zip"
WIDGET_DIR="$TEMP_APP_DIR/Contents/PlugIns/PomofocusWidgetExtension.appex"
MODULE_CACHE_DIR="$PROJECT_DIR/work/module-cache"

mkdir -p "$MODULE_CACHE_DIR/clang" "$MODULE_CACHE_DIR/swiftpm"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR/swiftpm"
# Build against the toolchain's own SDK. The Observation macro in Swift 6.2 generates
# code the older 15.x SDK headers cannot type-check, so the app must not pin 15.4.
unset SDKROOT

cleanup() {
  rm -rf -- "$TASK_BUILD_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift build --disable-sandbox --scratch-path "$TASK_BUILD_DIR" --jobs 1 -c release

mkdir -p "$TEMP_APP_DIR/Contents/MacOS" "$TEMP_APP_DIR/Contents/Resources" "$WIDGET_DIR/Contents/MacOS"
cp "$TASK_BUILD_DIR/arm64-apple-macosx/release/Pomofocus" "$TEMP_APP_DIR/Contents/MacOS/Pomofocus"
cp "$TASK_BUILD_DIR/arm64-apple-macosx/release/PomofocusWidgetExtension" "$WIDGET_DIR/Contents/MacOS/PomofocusWidgetExtension"
cp "$PROJECT_DIR/Resources/Info.plist" "$TEMP_APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/WidgetInfo.plist" "$WIDGET_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$TEMP_APP_DIR/Contents/Resources/AppIcon.icns"
chmod 755 "$TEMP_APP_DIR/Contents/MacOS/Pomofocus"
chmod 755 "$WIDGET_DIR/Contents/MacOS/PomofocusWidgetExtension"
# Drop local and debug symbols from the shipped binaries: smaller on disk and fewer
# pages mapped at launch. Signing happens below, after stripping.
/usr/bin/strip -x "$TEMP_APP_DIR/Contents/MacOS/Pomofocus"
/usr/bin/strip -x "$WIDGET_DIR/Contents/MacOS/PomofocusWidgetExtension"

/usr/bin/xattr -cr "$TEMP_APP_DIR"
/usr/bin/codesign --force --sign - \
  --entitlements "$PROJECT_DIR/Resources/PomofocusWidget.entitlements" \
  --requirements '=designated => identifier "org.pomodorononna.app.widget"' \
  "$WIDGET_DIR"
# Keep the designated requirement stable between local builds. Calendar privacy
# consent is keyed to this requirement; the default ad-hoc cdhash changes on
# every build and makes macOS treat an update as a different app.
/usr/bin/codesign --force --sign - \
  --requirements '=designated => identifier "org.pomodorononna.app"' \
  "$TEMP_APP_DIR"
/usr/bin/codesign --verify --deep --strict "$TEMP_APP_DIR"

rm -f -- "$ARCHIVE_PATH"
/usr/bin/ditto -c -k --keepParent "$TEMP_APP_DIR" "$ARCHIVE_PATH"
/usr/bin/ditto "$TEMP_APP_DIR" "$APP_DIR"

echo "$ARCHIVE_PATH"
