# Coordinator review: Densest Multi-System Nine (2026-09-27)

Checked against the §9 checklist in docs/SHADER_UPGRADE_BATCH.md. All nine pass on structure. Visual QA has to happen outside this VM, because there is no GPU here.
gen-chronos-biomechanical-void-leviathan is out of scope: its Ideas are from 2026-09-15 and are implemented in swimDistortion and map_wake_glow.

| Shader | Card | Ideas tagged | Diff | A packing | Saved params | Springs/ripples |
|---|---|---|---|---|---|---|
| abyssal-leviathan-skeleton | final | 3 | +78/-14 | HDR history, ACES on display only | byte-exact | inert HEAD kick left |
| astral-plasma-accretion-forge | final | 3 (+ full floor) | +125/-38 | ACES display (new) | byte-exact; updatedParams added | none |
| furnace-engine | final | 3 | +181/-53 | raw HDR (was ACES re-toned) | byte-exact | inert spring kept and marked |
| audiovisual-mandelbulb | final | 3 | +87/-9 | HDR pre-ACES | byte-exact | inert spring kept |
| auroral-ferrofluid-monolith | final | 3 (+ floor) | +103/-50 | ACES display (new) | byte-exact | none |
| bismuth-singularity-loom | final | 3 | +117/-31 | HDR pre-ACES | byte-exact | inert spring kept |
| chromodynamic-plasma-collider | final | 3 | +140/-20 | HDR pre-ACES | byte-exact | inert spring kept |
| cosmic-clockwork-dyson-sphere | final | 3 | +138/-26 | ACES display, blended after the tone-map | byte-exact (the dead duplicate `params` key was removed; the one JSON.parse keeps is unchanged) | none |
| 4d-projection-dream-weavers | final | 3 (+ floor) | +159/-22 | raw HDR peak-hold | byte-exact | none |

## Coordinator edits
- Stripped JSON feature tags that are not in the contract. collider: bunch-crossing-bursts, betatron-beam-steering, momentum-dispersion. bismuth: self-assembling-sectors, gravitational-time-dilation, singularity-shadow.
- mandelbulb JSON description: removed the false "spring-smoothed cursor" claim, because the spring is inert.
- bismuth: the per-sector assembly phase now blends toward the neighbouring sector's phase near each sector edge, reaching 50/50 at the boundary. Without this the per-sector stage tore the SDF at the sector seams. The camera looks down the -z axis, which is a sector boundary, so the centre-screen seam was the main case.
  - A residual seam may remain, because the twisted cube is not z-symmetric under the angular repeat. That seam is inherited from HEAD.

## Agreed deviation
- bismuth Extrusion: the card asked for the w=1, audio=0 output to reproduce HEAD. That is not possible, because HEAD renders no crystal at all at audio 0 (numpy: minimum SDF over a 121³ grid is +0.095).
  - Extrusion now has a resting term that depends on the assembly stage, and bass rides on top of it.
  - Accepted, because keeping HEAD's look would leave every geometric idea invisible.

## Default-look shifts to check on a real GPU (all from bug fixes or floor work, not reimagining)
- collider: a ringed tunnel with a beam is now visible. HEAD was a flat dark-blue screen, because solid discs were hit at step 6.
- ferrofluid-monolith: aurora appears for the first time. HEAD's fbm gate was always 0 and the march stopped at t=6.
  - Clicks no longer turn the pillar purple (the "audio" was read from config.y).
  - Output is no longer premultiplied.
- bismuth-loom: crystals are visible at audio 0, where HEAD showed only blue haze.
  - The camera moved to z=-6.2, because it used to sit inside the SDF.
  - There is a black shadow at the core.
- accretion-forge: about 38% darker in mean luma (ACES and dust absorption). The black hole now occludes only what is behind it.
- dyson-sphere: the core is no longer blown out. Previously exp() of a negative distance gave up to about 7x gain.
  - Voronoi is continuous now. HEAD added `neighbor` twice, so the noise jumped at every cell face.
  - A near-clip escape handles the roughly 6.5% of camera poses that started inside brass.
- 4d-dream-weavers: the interior is dark with filaments instead of flat cream. Crease lines show at audio 0.
- mandelbulb: diffuse lighting is about 30% darker from the new AO and shadow. Escape Radius is now the bailout and equals 2.4 at the default.
- furnace: you can see through the centre of the core. The pillar streams at audio 0. Trails are tighter because the double tone-map is gone.

## Gates (coordinator, run once over all nine)
- naga 9/9
- wgsl_precommit_gate 9/9
- dead-slider audit: every agent reported 1305 scanned, none new
- generate_shader_lists OK; check_duplicates: 1386 unique
- Jest: 741 pass, 6 fail. These are the known-bad suites on clean main (WASMBridge ×2, slotLimits, WebGPUCanvas, performanceStatus, bridgeSimRingRefusal). No new failures.
- `SKIP_WASM_BUILD=1 npm run build` green.
