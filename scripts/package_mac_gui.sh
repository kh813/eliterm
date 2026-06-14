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

cat << 'EOF' > "セキュリティ設定を開く.webloc"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>x-apple.systempreferences:com.apple.preference.security</string>
</dict>
</plist>
EOF

cat << 'EOF' > "1_インストールと起動の注意.txt"
【Eliterm のインストールと起動方法】

1. Eliterm.app を「アプリケーション」フォルダにコピーしてください。
2. コピーした Eliterm.app を右クリックし、「開く」を選択してください。
3. 警告が出た場合も、もう一度「開く」をクリックすると起動できます。

【それでも開けない場合（Macのセキュリティでブロックされる場合）】
「セキュリティ設定を開く.webloc」をダブルクリックしてください。
システム設定の「プライバシーとセキュリティ」が開きますので、
画面の下部にある「このまま開く」をクリックして許可してください。
EOF

echo "Creating DMG..."
# Note: GitHub Actions will run hdiutil on the directory containing both the app and the command.
mkdir -p Eliterm_Release
mv "$APP_DIR" Eliterm_Release/
mv "セキュリティ設定を開く.webloc" Eliterm_Release/
mv "1_インストールと起動の注意.txt" Eliterm_Release/

echo "App bundle created successfully."
