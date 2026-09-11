# Baseus Menu

A native macOS menu bar app for **Baseus Bass BP1 Pro ANC** built with SwiftUI, AppKit, and CoreBluetooth. Features zero WebView, Node.js, external dependencies, or telemetry.

Protocol ported from [elaxptr/baseus-desktop](https://github.com/elaxptr/baseus-desktop) (see [THIRD_PARTY_NOTICES.md](https://www.google.com/search?q=THIRD_PARTY_NOTICES.md)).

## Quick Start

1. Copy `dist/Baseus Menu.app` to `/Applications`.
2. Launch the app (runs purely in the menu bar).
3. Grant Bluetooth permissions. Open your earbud case and take the earbuds out.
4. Click the menu icon → **Search for earbuds** → **Connect**.
5. The app automatically links classic Bluetooth audio and selects the earbuds as output.

> **Note**: If your earbuds are not yet paired with macOS, pair them first in System Settings. The app uses ad-hoc codesigning; bypass Gatekeeper via *System Settings > Privacy & Security* if prompted. Requires macOS 13 Ventura or newer.

## Key Features

* **Battery Monitoring**: Separate L/R earbud levels, case status, charging indicators, and menu bar percentage.
* **Audio & Control**: Toggle ANC, Transparency, or Off; adjust ANC strength. Manage EQs and low-latency Game Mode.
* **Auto-Audio Routing**: Uses `IOBluetooth` and `CoreAudio` to auto-connect and route classic audio output alongside BLE controls.
* **Find My Earbuds**: Play a locator sound (auto-stops after 5s).
* **System Native**: Background reconnects, sleep/wake handling, low-battery notifications, native autostart (`SMAppService`), and light/dark theme support.
* **Privacy & Diagnostics**: Local session logs (`~/Library/Logs/BaseusMenu/session.log`) and export options.

## Limitations & Protocol Notes

* **Model Specific**: Exclusively supports **Bass BP1 Pro ANC**.
* **State Reading**: Initial ANC and Game Mode states are not read on connect (unsupported by firmware); toggling applies new states immediately.
* **Case Battery**: Case battery reports only when notified by the case.
* **Safety**: Always remove earbuds from your ears before using the "Find Earbuds" signal feature.

## Building & Development

Requires Xcode with Swift 6 toolchain and Command Line Tools.

```sh
# Run unit tests
swift test

# Build native binary
./scripts/build.sh

# Build universal binary (Apple Silicon + Intel)
./scripts/build.sh --universal

# Build with Developer ID signing
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh --universal

```

*Do not run `swift run` directly for Bluetooth operations, as the bundled `.app` wrapper contains required Info.plist permission keys.*

## License

MIT License. Independent project not affiliated with Baseus.