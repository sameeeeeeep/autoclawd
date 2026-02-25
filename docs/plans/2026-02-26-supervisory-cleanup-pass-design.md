# Supervisory Cleanup Pass (Pass 3) — Design

**Date:** 2026-02-26
**Status:** Approved

## Problem

After repeated synthesis passes the world model and todos accumulate duplicates, malformed lines, and near-identical entries. The Intelligence view similarly fills with redundant ExtractionItems. There is no mechanism to consolidate or reason about gaps.

Example of current todos.md:
```
-MEDIUM: Develop ambient AI solutions
-MEDIUM: Developing ambient AI solutions
-MEDIUM: Develop ambient AI solutions for various applications
-MEDIUM: Developing and refining ambient AI solutions for various applications
```

## Solution

Add **Pass 3: Supervisory Cleanup** — two focused LLM calls that run automatically after every Pass 2 synthesis and can also be triggered manually.

## Architecture

### New Files
- `Sources/CleanupService.swift` — owns both LLM calls and all write-back logic

### Modified Files
- `Sources/ExtractionService.swift` — call `await cleanup()` at end of `synthesize()`
- `Sources/ExtractionStore.swift` — add `collapse(keepId:canonical:dropIds:)` method
- `Sources/AppState.swift` — add `cleanupNow()` async method + `isCleaningUp: Bool` flag
- `Sources/IntelligenceView.swift` — add "Clean Up" button to header

## LLM Call 1 — Knowledge Rewrite

**Purpose:** Rewrite world-model.md and todos.md, eliminating redundancy. Also generate new dev-facing todos to improve AutoClawd.

**Input:**
- Current `world-model.md` content
- Current `todos.md` content
- Today's date

**Prompt intent:**
- Rewrite world model into clean structured markdown with proper `##` sections (People, Projects, Plans, Preferences, Decisions). No duplicate facts, no malformed lines.
- Rewrite todo list: merge near-duplicates into one canonical entry per intent, sort by priority (HIGH / MEDIUM / LOW / DONE).
- Analyze the world model and todos for gaps, inconsistencies, or missing action items that would improve AutoClawd as a product. Append these as new todos.

**Output format:**
```xml
<WORLD_MODEL>
...rewritten world model...
</WORLD_MODEL>
<TODOS>
...rewritten + new dev todos...
</TODOS>
```

**numPredict:** 2048

**Write-back:** If tags parse successfully, overwrite world-model.md and todos.md.

## LLM Call 2 — Intelligence Item Collapsing

**Purpose:** Collapse semantically duplicate ExtractionItems in the DB into single canonical items.

**Input:** All non-applied ExtractionItems as a flat list: `id | bucket | type | content`

**Prompt intent:** Group items that express the same idea. For each group with more than one member, output one line: `canonical text | id_to_keep | id1,id2,...` (ids to drop).

**Output format:** One line per group (no header, no explanation):
```
canonical text | keep_id | drop_id1,drop_id2
```

**numPredict:** 1024

**Write-back:** For each parsed line, call `ExtractionStore.collapse(keepId:canonical:dropIds:)` which updates the kept item's content and hard-deletes the rest.

## Triggers

| Trigger | How |
|---------|-----|
| Auto | `ExtractionService.synthesize()` calls `await cleanup()` at the very end, after marking items applied |
| Manual | "Clean Up" button in IntelligenceView header; calls `appState.cleanupNow()`; disabled while `appState.isCleaningUp` |

## Error Handling

- If Call 1 XML parse fails: log error, skip write-back (world model and todos unchanged)
- If Call 2 parse fails: log error, skip collapse (items unchanged)
- Each call fails independently — a Call 1 failure does not block Call 2

## Data Flow

```
synthesize()
  └── cleanup()
        ├── Call 1: LLM → rewrite world-model.md + todos.md + new dev todos
        └── Call 2: LLM → collapse duplicate ExtractionItems in DB
```
