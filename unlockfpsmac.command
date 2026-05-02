#!/bin/bash
echo "man why do you even need this, vsync better trust"


type=$(osascript -e 'display dialog "in what way do you want to unlock fps?" buttons {"OpenGL (breaks visuals)","Virtual Display (MAX 240 FPS!)","cancel or revert"} default button "Virtual Display (MAX 240 FPS!)"')
if [[ "$type" == *"cancel or revert"* ]]; then
sus=$(osascript -e 'display dialog "in what way do you want to unlock fps?" buttons {"revert changes","cancel"} default button "cancel"')
fi
if [[ "$sus" == *"revert changes"* ]]; then
mv /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json.old
elif [[ "$sus" == *"cancel"* ]]; then
exit 0
fi


if [[ "$type" == *"OpenGL (breaks visuals)"* ]]; then
sed -i '' 's/<int name="FramerateCap">[0-9]\+<\/int>/<int name="FramerateCap">1000067<\/int>/g' ~/Library/Roblox/GlobalBasicSettings_13.xml
sed -i '' 's/<int name="GraphicsQualityLevel">[0-9]\+<\/int>/<int name="GraphicsQualityLevel">1<\/int>/g' ~/Library/Roblox/GlobalBasicSettings_13.xml
if [ -e "/Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json" ]; then
cp /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json.bak
osascript -e 'display alert "Warning" message "Copied ur old fflags to /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json.bak" as warning'
else
mkdir /Applications/Roblox.app/Contents/MacOS/ClientSettings

touch /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json
fi
echo '{"DFIntTaskSchedulerTargetFps":"100067","FFlagTaskSchedulerLimitTargetFpsTo2402":"False","DFIntNetworkPrediction":"120","DFIntServerTickRate":"60","FFlagDebugGraphicsPreferOpenGL":"True","FIntRenderShadowIntensity":"0","FIntRenderGrassHeightScaler":"0","FFlagDisablePostFx":"True"}
' > /Applications/Roblox.app/Contents/MacOS/ClientSettings/ClientAppSettings.json
#r u subsribed yet
exit 1
fi

sed -i '' 's/<int name="FramerateCap">[0-9]\+<\/int>/<int name="FramerateCap">240<\/int>/g' ~/Library/Roblox/GlobalBasicSettings_13.xml

if [ ! -d "/Applications/Roblox-fps-unlocked.app" ]; then
  
echo "Creating Roblox FPS Unlocked app..."

  mkdir -p "/Applications/Roblox-fps-unlocked.app/Contents/MacOS"

  # Info.plist
  cat > "/Applications/Roblox-fps-unlocked.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Roblox FPS Unlocked</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.robloxfpsunlocked</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>run.sh</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF

  # credits to appleblox, precompiled binary from me
  curl -L -o "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/virtualdisplay240" https://raw.githubusercontent.com/aNebNeb/macos-fps-unlocker/refs/heads/main/virtualdisplay240

  chmod +x "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/virtualdisplay240"
  xattr -c "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/virtualdisplay240"

  # Main launcher (minimal, no polling)
  cat > "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/run.sh" <<'EOF'
#!/bin/bash

/Applications/Roblox-fps-unlocked.app/Contents/MacOS/virtualdisplay240 &
VD_PID=$!

trap "kill $VD_PID 2>/dev/null" EXIT

/Applications/Roblox.app/Contents/MacOS/RobloxPlayer &
RBX_PID=$!

wait $RBX_PID
EOF

  chmod +x "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/run.sh"
  xattr -c "/Applications/Roblox-fps-unlocked.app/Contents/MacOS/run.sh"

  echo "Done: /Applications/Roblox-fps-unlocked.app"
else
  echo "App already exists."
fi
