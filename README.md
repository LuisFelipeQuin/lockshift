# iOS Fake GPS

Set a fixed location, or drive a route along real roads, on a **non-jailbroken**
iPhone or iPad — all from a native macOS app. The phone just needs to be plugged
in.

iOS has no public "mock location" API, so an app installed *on the phone* can't
fake GPS for other apps. Instead the location is driven from a tethered Mac over
Apple's **developer tunnel** — the same mechanism Xcode uses to simulate location
while debugging. Whatever you set is seen **system-wide** by every app on the
device.

> **Use responsibly.** This is for testing location-aware apps you own and for
> personal use. Using it to defeat anti-cheat, commit fraud, or bypass
> location-based access controls breaks those services' terms — and possibly the
> law. See [DISCLAIMER.md](DISCLAIMER.md).

## What you can do

- **Pick a device** — iPhone or iPad; the sidebar shows its name, iOS version
  and UDID suffix, and lets you switch between attached devices.
- **Move to a place** — search an address or click the map to jump the device
  there instantly.
- **Build a route** — choose a starting point (this Mac's current location, or
  any address) and a destination; MapKit returns a **driving route that follows
  actual roads**, with its name, total distance and estimated time.
- **Play it back** — Walk / Cycle / Drive presets or a custom speed up to
  ~186 mph (300 km/h), with repeat, pause and resume. Positions are pushed at
  10 Hz, so movement is smooth rather than jumping between waypoints.
- **See the real state** — the sidebar says *Real location* or *Location
  edited*, so you always know whether the device is currently faked.
- **Restore the real location** — one button, and an automatic restore when you
  disconnect or quit, so you're never left on a fake position.

## Requirements

- A Mac on **macOS 14 or newer** (the bundled app builds as `arm64` — tested on
  M1 and M4).
- An **iPhone or iPad on iOS 17+** with a USB cable and **Developer Mode** on.
- Your admin password once per session — the developer tunnel must run as root.

## Setup

The app walks you through a four-step checklist on first launch; these are the
only steps Apple requires a human to do.

1. **Engine ready** — bundled inside the app, nothing to install.
2. **Connect your iPhone** — plug it in, tap **Trust**, and turn on Developer
   Mode (Settings ▸ Privacy & Security ▸ Developer Mode). The checklist ticks
   the moment it sees the device.
3. **Start the secure tunnel** — one button; it asks for your Mac password
   (the tunnel runs as root and mounts the Developer Disk Image, which iOS 17+
   requires).
4. **Connect** — links the app to the device. Done.

If you're opening a build that macOS flags as coming from an unidentified
developer, right-click the app → **Open**, or clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/FakeGPS.app
```

## Build from source

The project is a Swift package (`macapp/`) plus a Python engine (`sidecar/`).

Set up the Python side once. It lives in `~/.ios-fake-gps`, **not** in
`~/Documents`, because the root tunnel daemon can't read TCC-protected folders:

```bash
./setup.sh
```

Run the app from source:

```bash
cd macapp && swift run        # or open macapp/Package.swift in Xcode and Run
```

Produce the bundled, double-clickable app and a release zip:

```bash
./scripts/build_app.sh        # -> dist/FakeGPS.app + dist/FakeGPS-macos-arm64.zip
```

Pushing a `v*` tag runs the same build on a macOS runner and attaches the zip to
a GitHub release. Regenerate the app icon with:

```bash
~/.ios-fake-gps/venv/bin/python scripts/make_icon.py
iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
```

## How it works

```
macOS app (SwiftUI + MapKit)             bundled engine               iPhone / iPad
  search · click · plan a route ──────▶  pymobiledevice3  ──tunnel──▶  every app
  speed · repeat · pause        ◀──────  LocationSimulation   (DDI)     sees the
  interpolates movement at 10 Hz         (frozen, inside .app)          fake GPS
```

- The **app** owns the map, route planning (MapKit directions) and movement
  interpolation, so speed, pause and repeat are all controlled on the Mac side.
- The **engine** is a small Python program built on
  [pymobiledevice3](https://github.com/doronz88/pymobiledevice3), frozen into a
  standalone binary inside `FakeGPS.app` — no Python needed on your Mac. It
  holds one developer connection open and applies each coordinate.
- A small **tunnel daemon** (started by the app, as root) opens the developer
  tunnel and mounts the Developer Disk Image. Required on iOS 17+.

### Project layout

```
ios-fake-gps/
├── macapp/Sources/FakeGPS/   the macOS app (SwiftUI + MapKit)
├── macapp/Tests/             unit tests for device selection, update rate, map gestures
├── sidecar/                  the Python engine + runtime entry point
├── scripts/                  build_runtime.sh, build_app.sh, make_icon.py
├── assets/                   app icon
└── docs/                     screenshots
```

## Command line (optional)

The engine inside the app is also usable from the Terminal. It has three modes:
`tunneld`, `usbmux` and `sidecar`.

```bash
RUNTIME="/Applications/FakeGPS.app/Contents/Resources/runtime/fakegps-runtime"

sudo "$RUNTIME" tunneld       # start the developer tunnel (keep it running)
"$RUNTIME" usbmux             # list attached devices as one JSON line (no tunnel needed)
"$RUNTIME" sidecar --list     # list devices visible to the engine, as NDJSON
"$RUNTIME" sidecar            # NDJSON command loop: set / clear / ping / devices / quit
```

## Troubleshooting

- **Tunnel won't start** — make sure you entered the admin password; the daemon
  needs root. Logs are at `/tmp/ios-fake-gps-tunneld.log`.
- **Device never detected** — check the cable, tap **Trust** on the device, and
  confirm **Developer Mode** is enabled (then reboot the device).
- **"Could not open LocationSimulation"** — Developer Mode is off, or the
  Developer Disk Image hasn't mounted yet; give the tunnel a few seconds after
  starting it.
- **The phone still shows the fake location after restoring** — allow up to ten
  minutes, then restart the device. Recovery time varies and the app can't read
  the device's actual GPS fix to confirm.

## Limitations

- The Mac must stay tethered (USB; Wi-Fi works after an initial USB pairing).
- The tunnel runs as root, so it asks for your password once per session — an
  Apple requirement that can't be removed. It's why this can't be an App Store
  app, and why no on-device-only app can do this.
- It sets the reported location only; it doesn't fake Wi-Fi or cell-tower
  signals, so a few apps that cross-check those may notice the mismatch.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). For security reports, see
[SECURITY.md](SECURITY.md).
