# AutoClawd PRD — Addendum

**Extends:** `autoclawd_prd.md` (v5.0, February 2026)
**Addendum version:** v6.0
**Date:** 2026-02-25

This document extends the original PRD with three new Phase 1 UI features approved after the brutalist redesign shipped.

---

## UI Section — Updated

### Floating Pill (revised)

**Was (v5.0):**
> Always-visible, draggable, always-on-top. Black pill, brutalist. Rectangular waveform bars. JetBrains Mono. 1px border, no shadows, no gradients.

**Now (v6.0):**
Always-visible, draggable, always-on-top. **Liquid glass pill, brutalist-glass hybrid.** Rectangular waveform bars. JetBrains Mono. 1px border, native shadow. Sharp rectangle (no corner radius). Neon green `#00FF41` text labels and waveform bars. Glass fill: `.glassEffect(.regular, in: .rect)` on macOS 26+; `.ultraThinMaterial` + specular gradient sheen on macOS 13–25.

---

## New Features

### Log Toasts

A separate floating glass panel appears 8pt below the pill whenever a log event fires. One toast visible at a time — new events replace the current toast immediately. Auto-dismisses after 3 seconds.

**Scope:** All log events (all levels: debug, info, warn, error; all components).

**Visual:**
```
┌────────────────────────────────────┐
│  [●] Transcript saved        2.1s  │   ← info/debug (neon green badge)
└────────────────────────────────────┘

┌────────────────────────────────────┐
│  [!] Groq API error          0.8s  │   ← warn/error (red badge)
└────────────────────────────────────┘
```

**Glass recipe:** Same as pill — `.glassEffect(.regular, in: .rect)` on macOS 26+, `.ultraThinMaterial` + gradient on older.

**Architecture:** Separate `NSPanel` (`ToastWindow`) driven by a `PassthroughSubject<LogEntry, Never>` added to `AutoClawdLogger`. `AppDelegate` subscribes and manages the toast window.

**Non-goals for v6.0:** Toast stacking, level/component filtering, toast-follows-pill-while-dragging.

---

### "Show Flow bar at all times" Setting

New **Display** group in the Settings tab (above Transcription):

```
┌─── Display ─────────────────────────┐
│  Show Flow bar at all times  [ON]   │
└─────────────────────────────────────┘
```

**Default:** ON (pill always visible).

**Behaviour when toggled OFF:** Pill and any active toast are hidden.

**Behaviour when toggled ON:** Pill snaps back to default top-right corner position and becomes visible. This is the primary recovery mechanism if the pill is dragged off-screen.

**Storage:** `UserDefaults` key `show_flow_bar`, wrapped in `SettingsManager.showFlowBar: Bool`.

---

## Implementation Reference

See: `docs/plans/2026-02-25-glass-toasts-design.md`
