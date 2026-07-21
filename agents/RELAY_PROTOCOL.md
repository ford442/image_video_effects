# Relay Protocol — `gen-relay-psychedelia`

Multi-agent handoff protocol for building a complex psychedelic generative shader without producing mud.

**Shader:** `public/shaders/gen-relay-psychedelia.wgsl`
**Catalog:** `shader_definitions/generative/gen-relay-psychedelia.json`
**Queue:** `agents/swarm-tasks/relay-queue.json`

---

## Frozen contracts (do not duplicate — link only)

| Doc | Pins |
|-----|------|
| [`docs/BINDING_CONTRACT.md`](../docs/BINDING_CONTRACT.md) | Bindings 0–12 |
| [`agents/WGSL_BUILTINS_GENERATIVE.md`](WGSL_BUILTINS_GENERATIVE.md) | Safe builtins, palette helpers |
| [`scripts/AUTHORING.md`](../scripts/AUTHORING.md) | `wgsl_precommit_gate.py` |
| [`notes/CREATIVE_VISION.md`](../notes/CREATIVE_VISION.md) | Psychedelic + beautiful + strange |

---

## Pipeline (frozen order)

```
aspectUv → motionModulate → applyDomainWarp → applySymmetry
  → sampleField → applyPalette → applyTemporalFeedback → finalComposite → store
```

Relay agents **must not** reorder this chain or add blending outside `finalComposite` / chunk functions.

---

## CHUNK ownership

| CHUNK | Hop | Owner task | May modify |
|-------|-----|------------|------------|
| `motion-modulation` | 5 | `prompts/relay-hop-5-motion.md` | `MotionState`, `motionModulate` only |
| `domain-warp` | 1 | `prompts/relay-hop-1-domain-warp.md` | `applyDomainWarp` only |
| `symmetry-fold` | 2 | `prompts/relay-hop-2-symmetry.md` | `applySymmetry` only |
| `palette` | 3 | `prompts/relay-hop-3-palette.md` | `sampleField`, `applyPalette` only |
| `temporal-feedback` | 4 | `prompts/relay-hop-4-feedback.md` | `applyTemporalFeedback` only |
| `composite` | — | **FROZEN** | `finalComposite` — exposure tweak only with human approval |
| Utilities block | — | **FROZEN** | hash, fbm, aces, `aspectUv` |
| `main()` | — | **FROZEN** | orchestration only — no logic additions |

**Color rule:** Only `applyPalette` may assign RGB. Other chunks return `vec2<f32>` (UV/position) or modulate a passed `vec3<f32>` without introducing new hue sources.

**Output rule:** Every layer function returns bounded values. `finalComposite` is the sole ACES + exposure site.

---

## Validation gate (run between every hop)

```bash
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
```

Manual checks:
- [ ] Renders coherent warped field (not flat gray or saturated white)
- [ ] Feedback stable after ~30s (decay < 1.0)
- [ ] Mouse/time still animate
- [ ] fbm octaves ≤ 6 per call site (framerate budget)

Failed gate → **same agent retries**. Do not advance the queue.

---

## Handoff protocol

1. Read current full WGSL from `public/shaders/gen-relay-psychedelia.wgsl`
2. Edit **only** your CHUNK function(s)
3. Mark chunk header with agent id + date: `// OWNER: cursor-hop-1 2026-07-19`
4. Run validation gate
5. Update `relay-queue.json` hop `status` → `completed`
6. Next agent reads updated WGSL + their prompt file

---

## Parameters (`zoom_params`)

| Index | UI name | Role |
|-------|---------|------|
| x | Warp Depth | Domain warp strength |
| y | Saturation | Palette chroma vs luma |
| z | Hue Shift | Palette phase offset |
| w | Trail Echo | Temporal feedback mix |

---

## Regenerate catalog after edits

```bash
node scripts/generate_shader_lists.js
```
