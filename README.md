# GPS Changer

Mac app that sets a connected iPhone's location: search an address or place (Apple Maps), type or paste
coordinates (decimal, degrees-minutes-seconds, N/S/E/W, Google/Apple Maps links), or click the map. Then
**Set iPhone Location**; **Use Real Location** turns it off. Saved and recent places in the sidebar.

Under the hood it's Apple's `xcrun devicectl device simulate location coordinate|clear` (the location simulation
Xcode uses), so it needs Xcode, the iPhone paired with this Mac (cable or same Wi-Fi) and Developer Mode on.
The simulated location stays until Use Real Location (or the iPhone restarts).

- Build: `xcodegen generate && xcodebuild -project GPSChanger.xcodeproj -scheme GPSChanger -configuration Release -derivedDataPath build`,
  then `ditto "build/Build/Products/Release/GPS Changer.app" "/Applications/GPS Changer.app"`.
- Icon: `swift scripts/make-icon.swift`.
- devicectl reads "-79.38" as an option: pass `--longitude=-79.38`.
