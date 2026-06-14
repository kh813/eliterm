#!/bin/bash
set -e

echo "Building macOS GUI application..."
export MIX_ENV=prod

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
exec "$DIR/../Resources/eliterm/bin/eliterm" start
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
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
</dict>
</plist>
EOF

cat << 'EOF' > "1_【重要】初回起動の方法.txt"
【Eliterm のインストールと起動方法】

Eliterm は開発元未署名アプリのため、通常のダブルクリックでは起動できません。
システム設定を開かずに、以下の手順で起動してください：

1. 「Eliterm.app」を「アプリケーション」フォルダにコピーします。
2. コピーした Eliterm.app を **右クリック（または Controlキーを押しながらクリック）** し、メニューから「開く」を選択します。
3. 「開発元を検証できません」という警告ダイアログが出ますが、そこにある「開く」ボタンをクリックしてください。

この手順を行うことで、システム設定の「プライバシーとセキュリティ」画面を開く手間を省き、すぐにアプリを起動できます。
以降は通常のダブルクリックで起動できるようになります。
EOF

echo "Creating DMG..."
# Note: GitHub Actions will run hdiutil on the directory containing both the app and the command.
mkdir -p Eliterm_Release
mv "$APP_DIR" Eliterm_Release/
mv "1_【重要】初回起動の方法.txt" Eliterm_Release/

echo "App bundle created successfully."
