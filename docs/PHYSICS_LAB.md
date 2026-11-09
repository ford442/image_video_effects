# Physics Lab

Physics flagships — five texture-grid Tier C **multipass graph** simulations, the
canonical single-pass Optical Flow Dream, and the agent flagships that run on the
@group(1) sim ring (DLA Crystals, Murmuration, Photon Bins, Physarum Agents, SPH Fluid).
They should feel psychedelic, beautiful, and strange (see [`docs/CREATIVE_VISION.md`](CREATIVE_VISION.md)).

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
| `murmuration` | 3 (scatter → flock → render) | **battery OK** · balanced+ for the full 65k | Pointer is a predator · hold to stoop · bass tightens cohesion |
| `photon-bins` | 4 (march → scatter → splat → present) | **battery OK** (fits the 4-pass cap exactly) | Move the light · bass kicks the bending |
| `physarum-agents` | 3 (diffuse → agents → render) | **battery OK** | Click drops a pheromone bloom · hold to lure · bass pulses the deposit |
| `sph-fluid` | 4 (scatter → density → force → render) | **battery OK** (fits the 4-pass cap exactly, thanks to `keepsHash`) | Hold parts the fluid · click splashes · bass bursts the droplets · bright areas are obstacles |

The first six rows are texture-grid sims. Three agent rows (`murmuration`, `photon-bins`, `sph-fluid`) use the
sim ring's optional [spatial hash](BINDING_CONTRACT.md#spatial-hash-simhash-optional-binding-3): agents that
must find other agents, which a texture CA cannot do honestly. The scatter pass that builds the hash is
a counted pass (see [Pass budget](#pass-budget-render-quality-hud)). `physarum-agents` needs no neighbour
search (agents only read the trail field), so it runs on the plain v1 ring, like `dla-crystals`. All of
them are TS-renderer only: `?renderer=wasm` logs a skip and never calls `LoadShader` for them.
`murmuration` and `photon-bins` are not FP32-pinned (the trail and caustic fields tolerate half floats,
and agent state lives in a float32 buffer); `sph-fluid` is (`requiresRgba32Float`, `FP32_REQUIRED_SHADER_IDS`).

### Physics Lab set 2: physarum agents and SPH fluid (#1619)

Both are checked against a numpy model of their solver in `scripts/sim_models/` (`physarum_agents.py`,
`sph_fluid.py`). Each prints its stats and exits non-zero outside its stated tolerance; CI's Python job
runs both, and `src/renderer/webgpu/physicsLabSet2.test.ts` runs them when numpy is importable and checks
that the WGSL constants equal the model's. That validates the **CPU spec, not the WGSL**: the WGSL is
covered by `tests/physics-lab-set2.swiftshader.spec.ts` (compiles under Tint, plans the right passes,
draws, and moves between frames 5 and 30).

- **`physarum-agents`** — Jones (2010) agents, `simState[i] = (x, y, heading, alive)`, 65,536 of them. Each
  frame: the field diffuses (3×3 blur × decay), each agent senses trail + 0.6 × food (the image's red) at three
  sensors, turns (turn = 1.5 × sensor angle, Jones' reticulated regime), moves and deposits. The deposit races
  (storage textures have no atomics, WGSL has no f32 atomics), so every agent on a texel writes the same value,
  `dataC(texel) + dep`: at most one deposit per texel per frame, deterministically. The model de-duplicates
  texels to match. Sensor distance and speed scale with `s = clamp(sqrt(0.25 · W·H / agents), 1, 3)`, so the
  mesh looks the same at any working size and on any OOM rung. Model: network = giant component of the
  brightest quarter ≥ 0.80 with trail cv > 0.15, no collapse into hubs; a no-steering control must fail it.
- **`sph-fluid`** — weakly compressible SPH (Tait EOS, γ = 7, clamped ≥ 0 for the free surface; viscosity;
  XSPH; vorticity confinement; Akinci cohesion for surface tension) as zero-g droplets. One explicit step per
  frame in kernel units (h = 0.98 · min cell, dt = 1 frame, sound speed 0.6 h/frame, |v| ≤ 0.5 h/frame): no dt
  uniform, unconditionally bounded. Stride-2 records (see
  [`BINDING_CONTRACT.md`](BINDING_CONTRACT.md#stride-2-records-and-the-parked-sentinel)); 24,576 of the 32,768
  particle slots are active. Rest density is capped so a hash cell holds ≤ 8 particles at rest, half the visit
  cap of 16. Model (100-step stats): bulk |ρ − ρ₀|/ρ₀ < 2 % and max compression < 8 % at rest, particle-scale
  noise damped ≥ 80 %, a gentle strain stays under 10 %, a violent swirl stays bounded, a bright obstacle
  displaces the fluid, and an overfilled hash (occupancy ~18) trips the truncation check, which is the
  failure the visit cap causes (density underestimated, pressure blows up).
- **Known limits (decided):** statistically, not bitwise, reproducible (the `atomicExchange` link order and
  the deposit winner depend on scheduling, so golden-frame tests need tolerances). With one step per frame the
  fluid's Mach number is ~0.8: an impact at relative speed v compresses it by about v / c, so violent splashes
  compress 40–50 % (springy by construction) while rest and gentle flow stay in the few-percent WCSPH regime.
  Below 4 passes the shrinker drops the force pass first (the fluid freezes; the render still lands), and
  below 3 the physarum agents stop (the trails fade). ≥ 256k physarum agents is a contract change (ladder and
  device-policy ceiling) and out of scope here.

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

**Murmuration:** Cohesion (bass) · Alignment (mids) · Perception · Trail Length (treble)  
(Separation is fixed. Perception is the neighbour radius: small makes cliques, large makes sweeping sheets.)

**Photon Bins:** Index Contrast (bass) · Dispersion (mids) · Light Size · Persistence (treble)  
(The source image is the height field. Photons carry a wavelength bin and an energy; Dispersion splits blue from red.)

**Physarum Agents:** Sense Angle · Sense Distance · Move Speed (treble) · Trail Persistence  
(Persistence trades deposit against decay so the trail's scale stays put: low keeps only fresh trails, high lets veins thicken.)

**SPH Fluid:** Viscosity · Rest Density · Pointer Force (bass) · Obstacle Strength  
(Viscosity drives both the viscous term and XSPH. Rest Density swells or tightens the liquid, capped by hash-cell occupancy. Obstacles are the image's bright areas: a luma-gradient push plus drag.)

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
- **Attract mode:** the six texture-grid flagships plus `physarum-agents` and `sph-fluid` sit in `ATTRACT_PHYSICS_LAB_IDS` with a **22s** dwell (vs 12s default). Attract ids cannot be thumbnail-deferred.
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
npm test -- --watchAll=false --ci --testPathPattern='multipass|attractShowcase|multipassBadge|GraphRunner'
```

## Related

- [`VJ_STUDIO.md`](VJ_STUDIO.md) — performer guide + Physics Lab section
- [`MULTIPASS_GRAPH.md`](MULTIPASS_GRAPH.md) — schema / barriers / budgets
- No WASM graph port until Tier A decision ([GH #929](https://github.com/ford442/image_video_effects/issues/929))
