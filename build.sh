#!/bin/bash
# 編譯並更新 ~/Applications/Cryptobar.app
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/Cryptobar.app"
ICONSET="$(mktemp -d)/Cryptobar.iconset"

echo "▸ 編譯主程式"
swiftc -O main.swift -o cryptobar

echo "▸ 產生圖示"
swiftc -O makeicon.swift -o makeicon
./makeicon "$ICONSET"
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "▸ 打包 app bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp cryptobar "$APP/Contents/MacOS/Cryptobar"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "▸ 重新啟動"
pkill -f "Cryptobar" 2>/dev/null || true
sleep 1
open "$APP"

echo "✓ 完成：$APP"
