# GPS Changer

A Mac app that sets a connected iPhone's location. You can search an address or place (Apple Maps), type or paste
coordinates (decimal, degrees-minutes-seconds, N/S/E/W, or a Google/Apple Maps link), or click the map. Then press
**Set iPhone Location**. **Use Real Location** turns it off and the iPhone goes back to its real GPS.
Saved and recent places are in the sidebar.

It uses Apple's own location simulation (`xcrun devicectl device simulate location`, the same thing Xcode does), so
nothing is installed on the iPhone.

## What you need
- A Mac with **macOS 26** or later and **Xcode** installed (free on the Mac App Store; open it once so it finishes
  installing its components). The app runs Xcode's `devicectl` tool.
- The iPhone **paired with the Mac**: connect it with a cable once, unlock it and tap **Trust**. After that it also
  works over the same Wi-Fi.
- **Developer Mode** on the iPhone: Settings → Privacy & Security → Developer Mode → On (the iPhone restarts).
  If the switch isn't there, connect the iPhone to the Mac and open Xcode once (Window → Devices and Simulators);
  then it appears.

## Install
1. Download **GPS-Changer-macOS.zip** from the [latest release](../../releases/latest), unzip it, and move
   **GPS Changer** to Applications.
2. The app isn't notarized by Apple, so the first time macOS blocks it. Either open
   System Settings → Privacy & Security and click **Open Anyway**, or run once in Terminal:
   `xattr -dr com.apple.quarantine "/Applications/GPS Changer.app"`

## Use
1. Pick the iPhone in the toolbar (↻ looks again).
2. Search an address, paste coordinates, or click the map: this only puts a pin on the map.
3. Press **Set iPhone Location** (⌘↩). The status line says when the iPhone is there.
   Apps that already had a location (Google Maps, for example) may need to be closed and reopened.
4. **Use Real Location** when you're done. The simulated location stays until then.

If something fails, the status line shows the error, and every `devicectl` run is logged in
`~/Library/Logs/GPS Changer.log`.

## Build from source
```
brew install xcodegen
xcodegen generate
xcodebuild -project GPSChanger.xcodeproj -scheme GPSChanger -configuration Release -derivedDataPath build
ditto "build/Build/Products/Release/GPS Changer.app" "/Applications/GPS Changer.app"
```
- Icon: `swift scripts/make-icon.swift`.
- devicectl reads `-79.38` as an option, so the app passes `--longitude=-79.38`.
