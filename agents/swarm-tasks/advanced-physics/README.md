# Epic: Advanced Physics & Multipass Visual Simulations

**Source plan:** [`docs/plans/PLAN-ADVANCED-EFFECTS.md`](../../docs/plans/PLAN-ADVANCED-EFFECTS.md)  
**Creative pillars:** [`notes/CREATIVE_VISION.md`](../../notes/CREATIVE_VISION.md)  
**WGSL preamble (required for every agent prompt):** [`agents/WGSL_BUILTINS_GENERATIVE.md`](../../agents/WGSL_BUILTINS_GENERATIVE.md)  
**Multipass sim contract:** [`MULTIPASS_SIM_CONTRACT.md`](./MULTIPASS_SIM_CONTRACT.md)

---

## Dependency gate

| Tier | What ships | Blocker |
|------|------------|---------|
| **A — now** | Polish existing single-pass prototypes | None |
| **B — linear multipass** | 2–4 pass chains via `multipass.passes[]` + `buildMultipassRegistry.js` | Agent follows [`MULTIPASS_SIM_CONTRACT.md`](./MULTIPASS_SIM_CONTRACT.md) |
| **C — graph runner** | In-frame ping-pong loops (Jacobi×N, cloth constraint iterations, 2M photon batches) | **Landed** — see [`docs/MULTIPASS_GRAPH.md`](../../docs/MULTIPASS_GRAPH.md) |

**Rule:** If unsure, ship Tier A or B. Never add bind groups.

---

## Priority queue

| # | Effect | Agent file | Existing prototype | Target |
|---|--------|------------|-------------------|--------|
| 1 | **2D Wave Equation (ripple tank)** | [`agent-1-ripple-tank.md`](./agent-1-ripple-tank.md) | `wave-equation` (single-pass) | 3-pass: step → inject → render |
| 2 | **Fabric of Reality** (mass-spring cloth + tear) | [`agent-2-fabric-of-reality.md`](./agent-2-fabric-of-reality.md) | — | Tier B prototype, Tier C for full solver |
| 3 | **Photonic Caustics Accumulator** | [`agent-3-photonic-caustics.md`](./agent-3-photonic-caustics.md) | `photonic-caustics` (32 photons/pass) | Multipass emit → trace → accumulate |
| 4+ | Stretch goals | [`STRETCH_GOALS.md`](./STRETCH_GOALS.md) | partial / none | chromatographic separation, Poincaré disk, Droste |

---

## Acceptance checklist (every shipped effect)

- [ ] `shader_definitions/<category>/<id>.json` + `public/shaders/<id>.wgsl` (+ pass files if multipass)
- [ ] `python3 scripts/wgsl_precommit_gate.py` + `audit_orphan_shader_defs.py` green
- [ ] Four `zoom_params` with `mapping` fields in JSON
- [ ] Intentional **mouse** (`u.zoom_config`, `u.ripples`) and/or **audio** (`plasmaBuffer`)
- [ ] `public/thumbnails/<id>.png` + one-line showcase blurb in JSON `description`

---

## Agent launch template

Paste this preamble at the top of every swarm prompt:

```text
Read agents/WGSL_BUILTINS_GENERATIVE.md — copy the 13-binding header verbatim.
Read swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md for texture packing.
Follow notes/CREATIVE_VISION.md (psychedelic + beautiful + strange).
Do not add bind groups. Run wgsl_precommit_gate.py before finishing.
```

Then attach one agent file from this folder.

---

## Scaffolding commands

```bash
# New effect (single catalog entry)
python3 scripts/new_shader.py ripple-tank-v2 --category simulation

# Multipass secondary passes (no JSON — referenced from primary)
python3 scripts/new_shader.py ripple-tank-v2-pass2 --category simulation --skip-json

# Regenerate registry + lists
node scripts/buildMultipassRegistry.js
node scripts/generate_shader_lists.js
python3 scripts/audit_orphan_shader_defs.py
```

---

## QA pipeline

```bash
python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl
python3 scripts/bindgroup_checker.py public/shaders/<id>.wgsl
python3 scripts/audit_orphan_shader_defs.py
npx react-scripts test --watchAll=false --ci
```

---

## Status (2026-07-11)

| Effect | JSON | WGSL | Multipass | Audio | Thumbnail |
|--------|------|------|-----------|-------|-----------|
| `wave-equation` | ✅ | ✅ single-pass | ⬜ Tier B spec ready | 🟡 partial | ⬜ |
| `photonic-caustics` | ✅ | ✅ single-pass | ⬜ Tier B spec ready | ⬜ | ⬜ |
| `fabric-of-reality` | ⬜ | ⬜ | ⬜ blocked Tier C | — | — |
