# gen-chronos-labyrinth — Claude F1 Flagship Deep Upgrade (2026-06-07)

**Before:** 416 lines · **After:** 479 lines · **Net change:** +64 lines (within +30–80 mandate; 79 insertions / 15 deletions)
**Supersedes/extends:** `gen-chronos-labyrinth.claude-optimization.md` (2026-05-31 pass — MAX_STEPS reduction, soft-shadow removal, ACES swap)

## Gap Closed
Was missing: `dataTextureA` write, chromatic aberration, hue-preserve-clamp, distance LOD.
Already had: ACES, audio (bass/mid), mouse-orbit camera, IGN dither, AO, fog/atmosphere.

## Optimizations Applied

### 1. Distance-based ray-step LOD (`raymarch`, ~line 280)
`stepLOD = mix(0.8, 1.15, smoothstep(0.0, MAX_DIST * 0.6, t))` — stride relaxes from
0.8× (detail-preserving near camera) toward 1.15× past 60% of `MAX_DIST` (40 units →
relaxation begins at t≈24). Empty-space traversal toward the horizon needs fewer
iterations to resolve; residual under-stepping there is masked by fog.
**Expected gain:** background-heavy frames (looking between maze cells into the void)
should need roughly 15-20% fewer steps in the outer third of the marched volume —
a few-percent overall frame-time reduction since most pixels traverse some empty
space before a hit.

### 2. Early-exit on atmosphere-faded hits (`main`, ~line 349)
Computes `predictedAlpha = exp(-t * atm_perspective)` immediately after the raymarch
returns a hit — *before* calling `calcNormal` (6 `map()` evals), `calcAO` (5 `map()`
evals), or running the full lighting/fresnel/specular model. If `predictedAlpha < 0.02`
the pixel composites directly from the fog color; otherwise the ~11-extra-`map()`-call
lighting path runs as before.
**Expected gain:** at default Atmospheric Perspective (param4 = 0.5 → decay ≈ 0.045),
the cutoff sits near t≈87 — beyond `MAX_DIST`, so it rarely triggers. But raising the
slider toward 1.0 (decay ≈ 0.085) brings the cutoff to t≈46, which *is* reachable —
users who favor heavy atmosphere get an automatic ~11 `map()`-call discount on a
growing fraction of distant-hit pixels. The win scales with how much fog the user dials
in: "the moodier you make it, the cheaper it runs."

### 3. Temporal Rift memory / echo (multi-pass state packing)
Rifts in `map()` are gated by `rift_pulse < rift_intensity * 0.5` — they blink in and
out abruptly with no continuity. Added a slow-decaying memory:
`riftEcho = max(riftGlowNow * 0.5, prevMemory.r * 0.96)`, read from `dataTextureC`
and written to `dataTextureA.r` (alongside normalized depth, material id, alpha in
`.gba`). The echo blends a faint cyan afterglow (`echoColor * riftEcho * 0.12`) into
every frame — a rift that just vanished leaves a fading "ghost," matching the shader's
premise that these are anomalies bleeding through time rather than blinking lights.

### 4. Chromatic aberration on rift echo
`caStrength = (0.0015 + mid * 0.0025) * riftEcho` splits the echo color across R/B —
mid-band audio energy widens the split, giving rifts a glitchy, temporally-unstable
fringe that intensifies with the music. (Closes the "missing chromatic aberration" gap
flagged in the F1 brief without touching wall/floor rendering.)

### 5. huePreserveClamp before ACES
Rift cyan (`vec3(0.4, 0.9, 1.0)`) at `pulse + mid` peaks could exceed luminance 1 and
wash toward white under ACES; `huePreserveClamp(color, 2.4)` rescales by luminance
first, preserving the anomaly's color identity at its brightest.

## Visual / Transcendence Notes
- The afterimage effect is the headline change — temporal rifts now feel like wounds
  in spacetime that scar the frame rather than decorative blinking lights
- Chromatic fringe on the echo reads as a "reality glitch," reinforcing the Escher /
  impossible-geometry theme without altering the maze geometry itself

## Remaining Risks
- `riftEcho` accumulates from `riftGlowNow * 0.5` each visible frame — at very high
  Temporal Rifts param + sustained mid-energy, the echo could plateau near its `0.96`
  decay ceiling and read as constant haze rather than discrete echoes. If reported,
  expose decay rate as a param.
- Early-exit threshold (`0.02`) is conservative; could be raised to `~0.05` for more
  aggressive savings if the visual difference proves imperceptible in side-by-side tests

## Acceptance Checklist (per F1 brief)
- [x] Full upgraded-rgba stack: ACES + chromatic + temporal + dataA write + semantic alpha
- [x] Audio: `plasmaBuffer[0]` drives ≥2 params (bass→fog density/camera implicit via existing pass; mid→rift brightness + chromatic split — both new/extended here)
- [x] Mouse: `u.zoom_config.yz` drives camera orbit angle X/Y (pre-existing, preserved)
- [x] `writeDepthTexture` stores meaningful depth (raymarch hit distance / MAX_DIST)
- [x] Header `Features:` matches JSON `features` (both updated to include the 8 new tags)
- [x] naga pass + ready for `generate_shader_lists.js`
- [x] +64 lines net (within +30–80 mandate)

## JSON Changes
- Added `aces-tone-map`, `upgraded-rgba`, `depth-aware`, `temporal-feedback`,
  `chromatic-aberration`, `hue-preserve-clamp`, `ign-dither`, `distance-lod` to features
