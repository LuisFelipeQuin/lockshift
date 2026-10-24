A Lockito-style GPS location simulator for a non-jailbroken iPhone, driven from a native macOS app.

## Download & run (no Python needed)

The Python engine is bundled inside the app — just download and open.

1. Download **LockShift-macos-arm64.zip** below and unzip it.
2. Drag **LockShift.app** into **Applications**.
3. First launch: macOS warns it's from an unidentified developer (the app isn't notarized). **Right-click the app → Open** and confirm — only needed once. If it still refuses:
   ```bash
   xattr -dr com.apple.quarantine /Applications/LockShift.app
   ```
4. Open the app and follow the on-screen checklist: plug in your iPhone over USB, start the tunnel (one password prompt), and connect.

## Requirements

- macOS on Apple silicon (tested on M1 and M4)
- iPhone on iOS 17+ with **Developer Mode** enabled, connected by USB
- The tunnel runs as root, so it asks for your Mac password once per session — an Apple requirement that can't be removed.

## Features

- Teleport to any point (click the map or search an address)
- Route playback with adjustable speed, looping and GPS jitter
- Live position marker, distance and ETA
- Auto-reset back to real GPS when you disconnect or quit

## Prefer the command line?

The engine inside the app also works from the Terminal. Start the tunnel daemon:

```bash
sudo "/Applications/LockShift.app/Contents/Resources/runtime/lockshift-runtime" tunneld
```

Then check connected devices (or use the GUI):

```bash
"/Applications/LockShift.app/Contents/Resources/runtime/lockshift-runtime" sidecar --list
```

---

See the [CHANGELOG](https://github.com/LuisFelipeQuin/lockshift/blob/main/CHANGELOG.md) for what changed in this version.
