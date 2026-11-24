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
# From the macOS 27 SDK, SwiftUI's @State is a macro whose plugin comes only with Xcode.
# With the Command Line Tools alone, fall back to the newest installed 26.x SDK.
TOOLCHAIN_DIR=$(xcode-select -p)
if [[ "$TOOLCHAIN_DIR" == */CommandLineTools ]] && ! ls "$TOOLCHAIN_DIR"/usr/lib/swift/host/plugins/*SwiftUIMacros* >/dev/null 2>&1; then
  DEFAULT_SDK=$(xcrun --show-sdk-path)
  if [[ "${DEFAULT_SDK:A:t}" != MacOSX26* ]]; then
    FALLBACK_SDK=$(ls -d "$TOOLCHAIN_DIR"/SDKs/MacOSX26.*.sdk(N) | sort -V | tail -1)
    if [[ -n "$FALLBACK_SDK" ]]; then
      export SDKROOT="$FALLBACK_SDK"
      echo "No SwiftUI macro plugin in the Command Line Tools; building with ${FALLBACK_SDK:t}"
    fi
  fi
fi

cleanup() {
  rm -rf -- "$TASK_BUILD_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
# SwiftPM's newer default build system (swiftbuild) stamps the binary as built with the
# macOS 14 SDK, which puts AppKit and SwiftUI in old compatibility modes (sheets drew in the
# wrong place). The native build system records the real SDK, so use it while it exists.
BUILD_SYSTEM=()
if swift build --help 2>&1 | grep -q -- "--build-system"; then
  BUILD_SYSTEM=(--build-system native)
fi
swift build "${BUILD_SYSTEM[@]}" --disable-sandbox --scratch-path "$TASK_BUILD_DIR" --jobs 1 -c release 2> >(grep -v "has been deprecated" >&2)
BIN_DIR=$(swift build "${BUILD_SYSTEM[@]}" --disable-sandbox --scratch-path "$TASK_BUILD_DIR" -c release --show-bin-path 2>/dev/null)
# Refuse a binary that records an SDK older than 26, for the reason above.
for binary in "$BIN_DIR/Pomofocus" "$BIN_DIR/PomofocusWidgetExtension"; do
  LINKED_SDK=$(otool -l "$binary" | awk '/LC_BUILD_VERSION/ {found=1} found && $1 == "sdk" {print $2; exit}')
  if [[ "${LINKED_SDK%%.*}" -lt 26 ]]; then
    echo "error: ${binary:t} records SDK $LINKED_SDK; macOS would run it in compatibility mode" >&2
    exit 1
  fi
  echo "${binary:t}: SDK $LINKED_SDK"
done

mkdir -p "$TEMP_APP_DIR/Contents/MacOS" "$TEMP_APP_DIR/Contents/Resources" "$WIDGET_DIR/Contents/MacOS"
cp "$BIN_DIR/Pomofocus" "$TEMP_APP_DIR/Contents/MacOS/Pomofocus"
cp "$BIN_DIR/PomofocusWidgetExtension" "$WIDGET_DIR/Contents/MacOS/PomofocusWidgetExtension"
cp "$PROJECT_DIR/Resources/Info.plist" "$TEMP_APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/WidgetInfo.plist" "$WIDGET_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$TEMP_APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR"/Resources/Sounds/*.m4a "$TEMP_APP_DIR/Contents/Resources/"
# The London theme's skyline layers (made by Scripts/london/render.sh).
cp "$PROJECT_DIR"/Resources/London/*.png "$TEMP_APP_DIR/Contents/Resources/"
# Licensed audio (the focus reset's meditation music) ships inside the app but isn't in
# the public repo. Builds without it just don't offer that option.
for licensed in "$PROJECT_DIR"/Resources/Licensed/*.m4a(N); do
  cp "$licensed" "$TEMP_APP_DIR/Contents/Resources/"
done
# The widget's buttons and the app's Spotlight and Shortcuts actions are App Intents;
# macOS needs their metadata, which Xcode would write. Read from the unstripped binaries,
# so this comes before strip.
/usr/bin/python3 "$PROJECT_DIR/Scripts/appintents-metadata.py" \
  "$WIDGET_DIR/Contents/MacOS/PomofocusWidgetExtension" \
  "$PROJECT_DIR/Sources/PomofocusWidget" \
  "$WIDGET_DIR/Contents/Resources/Metadata.appintents"
/usr/bin/python3 "$PROJECT_DIR/Scripts/appintents-metadata.py" \
  "$TEMP_APP_DIR/Contents/MacOS/Pomofocus" \
  "$PROJECT_DIR/Sources/PomodoroNonna" \
  "$TEMP_APP_DIR/Contents/Resources/Metadata.appintents"
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
# --norsrc keeps macOS metadata (._ files) out of the archive.
/usr/bin/ditto -c -k --norsrc --keepParent "$TEMP_APP_DIR" "$ARCHIVE_PATH"
/usr/bin/ditto "$TEMP_APP_DIR" "$APP_DIR"
# The unpacked copy has the installed app's bundle id. Unregister it so macOS keeps
# running the widget from /Applications; otherwise the widget can vanish from the gallery.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP_DIR" 2>/dev/null || true
/usr/bin/pluginkit -r "$APP_DIR/Contents/PlugIns/PomofocusWidgetExtension.appex" 2>/dev/null || true

echo "$ARCHIVE_PATH"
