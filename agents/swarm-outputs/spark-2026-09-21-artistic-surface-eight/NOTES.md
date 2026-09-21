# Artistic surface eight — NOTES

Per shader: what was kept verbatim, A packing, and where each idea is in the diff (grep `Idea N`).

| Shader | Kept verbatim | A packing | Ideas in diff |
|---|---|---|---|
| graphic-novel (`graphic_novel.wgsl`) | screens + angles, adaptive contour, registration, poster, fibres, held/click ink | ACES display RGBA | 1 `spotBlack`; 2 `hatchLines()` ×2; 3 `wideContour * shadowSide` |
| rorschach-inkblot | fold, curl advection, vortex, blooms, ink key, history, invert | ACES display + ink alpha | 1 `crease` + `foldShade`; 2 `transferSide`/`contact`; 3 `halo * fibre` |
| polka-dot-reveal | density reveal, luma radius, alpha modes, trails, chroma | R bass env, GB mouse, A alpha | 1 `chain`/`diamond`; 2 `dragAmt` stretch; floor: per-cell jitter |
| frosty-window | voro/dend/fbm, heat melt + Laplacian, full display chain | R frost, **G meltwater** (was an unread crystal copy), B caustic, A alpha | 1 `frameSeed`/`frontier`/`grows`; 2 `fromAbove` transport, melt source, `wetCol` display |
| melting-oil | Sobel of C.r, mouse bend, turbulence, stirs, step, PHI hue, alpha | **pre-sheen melt RGB** + alpha (was post-sheen display) | 1 `loadHistoryBilinear` + `hold`; 2 `sag` |
| porcelain-fracture-glow | crack network, held crack, impact stars, veins, patina, ceiling | R crack, G leak, **B crack memory** (was a copy of the Light slider), A alpha | 1 `crackMemory`/`ripeness`/`gold`; 2 `crazeEdge()`/`crazeSpread` |
| static-reveal | brush mask, tracking, h-hold, snow, chroma noise, flash | display RGB + mask alpha | 1 `partialLock`/`rollY`/`blanking`; 2 `ghost`/`ghostAmt` |
| luminance-wind | history advection, curl layers, luma gate, jet, click gusts | raw HDR + alpha | 1 `shelter`; 2 `catsPaw` |

## Floor fixes found by reading (not counted as ideas)

- **frosty-window was dead.** C is zero-initialised, and `if (frost < 0.005) return` wrote 0 back, so
  frost never appeared. Idea 1's nucleation is the fix. The dynamics were checked with a numpy port
  (`frost.py`): 85% cover at 60 frames on a 160×90 grid (slower at full res, since the front moves
  ≤1 px/frame), and a runnel forms below the cursor. C reads are now exact `textureLoad`.
- **static-reveal**: `revealThreshold = u.zoom_config.y` was mouse X. Now 0.3. C read is exact.
- **polka-dot-reveal**: jitter/cellHash hashed per pixel, not per cell as documented.
- **melting-oil**: C was read only for the gradient, so the "melt" never went further than one
  pixel. Now it accumulates (Idea 1).

## Flagged, unchanged

- polka-dot-reveal and melting-oil carry `upgraded-rgba` without ACES (pre-existing tags).
- melting-oil and porcelain-fracture-glow keep an `extraBuffer[133..137]` spring that never
  persists (the region is re-uploaded every frame). It's harmless: it degenerates to the raw
  mouse position.
- porcelain-fracture-glow uses a hue-preserving ceiling, not ACES. It's documented in the file, so
  no tag was added.
- The dead-slider audit scans 7/8: it misses graphic-novel (id ≠ filename). All four
  `zoom_params` reads in `graphic_novel.wgsl` were checked by hand and are live.

JSON: `upgraded-rgba` added to graphic-novel only (it has ACES and the card is implemented). No
`params` changed anywhere.

## Gates

precommit 8/8 (naga + bindgroup); extraBuffer PASS; dead sliders PASS (7 scanned + 1 by hand);
generate_shader_lists + check_duplicates green (1383 ids); Jest 716 passed / 6 failed, the same
known suites as earlier today (WASMBridge ×2, slotLimits contract, WebGPUCanvas,
performanceStatus); `SKIP_WASM_BUILD=1 npm run build` OK. Real-GPU visual QA: external.
