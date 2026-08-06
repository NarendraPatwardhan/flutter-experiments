# UI North Star

Design rules for the **machine notebook** product: one AgentOS guest, one timeline, terminal-first cells, optional natural-language turns into the same machine, multi-agent work on that machine, and a load-bearing control plane.

Related:

- `SYSTEM.md` — product purpose and dual-host architecture
- `docs/agentos-capabilities.md` — control-plane surface area (AgentOS)
- `docs/control-plane-palette.md` — **Ctrl+K control plane palette**
- `docs/agent-spine.md` — **agent loop, multi-agent, continual harness on AgentOS**
- `docs/ui-toolkit.md` — **Forui hybrid vs invent** decision
- Grok Build (OSS) — thin status bars and interaction contracts; not a stack to port
- Stacklane / Opyt Cmd-K (`../stacklane`) — palette **mechanism** reference; not issue-tracker ontology
- Prime Intellect / RLM harness diagram — multi-agent orchestration **shapes** (see agent-spine)
- Pi analysis — `../agent-os/PI_AGENT_HARNESS_ANALYSIS.md` — thin harness **boundaries** (see agent-spine)

---

## 1. Vision

**A machine notebook.**

- Default cell is a **real Ghostty terminal** on AgentOS (libghostty-vt).
- **Shift+Tab** switches the active input cell to **natural language** — text into an agent that operates the **same** machine.
- **Ctrl+K** opens the **control plane** — mounts, image, caps, **snapshot / restore / fork**, relay, guest lifecycle. Core surface, not polish. Spec: [`docs/control-plane-palette.md`](control-plane-palette.md). Grok Build works *on* a machine that is already set; we *host* the machine, so control plane is load-bearing.
- **AgentOS is the execution kernel** for agent tools and sub-agents — not a host IPython and not N private REPLs. Spec: [`docs/agent-spine.md`](agent-spine.md).
- History **stacks upward** (newest work at the bottom input; completed cells flow up).
- Active surfaces **expand for reading**, then **hard-cap into scroll** (§4.9).
- Looks like a terminal (dark, mono, thin chrome) — not an IDE, not a generic chat app.
- Host chrome widgets: **hybrid toolkit** (Forui primitives + invented product systems). Spec: [`docs/ui-toolkit.md`](ui-toolkit.md).

Three equal entry paths: **type in the machine** (terminal) · **talk to the agent on the machine** (NL) · **control plane** (Ctrl+K).

### 1.1 Single machine timeline (canonical)

| Rule | Meaning |
|------|---------|
| **One guest** | One AgentOS kernel/session per notebook window (primary product path). |
| **One primary shell** | Terminal cells and agent shell blocks write the **same** machine. |
| **Notebook is a view** | Segmentation is UX over one session — **not** N isolated REPLs. |
| **No split brains** | `cd` in a terminal cell and an agent shell tool see the same guest state. |
| **Sub-agents share the guest** | Parallel / background / persistent workers default to the **same** guest; isolation is **fork/snapshot** via control plane. |

Rejected alternate: agent-tool shells or sub-agents as a separate universe from the live terminal (Grok-like isolation or host IPython). That is not this product.

### 1.2 Product layers

| Layer | Role |
|-------|------|
| **Machine** | AgentOS guest (kernel, image, mounts, caps, tools, snapshots). |
| **Terminal cells** | libghostty-vt — live grid for the active terminal cell; frozen snapshots for completed ones. |
| **Notebook host** | Flutter — cell list, focus, Shift+Tab modes, NL composer, agent block layout, status bars. |
| **Agent spine** | LLM transport + thin agent loop + harness store + guest-first tools. See `agent-spine.md`. |
| **Control plane** | Ctrl+K palette + short-lived sheets: mounts, catalog, snapshots, relay — not permanent sidebars. See `control-plane-palette.md`. |

Rules:

1. **Terminal-first.** Empty or single-cell session feels like a full-bleed terminal, not a chat welcome screen.
2. **You are the terminal host.** Do not ship nested-terminal capability theater (truecolor probes, tmux doctor, compact modes for living inside another emulator).
3. **No permanent IDE chrome.** No always-on file tree, activity bar, or multi-column IDE shell.
4. **Guest is the REPL.** Do not invent a second host runtime as the agent’s real computer.

---

## 2. Cell model

### 2.1 Cell types

| Type | Input | Output / body |
|------|--------|----------------|
| **Terminal** (default) | Keys → VT encode → same guest PTY/shell | Live VT while active; **freeze** when the cell is completed / left |
| **Natural language** | Host multiline text (not VT) | Agent turn: blocks (thinking, text, shell, …) |
| **Agent blocks** | (produced by agent / sub-agents) | Structured segments of one turn; shell blocks execute on the **bound** guest |
| **Control / system** | — | Host notices, errors, confirmations (cards) |

Only **one live VT** at a time: the focused terminal cell. Completed terminal cells are immutable snapshots (or fork-on-edit later). Do not stretch one continuous Ghostty grid into multi-cell notebook semantics.

### 2.2 Mode switch: Shift+Tab

On the **active input cell**:

| Mode | Behavior |
|------|----------|
| **Terminal** (default) | Input is the machine shell via Ghostty. |
| **Natural language** | Input is a host composer; submit runs the agent against the same guest. |

- Visible **mode chip** on the active surface (same spirit as Grok’s model/mode chip).
- Shift+Tab is a **host** chord when the notebook owns the input cell; do not steal it from guest apps when a full-screen TUI inside the guest has legitimate focus without host takeover — document the focus rule when implementing (Esc ladder applies).
- Do not overload Shift+Tab with unrelated meanings without updating the mode chip and footer hints.
- **Shift+Tab is not Ctrl+K.** Cell mode vs control plane stay separate.

### 2.3 History flow

- Completed cells stack **upward**.
- Active input stays **bottom-anchored**.
- Notebook scroll moves through the timeline; the active cell still follows expand → cap → internal scroll (§4.9).
- Sub-agent parallel/background output folds into blocks on this timeline (see `agent-spine.md` §5).

---

## 3. Chrome: Grok-clean bars + control plane + toolkit

Reference preference: **Grok Build’s top and bottom bars** are the cleanliness target among Codex, Claude Code, and peers — thin, quiet, high signal.

Reference preference for **Ctrl+K mechanism**: **Stacklane’s command palette** (modes, owned scorer, recents, state-scoped commands, peek pane) — adapted to machine kinds. Full spec: [`docs/control-plane-palette.md`](control-plane-palette.md).

Reference preference for **widgets/theme**: **hybrid Forui + invented systems**. Full decision: [`docs/ui-toolkit.md`](ui-toolkit.md).

### 3.1 Top status bar

Persistent, **fixed height**, never expands with draft content.

Examples of content (exact fields later):

- Session / machine identity (image, short id)
- Workspace or mount context when meaningful
- Quiet capacity or health meter if needed (tokens, disk, guest state) — not a dashboard
- Optional: background agent / harness activity chip (without becoming a multi-agent IDE)

Does **not** grow into a ribbon of tabs or a second navigation system.

### 3.2 Bottom status bar

Persistent, **context-sensitive**:

- Live key hints for the focused surface (`Enter:send`, `Shift+Tab:mode`, `Ctrl+K:…`)
- Mode / agent policy chip when relevant (e.g. approval mode) — prefer attachment to the **active input chrome** when composing (Grok pattern: chip on the composer)
- Hints **appear and disappear** with state; no dead shortcuts padding the bar
- Hints and chords share the **same action registry** as the control plane palette

### 3.3 Ctrl+K — control plane (core, not optional)

**Ctrl+K is the control plane entry**, equal in importance to the terminal cell and Shift+Tab NL mode.

Normative detail: **[`docs/control-plane-palette.md`](control-plane-palette.md)**.

#### Why peers do not carry this weight (and we do)

| Peer | Reality |
|------|---------|
| **Grok Build** | Runs on your machine; palette is mostly app actions. Machine is already “set.” |
| **Stacklane Cmd-K** | Excellent **reach** across a workspace graph. Workspace is already set. |
| **Pi / coding harnesses** | Host process tools; isolation is external. |
| **This product** | Hosts AgentOS. Image, mounts, caps, **snapshot / restore / fork** are product state. Ctrl+K’s center of gravity is **machine control plane**. Sub-agents **depend** on this for real isolation (fork). |

Steal Stacklane’s **mechanism**; do not steal issue/doc/channel ontology. Steal Grok’s **bar cleanliness**. Steal Pi/Prime **harness discipline** into `agent-spine.md`, not into palette nouns.

#### Summary of Ctrl+K duties

- Fuzzy list from one **action registry** (also drives keys + bottom hints)
- Modes via prefixes (machine-oriented — see palette doc)
- Sources: static verbs, live snapshots/mounts/images, state-scoped registrations, recents
- Peek for context; **destructive** runs go through parking cards / double-press
- Opens over the notebook; Esc peels / closes; not a permanent nav rail

#### What Ctrl+K is not

- Not Shift+Tab (terminal ↔ NL on the **same** machine)
- Not the agent loop (NL reasoning lives in the notebook + agent spine)
- Not a second permanent nav rail
- Not a substitute for typing in the terminal cell

### 3.4 Ephemeral heavy UI

Still prefer short-lived surfaces for depth:

- Control plane results → modals / pickers / sheets
- Overlay panes (mounts list, snapshot list, …)
- Blocking cards (permissions, destructive confirm — e.g. restore wipes live state)

Not permanent left/right docks.

### 3.5 UI toolkit (Forui hybrid)

Canonical decision: [`docs/ui-toolkit.md`](ui-toolkit.md).

| Do | Don’t |
|----|--------|
| Use Forui (or equivalent) for theme tokens + dialog/input/list primitives when pin cost is acceptable | Make Forui dictate Esc ladder, registry, or cell model |
| Invent palette scoring/modes, notebook, VT, agent blocks | Invent a full competing Material design system for free |
| Dark, dense, mono-friendly theme | Ship default generic shadcn SaaS look on the terminal |

If Forui fights Bazel hermetic pins or bundle size, use internal tokens + Flutter primitives and keep inventing product systems either way.

---

## 4. Steal list (interaction + harness contracts)

### 4.1 From Grok Build (chrome + session feel)

| Contract | Use here |
|----------|----------|
| Thin top + bottom bars | §3.1–3.2 |
| Overlay three-state + Esc peel | §4.4 |
| Esc ladder | §4.5 |
| Blocking cards that park | §4.6 |
| Destructive double-press | §4.7 |
| Expand → hard-cap → scroll | §4.9 |
| One action registry → keys + hints (+ palette) | §4.3 |

### 4.2 From Stacklane Cmd-K (palette mechanism)

Normative in `control-plane-palette.md`. Summary: kinded rows, prefix modes, owned scorer, recents, state-scoped registration, visual-order highlight, peek, fetch-when-open.

### 4.3 From Prime Intellect harness diagram + Pi analysis

Normative in `agent-spine.md`. Summary:

| Contract | Use here |
|----------|----------|
| Guest = persistent execution kernel | Not host IPython |
| Continual harness (prompt/memory/skill/subagent) | Cross-turn state beside trajectory |
| Sub-agents: parallel / background / persistent | Same guest by default; fork via Ctrl+K |
| Trajectory ↔ harness writeback | Cells visible; refine later |
| Split LLM / loop / product / machine | No god-object Flutter agent |
| Tiny default tool schemas | Guest-first, low fixed tax |
| Durable sessions before multi-agent theater | Persist before dashboards |
| Honest security via real sandbox | AgentOS caps + cards |

### 4.4 One action registry → three consumers

A single table of host actions feeds:

1. **Key dispatch**
2. **Control plane palette** (Ctrl+K)
3. **Bottom bar hints**

Do not maintain three parallel key maps.

### 4.5 Overlay three-state + shared Esc peel

```
Hidden ──shortcut──► Visible + Focused ──shortcut──► Hidden
                           │ Tab / Space
                           ▼
                     Visible + Unfocused
```

Esc peels **one** nesting level. Same contract for every control-plane pane.

### 4.6 Esc is a ladder (explicit priority)

1. Steal first: control plane palette, nested picker, host text fields, selection on host chrome.
2. Overlay stack peel.
3. Blocking card **park** (card stays; focus returns to notebook/terminal).
4. Active terminal cell / guest receives Esc only when no host surface owns the key.

### 4.7 Blocking cards that park

Confirmations stay on screen over the live timeline. Esc parks focus so the user can scroll history; Tab returns to the card. Never blank the machine. **Restore / fork / wipe** use this path.

### 4.8 Destructive = double-press

Arm on first press; confirm on second within a short window when a full card is unnecessary. Prefer cards for irreversible guest mutations.

### 4.9 Presentation split

| Concern | Owner |
|---------|--------|
| Live terminal paint, metrics, selection, OSC 52 | VT + terminal cell widget |
| Frozen terminal cell paint | Snapshot of grid / buffer owned by notebook |
| NL composer, agent blocks, status bars | Notebook host |
| Control plane palette + registry | Host control-plane module |
| Agent loop + harness | Agent spine (not VT) |
| Theme primitives | Toolkit hybrid (`ui-toolkit.md`) |
| Host state machines | Host state, not VT |

### 4.10 Expand for reading, then hard-cap into scroll

Surfaces that grow (active terminal cell, NL draft, agent block groups, long sheets):

1. **Expand first** so content is readable. Neighbors **flex**.
2. **Hard cap** (viewport fraction or max rows).
3. **Then scroll** inside that fixed region.

The control plane **palette shell** may stay fixed height with internal list scroll. Expand-cap applies to notebook cells and sheets.

---

## 5. Explicit non-goals

| Pattern | Why not |
|---------|---------|
| N isolated REPLs / one PTY per cell forever | Breaks single machine timeline. |
| Host IPython (or host REPL) as agent core | AgentOS is the computer. |
| One continuous VT faked into notebook cells | Fights libghostty-vt; use one live VT + freezes. |
| Agent shell disconnected from live terminal | Split brain; rejected. |
| Silent private FS per sub-agent | Use fork/snapshot if isolation is required. |
| Terminal `/doctor` / nested capability theater | We host the terminal. |
| Minimal/compact modes for nested TUI life | Not our environment. |
| Permanent IDE chrome | Rejected. |
| Chat-first empty state | Terminal-first machine notebook. |
| Ctrl+K as issue/doc/file search clone | Wrong ontology; use machine kinds. |
| Silent one-shot restore from palette | Destructive; needs card / confirm. |
| Forui (or any kit) as product identity | Terminal notebook + machine control plane is identity. |
| Dual production agent loops | One loop path (`agent-spine.md`). |

---

## 6. Map: references → this product

| Reference idea | This product |
|----------------|--------------|
| Grok transcript stacking up | Notebook cell timeline (terminal freezes + agent blocks) |
| Grok prompt composer | Active cell: terminal **or** NL (Shift+Tab) |
| Grok model/mode chip on composer | Mode + policy on active input chrome |
| Grok top path + usage meter | Top status bar (machine/session identity) |
| Grok bottom shortcuts bar | Bottom status bar (live hints from same registry) |
| Grok Ctrl+P app palette | **Ctrl+K control plane** — different job |
| Stacklane kinds + modes + scorer + recents | Same **mechanism**, machine **kinds/prefixes** |
| Stacklane route `useCommand` | State-scoped registration |
| Prime diagram: IPython kernel | **AgentOS guest** |
| Prime diagram: sub-agents | Parallel / bg / persistent on guest (or fork) |
| Prime diagram: continual harness | prompt / memory / skill / subagent store |
| Pi: thin loop + tiny tools + sessions | `agent-spine.md` layer split |
| Forui / shadcn Flutter | Primitives + theme only (`ui-toolkit.md`) |

---

## 7. Architecture constraints (implementation law)

1. **Notebook (Flutter) owns** layout, focus, cell list, mode, bars.
2. **libghostty-vt** is the engine for the **live** terminal cell only (plus encode/parse).
3. **Completed terminal cells** are frozen; reopening edit is an explicit fork if ever supported.
4. **Agent shell tools and sub-agents** target the AgentOS guest they are bound to (default: the notebook’s one guest).
5. **Control plane** remains AgentOS host API + ephemeral UI — not a second machine.
6. **One action registry** shared by Ctrl+K, key chords, and bottom hints.
7. **One agent loop path** — LLM transport / loop / harness / UI / AgentOS / VT stay split (`agent-spine.md`).
8. **UI toolkit hybrid** — product systems invented; chrome primitives optionally Forui (`ui-toolkit.md`).

---

## 8. Phase guidance

| Phase | Focus |
|-------|--------|
| Now / near | Dual-host quality (VT + AgentOS closed loop). Notebook as target UX; avoid paint that blocks cell freeze later. |
| Notebook spine (H1) | **Skeleton in tree:** `lib/notebook/*` — cell history, freeze (`VtFrame.clone`), top/bottom bars, Shift+Tab NL stub, Ctrl+K stub, host chords. Agent still stub. |
| Toolkit | Theme tokens (Forui or internal); palette shell can use primitives. |
| Control plane P0–P1 (H2) | Real Ctrl+K modes/scorer/recents; snapshot/mount/image + destructive cards. |
| Agent A1–A2 (H3) | Real loop + guest-first tools; harness kinds on disk. See `agent-spine.md` §8. |
| Agent A3+ | Parallel/background sub-agents; then persistent + fork isolation; refine later. |

---

## 9. North-star checklist

Before shipping UI / agent chrome:

- [ ] Single machine timeline: one guest; terminal, agent shell, and default sub-agents share it
- [ ] Default path feels terminal-first (not chat-first)
- [ ] Only one live VT; completed terminal cells freeze
- [ ] Shift+Tab toggles terminal ↔ NL with a visible mode chip (not Ctrl+K)
- [ ] Top bar thin and fixed; bottom bar live hints (Grok-clean)
- [ ] Ctrl+K implements control plane per `control-plane-palette.md`
- [ ] One registry → palette + keys + bottom bar
- [ ] Destructive control-plane verbs use parking cards / double-press
- [ ] Agent spine respects guest-as-REPL and layer split (`agent-spine.md`)
- [ ] UI toolkit hybrid respected (`ui-toolkit.md`)
- [ ] Expand → hard-cap → internal scroll on growing notebook surfaces
- [ ] Esc ladder and parking cards respected
- [ ] No permanent IDE chrome; no N isolated REPLs; no host IPython core

---

## 10. Open design (not decided here)

- Exact freeze format for terminal cells (grid snapshot vs text vs hybrid)
- When a terminal cell is “completed”
- Agent runtime package choice and block schema (within agent-spine constraints)
- Control plane palette shell density; Forui pin vs internal tokens first
- Harness file layout on guest vs host mirror
- Multi-window / multi-session later
- Mobile: same cell model and bars; larger hit targets; Ctrl+K still primary for control plane

---

*Alpha product: replace this document when a better interaction model wins. Do not preserve chrome out of habit.*
