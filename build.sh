#!/bin/sh
# Compila o DeviceBar.app. Use `./build.sh install` para copiar para ~/Applications
# ou `./build.sh release` para gerar o zip da release em build/.
set -e
cd "$(dirname "$0")"

VERSION=1.0.0
APP=build/DeviceBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Binário universal: Apple Silicon e Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 main.swift -o build/DeviceBar-$arch
done
lipo -create build/DeviceBar-arm64 build/DeviceBar-x86_64 -output "$APP/Contents/MacOS/DeviceBar"
rm build/DeviceBar-arm64 build/DeviceBar-x86_64

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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
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

if [ "$1" = "release" ]; then
  ZIP=build/DeviceBar-$VERSION.zip
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Release: $ZIP"

  # DMG com o app e um atalho para Aplicativos, para instalar arrastando.
  DMG=build/DeviceBar-$VERSION.dmg
  STAGE=build/dmg
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname DeviceBar -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Release: $DMG"
fi
