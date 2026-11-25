#!/bin/sh
# Archives the iOS app without code signing and packs it as out/<name>. Usage: sh scripts/ios_ipa.sh baytna-unsigned.ipa
set -e
NAME="$1"
ROOT="$(pwd)"
rm -rf build/App.xcarchive build/Payload
xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -archivePath build/App.xcarchive archive \
  MARKETING_VERSION="1.0.${BUILD_NUMBER:-0}" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS=YES \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" > build.log 2>&1 || { grep -nE "error:|fatal|ARCHIVE FAILED" -A3 build.log || tail -n 150 build.log; exit 1; }
mkdir -p build/Payload out
cp -R build/App.xcarchive/Products/Applications/App.app build/Payload/
ls build/Payload/App.app/PlugIns 2>/dev/null || true
(cd build && zip -qry "$ROOT/out/$NAME" Payload)
echo "packed out/$NAME"
