# Physics Lab

Physics flagships — five Tier C **multipass graph** simulations plus the
canonical single-pass Optical Flow Dream. They should feel psychedelic,
beautiful, and strange (see [`notes/CREATIVE_VISION.md`](../notes/CREATIVE_VISION.md)).

Canonical graph docs: [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md).

## Flagships

| Id | Passes | Fit | Interaction |
|----|--------|-----|-------------|
| `ripple-tank` | 7 (step×4 → inject → gather → render) | **balanced+** (battery shrinks steps) | Click rings · hold oscillator · audio rain |
| `fabric-of-reality` | 7 (verlet → constraint×4 → tear → render) | **balanced+** | Hold to tear · Self Heal knits · mouse spotlight |
| `photonic-caustics-graph` | 4 (emit → trace×2 → accumulate) | **battery OK** | Move light · chromatic accumulator trails |
| `chromatographic-fluid` | 7 (force → advect → diffuse×2 → interact → phase → render) | **balanced+** | Hold paints dye · click solvent · wind vane |
| `gray-scott-tank` | 6 (gs-step×4 → inject → render) | **balanced+** | Hold paints V · click seeds |
| `optical-flow-dream` | 1 (exact-history flow + advect + grade) | **battery OK** | Hold vortex · click temporal tear |

All six are FP32-pinned by explicit flags or the narrow physics allowlist.
Optical Flow Dream uses bindings 0–12 only and has no graph badge; the other
five show **graph · N passes**. The Shader Browser **Physics Lab** chip covers
the full showcase set.

### Params (4 clear `zoom_params`)

**Ripple Tank:** Wave Speed · Damping · Source Strength · Boundary Reflect

**Fabric of Reality:** Stiffness · Tear Threshold · Gravity · Self Heal  
(Damping is derived from stiffness — Self Heal owns `.w` exclusively.)

**Photonic Caustics:** IOR · Light Size · Dispersion · Intensity

**Chromatographic Fluid:** Viscosity Split · Wind · Temperature · Dye Inject  
(Shared velocity field — not three independent Navier–Stokes solvers. R/G/B dyes diffuse at different rates.)

**Gray-Scott Tank:** Feed · Kill · Diffusion · Seed Strength  
(Sliders map into classic Gray–Scott F/K ranges.)

**Optical Flow Dream:** Flow Scale · Decay · Chroma Smear · Dream Mix

## Pass budget (Render Quality HUD)

`effectiveCap = min(graph.maxPassesPerFrame, performancePolicy.maxPassesPerFrame)`

| Quality | `maxPassesPerFrame` |
|---------|---------------------|
| battery | 4 |
| balanced | 8 |
| ultra | 16 |
| auto mobile / desktop | 6 / 12 |

Over budget, **iterative `repeat` shrinks first** so the last `color` write still lands. Dev Tools shows `truncated steps: N / requested` plus graph validation errors (not console-only).

## Discoverability

- **Preset pack:** [`public/presets/physics-lab.json`](../public/presets/physics-lab.json) — also mirrored into the live gallery via [`public/preset_packs.json`](../public/preset_packs.json) (solos + original Triptych).
- **Attract mode:** all six flagships sit in `ATTRACT_PHYSICS_LAB_IDS` with a **22s** dwell (vs 12s default).
- **Thumbnails:** entry ids under `public/thumbnails/` — regenerate on a GPU host with `npm run thumbs:generate`.

## Visual QA checklist (GPU host)

For each flagship at **balanced**, 1080p-class internal:

1. Loads without magenta/black error frames; FPS overlay stays near target (60 on discrete).
2. All four sliders visibly change the look.
3. Mouse: click/hold/move produces clear force (rings / tear / light / dye / seed / freeze).
4. Audio (if mic allowed): bass/mids/treble modulate rain, drape, caustic sparkle, wind, feed, or decay.
5. No explode / NaN blowout after 30s of interaction (especially fabric at high gravity, Gray–Scott at extreme F/K).
6. Battery: photonic still presents and optical-flow remains a full single pass;
   6–7 pass stacks drop Jacobi/diffuse iters — the image must still render.

## Precommit

```bash
python3 scripts/wgsl_precommit_gate.py
npx react-scripts test --watchAll=false --ci --testPathPattern='multipass|attractShowcase|multipassBadge|GraphRunner'
```

## Related

- [`VJ_STUDIO.md`](VJ_STUDIO.md) — performer guide + Physics Lab section
- [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md) — schema / barriers / budgets
- No WASM graph port until Tier A decision ([GH #929](https://github.com/ford442/image_video_effects/issues/929))
