#!/bin/bash
# build/LuLu Sidekick.app を作って署名する。毎回同じ署名 ID・同じバンドル ID なので、
# 再ビルドしてもアクセシビリティ許可が外れにくい。
set -euo pipefail
cd "$(dirname "$0")/.."
# 署名 ID は環境変数 SIGN_IDENTITY で渡す（例: "Apple Development: Your Name (TEAMID)"）。
# 無ければ ad-hoc 署名（"-"）。ad-hoc だと再ビルドのたびにアクセシビリティの許可を付け直す必要がある。
IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-dev.kazuph.lulu-sidekick}"
APP="build/LuLu Sidekick.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LuLuSidekick"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LuLuSidekick"
# アプリのアイコン: Resources/AppIcon.png（1024px。元は Resources/AppIcon.svg）から .icns を作る
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# アプリのアイコン: Resources/AppIcon.png（1024px。元は Resources/AppIcon.svg）から .icns を作る
mkdir -p "$APP/Contents/Resources"
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>LuLu Sidekick</string>
  <key>CFBundleExecutable</key><string>LuLuSidekick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=2 "$APP"
echo "OK: $APP"
