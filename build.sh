#!/bin/sh
# Compila o DeviceBar.app. Use `./build.sh install` para copiar para ~/Applications.
set -e
cd "$(dirname "$0")"

APP=build/DeviceBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 main.swift -o "$APP/Contents/MacOS/DeviceBar"

# Ícone: o DeviceBar.icon (formato do Icon Composer) vira Assets.car, com Liquid Glass
# no macOS 26, e DeviceBar.icns, usado pelas versões anteriores.
# O actool não resolve caminhos relativos a partir da pasta atual, por isso o $PWD.
xcrun actool "$PWD/DeviceBar.icon" --compile "$PWD/$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 13.0 --app-icon DeviceBar \
  --output-partial-info-plist "$PWD/build/icon-info.plist" > build/actool.log
if [ ! -f "$APP/Contents/Resources/Assets.car" ]; then cat build/actool.log; exit 1; fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DeviceBar</string>
  <key>CFBundleIdentifier</key><string>dev.andersu.devicebar</string>
  <key>CFBundleExecutable</key><string>DeviceBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>DeviceBar</string>
  <key>CFBundleIconName</key><string>DeviceBar</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Gerado: $APP"

if [ "$1" = "install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/DeviceBar.app
  cp -R "$APP" ~/Applications/
  echo "Instalado em ~/Applications/DeviceBar.app"
fi
