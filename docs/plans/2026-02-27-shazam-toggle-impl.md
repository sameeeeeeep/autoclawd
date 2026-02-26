# Shazam External Music Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add a right-click context menu to the Music ♫ dot that toggles ShazamKit ambient recognition on/off, persisted to UserDefaults (default off).

**Architecture:** `SettingsManager` gains `shazamEnabled: Bool` (default `false`). `AppState` gets `@Published var shazamEnabled` with `didSet` that calls `shazam.start()`/`shazam.stop()`. The unconditional `shazam.start()` call in `AppState.init()` becomes `if shazamEnabled { shazam.start() }`. `AmbientMapView` gains a `.contextMenu` modifier on the Music dot that shows "Detect external music" with a checkmark when active.

**Tech Stack:** Swift, SwiftUI (`.contextMenu`), UserDefaults, `ShazamKitService`.

---

### Task 1: Add `shazamEnabled` to SettingsManager

**Files:**
- Modify: `Sources/SettingsManager.swift`

**Step 1: Add the UserDefaults key**

In `Sources/SettingsManager.swift`, find the `// MARK: - Keys` section. The last key is on line 51:
```swift
private let kHotWordConfigs = "hotWordConfigs"
```

Add the new key immediately after it:
```swift
private let kShazamEnabled  = "shazam_enabled"
```

**Step 2: Add the property**

Find the end of the `hotWordConfigs` property (closing `}` on line 133), right before `private init() {}` on line 135. Insert the new property there:

```swift
var shazamEnabled: Bool {
    get { defaults.bool(forKey: kShazamEnabled) }   // returns false when key is absent — correct default
    set { defaults.set(newValue, forKey: kShazamEnabled) }
}
```

**Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app`

**Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/SettingsManager.swift
git commit -m "feat: add shazamEnabled setting to SettingsManager (default false)"
```

---

### Task 2: Add `shazamEnabled` to AppState and make init conditional

**Files:**
- Modify: `Sources/AppState.swift`

**Step 1: Add the `@Published` property**

In `Sources/AppState.swift`, find line 109:
```swift
let shazam = ShazamKitService()
```

Immediately after it (line 110 area), add the new published property:

```swift
@Published var shazamEnabled: Bool = SettingsManager.shared.shazamEnabled {
    didSet {
        SettingsManager.shared.shazamEnabled = shazamEnabled
        if shazamEnabled { shazam.start() } else { shazam.stop() }
    }
}
```

> **Why no `didSet` fires on init:** Swift does not call `willSet`/`didSet` during the initial assignment of a stored property. So we must manually start Shazam in `init()` when the persisted value is `true` (Step 2 below).

**Step 2: Make `shazam.start()` conditional in `init()`**

Find line 203 in `AppState.swift`:
```swift
shazam.start()
```

Replace it with:
```swift
if shazamEnabled { shazam.start() }
```

This ensures Shazam only runs on launch if the user previously enabled it.

**Step 3: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app`

**Step 4: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/AppState.swift
git commit -m "feat: add shazamEnabled to AppState; conditional shazam.start() on launch"
```

---

### Task 3: Add context menu to Music dot in AmbientMapView

**Files:**
- Modify: `Sources/AmbientMapView.swift`

**Step 1: Add `.contextMenu` after the drag gesture**

In `Sources/AmbientMapView.swift`, the gestures on `VoiceDotView` are at lines 117-139:

```swift
.onTapGesture { ... }                    // line 117-121
.simultaneousGesture(DragGesture(...))   // line 122-139
```

Add a `.contextMenu` modifier immediately after the `.simultaneousGesture(...)` closing `)` on line 139:

```swift
.contextMenu {
    if person.isMusic {
        if appState.shazamEnabled {
            Button("✓  Detect external music") {
                appState.shazamEnabled = false
            }
        } else {
            Button("    Detect external music") {
                appState.shazamEnabled = true
            }
        }
    }
}
```

> **Why two buttons instead of one with `systemImage: "checkmark"`:** On macOS 13–15, `.contextMenu` `Label` with `systemImage: "checkmark"` renders inconsistently — the image appears as a small icon on the left, not a leading checkmark like native macOS menus. Using a Unicode checkmark prefix (`✓`) in the button title gives a clean, native-looking result.

> **Where to place it:** After line 139 (the closing `)` of `.simultaneousGesture`), before line 140 (the `}`  closing the ForEach body). Both `person` and `appState` are in scope here.

The resulting gesture chain for each dot will be:
```swift
VoiceDotView(...)
    .position(...)
    .onTapGesture { ... }
    .simultaneousGesture(DragGesture(...))
    .contextMenu {
        if person.isMusic { ... }
    }
```

**Step 2: Build**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd" && make all 2>&1 | tail -5
```
Expected: `Built build/AutoClawd.app`

**Step 3: Commit**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
git add Sources/AmbientMapView.swift
git commit -m "feat: right-click Music dot to toggle Shazam external music detection"
```

---

### Task 4: Bump version to v1.5.0 + install

**Files:**
- Modify: `Info.plist`

**Step 1: Bump version**

```bash
cd "/Users/sameeprehlan/Documents/Claude Code/autoclawd"
sed -i '' 's/<string>1\.4\.0<\/string>/<string>1.5.0<\/string>/g' Info.plist
grep "CFBundleShortVersionString" -A1 Info.plist
```
Expected: output confirms `1.5.0`.

**Step 2: Final build**

```bash
make all 2>&1 | tail -5
```

**Step 3: Commit + push**

```bash
git add Info.plist
git commit -m "chore: bump to v1.5.0"
git push origin main
```

**Step 4: Install**

```bash
cp "/Users/sameeprehlan/Documents/Claude Code/autoclawd/AutoClawd-adhoc.entitlements" /tmp/AutoClawd-adhoc.entitlements

osascript <<'EOF'
do shell script "pkill -x AutoClawd; true" with administrator privileges
do shell script "rm -rf '/Applications/AutoClawd.app' && cp -r '/Users/sameeprehlan/Documents/Claude Code/autoclawd/build/AutoClawd.app' '/Applications/AutoClawd.app' && xattr -cr '/Applications/AutoClawd.app' && codesign --force --sign - --entitlements /tmp/AutoClawd-adhoc.entitlements '/Applications/AutoClawd.app'" with administrator privileges
EOF
```

**Step 5: Verify + launch**

```bash
codesign --verify --deep /Applications/AutoClawd.app && \
defaults read /Applications/AutoClawd.app/Contents/Info.plist CFBundleShortVersionString && \
open /Applications/AutoClawd.app
```
Expected: `Signature OK` and `1.5.0`.

---

## Smoke Test Checklist

- [ ] App launches at v1.5.0
- [ ] Right-click Music ♫ dot → context menu appears with `"    Detect external music"` (no checkmark)
- [ ] Click "Detect external music" → menu item now shows `"✓  Detect external music"` on next right-click
- [ ] Play music from a speaker near the mic — Music dot activates with song title after ~10–15 s
- [ ] Right-click → click `"✓  Detect external music"` → Shazam stops, title clears
- [ ] Quit and relaunch app with Shazam enabled → Shazam auto-starts on launch (persisted)
- [ ] Quit and relaunch with Shazam disabled → Shazam does NOT start
- [ ] Right-clicking a non-Music dot → no context menu appears
