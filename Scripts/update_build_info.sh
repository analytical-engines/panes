#!/bin/bash
# ビルド番号とタイムスタンプを自動更新するスクリプト
# Xcodeの Build Phases > Run Script で実行

PLIST_PATH="${PROJECT_DIR}/Resources/Info.plist"

# 現在のビルド番号を取得してインクリメント
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST_PATH")
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))

# ビルド番号を更新
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD_NUMBER" "$PLIST_PATH"

# タイムスタンプを更新（ISO8601形式、UTC）
TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_DISPLAY=$(date -u +"%Y-%m-%d %H:%M UTC")
/usr/libexec/PlistBuddy -c "Set :BuildTimestamp $TIMESTAMP_ISO" "$PLIST_PATH"
YEAR=$(date +"%Y")
/usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright © $YEAR Analytical Engines
MIT License
Built: $TIMESTAMP_DISPLAY" "$PLIST_PATH"

echo "Build number updated: $BUILD_NUMBER -> $NEW_BUILD_NUMBER"
echo "Timestamp updated: $TIMESTAMP_DISPLAY"
