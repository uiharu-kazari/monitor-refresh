#!/bin/zsh
# Build MonitorRefresh.app into ~/Applications (no Xcode project needed).
set -e
cd "$(dirname "$0")"

APP="$HOME/Applications/MonitorRefresh.app"
mkdir -p "$APP/Contents/MacOS"

swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/MonitorRefresh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign -s - --force "$APP"

echo "Built $APP"
echo "Launch it with:  open \"$APP\""
echo "To start at login: System Settings → General → Login Items → add MonitorRefresh"
