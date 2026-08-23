# VJ Studio — Performer Guide

VJ Studio is the unified control surface for live visual performance in Pixelocity. Open **Controls** and expand **🎬 VJ Studio** at the top.

## Quick start

1. Load shaders into slots 1–6 via the slot stack below Studio.
2. Adjust parameters with on-screen sliders (touch-friendly on mobile).
3. Copy a **chain URL** to share your full stack + params with another machine.
4. Optional: map MIDI knobs to parameters (desktop + MIDI hardware).

## Studio sections

| Section | What it does |
|---------|----------------|
| **Active slots** | Jump between slots; shows shader id per slot |
| **Transitions** | Auto-transition timer or audio beat (requires AI VJ mode for some paths) |
| **MIDI & keyboard** | Map hardware CCs, notes, or keys to params and actions |
| **Audio-reactive** | Drive parameter motion from microphone / audio analysis |
| **Share & export** | Chain URL, VJ set link, JSON export/import |
| **My VJ sets** | Locally saved stacks (browser storage) |
| **VJ history** | Restore recent AI-generated stacks |

## MIDI learn (no console required)

1. Expand **VJ Studio → MIDI & keyboard** and enable MIDI.
2. On any parameter slider, click the **🎛** button next to the param name.
3. Move a knob or press a pad on your controller (or press a key for keyboard mapping).
4. Click **Confirm** when the capture appears.

Bindings persist in `localStorage` (`vj_control_bindings`).

## Share links

- **Copy chain URL** — encodes up to 6 slots with compact params (`?chain=…`). Safe to bookmark or send in chat.
- **Share VJ set link** — includes vibe metadata when available.
- **Export JSON** — full portable file including optional MIDI bindings; use **Import JSON** to restore on another machine.

## Mobile

On phones and tablets, MIDI controls are hidden. Use touch sliders and chain URLs. Keyboard learn may still work with external keyboards on some tablets.

## Tier C physics demos (Physics Lab)

Simulation category — look for the **graph · N passes** badge. Full guide: [`PHYSICS_LAB.md`](PHYSICS_LAB.md).

### Ripple Tank (`ripple-tank`, 7 passes)

- **Click** to drop expanding ring ripples
- **Hold** to drive a local oscillator
- **Audio** bass boosts sources; treble densifies ambient rain
- **4 wave steps/frame** under the pass budget — target **60 fps** on discrete GPU at **balanced**

Params: Wave Speed, Damping, Source Strength, Boundary Reflect.

### Fabric of Reality (`fabric-of-reality`, 7 passes)

- **Hold** near the cloth for a tear force; hover for a gentle push
- **Self Heal** slider reconnects torn springs when elevated
- Soft gravity + velocity clamp — drapes instead of exploding
- Bass breathes wind; mouse spotlight rides the weave

Params: Stiffness, Tear Threshold, Gravity, Self Heal.

### Photonic Caustics (`photonic-caustics-graph`, 4 passes)

- Move the mouse to steer the area light; hold raises light height
- Temporal **accumulator** leaves chromatic ribbons (visible, not a faint wash)
- `emit → trace×2 → accumulate` fits **battery** (4) and balanced alike — extra traces truncate first if over budget

Params: IOR, Light Size, Dispersion, Intensity.

### Chromatographic Fluid (`chromatographic-fluid`, 7 passes)

- **Hold** paints dye + local swirl; **move** steers the wind vane
- **Click** solvent splashes; bass gusts, mids heat, treble sparkle
- Shared velocity — R/G/B dyes separate by viscosity, not three NS solvers

Params: Viscosity Split, Wind, Temperature, Dye Inject.

### Gray-Scott Tank (`gray-scott-tank`, 6 passes)

- **Hold** paints V; **click** seeds spots; four Jacobi steps per frame at balanced
- Feed/Kill sliders map to classic Gray–Scott ranges (clamped U/V)

Params: Feed, Kill, Diffusion, Seed Strength.

### Optical Flow Dream (`optical-flow-dream`, 4 passes)

- History ring (binding 13) estimates flow; **hold** freezes the lens; **click** tears time
- Battery-friendly like photonic; decay + chroma smear along the flow

Params: Flow Scale, Decay, Chroma Smear, Dream Mix.

### Pass budget in the HUD

**Controls → Render Quality** shows `≤N passes/frame`. That is `performancePolicy.maxPassesPerFrame` (battery 4 / balanced 8 / ultra 16). Over budget, Jacobi/diffuse repeats shrink first so the color pass still runs. Prefer **balanced+** for the 6–7-pass stacks.

### Preset pack

Open **Preset Packs** in VJ Studio for **Physics Lab** solos (Ripple / Fabric / Photonic / Chroma / Gray-Scott / Dream) and the original Triptych, or load [`public/presets/physics-lab.json`](../public/presets/physics-lab.json).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MIDI devices empty | Grant browser MIDI permission; use Chrome/Edge on desktop |
| Chain link doesn't restore | Ensure shader ids exist in catalog; check URL wasn't truncated |
| Import JSON fails | File must be `.vjset.json` from Export JSON or compatible schema v1 |
| Ripple/fabric look “stuck” on battery | Raise quality to balanced — 7-pass graphs exceed the battery pass cap |
| Fabric explodes | Lower Gravity / raise Stiffness; Self Heal mid-high after tearing |

## Related

- [`PHYSICS_LAB.md`](PHYSICS_LAB.md) — flagship QA, attract dwell, thumbnails
- [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md) — Tier C graph schema
- [`WASM_SMOKE_TEST.md`](../WASM_SMOKE_TEST.md) — renderer smoke (separate from Studio)
- Live Studio tab (canvas overlay) — recording / stream bridge via `LiveStudioTab`
