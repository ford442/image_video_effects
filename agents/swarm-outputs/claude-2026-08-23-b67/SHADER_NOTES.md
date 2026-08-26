# Batch 67 shader notes — 2026-08-23 (tracker #521–530)

Ten shaders under an extra creative brief on top of the 13-binding contract:
two distinct **closed-form** fast-motion techniques per shader, vivid multi-hue
psychedelic colour, and playful high-energy personality.

## Note on the base

Four of the ten (`ferrofluid-spikes`, `glass-wipes`, `holographic-flicker`,
`liquid-jelly`) were rewritten on `main` by concurrent agents while this batch
was in flight. Rather than overwrite that work, the Batch 67 changes for those
four were **re-derived on top of main's newer versions** — so their contract
fixes are preserved and this batch adds only the creative brief (plus, in
`holographic-flicker`'s case, three real bugs main's rewrite introduced or left
behind). The remaining six are unchanged on `main` and carry the full upgrade.

## Feedback ownership (which slot carries what)

Display RGBA lives in `dataTextureA` unless the shader runs a genuine
simulation, in which case A carries state and display goes to `writeTexture`
(the Batch 58B convention). The engine copies B→C then A→C, so **A wins** and
whatever A holds is what the next frame reads back as `dataTextureC`.

| Shader | `dataTextureA` | `dataTextureB` |
|---|---|---|
| `bubble-chamber` | display RGBA | (unused) |
| `crystal-freeze` | **state** `[freeze, growthVel, burstFlash, 1]` | (unused) |
| `ferrofluid-spikes` | display RGBA (HDR, pre-tone-map) | (unused) |
| `frost-reveal` | **state** `[mask, maskVel, burstFlash, 1]` | (unused) |
| `glass-wipes` | **state** `[wetness, flow, thickness, coverage]` | (unused) |
| `heat-haze` | **state** `[heat, warp.xy, alpha]` | display RGBA |
| `holographic-flicker` | display RGBA | (unused) |
| `liquid-jelly` | display RGBA | (unused) |
| `magnetic-dipole` | **state** `[fieldDir.xy, alignment, fieldStrength]` | `[fieldAngle, fieldStrength, pulseRing, 1]` |
| `radial-blur` | display RGBA (both exit paths) | (unused) |

`heat-haze` was writing its heat field into `writeDepthTexture` — simulation
state smuggled through the depth target, so every depth-aware shader downstream
read a temperature as scene geometry. The heat sim now lives in A/C and the
depth target passes real geometry through.

`magnetic-dipole`'s A packing was `[fieldDirection.xy, fieldStrength, …]` while
the persistence term read channel `b` back as *alignment*. A is repacked so the
channel names match the reads, and B's `.r` is now the sprite angle (it was
previously reading `fieldDirection.x` as an angle).

## extraBuffer occupancy (all inside [133..138], invocation (0,0) only)

| Shader | Slots |
|---|---|
| `ferrofluid-spikes` | 133–134 magnet position, 135–136 magnet velocity, 137 last time, 138 seeded flag |
| `glass-wipes` | 133–134 wiper position, 135–136 wiper velocity, 137 last time, 138 seeded flag |
| `holographic-flicker` | 133 press state, 134 press velocity, 135–136 sprung pointer, 137–138 pointer velocity |
| `liquid-jelly` | 133–134 sprung pointer, 135–136 pointer velocity, 137 last time, 138 seeded flag |
| `radial-blur` | 133–134 smoothed pointer, 135–136 pointer velocity |

The other five derive all their motion analytically from `config.x` and the
ripple queue, so they need no persistent scalar state.

`radial-blur` previously took its pointer velocity from `u.ripples[0].zw` —
`.z` is a ripple *start time* and `.w` is padding the engine always leaves at
`0.0`, so the "velocity" was a timestamp paired with a constant zero.

## Fast-motion pairs

Every technique below is closed form in `config.x` — no frame hashes, no
per-frame accumulation that could run away, and every velocity clamped.

| Shader | Technique A | Technique B |
|---|---|---|
| `bubble-chamber` | Relativistic streak stretch: `gamma = 1/sqrt(1-beta²)` with `beta = clamp(len(v)*26, 0, 0.985)`, streak length clamped to 0.05 UV | Helical momentum spiral whose pitch keys off the track's transverse momentum |
| `crystal-freeze` | Dendrite growth fronts advancing at `frontRate = clamp(0.18 + p2*0.35 + mids*0.25, 0, 0.65)` | Facet light-burst whip triggered by click fronts |
| `ferrofluid-spikes` | Spike eruption packets: three Gaussian envelopes racing outward at `clamp(0.30 + magnet*0.55 + bass*0.45, 0, 1.4)` | Travelling field conveyor translating the whole Rosensweig lattice at a clamped rate |
| `frost-reveal` | Crystallisation wavefronts expanding from click points | Radial shatter streaks along the melt gradient |
| `glass-wipes` | Elastic wiper sweep with snap-back recoil `exp(-t*6) * sin(34t) * 0.06` | Scrolling bead lattice conveyor (the cell hash keys on position, never on time) |
| `heat-haze` | Buoyant updraft packets rising at a clamped terminal velocity | Shear-layer shimmer streaks stretched along the local warp gradient |
| `holographic-flicker` | Scan-line conveyor: hash keys on the **line index only**, travel from `sin(linePhase + t*7r) * 0.6 + sin(linePhase*2.3 - t*11r) * 0.4` | Parallax ghost whip along the sprung pointer velocity, radius clamped to 0.05 UV |
| `liquid-jelly` | Finite-speed shear wave: `c = clamp(sqrt(G)*0.16 + bass*0.10, 0.05, 0.9)`, arrival-gated by `step(0, age - r/c)` | Jiggle overshoot streaks: five taps smeared along the displacement direction, length clamped to 0.045 UV |
| `magnetic-dipole` | Field-line particle dance advecting along **B** | Pole-flip orbital whip on click |
| `radial-blur` | Zoom-burst speed lines scaled by the blur radius | Rotational shear streaks driven by the pointer spring |

## Strobe removal

`holographic-flicker` carried two sites that hashed a continuous time value:

```
hash21(vec2(glitchLine, time))                        // scanline jitter
hash21(vec2(floor(time * flickerSpeed * 30.0), uv.y)) // flicker blackout
```

Hashing time produces white noise, not motion: consecutive frames are
uncorrelated, so the eye reads a strobe rather than movement, and `floor(…)`
additionally quantises it. The replacements keep the hash for *spatial*
variation (which line) and supply all time dependence analytically:

```wgsl
let linePhase = hash21(vec2<f32>(glitchLine, 17.0)) * 6.2831853;   // line only
let travel = sin(linePhase + time * 7.0 * conveyorRate) * 0.6
           + sin(linePhase * 2.3 - time * 11.0 * conveyorRate) * 0.4;
let duty = 0.5 + 0.5 * sin(dutyPhase);
let blackout = smoothstep(0.86 - bass * 0.30, 0.98, duty) * 0.4 * (1.0 + glitchAmt);
let microGlitch = sin(time * 63.0 + uv.y * 240.0) * glitchAmt * treble * 0.02;
```

`bubble-chamber`'s `floor(time * 3.0)` spawn quantisation was removed the same
way. `glass-wipes` already had a coherent bead conveyor on `main`.

## Three further bugs in `holographic-flicker`

Found while porting, all in main's current version:

1. **The shader did not compile.** `let target = …` — `target` is a reserved
   keyword in WGSL and naga rejects it outright. Renamed to `pressTarget`.
2. **`u.config.y` used as a mouse-down flag.** `config.y` is the *ripple
   count*; the press flag is `zoom_config.w`. As written the press spring
   latched on after the first click of the session and never released.
3. **`ripples[i].z` treated as an elapsed age.** It is a *start time*; the age
   has to be derived as `time - r.z`. The loop was also a fixed `i < 5` rather
   than bounded by the live ripple count.

## Colour

Each shader uses an IQ cosine palette keyed to a physical quantity — track
momentum, freeze fraction, spike height, field strength, film thickness, gel
thickness, blur radius, heat — with prismatic dispersion sampled along the
motion direction and per-band FFT hue offsets from `plasmaBuffer[1..8].x`.

Saturation is boosted rather than averaged. The shared helper is:

```wgsl
fn vivify(c: vec3<f32>, amount: f32) -> vec3<f32> {
  let luma = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return max(vec3<f32>(0.0), mix(vec3<f32>(luma), c, 1.0 + amount));
}
```

Extrapolating *away* from luma is what keeps multi-hue mixes from collapsing to
grey, which is the usual failure mode when several palettes are summed.

## Verification

- WGSL precommit gate (naga 30.0.1 + bindgroup + workgroup + extraBuffer): 10/10
- `audit_extrabuffer.py`: 0 new violations, all writes inside `[133..138]`
- `audit_dead_sliders.py`: 0 new, 0 known (four `holographic-flicker` entries
  retired from the baseline after making the reads per-field)
- `audit_audio_mappings.py`: verified
- `audit_config_y_misuse.py`: no misuse in this cohort after the
  `holographic-flicker` fix
- Strobe grep `hash[0-9]*\(.*time|floor\(t`: only comment lines documenting the
  removed patterns
- Lists regenerated, URL and uniform checks pass; Jest and build pass

Real-GPU visual QA remains external — there is no WebGPU device in this
container, so the vividness and motion claims are verified structurally
(palette maths, clamped velocity bounds, analytic phases), not visually.
