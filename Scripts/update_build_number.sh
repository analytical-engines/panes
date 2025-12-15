#!/bin/bash
# Update build number to current timestamp (YYYYMMDDHHMM)

PLIST_PATH="${PROJECT_DIR:-$(dirname "$0")/..}/Resources/Info.plist"
BUILD_NUMBER=$(date +%Y%m%d%H%M)

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"
echo "Updated CFBundleVersion to $BUILD_NUMBER"
