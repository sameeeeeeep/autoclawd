# Shazam External Music Toggle — Design

**Date:** 2026-02-27
**Version target:** v1.5.0

## Problem

ShazamKit ambient recognition starts automatically on launch. There is no way to turn it on or off. Users should be able to opt in explicitly, with the setting persisting across restarts.

## Approach

Add a right-click context menu to the Music ♫ dot in `AmbientMapView`. One menu item: **"Detect external music"** with a checkmark when active. The setting is persisted in `UserDefaults` via `SettingsManager` and defaults to `false`.

## Architecture

```
Right-click Music dot
    → .contextMenu { Button("Detect external music") }
        → appState.shazamEnabled.toggle()
            → didSet: shazam.start() or shazam.stop()
                → ShazamKitService session active / nil
```

## Components

### `Sources/SettingsManager.swift` (minor addition)

Add key + property:

```swift
private let kShazamEnabled = "shazam_enabled"

var shazamEnabled: Bool {
    get { defaults.bool(forKey: kShazamEnabled) }   // default false (UserDefaults returns false for missing key)
    set { defaults.set(newValue, forKey: kShazamEnabled) }
}
```

### `Sources/AppState.swift` (two changes)

1. Add `@Published` property with persistence + side-effect:

```swift
@Published var shazamEnabled: Bool = SettingsManager.shared.shazamEnabled {
    didSet {
        SettingsManager.shared.shazamEnabled = shazamEnabled
        if shazamEnabled { shazam.start() } else { shazam.stop() }
    }
}
```

2. In `init()`, guard `shazam.start()` behind the persisted value:

```swift
// Only start Shazam if the user previously enabled it
if shazamEnabled { shazam.start() }
```

(Remove the unconditional `shazam.start()` call added in v1.4.0.)

### `Sources/AmbientMapView.swift` (context menu on Music dot)

In `VoiceDotView`, inside the `ZStack` that holds the dot, add a `.contextMenu` modifier **only when `person.isMusic`**:

```swift
.contextMenu {
    if person.isMusic {
        Button {
            appState.shazamEnabled.toggle()
        } label: {
            Label(
                "Detect external music",
                systemImage: appState.shazamEnabled ? "checkmark" : ""
            )
        }
    }
}
```

> Note: SwiftUI `.contextMenu` items don't natively support a leading checkmark via `systemImage: "checkmark"` in all macOS versions. The reliable approach is two separate buttons conditioned on `appState.shazamEnabled`:
>
> ```swift
> if appState.shazamEnabled {
>     Button("✓  Detect external music") { appState.shazamEnabled = false }
> } else {
>     Button("    Detect external music") { appState.shazamEnabled = true }
> }
> ```
>
> During implementation, prefer whichever approach renders a clean checkmark on macOS 13+.

## Behaviour

| State | On launch | Right-click menu | Shazam session |
|-------|-----------|------------------|---------------|
| `shazamEnabled = false` (default) | No Shazam | No checkmark | nil |
| User enables | — | Checkmark shown | Active |
| App restart (enabled) | `shazam.start()` auto-called | Checkmark shown | Active |
| User disables | — | No checkmark | nil, title cleared |

**NowPlayingService is unaffected** — Apple Music/Spotify detection always runs regardless of this toggle.

## Files Touched

- `Sources/SettingsManager.swift` — add `kShazamEnabled` key + `shazamEnabled` property
- `Sources/AppState.swift` — add `@Published var shazamEnabled`, fix init to be conditional
- `Sources/AmbientMapView.swift` — add `.contextMenu` to Music dot in `VoiceDotView`

## Out of Scope

- Visual indicator on the dot when Shazam is active (intentionally omitted — keep it simple)
- Settings panel toggle (context menu is the only surface)
- Per-person Shazam settings
