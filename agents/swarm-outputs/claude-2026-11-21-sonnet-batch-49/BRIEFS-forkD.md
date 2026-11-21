# BRIEFS — fork D (aerogel-smoke-hdr, atmos-fog-volumetric) — written BEFORE any WGSL edit

Baseline = migrated worktree files (copies in scratchpad `d/*_head.wgsl`). Depth convention verified from the sibling `alpha-depth-fog-volumetric.wgsl:76` (`distanceThroughFog = 1 − depth`): the app's DPT/MiDaS map is **inverse depth, 1 = near, 0 = far**.

Both files share one template (4-field Eulerian state + 6/8 slice render). The two cards below are deliberately different mechanisms: aerogel changes *what colour is lost/scattered* (spectral physics + lamp phase), fog changes *how far the ray travels and from where it is lit* (scene depth + sun direction + height). They share no formula except the HG term, applied to a point lamp (aerogel) vs a distant sun (fog) — within the ≤2-file cap.

---

## SHADER: aerogel-smoke-hdr

IDENTITY (one sentence): a drifting body of translucent silica-aerogel smoke over the photo — density that scatters blue (Rayleigh), carries warm Mie energy and a bright HDR halo, fed by the held pointer and click rings.

KEEP VERBATIM:
- State packing A/C = (ρ density, scatter energy, vel.x, vel.y); the whole update path: semi-Lagrangian advect `adv`, 4-neighbour diffusion mix 0.06/0.08/0.05, buoyancy-ish `vel += (n.x−s.x, w.x−e.x)·0.22`, white velocity jitter, brush (held pointer) and click rings injecting ρ/energy/vel, decay constants, clamps.
- 4 params and roles: `density→densityGain`, `scattering→scatter ("Blue Scatter")`, `glow→light`, `bloom→bloom`; ids/defaults/ranges byte-exact.
- Render: scene warped by `vel`, `rim = pow(clamp(|∇ρ|·7), 0.65)`, Rayleigh vector (0.18,0.62,2.4) and Mie vector (2.6,1.45,0.42), `halo` from the energy channel, ACES on writeTexture only, alpha = 1 − trans + 0.2·rim (semantic coverage).
- A = raw sim state, **not** tone-mapped; unchanged.

MECHANISM INTERROGATION (§12.1)
- T1 deepen the kernel: HEAD approximates the medium with one scalar optical depth `trans = exp(−ρ·gain)`; real Rayleigh extinction is wavelength dependent, `σ(λ) ∝ λ⁻⁴`. Next-better approximation of the same operator: per-channel Beer–Lambert with the Rayleigh ratio.
- T2 physics one step further: the first-order side-effect of Rayleigh scattering is that **transmitted** light reddens (blue is removed first) while scattered light is blue — aerogel's signature. The Mie term is strongly forward-peaked (g≈0.6), the Rayleigh term has the `(1+cos²θ)` lobe; HEAD has neither angle. A bloom that only *adds* halo doubles the exposure; the real glow is energy moved out of the core.
- T3 promote an intermediate: `rim`/`grad` and the four loaded neighbour states (`n,s,e,w`, only `.y` used for `halo`) are computed and mostly thrown away; the energy channel `.y` is already loaded at radius 1 only.
- T6 history already owned: C is read as fields (ρ, energy, vel). All three ideas are render-stage and need no new packing; the only state change is the idle source (rescue, below).

ADD (3 native ideas):
1. **Rayleigh λ⁻⁴ chromatic extinction** (§12.2F Rayleigh row) — `trans` becomes a `vec3`, `exp(−ρ·gain·σ)` with σ = normalised (650/λ)⁴ ≈ (0.41, 0.80, 1.79) mixed toward grey by the Blue Scatter slider (slider keeps its role: how blue the medium is). Dense smoke now transmits the photo orange-red and scatters blue — the aerogel look; mean σ = 1 so the overall opacity at default stays ≈ HEAD.
2. **Angular phase functions toward a lamp** (§12.2F Henyey–Greenstein term + the Rayleigh `(1+cos²θ)` lobe) — a point lamp slightly behind the smoke (slow drift) defines a per-pixel scattering angle; the existing Rayleigh blue term gets `0.75(1+cos²θ)`, the existing Mie warm term gets a forward HG (g≈0.6, normalised so isotropic = 1) and a soft inverse-square `1/(d²+r0²)`. `Light Intensity` keeps its role as the overall lamp gain. Without a direction HEAD's Mie term is uniform.
3. **Energy-conserving bloom** (§12.2F) — the existing `halo` kernel gets a second, wider ring (4 extra loads of the energy channel) and the spread energy is **subtracted** from the scatter core (`core·(1−k) + halo·k`, k from the existing `bloom` slider), so the HDR bloom redistributes light instead of doubling it.

RESCUE (not an idea): Finding 1 — HEAD is pass-through at defaults (`meanA 0.000`). Add an **idle emitter that is the brush on autopilot** (same ρ/energy/vel injection, small gain, Lissajous path, switched off while the pointer is held). Pointer/click behaviour unchanged. Finding 2 — click-ring `pow(x,2.0)` → `x*x` (latent on real GPUs, SwiftShader-silent, NOT a confirmed bug).

FORBID on this file: IQ palettes, springs/extraBuffer, new ripple shockwaves, scanline/holographic costume, any change to the sim step or constants, any new param or rewire.
A PACKING: raw sim state (ρ, energy, vel.xy) in A — unchanged; ACES on `writeTexture` only.

FORMULA ADMISSION (§12.4): Rayleigh row (family F: haze/atmosphere — aerogel *is* a Rayleigh scatterer); HG term (F; acts on the existing Mie vector); energy-conserving bloom (F; acts on the existing `halo`). All three consume quantities the file already has (ρ, energy, n/s/e/w taps, Rayleigh/Mie vectors), need no new state/binding/solver. Deletion test: removing any one leaves exactly this smoke; keeping only the idea (no scalar-ρ smoke) is not aerogel. Note: that is 3 rows, one above §12.4's "at most two"; the batch claim table (COMMON.md) assigned all three to this file and they are each one expression in the existing render tail, so it is within §2's 2–4 ideas.

---

## SHADER: atmos-fog-volumetric

IDENTITY (one sentence): a bank of fog drifting through the photo that pools at an adjustable height, can be wiped by the held pointer, is stirred by click rings, and is rendered by integrating transmittance through 8 depth slices.

KEEP VERBATIM:
- State packing A/C = (ρ fog density, vel.x, vel.y, moisture); entire update path (advect, diffuse mix `0.045+0.04·turb`, `terrain` source band, turbulence jitter, pointer clear/moisture/stir, click rings, decay, clamps).
- 4 params and roles: `density→densityGain`, `height→height` (source band position), `depth_weight→depthWeight` (optical-depth multiplier per slice), `turbulence→turb`; ids/defaults byte-exact.
- Render: scene warped by `vel`, 8-slice loop with `layer=ρ·(0.65+0.5·hash)·(1.15−z·0.5)`, `absorb=exp(−layer·gain·depthWeight·0.1)`, in-scatter accumulation, ACES on writeTexture, alpha = 1 − trans.
- A = raw sim state; unchanged.

MECHANISM INTERROGATION (§12.1)
- T1 deepen the kernel: the slice loop integrates a fixed z ∈ (0,1) path through the fog for every pixel, whatever is behind it. The real operator is Beer–Lambert along the path *to the surface*, so the integration length must be the scene distance.
- T2 physics one step further: real fog is lit by the sun and shows the HG forward-scatter glare around the sun; its density is exponentially stratified with height. HEAD's in-scatter colour is the same for every pixel (the "phase" is computed from the constant `sun.z`).
- T3 promote an intermediate: the slice depth `z` is already computed (used only for a ±25 % thinning) → compare it with scene distance; the 3-vector `sun` is already defined but only `.z` is used → use it for the per-pixel angle; the ray direction is implied by `uv`.
- T6 history already owned: C is read as fields (ρ, vel, moisture). All ideas are render-stage; no packing change.

ADD (3 native ideas):
1. **Beer–Lambert on real scene depth** (§12.2F Beer–Lambert term) — read `readDepthTexture` once (`dist = 1 − depth`, 1 = far), and let each slice contribute only if it lies *in front of* the surface (`smoothstep` window at `dist`). Near objects stay crisp, distant ones sink into the fog; the `Depth Weight` slider keeps its role as the optical-depth multiplier. With no depth map (all 0) `dist = 1` and the loop is exactly HEAD's.
2. **HG forward scatter toward a real per-pixel sun direction** (§12.2F Henyey–Greenstein term) — the per-pixel view ray `normalize(((uv.x−0.5)·aspect, 0.5−uv.y, 1))` vs the file's existing `sun` vector gives `cosθ`; a two-lobe HG (g=+0.55 forward / −0.2 back) scales the in-scatter and drives the existing warm↔cool `mix` so glare is warm and bright around the sun and cooler/dimmer away from it. The sun vector is HEAD's; only its use changes.
3. **Exponential height fog** (§12.2F/E height-density stratification) — each slice's density gets `exp(−max(rayY·z·Zmax,0)/H)` where `H` derives from the existing `height` slider: rays climbing out of the layer thin with distance, the bank hugs the ground the slider already positions. (JSON promises "height-based density mixes with Beer's Law"; HEAD only has the source band.)

RESCUE: Finding 2 — `pow(x,2.0)` → `x*x` (terrain band + click ring; latent on real GPUs). Finding 1 does not apply (ambient `terrain` source, meanA 0.038). Finding 3 — tags `depth-aware` / `beers-law` / param `depth_weight` were not backed by code; Idea 1 makes them true.

FORBID on this file: IQ palettes, spring/extraBuffer, a second sim, ripple costumes, new sliders, changing HEAD's update step, changing HEAD's colour pair (cool `(0.2,0.32,0.48)` / warm `(1.4,0.92,0.5)`) — only *where* each applies.
A PACKING: raw sim state (ρ, vel.xy, moisture) in A — unchanged; ACES on `writeTexture` only.

FORMULA ADMISSION (§12.4): Beer–Lambert term and HG term of the Fresnel/HG/Beer row (family F: volumetrics ✓), plus height stratification (the density profile of the same fog; operates on the existing `layer`). All consume `z`, `sun`, `layer`, `uv` that exist; new input is one `readDepthTexture` load (a binding the file already declares). Deletion test: removing any leaves this fog; removing the original slice integration leaves nothing → additive.

---

## Cross-file de-dup (within fork D)
HG appears on both files (cap 2 ✓): aerogel = point lamp + inverse-square + Rayleigh lobe; fog = distant sun + per-pixel ray. Beer–Lambert: fog only here (jelly is the other claimed file, in fork C). Rayleigh row, energy-conserving bloom: aerogel only. No shared spring/ripple/IQ overlay; the idle emitter exists only on aerogel.
