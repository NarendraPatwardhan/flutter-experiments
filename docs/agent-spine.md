# Agent spine

How the **NL agent**, **multi-agent work**, and **continual harness** sit on **AgentOS** inside the machine notebook.

Related:

- `docs/ui-northstar.md` — notebook UI, three entry paths, single machine timeline
- `docs/control-plane-palette.md` — Ctrl+K reshapes the machine agents share
- `docs/agentos-capabilities.md` — guest OS surface (caps, mounts, snapshots, tools)
- **Prime Intellect / RLM harness diagram** — orchestration shapes (model ↔ persistent kernel ↔ sub-agents ↔ continual harness)
- **Pi agent harness analysis** — `../agent-os/PI_AGENT_HARNESS_ANALYSIS.md` (earendil-works/pi): thin loop, tiny tools, durable sessions, extensions
- Prime Agent runtime (clone) — harness kinds: prompt / memory / skill / subagent

This document freezes **architecture decisions**. It is not a vendor port of Pi or Prime Intellect.

---

## 1. Thesis

```
Flutter notebook (cells, bars, Ctrl+K)
        │
        ▼
Agent loop library (thin, evented, multi-provider)
        │  tools: minimal, guest-first
        ▼
AgentOS guest  ←── single machine timeline
        │
        ├── shell / VT cell (same guest)
        ├── skills, memory, harness files (continual state)
        └── sub-agents as jobs on same guest (or forked snapshot)
```

| Principle | Meaning |
|-----------|---------|
| **Guest is the REPL** | AgentOS is the persistent programmable computer. Do **not** invent a host IPython (or second host runtime) as the product core. |
| **Notebook is the trajectory view** | Cells/blocks are how humans see turns. The machine is not N chat sandboxes. |
| **One timeline by default** | Terminal cells, agent shell blocks, and sub-agent work share **one** guest unless the user **forks** via control plane. |
| **Harness state survives turns** | Prompt notes, memory, skills, subagent specs live outside a single model context window. |
| **Thin default tools** | Always-on tool schemas stay small; power is optional and capability-gated. |

---

## 2. Lessons from the Prime Intellect harness diagram

The diagram describes one turn, repeated each session:

- **TASK** → **MODEL** (writes code / reads results)
- **IPYTHON KERNEL** (persistent REPL: skills, tools, `rlm`)
- **`rlm`** → **SUB-AGENTS** (parallel / background / persistent)
- **CONTINUAL HARNESS** (reads trajectory, writes harness state: refine, prompt, memory, skill, subagent)

### 2.1 Map to this product

| Diagram box | PI meaning | This product |
|-------------|------------|--------------|
| **TASK** | User / prior turn | NL cell submit (later: tasks derived from terminal context) |
| **MODEL** | Frontier LLM | Host-side agent loop (not inside Ghostty) |
| **IPYTHON KERNEL** | Persistent Python REPL | **One AgentOS guest** — shell, VFS, mounts, tools, guest languages/services |
| **rlm** | Recursion into sub-agents | Spawn child agent work that still targets the **same** guest (or a **forked** guest) |
| **SUB-AGENTS · parallel** | `asyncio.gather`-style fan-out | Concurrent tool/shell work on the shared guest; results fold into parent turn blocks |
| **SUB-AGENTS · background** | `create_task` | Long work that does not block the next NL cell; visible as blocks / control-plane status |
| **SUB-AGENTS · persistent** | Named, message later | Named long-lived agent specs + handles; still bound to a guest (or fork) |
| **CONTINUAL HARNESS** | Cross-turn state | Durable harness store (§4); optional background **refine** over trajectory |
| **trajectory ↔ harness** | Bidirectional | Notebook cells = trajectory view; refine/tools write harness state |

### 2.2 What we adopt

1. **Turn vs continual state** — each NL turn produces cell blocks; harness state (memory, skills, subagent specs, prompt notes) persists across turns.
2. **Sub-agent modes** — parallel, background, and persistent are first-class **execution modes**, not extra full-bleed terminals by default.
3. **Results fold back** — sub-agent output appears as blocks on the **single machine timeline** (or on an explicitly forked machine’s notebook).
4. **Background refine** — design room for a later `refine`-class pass: read trajectory, update memory/skills, compact context (not required for P0).

### 2.3 What we reject

| Pattern | Why |
|---------|-----|
| Host IPython as product soul | Duplicates AgentOS; fights dual-host architecture |
| Code-only agent (must write host Python for every act) | Default cell is terminal + NL; guest shell is native |
| Each sub-agent gets a private FS/REPL by default | Breaks single machine timeline |
| Harness only as host JSON with no guest link | Snapshot/restore desyncs “agent brain” from machine |

### 2.4 Isolation when needed

Isolation is a **control-plane** act:

- **Snapshot / fork** the guest (Ctrl+K)
- Attach a sub-agent or notebook view to the fork
- Do not silently create N independent PTYs that pretend to be one machine

---

## 3. Lessons from Pi harness analysis

Source: `../agent-os/PI_AGENT_HARNESS_ANALYSIS.md` (Pi / earendil-works — thin coding-agent harness). Use **boundaries and discipline**, not Pi’s host-FS product identity.

### 3.1 Architecture (high priority)

| Pi lesson | Apply here |
|-----------|------------|
| Split **transport / loop / product** | LLM provider ≠ agent loop ≠ Flutter notebook ≠ AgentOS host FFI |
| Minimize always-on tool schemas | Default guest-first tools; optional tools must not tax every turn |
| Durable, inspectable sessions before multi-agent theater | Persist timeline + harness before multi-session dashboards |
| Extension points strong enough that core stays thin | Skills/tools/prompts as data (guest packages / host plugins), not a new screen per feature |
| Multiple frontends on one core | One agent session core; Flutter is the primary frontend today |
| Honest security model | **AgentOS caps, mounts, snapshots** are the sandbox story; UI confirms map to real authority |
| Avoid dual live architectures without a banner | One production agent loop path — no silent “demo loop” vs “real loop” |

### 3.2 Product UX (medium)

| Idea | Notebook / app |
|------|----------------|
| Tiny default surface | Terminal-first empty state; no wall of agent chrome |
| Skills progressive disclosure | Metadata cheap; full body on demand |
| Branchable sessions | Align with snapshot/fork; session tree later |
| Mid-turn steering | Queue / interject / cancel ladder (see UI North Star Esc rules) |
| Embeddable loop | Agent runtime is a library behind the notebook, not “Flutter *is* the agent” |

### 3.3 Explicitly not Pi’s defaults

| Pi | This product |
|----|--------------|
| Runs as user process on host FS | Guest is sandboxed AgentOS machine |
| Default tools on host files | Tools prefer **guest** FS/shell |
| TUI coding-agent product | Machine notebook + Ghostty + control plane |
| Arbitrary host TS extensions as main growth | Prefer guest packages + clear host plugin trust |

---

## 4. Continual harness state

Minimal kinds (aligned with Prime Agent `HarnessKind`, names can evolve):

| Kind | Role |
|------|------|
| **prompt** | Standing instructions / prompt notes for the agent |
| **memory** | Durable facts the agent should keep |
| **skill** | On-demand procedures (progressive disclosure) |
| **subagent** | Specs for how to spawn workers (parallel / bg / persistent) |

### 4.1 Storage preference

1. **Prefer guest FS** (and thus snapshots) for harness material the machine should carry across restore.
2. **Host session store** may mirror for UI speed and when the guest is down.
3. **Never** let host-only harness be the sole copy of critical machine-bound memory if restore is a product feature.

### 4.2 Who writes harness state

- Agent tools during a turn  
- Explicit user edits (future settings / control-plane)  
- Background **refine** over trajectory (later phase)

### 4.3 Trajectory

- Notebook cells + agent blocks = human-visible trajectory  
- Compaction may summarize old cells without deleting harness memory  
- Refine reads trajectory and **writes harness**, not only chat text

---

## 5. Multi-agent on AgentOS

### 5.1 Modes

| Mode | Behavior | UI |
|------|----------|-----|
| **Parallel** | Concurrent tool/shell invocations on the **same** guest | Sibling blocks under one parent turn; clear completion aggregation |
| **Background** | Work continues after the parent turn idles | Block or status chip; bottom bar / control plane can surface “still running” |
| **Persistent** | Named agent; message later | Spec in harness; activity on timeline when messaged |

### 5.2 Rules

1. Default world = **one guest** (north star).  
2. Sub-agents do not get a silent private machine.  
3. Need isolation → **fork/snapshot** via control plane, then bind work to that guest id.  
4. Shell blocks from any agent write the guest they are bound to — no split brain within a binding.  
5. Permissions / destructive host ops still use parking cards and AgentOS caps.

### 5.3 Tool surface (default tax)

Keep the **always-on** tool set small, for example:

- Guest shell / exec  
- Guest read (and limited write)  
- Optional: guest search  

Everything else (web, heavy MCP, niche tools) is **optional** and must not bloat every turn’s schema. Align with AgentOS capability bits and mounts.

---

## 6. Layer split (implementation law)

| Layer | Owns | Must not own |
|-------|------|----------------|
| **LLM transport** | Providers, streaming, auth | Tools, VT, AgentOS FFI |
| **Agent loop** | Turn state, tool batching, stop conditions, hooks | Flutter widgets, Ghostty paint |
| **Harness store** | prompt/memory/skill/subagent records | Model HTTP |
| **Notebook UI** | Cells, bars, focus, Shift+Tab, block layout | Provider SDKs |
| **Control plane UI** | Ctrl+K, machine mutations | Agent sampling |
| **AgentOS host** | Kernel, guest, caps, snapshots, mounts | Chat markdown chrome |
| **libghostty-vt** | Live terminal cell encode/parse/paint | Agent tools |

Dependency direction: UI → loop/harness → AgentOS; VT is sibling under UI for terminal cells only.

---

## 7. Relation to three entry paths

| Path | Role relative to agent spine |
|------|------------------------------|
| **Terminal cell** | Human drives the guest directly; trajectory may still record freezes |
| **Shift+Tab NL** | Enters the agent loop; tools hit the same guest; blocks stack on timeline |
| **Ctrl+K** | Reshapes guest (image, mounts, snapshot/fork) that **all** agents and the shell share |

Agents never replace control plane for snapshot/restore/fork. Control plane never replaces the agent loop for NL reasoning.

---

## 8. Phases

| Phase | Ship |
|-------|------|
| **A0** | Layer split documented; no dual loops. NL can stub. |
| **A1** | Real agent loop + minimal guest tools; multi-block turn UI |
| **A2** | Harness kinds on disk (guest and/or host mirror); skills disclosure |
| **A3** | Parallel + background sub-agents on same guest; timeline blocks |
| **A4** | Persistent named agents; fork-bound isolation via control plane |
| **A5** | Background refine / compaction over trajectory |

Do not build A3–A5 dashboards before A1 sessions are durable and inspectable.

---

## 9. Checklist

- [ ] Guest is the execution kernel — no host IPython product core  
- [ ] Single machine timeline unless user forks via control plane  
- [ ] LLM / loop / UI / AgentOS / VT boundaries respected  
- [ ] Default tool surface small; guest-first  
- [ ] Harness kinds: prompt, memory, skill, subagent (or equivalent)  
- [ ] Sub-agent modes: parallel, background, persistent — fold into timeline  
- [ ] Destructive / machine reshape stays on Ctrl+K + cards  
- [ ] One production agent loop path  

---

## 10. Open decisions

- Exact tool schema v1 and which live in-guest vs host bridge  
- Harness file layout on guest vs host mirror format  
- Whether refine is user-visible or silent  
- Sub-agent identity in the top status bar  
- Multi-window: one guest per window vs multiple guests later  

---

*Alpha: replace harness kind names and tool lists when AgentOS or agent runtime pins change. Keep guest-as-REPL and single-timeline defaults.*
