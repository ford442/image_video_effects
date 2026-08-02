# Physics Lab

Tier C **multipass graph** flagships — living sims that feel psychedelic, beautiful, and strange (see [`notes/CREATIVE_VISION.md`](../notes/CREATIVE_VISION.md)). Prefer polishing these stacks over shipping dozens of new single-pass generatives.

Canonical graph docs: [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md).

## Flagships

| Id | Passes | Fit | Interaction |
|----|--------|-----|-------------|
| `ripple-tank` | 7 (step×4 → inject → gather → render) | **balanced+** (battery truncates) | Click rings · hold oscillator · audio rain |
| `fabric-of-reality` | 7 (verlet → constraint×4 → tear → render) | **balanced+** | Hold to tear · Self Heal knits · mouse spotlight |
| `photonic-caustics-graph` | 4 (emit → trace×2 → accumulate) | **battery OK** | Move light · chromatic accumulator trails |

All three require `rgba32float` (`requiresRgba32Float`). Look for the **graph · N passes** badge in Shader Browser / coordinate menu.

### Params (4 clear `zoom_params`)

**Ripple Tank:** Wave Speed · Damping · Source Strength · Boundary Reflect

**Fabric of Reality:** Stiffness · Tear Threshold · Gravity · Self Heal  
(Damping is derived from stiffness — Self Heal owns `.w` exclusively.)

**Photonic Caustics:** IOR · Light Size · Dispersion · Intensity

## Pass budget (Render Quality HUD)

`effectiveCap = min(graph.maxPassesPerFrame, performancePolicy.maxPassesPerFrame)`

| Quality | `maxPassesPerFrame` |
|---------|---------------------|
| battery | 4 |
| balanced | 8 |
| ultra | 16 |
| auto mobile / desktop | 6 / 12 |

Excess dispatches are sliced with a console warn. The Render Quality panel shows `≤N passes/frame` and a short budget hint.

## Discoverability

- **Preset pack:** [`public/presets/physics-lab.json`](../public/presets/physics-lab.json) — also mirrored into the live gallery via [`public/preset_packs.json`](../public/preset_packs.json) (Physics Lab · Ripple / Fabric / Photonic + Triptych).
- **Attract mode:** `ripple-tank` and `photonic-caustics-graph` sit in the attract pool with a **22s** dwell (vs 12s default) so sims have time to breathe.
- **Thumbnails:** entry ids under `public/thumbnails/` — regenerate on a GPU host with `npm run thumbs:generate`.

## Visual QA checklist (GPU host)

For each flagship at **balanced**, 1080p-class internal:

1. Loads without magenta/black error frames; FPS overlay stays near target (60 on discrete).
2. All four sliders visibly change the look.
3. Mouse: click/hold/move produces clear force (rings / tear / light).
4. Audio (if mic allowed): bass/mids/treble modulate rain, drape, or caustic sparkle.
5. No explode / NaN blowout after 30s of interaction (especially fabric at high gravity).
6. Battery: photonic still presents; ripple/fabric may drop iterative steps — expected.

## Precommit

```bash
python3 scripts/wgsl_precommit_gate.py
npx react-scripts test --watchAll=false --ci --testPathPattern='multipass|attractShowcase|multipassBadge'
```

## Related

- [`VJ_STUDIO.md`](VJ_STUDIO.md) — performer guide + Physics Lab section
- [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md) — schema / barriers / budgets
- No WASM graph port until Tier A decision ([GH #929](https://github.com/ford442/image_video_effects/issues/929))
