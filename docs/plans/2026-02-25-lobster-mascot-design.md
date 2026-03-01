# AutoClawd 8-bit Blue Lobster Mascot — Design Doc
**Date:** 2026-02-25
**Type:** Visual / SVG asset

---

## Concept

An 8-bit pixel-art blue lobster mascot for AutoClawd. Named "Clawd" — a lobster whose left claw is the defining feature, riffing on the app's name.

## Selected Approach: Option C — Head + Claw Bust

A close-up bust showing the lobster's expressive face and one *massive* left claw. No full body — just personality and the claw. This reads clearly at 16×16 icon size but is also expressive as a sticker.

## Canvas & Grid

- **SVG size:** 256 × 256
- **Pixel grid:** 32 × 32 logical pixels, 8px per pixel
- **Background:** Transparent (works on any surface)

## Layout (pixel coordinates, 0-indexed)

```
Rows 0–3   : Antennae (two thin vertical lines)
Rows 4–10  : Head (10px wide, eyes at row 5, highlights)
Rows 10–14 : Thorax (wider, connects to claw arm)
Rows 4–19  : BIG LEFT CLAW (dominant, left side of canvas)
  - Upper pincer : cols 0–4, rows 4–11
  - GAP (opening): cols 0–3, rows 12–13  ← the "clawd"
  - Lower pincer : cols 0–4, rows 14–19
  - Palm          : cols 4–9, rows 9–19
  - Arm           : cols 9–12, rows 10–14
Rows 11–13 : Small right arm stub (cols 23–27)
```

## Color Palette (5 blue shades + white + orange)

| Swatch | Hex       | Role                    |
|--------|-----------|-------------------------|
| ████   | `#0a1628` | Outline / near-black    |
| ████   | `#1d4ed8` | Shadow / deep blue      |
| ████   | `#2563eb` | Body main               |
| ████   | `#3b82f6` | Mid highlight           |
| ████   | `#60a5fa` | Bright highlight        |
| ████   | `#ffffff` | Eye whites              |
| ████   | `#f97316` | Eye pupils (orange pop) |

## Key Design Decisions

- **One eye is white+dark, the other is white+orange** — asymmetry gives personality
- **Upper pincer is slightly longer than lower** (anatomically correct, visually interesting)
- **Gap is 2 rows tall × 4 cols wide** — clearly visible claw opening at any size
- **No body/tail** — this is a bust; the claw takes up ~45% of the image area
- **Antennae are straight vertical** — clean and readable at small sizes

## Deliverable

Single SVG file saved to: `Resources/autoclawd-mascot.svg`
