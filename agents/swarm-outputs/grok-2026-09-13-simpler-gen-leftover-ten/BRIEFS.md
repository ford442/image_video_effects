# Grok-1 batch — simpler generative leftover (10) — Audit (2026-09-13)

Requested batch:

```
gen-fireworks-nocturne
gen-fireworks-ring-shell
gen-fireworks-roman-candle
gen-fireworks-smoke-bloom
gen-fireworks-strobe-shell
gen-fireworks-willow-cascade
gen-fireworks-wind-ripple
gen-fluffy-raincloud
gen-fourier-epicycles
gen-grid
```

## Pre-flight finding

Before writing any Idea Card, read all 10 headers + the executed WGSL (and JSON
tags). **The list is stale: 10/10 already carry a real, dated `Ideas:` header
and those ideas are pointable in the kernel.** Per
`docs/SHADER_UPGRADE_BATCH.md` §5.3 ("Floor present, already idea-rich → Skip.
Do not bump the `Upgraded:` date for hygiene"), **all 10 were left untouched.**
No metadata pass: JSON already has `upgraded-rgba`; packing comments already
match C reads.

Underscore-backed files (catalog IDs stay hyphenated):

- `gen-grid` → `public/shaders/gen_grid.wgsl` / `shader_definitions/generative/gen_grid.json`
- `gen-fluffy-raincloud` → `public/shaders/gen_fluffy_raincloud.wgsl` / `shader_definitions/generative/gen_fluffy_raincloud.json`

Prior owners:

| ID | Dated Ideas | Prior batch |
|---|---|---|
| `gen-fireworks-nocturne` | 2026-09-11 | fireworks leftover atmospheric six |
| `gen-fireworks-smoke-bloom` | 2026-09-11 | fireworks leftover atmospheric six |
| `gen-fireworks-wind-ripple` | 2026-09-11 | fireworks leftover atmospheric six |
| `gen-fireworks-ring-shell` | 2026-09-10 | fireworks shell taxonomy ten |
| `gen-fireworks-roman-candle` | 2026-09-10 | fireworks shell taxonomy ten |
| `gen-fireworks-strobe-shell` | 2026-09-10 | fireworks shell taxonomy ten |
| `gen-fireworks-willow-cascade` | 2026-09-10 | fireworks shell taxonomy ten |
| `gen-fluffy-raincloud` | 2026-09-06 | Grok kinetic ten B |
| `gen-fourier-epicycles` | 2026-09-06 | Grok kinetic ten A |
| `gen-grid` | 2026-09-06 | Grok kinetic ten A |

Cards below are **audit cards** (ALREADY PRESENT), not new ADD cards. No WGSL
or JSON was edited.

---

SHADER: gen-fireworks-nocturne
IDENTITY: mixed mortar field — staggered launches, bursts, crackle, lingering embers over a night sky
KEEP VERBATIM: energy / tempo / density / color-drift; 9 staggered mortars; mouse command shell
ALREADY PRESENT:
  1. muzzle flash at launchPos during early ascent
  2. even shells keep a round burst; odd shells droop
FORBID: date bump; cloning chrysanthemum/willow wholesale; new springs
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-ring-shell
IDENTITY: crisp Saturn-ring / donut halo front
KEEP VERBATIM: ringR / thick / count / colorC; ring spark loop; mouse halo
ALREADY PRESENT:
  1. Saturn tilt — inclined ellipse, not a face-on circle
  2. empty core — suppress sparks inside ringR − thick
FORBID: filling as a peony; springs; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-roman-candle
IDENTITY: fixed-tube star barrage (not an aerial shell)
KEEP VERBATIM: fireRate / starSize / tubeSpread / trailLen; tubes; held mouse + click ripples
ALREADY PRESENT:
  1. muzzle flash at the tube mouth on each shot
  2. per-tube color sequence on starCol
FORBID: turning it into an aerial shell; new springs; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-smoke-bloom
IDENTITY: FBM smoke puffs around bursts plus neighbor-feedback bloom on the bright cores
KEEP VERBATIM: smokeDensity / bloomStrength / burstEnergy / trailDecay; smokePuff; mouse smoky peony
ALREADY PRESENT:
  1. buoyancy — smoke rises as sparks fall
  2. burst-lit smoke from the local flash
FORBID: Gray-Scott; springs; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-strobe-shell
IDENTITY: multi-flash blink shell before color fall
KEEP VERBATIM: flashRate / pulsePow / afterglow / colorFlash; strobePulse; afterglow embers
ALREADY PRESENT:
  1. per-spark flash phase (many blinking stars, not one sine)
  2. true dark interval (pulse can hit 0)
FORBID: continuous peony rewrite; springs; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-willow-cascade
IDENTITY: long gravity-drooping golden/silver willow curtain
KEEP VERBATIM: trailLen / droopAmt / windAmt / warmth; willowPos; 5-sample trail; mouse willow
ALREADY PRESENT:
  1. terminal hang at strand tips
  2. leeward lean of the whole curtain from the existing wind term
FORBID: kamuro glitter; horse-tail rain; springs; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fireworks-wind-ripple
IDENTITY: wind-integrated sparks with UI ripple shock-front barrages
KEEP VERBATIM: windEnergy / rippleSensitivity / trailLength / colorDrift; sparkPosWind; click-ripple fronts
ALREADY PRESENT:
  1. altitude shear — higher sparks drift more
  2. leeward streak downwind of each spark
FORBID: new springs; cloning willow leeward wholesale; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

SHADER: gen-fluffy-raincloud (`gen_fluffy_raincloud.wgsl`)
IDENTITY: curl-noise cloud + rain sheet + Mie lining. Packing is density/vel/moisture.
KEEP VERBATIM: coverage / turbulence / rain / wind; vorticity; A = (ρ, vx, vy, moisture)
ALREADY PRESENT:
  1. anvil deck at cloud top
  2. virga — rain fading before ground
FORBID: replacing the solver with display sparkles; new extraBuffer; date bump
A PACKING: raw density, velocity.xy, moisture
ACTION: skip

---

SHADER: gen-fourier-epicycles
IDENTITY: stacked rotating wheels whose last center is a pen
KEEP VERBATIM: speed / cycle count / rim / trail params; radius∝1/n
ALREADY PRESENT:
  1. arm-segment glow hub→next
  2. pen ink into the existing C trail pack
FORBID: particle-galaxy rewrite; extraBuffer springs; date bump
A PACKING: bassEnv, trail.r, trail.g, alpha
ACTION: skip

---

SHADER: gen-grid (`gen_grid.wgsl`)
IDENTITY: domain-warped FBM lattice with chromatic line edges and recursive moiré at intersections
KEEP VERBATIM: warp / density / thickness / palette sliders; domainWarp; gridLine; existing spring well + click warp
ALREADY PRESENT:
  1. anisotropic H/V lattice from warp Jacobian
  2. intersection phosphor from exact C
FORBID: CA rewrite; extra IQ overlay; date bump
A PACKING: ACES display RGBA
ACTION: skip

---

## Not started here — real leftover simpler-generative

Scope was the 10 supplied IDs. A discovery pass over generative defs **without**
an `Ideas:` header found ~361 files. Classic math / CA / field leftovers that
are short and not ethereal-creature names (June floor often present, no Idea
Card):

- `gen-mandelbox-explorer` — boxFold + sphereFold orbit-trap slice; filtering C
- `gen-rgb-diffraction` — 6-slit grating, no ACES
- `gen-langton-ant` — 3-ant heat map; `applyGenerativePrimaryControls` overlay
- `gen-klein-bottle-walk` — parametric surface walk
- `gen-verlet-cloth-wind` — 64×64 height/vel cloth (A write only on the lattice)
- `gen-koch-snowflake-storm`
- `gen-phyllotaxis-galaxy-spiral`
- `gen-sierpinski-tetrahedron`
- `gen-magnetic-field-warp`
- `gen-newton-fractal` — June-29 feature-rich; likely metadata vs ideas

Skip for a leftover of this family: `gen-percolation-threshold` (writes
`extraBuffer[0..]` spanning labels into the engine FFT zone). Skip
`gen-belousov-zhabotinsky` / `gen-protocell-division` / `gen-hyperbolic-tree`
as already idea-rich without an `Ideas:` line (metadata-pass candidates, not
upgrades). Also still skipped globally: tropism-rich `mycelium-network`,
physarum `extraBuffer[0..]` agents, `crt-clear-zone`, liquid-small, blackbody
Phase-C.
