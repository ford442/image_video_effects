# crt-scanline-damage — implementer notes (2026-09-28)

Files: `public/shaders/crt-scanline-damage.wgsl`, `shader_definitions/image/crt-scanline-damage.json`.

## Kept verbatim
Depth-scaled barrel (`distortion = 1 + d*r2 + d*0.5*r4`, `d = amount*(1+depth*0.5)`), degauss ring loop (age = time - rp.z, cap `min(u32(u.config.y), 50u)`, `ring`/`core`/`wave`, radial displacement `wave*0.004*(0.5+amount)`), horizontal RGB split `rgbSeparation*0.008*(1+bass*0.4+rippleDamage*0.8)`, triad mask on `gid.x % 3` (0.85 floor), flicker `1 + sin(t*f*10)*0.03*f`, dark-band fault (`hash11(floor(t*2)) < 0.05`, rolling band), treble snow + scar rows, degauss channel push and bruise desaturation, edge darken, phosphor decay mix constants (`mix(col, prev*0.85, 0.06+mids*0.02)` then 0.5), slider roles (x scanline, y distortion, z flicker, w rgb separation). No pointer read (HEAD never read `zoom_config`).

## A packing
Pre-ACES linear display RGB + semantic alpha in `dataTextureA`; outside the warped raster A/display are opaque black (bezel). `dataTextureC` is read exactly per texel (`textureLoad(dataTextureC, coords, 0)`, line 198) as that linear colour for phosphor persistence. ACES only on `writeTexture` (line 207).

## Ideas (line ranges in the WGSL)
1. **Misconvergence swirl** — accumulators lines 84-87, per-ripple maths lines 104-116, cap/normalise lines 119-123, application lines 130-132 (`chromaOffset` includes `misconvergence`; G is pushed the opposite way at 0.35) and line 145 (`col *= purity`). Behind each degauss front (`behind = smoothstep(0, 0.08, age*0.34 - dist)`) the R and B rasters are pulled apart along the radial by up to 0.012 uv, relaxing with `exp(-age*1.6)`. A purity blotch rotating with age (`lobe = sin(2*angle + age*3.5 + rp.x*9)`) tints the struck area magenta ↔ green; multiple rings are normalised so stacking cannot exceed one full blotch.
2. **Flyback retrace lines** — lines 167-173. Only while the dark-band fault is active (`rollTrigger`), thin bright diagonals (`fract((uv.y - 0.18*uv.x)*7 + time*4)`, width 0.06) race upward; gain 0.08 base + 0.14 near the dark band, mids lift it.
3. **Radial chromatic barrel** — lines 126-133. `radialSep = centered * r2 * rgbSeparation * 0.10 * (1 + bass*0.4)` added to the R offset and subtracted from B, so the split is HEAD's horizontal one at centre and grows radially toward the corners (≈0.006 uv at a corner at the default 0.5).

## Floor fixes
- **Real scanlines** (lines 147-151): HEAD's `sin(uv.y*res.y*π)` with `uv = gid/res` is `sin(kπ) = 0` → constant 0.5 mask. Now `0.5 + 0.5*sin(gid.y*π/2)` on integer screen rows (4-row beam profile: 0.5, 1, 0.5, 0). Mean over a period is 0.5, so the default brightness (0.925 at slider 0.8) is unchanged while the raster is actually visible.
- **Black bezel outside the warp** (lines 136-140, 194, 204): `tubeMask` from `distortedUV ∈ [0,1]` with a 1.5-px soft edge; colour is zeroed and alpha is 1 there (HEAD clamped UVs, streaking the edge texel outward).
- `dataTextureC` via exact `textureLoad` (HEAD used the filtering `u_sampler` at `gid/res`, i.e. texel corners). Depth via `textureLoad` too (line 69).
- `degaussBand` clamped to ±1.5 (line 119) so stacked clicks cannot blow the channel push out.
- ACES on display only; A stores linear (clamped to [0,4]). Alpha = source alpha (+ bruise) inside the tube, 1 outside.
- No extraBuffer access; audio only from `plasmaBuffer[0].xyz`.

## Deviations from the card
None. The card's "keep no pointer" is honoured: `zoom_config` is not read.

## JSON changes
- `params`: byte-exact (python dump diff before/after identical; `0.0` literals preserved).
- `updatedParams`: unchanged (already aligned).
- `description`: rewritten to name the three ideas and the real raster.
- `features`: dropped `mouse-driven` (no pointer at HEAD or now); kept `upgraded-rgba`, `temporal`, `glitch`, `audio-reactive`, `depth-aware`, `click-reactive`. Tags untouched.

## Gate / audits
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/crt-scanline-damage.wgsl` → PASS (naga OK, bindgroup compatible, 0 extraBuffer violations).
- `python3 scripts/audit_extrabuffer.py --files …` → AUDIT PASS.
- `python3 scripts/audit_dead_sliders.py --files crt-scanline-damage` → AUDIT PASS.

## GPU risks (not visually verified — the VM has no WebGPU)
- The bezel is new at the default distortion 0.15: the outermost few pixels at each edge go black instead of streaking. Intended per card, but it is a visible edge change.
- Scanlines are now actually visible at default (4-px period, 15 % depth × 0.8). Intended — HEAD's were dead.
- ACES brightens midtones slightly versus HEAD's raw clamp (batch-wide).
- The purity blotch uses `atan2` per ripple per pixel; with 50 live ripples that is 50 `atan2` calls — acceptable but the heaviest part of the loop.
