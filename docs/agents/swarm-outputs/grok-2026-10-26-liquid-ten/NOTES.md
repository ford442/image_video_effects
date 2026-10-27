# Upgrade Notes — Grok (`grok/liquid-ten`, 2026-10-26)

Ten liquid, vortex, and field shaders. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Seven pasted headers were migrated with `migrate_to_prelude.py` (`quantum-foam`, `ink-bleed`, `ambient-liquid`, `magnetic-interference`, `lava-lamp-blobs`, `tornado-vortex`, `gen_reaction_diffusion.wgsl`). `ink-bleed` binding 11 was renamed from `comparisonSampler` to `comparison_sampler` so the codemod could see a canonical header. That swap is not the upgrade.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 10/10, extraBuffer clean, dead sliders clean, `generate_shader_lists.js`. Vitest 169 files / 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded.

## Per shader

### quantum-foam
- Kept: foam scale / flow / diffusion / octaves, three-layer curl, Voronoi F1/F2, interference, quaternion rotate, spectral remix, anisotropic history blend, click bursts.
- Added: necked walls from the Voronoi gap; bubble memory so a bright cell center holds plasma through the existing diffusion blend.
- Formula: none. A is linear display RGBA (C is that blend). ACES is on `writeTexture` only.

### vortex
- Kept: four Lamb-Oseen vortices, confinement, inflow, local swirl, LIC streaks, Lorentzian dimple and throat darkening. Older comments still mark those as Idea 1–3.
- Added: shear-layer billows on the speed peak (`x ≈ 1.12`); a cool caustic on the dimple shoulder.
- Formula: none. A packing unchanged (ACES display RGBA).

### liquid-optimized
- Kept: analytic height and gradient, eight capillary trains, Fresnel, slant-path absorption, sheen, slider roles.
- Added: a meniscus bead on the capillary node; Marangoni crawl along the height gradient, scaled by Surface Tension and Turbidity.
- Formula: none (Fresnel and Beer-Lambert were already in the file). A packing unchanged.

### hybrid-particle-fluid
- Kept: curl advection, exact-C LIC ribbon, cosine palette, trail decay, glow radius, bass velocity tint.
- Added: each trail follows that particle's last curl step; crowded dye goes milky and more opaque. Mids now scale Flow Speed (the band was read and unused).
- Formula: none. A stays pre-ACES dye.

### ink-bleed
- Kept: fibre-frame wick, spring nib, speed-thinned deposit, click splats, fade, hue and density. A stays `(ink, 0, 0, ink)`.
- Added: wet-edge bead written back into the ink field; paper granulation on the thin wash, using the existing paper hash, display only.
- Formula: wet-edge accumulation (§12.2C); paper granulation (§12.2C).

### ambient-liquid
- Kept: curl displacement, Gray-Scott feed/kill, metaball ink, HSV shift, anisotropic spec. A stays `(U, V, inkMask, luma)`.
- Added: isotropic 9-point Laplacian, rescaled by 4 so the step matches the old cross; a depletion stain where U is spent under live V.
- Formula: isotropic 9-point Laplacian (§12.2D). Description in the JSON now says 9-point.

### magnetic-interference
- Kept: pull, swirl, domain walls, coercivity and remanence, scanlines, sparkle, `extraBuffer[133..135]`.
- Added: Barkhausen crackle only while the hysteresis switch is mid-flip; three iron-filing taps along `totalDisp`, inside the magnet radius.
- Formula: none. A packing unchanged (ACES display RGBA).

### lava-lamp-blobs
- Kept: blob field, per-blob FFT, click heat, spring pointer, saddle meniscus, cooler skin. A stays `(blobShape, blobHalo, heat, alpha)`.
- Added: convection bands scrolling with Rise Speed inside the wax; a cooled cap where the vertical field gradient says "top of the blob".
- Formula: none. ACES on display only.

### tornado-vortex
- Kept: Rankine circulation, inflow, updraft, debris, satellites, condensation wall, lightning.
- Added: fog suppressed inside the core (clear eye); mid-height core swell and updraft stall (breakdown bulb), scaled by Intensity.
- Formula: none. A packing unchanged (ACES display RGBA).

### gen-reaction-diffusion
- Kept: both models, 9-point Laplacian, gradient-stretched feed, refractory trough on the color, spiral seeds, raw A with negatives allowed.
- Added: FHN stimuli gated by the same refractory trough (Gray-Scott stays open); FHN timestep shortened on tight bends, with a faint tip highlight.
- Formula: none. The 9-point row is used on `ambient-liquid` only; this file already had the stencil.

## Formula rows

| Row | Files |
|---|---|
| Wet-edge accumulation (§12.2C) | ink-bleed |
| Paper granulation (§12.2C) | ink-bleed |
| Isotropic 9-point Laplacian (§12.2D) | ambient-liquid |

No row is on more than one file.
