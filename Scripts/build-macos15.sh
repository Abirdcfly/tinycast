#!/bin/bash
# Builds Tinycast for macOS 15 on an Intel Mac without Xcode: the Command Line Tools toolchain,
# a hand-assembled bundle, and the same Debug channel Xcode produces. docs/macos15-intel.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
TARGET="${TARGET:-x86_64-apple-macos15.0}"
BUILD="$ROOT/build/macos15"
APP_NAME="Tinycast Dev"
BUNDLE_ID="com.abueammar.tinycast.dev"
APP="$BUILD/$APP_NAME.app"
HELPERS="$APP/Contents/Helpers"

echo "==> Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HELPERS"

app_sources() {
    find Tinycast -name '*.swift' \
        ! -path 'Tinycast/Features/Clipboard/Service/ClipboardTextExtractor.swift' \
        ! -path 'Tinycast/Features/Clipboard/Service/ClipboardTextHelper.swift' \
        ! -path 'Tinycast/Features/Dictation/Helper/*' \
        ! -path 'Tinycast/Features/FileSearch/Helper/*'
}

echo "==> Compiling $APP_NAME (${TARGET})"
app_sources > "$BUILD/app-sources.txt"
# FoundationModels has no macOS 15 runtime; a weak link keeps launch working without it.
swiftc -swift-version 6 -target "$TARGET" -sdk "$SDK" -module-name Tinycast \
    -DDEBUG -Onone -parse-as-library \
    -Xlinker -weak_framework -Xlinker FoundationModels \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    @"$BUILD/app-sources.txt"

echo "==> Helpers"
compile_tool() {
    local name=$1
    shift
    swiftc -swift-version 6 -target "$TARGET" -sdk "$SDK" -module-name "$name" \
        -DDEBUG -Onone -parse-as-library -o "$HELPERS/$name" "$@"
}

compile_tool ClipboardTextHelper \
    Tinycast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
    Tinycast/Features/Clipboard/Service/ClipboardTextHelper.swift

compile_tool FileIndexHelper \
    Tinycast/Features/FileSearch/Helper/FileIndexHelper.swift \
    Tinycast/Features/FileSearch/Model/FileSearchIgnoreList.swift \
    Tinycast/Features/FileSearch/Model/FileSearchPolicy.swift \
    Tinycast/Features/FileSearch/Model/FileSearchQuery.swift \
    Tinycast/Features/FileSearch/Model/FileSearchResult.swift \
    Tinycast/Features/FileSearch/Model/FileSearchScope.swift \
    Tinycast/Features/FileSearch/Service/FileIndexCrawler.swift \
    Tinycast/Features/FileSearch/Service/FileIndexSnapshot.swift

echo "==> Dictation helper"
DICTATION_NAME="Tinycast Dev Dictation"
DICTATION_APP="$HELPERS/$DICTATION_NAME.app"
mkdir -p "$DICTATION_APP/Contents/MacOS"
swiftc -swift-version 6 -target "$TARGET" -sdk "$SDK" -module-name DictationHelper \
    -DDEBUG -Onone -parse-as-library \
    -o "$DICTATION_APP/Contents/MacOS/$DICTATION_NAME" \
    $(find Tinycast/Features/Dictation/Helper -name '*.swift') \
    Tinycast/Features/Dictation/Model/DictationModel.swift \
    Tinycast/Features/Dictation/Model/DictationAudioChunks.swift \
    Tinycast/Features/Dictation/Model/DictationLanguage.swift \
    Tinycast/Features/Dictation/Service/DictationWire.swift
python3 "$ROOT/Scripts/render-plist.py" Tinycast/Features/Dictation/Helper/Info.plist \
    "$DICTATION_APP/Contents/Info.plist" \
    DEVELOPMENT_LANGUAGE=en \
    DICTATION_EXECUTABLE_NAME="$DICTATION_NAME" \
    EXECUTABLE_NAME="$DICTATION_NAME" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID.dictation"

echo "==> Info.plist"
python3 "$ROOT/Scripts/render-plist.py" Tinycast/Info.plist "$APP/Contents/Info.plist" \
    EXECUTABLE_NAME="$APP_NAME" \
    PRODUCT_NAME="$APP_NAME" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION=0.1.0 \
    CURRENT_PROJECT_VERSION=1 \
    MACOSX_DEPLOYMENT_TARGET="${TARGET##*macos}" \
    TINYCAST_URL_SCHEME=tinycast-dev
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"

echo "==> Resources"
cp Tinycast/Resources/RaycastRuntime.generated.js "$APP/Contents/Resources/"
cp NOTICE.md "$APP/Contents/Resources/"
cp -R Tinycast/Resources/EmojiKeywords "$APP/Contents/Resources/EmojiKeywords"

# actool is part of Xcode; each imageset is copied beside the bundle under the name its views ask
# for, which is how `NSImage(named:)` resolves it without a catalog.
for set in Tinycast/Assets.xcassets/*.imageset; do
    python3 "$ROOT/Scripts/flatten-imageset.py" "$set" "$APP/Contents/Resources"
done

echo "==> Localizations"
python3 "$ROOT/Scripts/localize-xcstrings.py" \
    Tinycast/Resources/Localizable.xcstrings "$APP/Contents/Resources"

echo "==> Icon"
swift "$ROOT/Scripts/make-icon.swift" \
    Tinycast/Assets.xcassets/MenuBarIcon.imageset/thunder.svg \
    "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$HELPERS/ClipboardTextHelper"
codesign --force --sign - "$HELPERS/FileIndexHelper"
codesign --force --sign - "$DICTATION_APP"
codesign --force --sign - "$APP"

echo "==> Built $APP"
echo "    Run: open \"$APP\""
