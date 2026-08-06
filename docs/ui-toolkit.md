# UI toolkit decision

How we build **host chrome** (control plane palette, sheets, bars, dialogs) without fighting the terminal-first notebook.

Related:

- `docs/ui-northstar.md` — visual and interaction north star  
- `docs/control-plane-palette.md` — palette **behavior** (not widget brand)  
- [Forui](https://forui.dev/) — Flutter UI library inspired by shadcn/ui  

---

## 1. Decision (canonical)

**Hybrid.**

| Layer | Approach |
|-------|----------|
| **Theme tokens + primitive widgets** | Prefer **Forui** (`FTheme`, buttons, text fields, dialogs, lists, overlays) when the dependency is compatible with the Bazel / rules_flutter pin |
| **Product interaction systems** | **Invent** — control plane palette logic, notebook cells, Esc ladder, overlay 3-state, action registry, VT embed |
| **Brand / density** | Force a **dark, dense, mono-friendly** Forui (or token) theme so chrome does not look like a generic SaaS dashboard on a terminal |

**Not** “invent a full design system from zero.”  
**Not** “the app is a Forui template with a terminal stuck in.”

---

## 2. Why hybrid

### 2.1 What Forui is good for

- Consistent radii, colors, type, focus rings  
- Dialog / popover / input / button / scroll list primitives  
- Faster P0 for control-plane **frame** (shell around Stacklane-like palette behavior)  
- Optional theme CLI / visual theme tooling ([create.forui.dev](https://create.forui.dev))  

### 2.2 What Forui does not provide

| Need | Owner |
|------|--------|
| Mode prefixes, owned scorer, recents, kinds | `control-plane-palette.md` — our code |
| State-scoped action registration | Our registry |
| Peek policy + destructive confirm | Our code + parking cards |
| Notebook cell model, freeze, Shift+Tab | Our code |
| libghostty-vt paint / PTY | Dual-host stack |
| Grok-thin status bar geometry | Our layout |

### 2.3 Risks of full custom

- Slow chrome polish; inconsistent focus/a11y  
- Re-implementing dialogs and lists poorly  

### 2.4 Risks of Forui-first product

- Generic shadcn look clashes with terminal notebook  
- Interaction contracts drift into “whatever the kit encourages”  
- Extra dependency pin under zero-local-analysis Bazel builds  

---

## 3. Rules

1. **Contracts beat components.** Esc ladder, single registry, expand-cap-scroll, single machine timeline are law; widgets only implement them.  
2. **Palette logic is ours.** Forui may supply `Dialog` + `TextField` + list rows; scoring/modes/recents are pure Dart modules.  
3. **Retheme early.** Ship a custom dark theme (primary/background/border/mono) before adding many screens.  
4. **Bundle cost matters.** If Forui fights hermetic pins or bloating `linux_product_bundle`, fall back to Flutter primitives + a tiny internal token file (`lib/theme/tokens.dart` or equivalent) and revisit.  
5. **VT and notebook are not Forui trees.** Terminal cell is a custom render surface; notebook list is our structure with optional Forui chips/buttons at edges.

---

## 4. Suggested use matrix

| Surface | Toolkit |
|---------|---------|
| Ctrl+K shell (backdrop, popup, input, footer chrome) | Forui dialog + layout primitives |
| Palette rows / groups | Forui list/button styles **or** custom rows using theme colors |
| Peek pane | Custom layout + theme tokens |
| Top / bottom status bars | Custom layout; tokens for color/type |
| Parking cards / confirms | Forui dialog or custom card + tokens |
| Settings-ish sheets | Forui where boring forms help |
| Live / frozen terminal cells | Custom (Ghostty + Flutter) |
| Agent block chrome (thinking/text/shell) | Custom; tokens for borders/type |

---

## 5. Phases

| Phase | Action |
|-------|--------|
| **T0** | Decide pin: add Forui when first non-VT host chrome lands, **or** internal tokens only if pin cost is high |
| **T1** | Dark dense theme applied; palette shell uses shared tokens |
| **T2** | Sheets/cards reuse the same theme; no second ad-hoc color system |

---

## 6. Checklist

- [ ] Hybrid decision respected (no full invent, no full kit-as-product)  
- [ ] Control plane behavior matches `control-plane-palette.md` regardless of widget brand  
- [ ] Dark dense mono-friendly theme, not default marketing shadcn  
- [ ] Exit ramp if Bazel/bundle cost is unacceptable  

---

*Alpha: swap Forui for another tokenized kit only with an explicit product decision; keep inventing product systems either way.*
