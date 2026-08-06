# Control plane palette (Ctrl+K)

Specification for the **control plane** entry surface. Complements `docs/ui-northstar.md`.

**Job.** Operate or reshape the AgentOS guest under the machine notebook: mounts, image/catalog, caps, **snapshot / restore / fork**, relay, session lifecycle — plus a thin set of host/notebook actions. Not a second permanent nav rail. Not Shift+Tab (cell mode). Not a substitute for the terminal cell.

**References (mechanism only, not product ontology):**

- Stacklane / Opyt Cmd-K — `../stacklane/apps/web/src/lib/palette/`, `command-palette.tsx`, `lib/keymap/` (modes, owned scorer, recents, route-scoped registration, peek, scope stack)
- Grok Build — thin footer hints and action registry idea; **not** the content center of gravity (their machine is already set)
- `docs/ui-northstar.md` — three entry paths; control plane vs NL vs terminal
- `docs/agent-spine.md` — sub-agents and fork/snapshot isolation via this palette
- `docs/ui-toolkit.md` — Forui hybrid for palette **chrome** only; scoring/modes stay ours

---

## 1. Product contract

### 1.1 Why this surface is load-bearing

| Grok Build / Stacklane workspace apps | This product |
|---------------------------------------|--------------|
| Run **on** a machine or inside a workspace that is already set | **Host** the machine (AgentOS guest is product state) |
| Palette reaches app destinations and light actions | Palette **mutates or selects machine state** |
| Snapshot/restore/fork of a guest is not the main job | Snapshot / restore / fork / image / mounts are first-class |

Three equal entry paths (see UI North Star):

1. **Terminal cell** — type into the machine  
2. **Shift+Tab NL** — talk to an agent on the **same** machine  
3. **Ctrl+K** — control plane for the machine itself  

### 1.2 What must always be reachable

Every important control-plane destination and mutation appears in the palette (directly or as a verb that opens a sheet). State-scoped verbs register only while their state is active (§5).

### 1.3 What it is not

- Not cell mode (Shift+Tab)
- Not the NL agent composer or agent loop (`agent-spine.md`)
- Not an IDE file tree or always-on sidebar
- Not a dump of every keybinding in the product
- Not silent execution of **destructive** machine mutations without confirm (§7)
- Not the place to implement multi-agent reasoning — only **machine shape** those agents share (including **fork** for isolation)

---

## 2. Kinds

First-class row categories. Each kind has a default group, icon policy, and peek verb.

| Kind | Purpose | Typical `run` |
|------|---------|----------------|
| `recent` | Rehydrated MRU (empty-query top) | Same as underlying kind |
| `action` | Imperative host/machine verb | Snapshot now, open mounts sheet, toggle policy, … |
| `snapshot` | Named guest snapshot | Select → peek → restore/fork/delete flows |
| `mount` | Mount / volume / bind target | Attach, detach, reveal |
| `image` | Guest image / catalog entry | Switch image, inspect |
| `session` | Session / machine identity ops | Rename, disconnect relay, … |
| `relay` | Relay / remote linkage | Connect, status, copy endpoint |
| `cap` | Capability / tool / permission surface | Inspect or open cap sheet |
| `nav` | Host surfaces (overlays, notebook places) | Open sheet / jump focus |
| `setting` | Host/notebook preference destinations | Open settings row / sheet |
| `help` | Shortcut / help entries | Open host shortcut cheatsheet |

**Center of gravity:** `action`, `snapshot`, `mount`, `image`, `relay`, `session`, `cap`.  
**Secondary:** `nav`, `setting`, `help`. Do not let nav/settings crowd out machine verbs in default ranking when query is empty.

Add kinds only when a new AgentOS or host noun needs distinct row chrome or grouping — not one kind per button.

---

## 3. Mode prefixes

Slack/Stacklane pattern: leading prefix selects **mode** (kind allowlist + chip + placeholder); remainder is the query. No prefix = everything bucket (machine-first).

| Prefix | Mode | Accepts kinds | Chip | Placeholder |
|--------|------|---------------|------|-------------|
| *(none)* | `default` | all (machine-weighted empty state) | — | Search machines, snapshots, mounts… |
| `>` | `actions` | `action`, `help` | Actions | Run an action… |
| `s ` or `s` | `snapshots` | `snapshot` | Snapshots | Find a snapshot… |
| `m ` or `m` | `mounts` | `mount` | Mounts | Find a mount… |
| `i ` or `i` | `images` | `image` | Images | Find an image… |
| `r ` or `r` | `relay` | `relay`, `session` | Relay | Relay and session… |
| `g ` or `g` | `nav` | `nav`, `setting` | Go to | Go to… |
| `?` | `help` | `help` | Help | Shortcuts and help… |

**Rules:**

1. Parse prefix → `{ mode, query, prefixLen }`. Render a **mode chip** in place of the consumed prefix characters.
2. **Backspace** when the visible query is empty but `prefixLen > 0` **exits the mode** (clear input to default).
3. Footer reflects mode: `⌫ exit snapshots` vs `> / s / m filter`.
4. Do not reuse Stacklane’s `@` / `#` unless we gain people/channels nouns; our prefixes track **machine nouns**.
5. Single-letter prefixes that conflict with typing bare queries use the **`x ` (letter + space)** form where ambiguity is high (`s`, `m`, `i`, `r`, `g`). Leading `>` and `?` stay single-character.

Exact prefix grammar is implementation-tunable; the mode table above is the product contract.

---

## 4. Scoring and recents

### 4.1 Owned scorer (no opaque fuzzy dependency)

Port the Stacklane policy, not a library:

```
score(item, q, recency) =
  0.45 * exactPrefix(label, q)
+ 0.25 * subsequence(label + keywords)   // < 0.5 → drop (score 0)
+ 0.15 * camelHumpMatch(label, q)
+ 0.10 * (1 - lengthPenalty(label))
+ 0.05 * recencyDecay(lastUsedAt)        // ~1 week half-life
```

Empty query:

```
0.7 * recency + 0.3 * freq   // recents / habitual machine ops
```

**Show limit** for the list (e.g. 80). Hard drop weak matches so the list never fills with noise.

### 4.2 Recents store

- Keyed by **session / machine identity** (not a generic global bucket alone).
- Cap entries (e.g. 30); prune by age (e.g. 30 days).
- **Bump on successful run** (after confirm if destructive).
- Empty open: top N recents rehydrated against **live** catalog; stale ids drop.
- Host action: “Clear recent control-plane items.”

---

## 5. Sources and registration

### 5.1 Source merge (while open)

| Source | When loaded |
|--------|-------------|
| Static control-plane actions | Always when open |
| State-scoped actions | While registered (§5.2) |
| Snapshot list | When open (and mode allows) |
| Mount list | When open |
| Image / catalog | When open; search gate if large |
| Relay / session rows | When open |
| Nav + curated settings | Always when open (secondary) |
| Recents | On open; re-read after bump |

**Fetch policy:** assemble sources when the palette is open. Heavy search (large catalogs) gates on **query length ≥ 2** (or equivalent) so empty open stays clean and cheap.

### 5.2 State-scoped registration (Stacklane `useCommand` analogue)

Surfaces register actions for their lifetime:

| Scope example | Example commands |
|---------------|------------------|
| Live terminal cell focused | Freeze cell, copy selection (host), open VT-related host tools |
| Snapshot highlighted in an overlay | Restore…, Fork…, Delete… |
| Mount sheet open | Detach selected, remount |
| NL mode active | (Prefer agent path; only host control-plane verbs here) |
| Restore pending / card parked | Confirm restore, cancel |

**Rules:**

- Register on enter scope; unregister on leave or `enabled: false`.
- Same action **id** does not double-register.
- Scoped actions appear in `>` / default with keywords so they remain discoverable.

### 5.3 Single registry → three consumers

One host action table feeds:

1. **Ctrl+K palette** (this doc)
2. **Key dispatch** (chords)
3. **Bottom status bar hints**

Do not maintain three parallel maps. Each action: `id`, `kind`, `label`, `keywords`, `meta` (optional kbd), `run`, `scope` / `enabled`, optional `destructive` flag.

---

## 6. UI chrome

### 6.1 Shell

- Modal/dialog over the notebook (blurred or dimmed backdrop). Fixed shell is fine (Stacklane-style); list scrolls inside. Do not expand the palette forever over the guest.
- Input row: optional **mode chip** + query field.
- Body: **list** (primary) + **peek** (secondary).
- Footer: live chords — navigate, open/run, mode filter or exit mode, Esc close.

### 6.2 Groups

Fixed group order (example):

1. Recent  
2. Actions  
3. Snapshots  
4. Mounts  
5. Images  
6. Relay / session  
7. Caps  
8. Go to  
9. Settings  
10. Help  

Sticky group headers with counts. **Highlight index uses visual (flat) order after grouping**, not raw score order — arrow keys match what the user sees.

### 6.3 Row

- Kind icon (or payload-specific: snapshot age, mount state)
- Label + optional secondary line
- Right meta: kbd hint, tag, danger mark
- Disabled state for unavailable ops

### 6.4 Peek pane

Raycast/Spotlight pattern:

| State | Peek content |
|-------|----------------|
| Empty query, no arrow yet | Tips: prefixes, what control plane is for |
| Highlighted row | Kind tag, title, secondary, machine-relevant detail |
| Destructive highlight | Explicit consequence copy (“Restores guest; live state is replaced”) |

Peek is context, not a second navigator. Empty query does not pretend to “preview” the first action until the user types or moves highlight (Stacklane policy).

### 6.5 Keyboard inside palette

| Key | Behavior |
|-----|----------|
| ↑ / ↓ | Move highlight in flat list |
| Home / End | First / last |
| Enter | Run highlighted (or arm confirm if destructive — §7) |
| Esc | Close palette (or peel nested picker first) |
| Backspace | Exit mode when only prefix remains |
| Typing | Filter; reset highlight to 0 on query change |

Mouse: hover updates highlight; mousedown on row must not steal focus from the input.

---

## 7. Destructive mutations

Control plane is dangerous by nature. Compose with UI North Star:

| Risk | Pattern |
|------|---------|
| Restore, delete snapshot, wipe mount, replace image | **Parking card** or in-palette confirm step — never one silent Enter from cold open if irreversible |
| Quit / kill guest | **Double-press** or card |
| Fork (usually safer) | May run more lightly; still peek consequences |

**Flow:**

1. User selects destructive row → Enter.  
2. Either: palette closes and a **blocking card** arms over the notebook, or palette shows a confirm substep.  
3. Esc parks or cancels per card ladder; does not half-apply.  
4. Recents bump only after **confirmed** success.

Mark actions `destructive: true` in the registry so peek and footer can show the right affordance.

---

## 8. Open / close and focus

- **Open:** Ctrl+K (Mod+K). Host chord; must work when notebook owns focus. When guest fullscreen TUI has focus without host takeover, document whether Ctrl+K is still host-global (recommended: **yes** — control plane is host).
- **Close:** Esc, backdrop click (if any), successful non-nested run, or explicit close from `run({ close })`.
- Opening clears query (fresh default mode) unless a deep-link opens with a prefilled mode.
- Nested pickers (e.g. pick snapshot then confirm) push onto a small stack; Esc peels one level; optional restore of previous query/mode snapshot (Stacklane `previous_palette` idea).

Palette participates in the **Esc ladder** above guest VT (UI North Star §4.3).

---

## 9. Implementation sketch (Flutter)

Logical modules (names indicative):

```
lib/control_plane/
  kinds.dart          // PaletteKind, groups
  modes.dart          // parseMode, chip, allowlist, placeholders
  scorer.dart         // scoreItem pure
  recent.dart         // session-keyed MRU
  registry.dart       // register / unregister / list
  actions_static.dart // snapshot now, open mounts, …

lib/widgets/control_plane_palette.dart  // shell, list, peek, footer
```

- Pure Dart for modes/scorer/recent — unit-test without Flutter.  
- Registry is the single source for palette + keys + bottom hints.  
- Data from AgentOS host FFI / existing product session APIs; no second machine.

---

## 10. Phase guidance

| Phase | Ship |
|-------|------|
| **P0** | Open/close, static actions, modes (`>` + default), scorer, recents, groups, keyboard nav, footer |
| **P1** | Snapshot + mount + image sources, peek with destructive copy, parking-card restore |
| **P2** | State-scoped registration, relay/session, nested confirm stack |
| **P3** | Full help mode, polish empty tips, large-catalog search gate |

Do not block notebook spine on full P2; do not ship irreversible restore as a one-shot Enter without §7.

---

## 11. Checklist

- [ ] Ctrl+K opens control plane; center of gravity is machine verbs  
- [ ] Kinds and mode prefixes match §2–§3  
- [ ] Owned scorer + recents; weak matches dropped  
- [ ] State-scoped registration for context verbs  
- [ ] One registry → palette + keys + bottom bar  
- [ ] Highlight follows visual order; peek + footer live  
- [ ] Destructive paths use card / double-press; recents after confirm  
- [ ] Esc ladder respected; not a permanent nav rail  
- [ ] Distinct from Shift+Tab and terminal typing  

---

## 12. Open decisions

- Final prefix characters if any conflict with host typing habits on Linux  
- Peek always-on vs collapse on narrow windows  
- Whether “snapshot now” is always static or also a chord outside the palette  
- Catalog pagination UX when image list is huge  
- Multi-machine later: palette scope = active notebook guest only until multi-session exists  

---

*Alpha: replace kinds and prefixes when AgentOS nouns change. Keep the contracts (modes, scorer, scoped register, destructive confirm, single registry).*
