# Batch Notes — sentient-singularity-ten

All target shaders in this batch now use `#include "_prelude.wgsl"` (9 migrated, 1 already migrated).
Saved `params` were preserved for all 10 matching definitions.

## Per-shader upgrade notes

- `gen-sentient-plasma-silk-nebula-forge`
  - Kept verbatim: spindle-centered plasma-silk structure and slider semantics.
  - Added: magnetized silk braid knots (`braid` modulation), forge-shell ion bloom fronts (`ionFront`).
  - A packing: ACES display RGBA.

- `gen-sentient-quantum-chrono-leviathan-moth`
  - Kept verbatim: body/wing split, frozen-time lamellae, volumetric nebula trail workflow.
  - Added: electroreceptor antenna arcs (`snout` + `arc`), trailing feather-wake vortices (`wake` + `feather`).
  - A packing: ACES display RGBA.

- `gen-sonoluminescent-chrono-geode-matrix`
  - Kept verbatim: collapse cycle, shock shell, agate strata, thin-wall translucency and feedback history.
  - Added: cavitation pearl chains (`pearls`), piezoelectric twinning glints (`twinA`/`twinB`).
  - A packing: raw HDR history RGB + semantic alpha (unchanged).

- `gen-spectral-ferrofluid`
  - Kept verbatim: dipole stack, Cotton-Mouton birefringence, meniscus mound normals, temporal field memory.
  - Added: Rosensweig crown ringlets (`crown`/`crownPhase`), Barkhausen jump flicker (`barkhausen`).
  - A packing: raw field state (unchanged).

- `gen-stable-fluids-jos-stam`
  - Kept verbatim: stable-fluids advection/projection core, vorticity confinement, buoyancy, dye injection.
  - Added: baroclinic shear jets (`baroclinic`), enstrophy-cascade shimmer (`enstrophy` from local curl).
  - A packing: raw `vel.xy`, `pressure`, `dye` (unchanged).

- `gen-stellar-acoustic-resonance-manifold`
  - Kept verbatim: repeated stellar cells, p/g-mode shell logic, compression-antinode blackbody heating.
  - Added: nodal dislocation seams (`phaseSlip`), coronal loop arc curtains (`arc` term).
  - A packing: ACES display RGBA.

- `gen-stellar-plasma-ouroboros`
  - Kept verbatim: peristaltic scale hinging, seam-light leakage, inner plasma body, Fresnel framing.
  - Added: scale-edge sputter aurora (`edgeSpark`/`sputter`), magnetotail streamer ribbons (`tail`/`streamer`).
  - A packing: ACES display RGBA.

- `gen-superfluid-quantum-foam`
  - Kept verbatim: bubble-neck coalescence, drainage/pop lifecycle, Kelvin-wave core swirl and temporal history.
  - Added: second-sound thermal fronts (`secondSound`), vortex reconnection sparks (`reconSpark`).
  - A packing: premultiplied ACES display RGBA (unchanged).

- `gen-sentient-liquid-neon-fractal-heart`
  - Kept verbatim: lub-dub beat model, systolic wavefront, oxygenation gradient, temporal plasma-flow trails.
  - Added: Purkinje conduction flashes (`branch`), diastolic refill glow wash (`refill`).
  - A packing: bounded raw HDR history + semantic coverage (unchanged).

- `gen-singularity-forge`
  - Kept verbatim: relativistic beaming/redshift, log-spiral arm structure, helical jet cadence, history trails.
  - Added: frame-drag nodal precession ripples (`ltPrecess`), photon-ring caustic scintillation (`photonRing`/`scint`).
  - A packing: raw HDR rgb + semantic alpha (unchanged).

## Validation

- Scoped naga-wasm: 10/10 valid.
- Scoped precommit gate: 10/10 pass, no pasted headers.
- `npm run audit:extrabuffer`: pass (0 new violations).
- `npm run audit:dead-sliders -- --files <10 ids>`: pass (0 new dead sliders; scanner reported 3 definitions in this mixed-schema subset).
- `node scripts/generate_shader_lists.js` + `node scripts/check_duplicates.js`: pass.
- `npm test -- --watchAll=false --ci`: pass (`134` suites passed, `1033` passed / `1034` total tests).
- `SKIP_WASM_BUILD=1 npm run build`: pass.
