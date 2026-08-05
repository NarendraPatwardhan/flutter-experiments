# Ghostty lib-vt embed — design sketch

Working notes for making this product’s terminal **look and behave like Ghostty**, not like a demo that happens to link `libghostty-vt`.

**This document is not sacred.** It is not `SYSTEM.md`. Prefer a clean break over shims when the design is wrong. Quality is not deferred: if the embed is wrong, fix it.

Related:

- Permanent rules: `SYSTEM.md`, `AGENTS.md`
- AgentOS control plane: `docs/aos-c-api.md`, `docs/native-host-ffi.md`
- Pin: `@ghostty` (commit in `MODULE.bazel`) via `//third_party/ghostty`
- Product surface: `lib/vt/*`, `lib/session/product_session.dart`, `lib/main.dart`

Upstream itself warns that the C API is still evolving. We treat **libghostty-vt as the authority** for terminal semantics and encoding; we own only the Flutter presentation and the glue into AgentOS.

---

## 1. What problem this product is solving

The product vision is **computer-in-a-terminal**: a native AgentOS machine whose primary UI is a terminal surface that feels as good as opening Ghostty itself.

That splits cleanly into two hosts:

| Concern | Owner | Library |
|---------|--------|---------|
| Guest machine, caps, tools, snapshots | AgentOS | `libagentos_flutter_host` → `KernelHost` |
| Escape sequences, grid, styles, scrollback, input encoding | Ghostty | `libghostty-vt` |

AgentOS must never grow a second VT parser. Flutter must never invent CSI/Kitty encodings “for convenience.” Ghostty already solved those problems; we are an **embedder**.

A pristine terminal experience is not “draw characters on a grid.” It is the full closed loop Ghostty implements:

```text
   guest / PTY bytes  ──vt_write──►  terminal state
                                         │
                    effects (write_pty, title, clipboard, …)
                                         │
   render state  ◄── update ─────────────┘
         │
         ▼
   paint (cells, styles, cursor, selection, Kitty images)
         │
   keys / mouse / focus / paste
         │
   key|mouse encoder (modes from terminal)
         │
         ▼
   bytes back into the guest (AgentOS send_input)
```

That closed loop is implemented: `ProductSession` ticks AgentOS, feeds `take_output` into `vt_write`, drains WRITE_PTY back into `send_input`, encodes keys/focus/paste through Ghostty, projects render-state into `VtFrame` (styles, selection, dirty rows), and paints Kitty image layers. Further work is fidelity and product taste on that spine — not a second architecture.

---

## 2. What libghostty-vt is (and is not)

### Is

- A portable **virtual terminal core** extracted from Ghostty: parse, state, scrollback, reflow, modes, selection, input encoding helpers, render-state snapshots for custom renderers.
- Designed for **embedders that bring their own window, font, and GPU/CPU paint**.
- Already what we ship in `lib/libghostty-vt.so` (~full public symbol set for the pin).

### Is not

- The full Ghostty **application** (`ghostty_app_*`, surfaces, config files, Metal inspector, splits). That lives in `include/ghostty.h` and is the wrong dependency for a Flutter product.
- A look-and-feel library. Fonts, padding, anti-aliasing, and chrome are **ours** — but they should **match Ghostty’s visual rules** (metrics, cursor, cell layout), not Material defaults.
- A substitute for AgentOS. It does not boot kernels or enforce capabilities.

### Authoritative docs in the pin

The map of the world is `include/ghostty/vt.h` and the module headers it includes. Upstream examples under `example/c-vt-*` are the intended usage patterns (render, effects, encode-key, selection-gesture, colors, compression). Prefer those over inventing new shapes.

---

## 3. Where we stand today

### Native

`//third_party/ghostty` builds a real `libghostty-vt` against the git pin. Unicode tables, terminal options packages, and Zig 0.16 are product-constrained.

### Dart embedder

`lib/vt/*` is a plane-split embedder:

| Module | Role |
|--------|------|
| `bindings.dart` / `keys.dart` | FFI surface used by G1–G4 |
| `terminal.dart` | Terminal ownership, theme/palette, effects, write/resize/scroll |
| `encoder.dart` / `mouse.dart` | Key / focus / paste / mouse encode from live terminal modes |
| `render.dart` / `frame.dart` | Render-state → immutable `VtFrame` (full style, selection, dirty) |
| `painter.dart` / `metrics.dart` / `theme.dart` | Ghostty-aligned paint + chrome |
| `selection.dart` / `scroll.dart` | Gesture selection + viewport scroll |
| `graphics.dart` / `png.dart` / `image_cache.dart` | Kitty graphics → `ui.Image` layers |
| `compress.dart` / `snapshot.dart` / `format.dart` | Idle compression + export helpers |

### Product session

`lib/session/product_session.dart` owns both hosts and the ~50 Hz loop:

- boot VT (theme + 256 palette + Kitty + effects) + AgentOS
- tick → take_output → vt_write → WRITE_PTY → send_input
- keys/focus/paste via Ghostty encoders only (no hand-rolled CSI)
- selection, scroll, clipboard write (OSC 52), progress, notifications → chrome
- keep both hosts alive until dispose

So: **library rich, embedder real.** Quality work is fidelity (modes, mouse protocol when tracking is on, paint parity), not reopening the architecture.

---

## 4. Design principles

1. **Ghostty owns terminal truth.** Grid, modes, styles, scrollback, selection geometry, and key/mouse encoding come from lib-vt. Flutter only *presents* and *routes*.

2. **Do not reimplement CSI.** If lib-vt has an encoder, use it. Hand-rolled key maps drift from Kitty keyboard protocol and application-cursor modes the first week a real TUI runs.

3. **Effects are not optional chrome.** By default, `vt_write` **drops** sequences that need host action (device attributes, size reports, bells, OSC clipboard, …). Without `GHOSTTY_TERMINAL_OPT_WRITE_PTY` (and friends), programs that probe the terminal misbehave. That is a correctness bug, not a polish item.

4. **Render state is the paint boundary.** Prefer `ghostty_render_state_*` over poking raw grid refs for the hot path. Upstream designed update → dirty → row/cell walk for custom renderers. Honor that, including dirty layers (global + per-row) when we care about performance.

5. **Style is part of the cell, not a post-process.** Bold/underline/inverse must live on the Dart cell model and drive paint. Resolving “bold as bright” is an embedder policy Ghostty explicitly leaves to us; pick a policy and apply it consistently.

6. **One VT session owner.** Same discipline as AgentOS: one object owns the terminal handle; serialize access; UI isolate paints immutable snapshots (`VtFrame`). Callbacks from effects run during `vt_write` — keep them short; enqueue work, do not re-enter `vt_write`.

7. **AgentOS is a PTY-shaped peer.** Guest stdout/stderr/log → `vt_write`. Encoded keys / paste / focus → `aos_vm_send_input`. Effect `WRITE_PTY` responses → the same input path. The “pty” is conceptual; there is no host PTY device — AgentOS is the other end of the wire.

8. **Match Ghostty’s visual grammar, not its binary.** Font is Flutter/`fontconfig` mono; metrics should follow Ghostty’s cell/cursor rules (`metrics.dart` already aims here). Padding, scrollbar, selection highlight, and unfocused hollow cursor should feel familiar to a Ghostty user.

9. **Prefer the right model over preserving dead paths.** If `lib/vt` shape is wrong, rewrite it; do not pile flags onto obsolete session facades.

10. **Do not pull full Ghostty app/runtime into the product.** No `ghostty_app_*`, no embedding GTK Ghostty. lib-vt only.

---

## 5. Ideal architecture

### 5.1 Three planes

Think of the embed as three planes that must all exist; product code owns all three.

```text
┌─────────────────────────────────────────────────────────────┐
│  PLANE A — Stream (bidirectional VT)                        │
│                                                             │
│  AgentOS take_output ──► vt_write                           │
│  WRITE_PTY / size replies ──► send_input                    │
│  key/mouse/focus/paste encoders ──► send_input              │
│  effects (title, pwd, clipboard, bell, notifications)       │
│            ──► Dart chrome / system services                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  PLANE B — Terminal state (libghostty-vt)                   │
│                                                             │
│  screen, alt screen, scrollback, modes, palette, selection  │
│  kitty graphics storage, cursor, styles                     │
└─────────────────────────────────────────────────────────────┘
                              │
                     render_state_update
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  PLANE C — Presentation (Flutter)                           │
│                                                             │
│  VtFrame (immutable): cells with full style, cursor,        │
│  selection marks, palette snapshot, dirty hint              │
│  VtPainter + VtMetrics + VtTheme                            │
│  chrome: title, pwd, progress, bell flash                   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Ownership and threading

**Recommended end state:**

- A **session owner** (today: main-isolate `ProductSession`; may move to a worker isolate) holds:
  - `GhosttyTerminal`
  - `GhosttyRenderState` + reusable row/cell iterators
  - `GhosttyKeyEncoder` + mouse encoder helpers
  - selection-gesture state
  - AgentOS `AgentOsVm` handle (or a channel to the VM owner if split further)
- UI receives **immutable** `VtFrame` + chrome model updates; sends **input intents** (key, pointer, paste, focus, scroll).

Effects fire **synchronously** inside `vt_write` on the session owner’s thread. Their job is to enqueue:

- bytes for AgentOS input (WRITE_PTY),
- chrome events (title, pwd, progress),
- clipboard / notification intents for the platform.

They must never call `vt_write` re-entrantly and should not block on UI.

### 5.3 Coupling to AgentOS (the closed loop)

Ideal live session (product spine), terminal-first:

```text
boot AgentOS (deny caps, loom) + open Ghostty terminal (cols×rows, cell px)
install effects (at least WRITE_PTY → queue toward send_input)
install default theme (palette + FG/BG/cursor, not only three colors)
loop:
  drain AgentOS relay if any (orthogonal; do not block paint forever)
  tick AgentOS
  take_output → vt_write
  process effect queue → send_input / chrome
  if dirty: render_state_update → VtFrame → UI
  on key/mouse/focus/paste:
    sync encoder from terminal
    encode → send_input
  on resize:
    terminal_resize(cols, rows, cellW, cellH)
    (AgentOS size awareness is optional; VT size reports go via effects)
  status / at_prompt → optional chrome
keep both hosts alive until app dispose
```

`exec`-driven demos remain useful as diagnostics, not as the primary UX.

### 5.4 The paint model we want

`VtFrame` should become a **render-state projection**, not a text dump:

- Per cell: grapheme cluster, resolved fg/bg, full style flags (bold, italic, faint, inverse, invisible, strikethrough, overline, underline kind + underline color), selected bit, wide-cell awareness as needed for cursor.
- Frame-level: cols/rows, default fg/bg, optional cursor color, cursor geometry + blink + visible, palette snapshot (for bold-bright policy and debugging), global dirty kind.
- Painter responsibilities (Ghostty-aligned):
  - cell background pass
  - selection overlay policy (invert or theme selection colors — pick one and document)
  - glyph pass with font weight/style from cell flags
  - underline / strikethrough / overline decorations from metrics
  - cursor under or over glyphs per style (block under text; bar/underline after)
  - unfocused → hollow block
  - kitty image layers (z < 0 below text, z ≥ 0 above; ui.Image cache)

Metrics stay measured mono (JetBrains Mono / system mono): **cell advance = face advance**, height from face metrics — already the Ghostty direction. Do not invent a second layout system.

### 5.5 Input model we want

Flutter `KeyEvent` / pointer events are **host** events. They become terminal bytes only through:

1. Map to `GhosttyKeyEvent` / mouse event (key code, mods, action, utf8 if any).
2. `ghostty_key_encoder_setopt_from_terminal` (or mouse equivalent) so application cursor keys, Kitty flags, mouse modes match live state.
3. `encode` into a buffer.
4. `aos_vm_send_input`.

Focus in/out uses `ghostty_focus_encode` when the surface gains/loses focus. Paste uses `ghostty_paste_is_safe` + encode (bracketed paste when the terminal is in that mode).

Guessing “Enter is `\r`” is **wrong** as product architecture — always use the Ghostty key encoder.

### 5.6 Effects model we want

Minimum viable honesty:

| Effect | Destination |
|--------|-------------|
| `WRITE_PTY` | AgentOS `send_input` (query answers) |
| `TITLE_CHANGED` | chrome title (read via terminal get or OSC path as upstream recommends) |
| `PWD_CHANGED` | chrome / status |
| `BELL` | brief visual flash (and optional system bell) |
| `CLIPBOARD_WRITE` | platform clipboard (OSC 52 / OSC 1337; text MIME; empty clears) |
| `DEVICE_ATTRIBUTES` / `SIZE` / `COLOR_SCHEME` / `XTVERSION` | usually satisfied *through* WRITE_PTY if the terminal emits replies; install callbacks when the pin requires explicit handling |

Register via `ghostty_terminal_set` with a single userdata pointing at the session owner. Clearing callbacks is part of dispose.

### 5.7 Scroll and selection — **Done**

Ghostty users expect, and we implement:

- **Scrollback**: viewport moves through history (`scroll_viewport`); scrollbar metrics available from terminal data.
- **Selection**: gesture state machine in lib-vt (`selection_gesture_*` + terminal selection opts), paint via per-cell selected, copy via `selection_format_*` (Ctrl/Cmd+Shift+C).

### 5.8 Kitty graphics — **Done**

Terminal storage limit + process-global PNG decoder (`sys`), placement walk → `VtImageLayer`, async `VtImageCache` → `ui.Image`, painter composites below/above text by z. Geometry from `ghostty_kitty_graphics_placement_render_info`.

---

## 6. What “looks like Ghostty” means here

Subjective, but bound to concrete rules:

1. **Dark, quiet chrome** — thin status strip, not Material AppBar marketing. (`VtTheme` already leans this way.)
2. **Correct mono metrics** — no double-spacing, no clamped advances that butcher JetBrains Mono.
3. **Full SGR fidelity** — bold/italic/underline/inverse/faint and 256/truecolor look right.
4. **Cursor language** — block/bar/underline/hollow; blink when mode says so; hollow when unfocused.
5. **Selection** that behaves like a terminal (word/line/drag), not a TextField.
6. **Input that TUIs accept** — Kitty keyboard, application cursor keys, mouse tracking when enabled.
7. **Programs that query the terminal get answers** — WRITE_PTY closed loop.
8. **Resize** reflows primary screen and reports pixel cell size for protocols.

If those hold, the product can sit next to Ghostty without apology even though the window is Flutter and the guest is AgentOS.

---

## 7. Layering of the Dart codebase (ideal shape)

Not sacred names — the **roles** matter:

```text
lib/vt/
  bindings.dart      // raw FFI; lib-vt surface for G1–G4
  terminal.dart      // GhosttyTerminal + effects + write/resize/get
  encoder.dart       // key / mouse / focus / paste encode helpers
  render.dart        // render_state update → VtFrame (partial dirty)
  frame.dart         // immutable paint model (rich cells + dirtyRows + chrome events)
  painter.dart       // CustomPainter; cells + Kitty image layers
  metrics.dart       // font → cell geometry (Ghostty rules)
  theme.dart         // product defaults; optional palette presets
  graphics.dart      // Kitty placement → VtImageLayer + sys PNG hook
  png.dart           // sync 8-bit PNG → RGBA (sys decode callback)
  image_cache.dart   // async ui.Image cache for sync paint
  compress.dart      // idle scrollback compression scheduler
  snapshot.dart      // snapshot_encode_buf grow helper
  format.dart        // terminal formatter plain/vt/html
  selection.dart / scroll.dart / mouse.dart  // G3 interaction
  session.dart       // legacy façade (palette-aligned; product uses terminal.dart)
```

Split is already by plane. Product ownership lives in `lib/session/product_session.dart` — that object is **not** the Ghostty terminal handle.

AgentOS stays in `lib/agent_os/`.

---

## 8. Phased expansion (narrative history)

Phases describe **capability thresholds** that have been crossed. G0–G4 are in tree.

### Phase G0 — Smoke

Write bytes, paint text and flat colors, resize grid, default theme colors. Proved `.so` load + AgentOS dump. Superseded.

### Phase G1 — Honest picture — **Done**

Styles, inverse, underline, palette-aware colors, real cursor attributes. Comparison to Ghostty is fair on static styled output.

### Phase G2 — Honest machine — **Done**

Effects + WRITE_PTY closed with AgentOS; key encoder driven from terminal modes; focus encode; paste safety. Live dual-host session.

### Phase G3 — Honest interaction — **Done**

Selection gestures, copy, scrollback navigation, mouse helpers. Daily-driver terminal habits work.

### Phase G4 — Full embedder ambition — **Done**

Kitty graphics, scrollback compression, snapshots/formatter, partial dirty projection, progress OSC + desktop notifications, OSC 52 clipboard write.

---

## 9. Relationship to the AgentOS C ABI sketch

| Document | Authority |
|----------|-----------|
| `aos-c-api.md` | Control plane over `KernelHost` |
| **this file** | Embed of `libghostty-vt` + Flutter presentation |

Cross-rules already in the AgentOS sketch remain true:

- Ghostty / paint / key encode stay **out** of `libagentos_flutter_host.so`.
- AgentOS does not parse VT.
- Product loop: relay (when needed) → tick → take_output → **vt_write** → paint; keys → **encode** → send_input.

If the two sketches conflict, fix the sketch or the code — not permanent system rules — unless product intent itself changed.

---

## 10. Explicit non-goals (for this sketch)

- Replacing Flutter with Ghostty’s GTK/macOS app runtime.
- Implementing a second terminal emulator in pure Dart.
- Pixel-identical output to Ghostty’s GPU shaders (different font stack and painter; **behavior and grammar** match, not hash-identical frames).
- Freezing the lib-vt C API (upstream may break; pin and adapt).
- Binding every last symbol with no product path — still prefer plane-driven bind, but **do not defer whole planes** once the vision calls for them.

---

## 11. Implementation status (honest)

| Area | Status |
|------|--------|
| Ship `libghostty-vt.so` from pin | **Done** |
| Dart FFI: lib-vt surface for G1–G3 | **Done** (`bindings.dart`, `keys.dart`) |
| Cell style / selection in frame+paint | **Done** (G1: `render.dart`, `painter.dart`) |
| Effects + WRITE_PTY ↔ AgentOS | **Done** (G2: `terminal.dart` → `ProductSession`) |
| Key / focus / paste encoders | **Done** (G2: `encoder.dart`) |
| Live dual-host session loop | **Done** (`lib/session/product_session.dart`, `main.dart`) |
| Selection + scroll + mouse helpers | **Done** (G3: `selection.dart`, `scroll.dart`, `mouse.dart`) |
| OSC 52 clipboard write | **Done** (effect → platform text clipboard) |
| Default 256-color palette | **Done** (`ghostty_color_palette_default` on open) |
| Kitty graphics + image paint | **Done** (G4: `graphics.dart`, `image_cache.dart`, painter z-layers) |
| Partial dirty projection | **Done** (G4: `render.dart` clean/partial/full + `VtFrame.dirtyRows`) |
| Scrollback compression scheduler | **Done** (G4: `compress.dart` idle 300ms incremental) |
| Snapshot / formatter export | **Done** (G4: `snapshot.dart`, `format.dart`) |
| Progress OSC + desktop notifications | **Done** (G4: `VtChromeProgress` / `VtChromeNotification` → status) |
| Docs for embed intent | **This sketch** |

G1–G4 embedder planes are implemented. Further work is fidelity and product taste, not a missing plane.

---

## 12. Bottom line

Ideal is **not** “call more Ghostty functions until the symbol table is empty.”

Ideal is a **full Ghostty-shaped embed**:

1. lib-vt as the only VT authority,
2. Flutter as a faithful renderer of render-state + style,
3. encoders for all host input,
4. effects that close the loop with AgentOS as the pty peer,
5. scroll, selection, graphics, and clipboard as first-class host duties.

G1–G4 are in tree. Treat further work as product quality on that spine, not as a missing plane.

Update this file when the embed architecture diverges. Prefer rewriting `lib/vt` over piling flags onto dead paths.
