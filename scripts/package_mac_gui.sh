#!/bin/bash
set -e

echo "Building macOS GUI application..."
export MIX_ENV=prod

# Compile sleep watcher to priv/ so it gets bundled into the release
swiftc priv/mac_sleep_watcher.swift -o priv/eliterm_sleep_watcher

# Build the release
mix release eliterm --overwrite

# Create .app structure
APP_DIR="Eliterm.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy icon
cp priv/icon.png "$APP_DIR/Contents/Resources/icon.png"

# Copy the Elixir release into Resources
cp -R _build/prod/rel/eliterm "$APP_DIR/Contents/Resources/eliterm"

# Create launcher script
cat << 'EOF' > "$APP_DIR/Contents/MacOS/Eliterm"
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR/../Resources/eliterm"
export RELEASE_ROOT="$(pwd)"
pkill -f "Eliterm.app/Contents/Resources" 2>/dev/null || true
killall eliterm_sleep_watcher 2>/dev/null || true
sleep 0.5
exec ./bin/eliterm start
EOF

chmod +x "$APP_DIR/Contents/MacOS/Eliterm"

# Create Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Eliterm</string>
    <key>CFBundleIconFile</key>
    <string>icon.png</string>
    <key>CFBundleIdentifier</key>
    <string>com.kh813.eliterm</string>
    <key>CFBundleName</key>
    <string>Eliterm</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.15</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
EOF

cat << 'EOF' > "1_【重要】初回起動の方法.txt"
【Eliterm の初回起動について（重要）】

Elitermはオープンソースソフトウェアであり、現在Appleの有償開発者署名を行っていないため、
Macのセキュリティ機能（Gatekeeper）により、そのままダブルクリックしても起動できません。

初回のみ、以下の手順で起動してください。

1. 「Eliterm.app」を「アプリケーション (Applications)」フォルダにドラッグ＆ドロップしてコピーします。
2. コピー先の「Eliterm.app」を **右クリック（またはControl+クリック）** します。
3. メニューから「開く」を選択します。
4. 「開発元を検証できません」という警告ダイアログが出ますが、そこにある「開く」ボタンをクリックしてください。

この操作を行うことで、2回目以降は普通にダブルクリックで起動できるようになります。
EOF

echo "Creating DMG..."
# Note: GitHub Actions will run hdiutil on the directory containing both the app and the command.
rm -rf Eliterm_Release
mkdir -p Eliterm_Release
mv "$APP_DIR" Eliterm_Release/
mv "1_【重要】初回起動の方法.txt" Eliterm_Release/
ln -s /Applications Eliterm_Release/Applications

echo "App bundle created successfully."
