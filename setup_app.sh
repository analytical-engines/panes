#!/bin/bash
# Panes.appバンドルのセットアップスクリプト

APP_PATH="Panes.app"
BUILD_PATH=".build/debug/Panes"

# .appバンドル構造を作成
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# 実行ファイルをコピー
cp "$BUILD_PATH" "$APP_PATH/Contents/MacOS/"

# Info.plistをコピー
cp Resources/Info.plist "$APP_PATH/Contents/"

# アイコンをコピー
cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/"

echo "✅ Panes.app bundle created successfully!"
echo "📍 Location: $APP_PATH"
