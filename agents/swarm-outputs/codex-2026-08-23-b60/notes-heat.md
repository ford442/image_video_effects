# Batch 60 notes — heat-haze + heat-haze-mirage

**Branch:** `upgrade/batch-60-heat-echo-elastic`  
**Date:** 2026-08-23

## Line counts

| Shader | Before | After |
|--------|--------|-------|
| `public/shaders/heat-haze.wgsl` | 144 | 160 |
| `public/shaders/heat-haze-mirage.wgsl` | 240 | 209 |

(Mirage shrank by consolidating header comments while deepening visuals.)

## A packing

| Shader | A packing |
|--------|-----------|
| **heat-haze** | `dataTextureA` mirrors **display RGBA** (post-ACES). Simulation heat lives only in `writeDepthTexture` (r32float). B unused. No `extraBuffer` writes. |
| **heat-haze-mirage** | `dataTextureA` stores **temporal haze accumulation** `RGBA` (`col.rgb` + source `a`), resurfaced via exact `textureLoad(dataTextureC)`. B writes diagnostics `(heatDisp.xy, heatFactor, bass)`. Spring owns `[133..137]` from pixel `(0,0)` only. |

## Key visual changes

### heat-haze (#521)
- Dual-octave convection columns (stronger sway / rise).
- Hotter upward runners (`pow` 16, faster phase).
- Stronger Schlieren CA (`caSpread` ~0.095 × heat).
- Held nozzle: wider radius (0.085) + denser gain (×1.85).
- Per-band FFT shimmer from `plasmaBuffer[1..8]`.
- Warm amber/ember tint; ACES on display; semantic alpha.
- Click loop capped `min(u32(u.config.y), 50u)`.

### heat-haze-mirage (#522)
- Stronger false-water TIR fold (higher mix, lower critical when held).
- Amber caustic runners through the hot layer.
- Held press: wider nozzle, stronger `dn/dy`, earlier inversion.
- Spring ownership `[133..137]` unchanged; C still exact `textureLoad`.
- Depth: exact `textureLoad(readDepthTexture, coord)` + mirage relief (no heat-column clobber).
- ACES + semantic alpha retained/tuned.

## Contract risks
- **None known.** Params ids/defaults/ranges preserved. No illegal `extraBuffer[0..132]` writes. Heat-haze keeps depth ownership for heat; mirage keeps spring + A temporal ownership.
- Structural only on Cloud VM (no GPU); visual QA needs real GPU.
