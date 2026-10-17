#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "==> [1/6] Running unit tests..."
swift run CMDVTestRunner

echo "==> [2/6] Building release binary..."
swift build -c release --product CMDV
BIN_PATH="$(swift build -c release --show-bin-path)/CMDV"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Release binary not found at $BIN_PATH"
    exit 1
fi

APP_BUNDLE="$PROJECT_DIR/build/CMDV.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"

echo "==> [3/6] Generating AppIcon.icns..."
rm -rf "$ICONSET_DIR" "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
swift "$PROJECT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> [4/6] Assembling CMDV.app bundle..."
cp "$BIN_PATH" "$MACOS_DIR/CMDV"
chmod +x "$MACOS_DIR/CMDV"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "==> [5/6] Codesigning CMDV.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> [6/6] Installing to /Applications/CMDV.app and configuring LaunchAgent..."
pkill -x CMDV 2>/dev/null || true
rm -rf "/Applications/CMDV.app"
cp -R "$APP_BUNDLE" "/Applications/CMDV.app"

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
PLIST_PATH="$LAUNCH_AGENTS_DIR/com.cmdv.app.plist"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cmdv.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/CMDV.app/Contents/MacOS/CMDV</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

echo "==> Build & Installation complete:"
echo "    Workspace bundle: $APP_BUNDLE"
echo "    Installed bundle: /Applications/CMDV.app"
echo "    LaunchAgent:      $PLIST_PATH"
