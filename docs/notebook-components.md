# Machine notebook — component system design

Normative UI/component design for the machine notebook. Implementation may replace `lib/notebook/*` freely to match this document.

Related:

- `SYSTEM.md` — product purpose, dual-host, phases
- `docs/ui-northstar.md` — interaction north star
- `docs/agent-spine.md` — agent loop (later)
- `docs/control-plane-palette.md` — Ctrl+K (later)

---

## 0. Problems the current code keeps reintroducing

| Symptom | Root cause class |
|---------|------------------|
| Ghost paint outside cell | Grid sized independently of cell box |
| No in-cell scroll (live) | Min-rows floor + scroll not treated as cell trait |
| No in-cell scroll (history freeze) | Freeze is a static paint, not a **TerminalSurface** with overflow policy |
| Missing `$` after freeze → live | Display clear without a **prompt reattach** contract |
| Trailing `$` on freeze | Freeze crop rules incomplete / not shared |
| Terminal vs ask rest height jump | Two height policies instead of one **ActiveSlot** |
| Mode switch “loses” or “duplicates” work | Mode, freeze, and guest lifetime not one state machine |

These are not polish bugs. They come from **widgets without a shared product model**.

---

## 1. Product laws (non-negotiable)

1. **One guest** — one AgentOS session per window. Mode switch never boots a second machine.
2. **One live VT** — only the active terminal surface is live; history terminals are immutable freezes.
3. **Notebook = timeline + one active slot** — air only above history; active always bottom-anchored.
4. **Three equal paths** — terminal · ask (Shift+Tab) · control plane (Ctrl+K). Not nested chrome.
5. **Cell is the unit of chrome and overflow** — every cell has the same frame; overflow scrolls **inside** the cell.
6. **Guest state ≠ display state** — clear/crop/scroll the display without forking AgentOS.
7. **Expand → hard-cap → internal scroll** — never grow the notebook chrome forever; never paint outside the cell.

---

## 2. Layering

```
┌─────────────────────────────────────────────────────────┐
│  NotebookApp (window, focus ladder, key chords)         │
├─────────────────────────────────────────────────────────┤
│  NotebookShell (layout only: top · body · bottom)       │
│    body = HistoryColumn + ActiveSlot                    │
├─────────────────────────────────────────────────────────┤
│  Cell model (pure Dart)     Session / VT / AgentOS      │
│  Timeline, modes, freezes   ProductSession, one guest   │
└─────────────────────────────────────────────────────────┘
```

**Rule:** Flutter widgets do not invent guest or VT policy. They bind to a small set of surfaces and a controller.

---

## 3. Core types (domain, not widgets)

### 3.1 `NotebookDocument`

Owns:

- `timeline: List<Cell>` (oldest → newest)
- `active: ActiveCell` (mode + draft + link to live VT when terminal)
- `revision` for scroll-to-bottom of history

### 3.2 `Cell` (sealed)

| Kind | Mutability | Body |
|------|------------|------|
| `TerminalFreezeCell` | Immutable | Cropped `VtFrame` + meta (time) |
| `UserMessageCell` | Immutable | Text |
| `AgentTurnCell` | Immutable (blocks later) | Text / blocks |
| *(future)* `SystemNoticeCell` | Immutable | Card |

### 3.3 `ActiveCell`

| Field | Meaning |
|-------|---------|
| `mode: terminal \| ask` | Shift+Tab toggles **this**, not layout topology |
| `askDraft` | Host text when mode=ask |
| `liveTerminal` | Handle to the single live surface (not a second PTY) |

### 3.4 `MachineSession` (role of the dual-host session)

| Concern | Contract |
|---------|----------|
| Guest | Boot, tick, input, caps — **lifetime independent of UI mode** |
| Live VT | One grid; resize to **ActiveSlot content box only** |
| Freeze | `snapshotForHistory()` → frame policy (§7) |
| After freeze | `beginNewTerminalSurface()` — display reset + **prompt reattach** (§6) |
| Scroll | `scrollLive(delta)` — only live terminal scrollback |

---

## 4. Shared visual components

### 4.1 `CellChrome` (one outline system)

**Traits (identical for history and active):**

- Full rectangle border (same stroke for all kinds)
- Header strip: kind chip + optional meta (time)
- Active: left accent bar only difference (not a different box system)
- Content area: **always** hard-clipped
- Content area: **always** participates in overflow policy

**Non-traits:** metrics in header, grid size, boot diary, restart button.

### 4.2 `CellBody` overflow policy (shared)

```
content intrinsic size
  → if ≤ hard-cap: size to content (history) or fill slot (active)
  → if > hard-cap: fixed height = hard-cap, scroll INSIDE
```

| Surface | Intrinsic | Cap | Scroll owner |
|---------|-----------|-----|--------------|
| Live terminal | = slot size (grid fits slot) | slot | **VT scrollback** (wheel) |
| Frozen terminal | used rows × cellH | e.g. 8–12 rows | **Flutter scroll** if still over cap after crop |
| Ask | draft height | same rest height as live term; grow to cap | **TextField** internal scroll |
| User / agent text | text height | cap | Flutter scroll if needed |

**One rule:** nothing paints outside `CellChrome` content rect. Ever.

### 4.3 `ActiveSlot`

**Traits:**

- Always bottom-anchored under history
- **Single rest height** for terminal and ask (one constant / one formula)
- Hosts exactly one of: `LiveTerminalSurface` | `AskSurface`
- Mode switch swaps surface **inside the same slot geometry**

**Not responsible for:** timeline, freeze crop, guest boot.

### 4.4 `HistoryColumn`

**Traits:**

- Reverse-glued: newest history cell touches ActiveSlot
- Void only above oldest
- Scrolls the **timeline** when history is taller than body (notebook page scroll)
- Does **not** scroll VT; that is cell-internal

### 4.5 `LiveTerminalSurface`

**Traits:**

- Grid cols/rows = `fit(contentBox)` with **minRows/minCols = 1** (never invent size > box)
- Resize live VT on every box change
- Wheel → `session.scrollLive` (scrollback)
- Focus: tap requests host focus; keys only when active mode=terminal
- Clip paint to box
- On show after freeze: session already ran `beginNewTerminalSurface()` so prompt is correct

### 4.6 `FrozenTerminalSurface`

**Traits:**

- Built only via `FreezePolicy.apply(liveFrame)`
- No cursor
- No trailing bare prompt line (`$` alone)
- Cropped to used content rows
- If still taller than freeze cap → **internal** scroll (history cell scroll)
- Immutable; never resizes the live VT

### 4.7 `AskSurface`

**Traits:**

- Same ActiveSlot height at rest as live terminal
- Multiline; expand → cap → internal scroll (same policy table)
- Submit appends User + Agent (stub/real) cells; does not destroy guest
- Shift+Tab → terminal without losing timeline

### 4.8 `NotebookChromeBars`

- Top: identity + quiet status only
- Bottom: hints from **one action registry** (keys = hints = palette later)

---

## 5. Freeze / mode state machine

```
                    ┌──────────────────┐
                    │  ACTIVE terminal │
                    │  (live VT+guest) │
                    └────────┬─────────┘
               Shift+Tab     │
                             ▼
              FreezePolicy.snapshot(live)
                             │
                             ▼
              timeline.append(TerminalFreezeCell)
                             │
                             ▼
         MachineSession.beginNewTerminalSurface()
           • clear VT display (+ scrollback for display)
           • guest UNCHANGED
           • reattach prompt (§6)
                             │
                             ▼
                    ┌──────────────────┐
                    │   ACTIVE ask     │
                    └────────┬─────────┘
               Shift+Tab     │
                             ▼
                    ACTIVE terminal again
                    (empty/fresh surface, same guest)
```

**Invariants:**

- Freeze always before leaving terminal if there is ink
- Live after freeze **must not** visually equal the freeze (no repeat)
- Guest cwd/process state preserved

---

## 6. Prompt reattach contract (fixes missing `$`)

Clear display → empty buffer → guest still at prompt but **no glyphs** is invalid product state.

**Required API on MachineSession:**

```
beginNewTerminalSurface():
  1. snapshot already taken by caller
  2. clear display (CSI wipe) for visual only
  3. reattachPrompt():
       Prefer: guest-native redraw if AgentOS exposes it
       Else:   if session.atPrompt → write a display-only prompt line
               that matches guest style, OR send a no-op that elicits prompt
       Never:  fake a second shell / second guest
```

**Options:**

| Option | Pros | Cons |
|--------|------|------|
| **A.** Display-only `$ ` after clear when `atPrompt` | Simple, instant | Visual-only; not from guest |
| **B.** Host sends empty line / probe to guest to reprint prompt | Real guest bytes | Extra blank line risk |
| **C.** Don’t wipe scrollback; only mark freeze boundary in UI | Always have `$` | Harder “no repeat” |

**H1 recommendation:** **A** (honest “view reset”). Prefer **B** later if loom probe is clean. **C** is wrong for “no repeat.”

---

## 7. FreezePolicy (single place for crop rules)

```
input: VtFrame live
output: VtFrame freeze

1. Strip cursor (visible=false, pos clear)
2. used = last row with ink
3. While used > 1 and row is bare prompt only ($ # % >): used--
4. Crop to rows [0, used)
5. Optional: hard max rows for storage; UI scrolls if over paint cap
```

History cell height = f(freeze.rows, cell metrics), capped; **scroll inside cell if over cap**.

---

## 8. Layout composition (only legal tree)

```
NotebookShell
├── TopBar                         // fixed height
├── Body (Expanded)
│   └── Padding
│       └── Column
│           ├── Expanded
│           │   └── HistoryColumn  // reverse list, page scroll
│           │         └── for cell in timeline.reversed:
│           │               CellChrome → body surface
│           └── ActiveSlot         // FIXED rest height (shared)
│                 └── CellChrome(active)
│                       └── LiveTerminalSurface | AskSurface
└── BottomBar                      // fixed height, registry hints
```

**Illegal (ban in review):**

- Full-bleed terminal bypassing CellChrome
- Terminal + ask stacked as two actives
- `minRows` / grid size larger than content box
- Painting without clip
- Mode-specific ActiveSlot heights at rest
- Freeze that keeps live frame identity (shared mutable cells)

---

## 9. Focus & input ladder

1. Ctrl+K / palette / dialogs
2. Ask TextField when mode=ask
3. Live terminal keys when mode=terminal and shell focused
4. Host chords (Shift+Tab, Ctrl+K) via one registry

Tap ActiveSlot terminal → request shell focus.  
History cells never take typing focus (selection optional later).

---

## 10. Mapping known bugs → design fixes

| Bug | Design fix |
|-----|------------|
| No interior scroll in **history** terminal | `FrozenTerminalSurface` always uses overflow policy §4.2 (Flutter scroll when cap hit) |
| No interior scroll in **live** | Grid fits box + VT scrollback + clip; never minRows > fit |
| Ghost text above cell | Clip + fit; ban oversized grid |
| Missing `$` after text cell → terminal | `beginNewTerminalSurface` + prompt reattach §6 |
| Trailing `$` on freeze | FreezePolicy step 3 |
| Rest size differs | One ActiveSlot height |

---

## 11. Refactor plan (replace freely)

### Phase R0 — This document

Land and agree traits before large code moves.

### Phase R1 — Domain package (no Flutter layout)

- `notebook/document.dart` — Document, Cell sealed hierarchy
- `notebook/freeze_policy.dart` — pure frame transforms
- `notebook/active_slot_state.dart` — mode, draft
- `session/machine_session.dart` — guest + live VT + `beginNewTerminalSurface`

### Phase R2 — Presentational widgets only

- `CellChrome`
- `HistoryColumn`
- `ActiveSlot`
- `LiveTerminalSurface` / `FrozenTerminalSurface` / `AskSurface`
- Delete ad-hoc frames, dual height paths, unclipped paints

### Phase R3 — Shell wire-up

- One layout tree §8
- Mode machine §5
- Registry → bottom hints

### Phase R4 — Verify by scenario (acceptance)

1. Cold open: ActiveSlot bottom, outlined, rest height H, prompt visible when ready
2. Type many lines: content stays in cell; wheel scrolls inside; nothing above cell
3. Shift+Tab: freeze tight, no trailing `$`, no cursor; ask same height H
4. Shift+Tab back: fresh live surface, **`$` present**, guest cwd same (`pwd`)
5. History freeze taller than cap: scroll **inside** freeze cell
6. NL submit: you+agent above active; stack glued; air only above

---

## 12. Explicit non-goals for this refactor

- Real agent loop / multi-agent UI
- Full Ctrl+K scorer
- Multiple guests
- Editing freezes in place
- Pixel-perfect Ghostty app chrome

---

## 13. One-sentence architecture

**A notebook is a timeline of immutable cells plus one bottom ActiveSlot; a single MachineSession owns the guest and one live VT; CellChrome + overflow policy are universal; freeze and prompt-reattach are session operations, not layout hacks.**

---

*Alpha: replace this document when a better component model wins. Do not preserve chrome out of habit.*
