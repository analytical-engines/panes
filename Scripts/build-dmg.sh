#!/bin/bash
set -euo pipefail

# Panes DMG Build Script
# Usage: ./scripts/build-dmg.sh [version]
# Example: ./scripts/build-dmg.sh 0.3.1

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/Panes.xcodeproj"
SCHEME="Panes"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Panes.app"

# バージョンを引数またはInfo.plistから取得
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist")
fi

DMG_NAME="Panes.v${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "=== Panes DMG Builder ==="
echo "Version: $VERSION"
echo "Output:  $DMG_PATH"
echo ""

# ビルドディレクトリをクリーン
echo "--- Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Info.plistのビルドタイムスタンプを更新
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")
/usr/libexec/PlistBuddy -c "Set :BuildTimestamp $TIMESTAMP" "$PROJECT_DIR/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright '© 2026 Analytical Engines
MIT License
Built: $BUILD_DATE'" "$PROJECT_DIR/Resources/Info.plist"

# ビルド番号をインクリメント
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/Resources/Info.plist")
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PROJECT_DIR/Resources/Info.plist"
echo "--- Build number: $CURRENT_BUILD -> $NEW_BUILD"

# Release ビルド
echo "--- Building $SCHEME (Release)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/Panes.xcarchive" \
    archive \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -5

# .appを取り出す
ARCHIVE_APP="$BUILD_DIR/Panes.xcarchive/Products/Applications/$APP_NAME"
STAGE_DIR="$BUILD_DIR/dmg-stage"
mkdir -p "$STAGE_DIR"
cp -R "$ARCHIVE_APP" "$STAGE_DIR/"

echo "--- App size: $(du -sh "$STAGE_DIR/$APP_NAME" | cut -f1)"

# DMG作成
echo "--- Creating DMG..."
# Applicationsへのシンボリックリンクを追加
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "Panes" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    2>&1 | tail -3

echo ""
echo "=== Done ==="
echo "DMG: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "Next steps:"
echo "  git add Resources/Info.plist"
echo "  git push origin main --tags"
echo "  gh release create v$VERSION '$DMG_PATH' --title 'v$VERSION' --notes-file RELEASE_NOTES.md"
