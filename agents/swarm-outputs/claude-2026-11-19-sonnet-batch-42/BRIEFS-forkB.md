# BRIEFS — fork B (nebula-gyroid, bioluminescent-bloom)

## nebula-gyroid (first pass; no Ideas:/Upgraded: lines)
HEAD reality (read + render): NOT a raymarch. It is a 5-layer recursive zoom of `readTexture` around the cursor, noise flow-warp per layer, depth-weighted average, R/B chromatic split by depth, depth-edge glow, fog to navy, `applyGenerativePrimaryControls`. Description ("raymarched gyroid SDFs") is false; identity kept = the layered zoom nebula. No gyroid anywhere.
HEAD render 192 default 0.5,0.7,0.3,0.5: idle meanL 0.266 stdL 0.120 meanA 0.554; held+audio meanL 0.245. Image visible through zoom layers, fine.
Defects found by reading:
- R1 `chroma = extraBuffer[0]` = **bass** (audioDepth.ts layout), used as a UV offset × depth: idle → 0 (split dead, the 0.02 fallback never used), loud → up to 0.8 UV shift. Rescue: `chroma = 0.006 + bass*0.014`.
- R2 `clickIntensity = extraBuffer[10]` = an FFT bin, not a click; vortex therefore idle-dead. Rescue: vortex from bass (plasmaBuffer[0].x) + age-windowed ripple scan (`ripples[i].z`, no `.w`).
- Features claim audio-reactive; HEAD reads no plasmaBuffer. Fixed by R1/R2 + Idea 1.
§12.1: (1) what moves = layer zoom phase, noise flow; (2) what's flat = layers are identical copies of the image — no "gyroid", no depth colour; (3) cursor = zoom centre; (6) deletion test applied to each idea below.
Ideas (2):
1. **Gyroid veil warp** (native) — each zoom layer's flow offset is the gradient of a gyroid field g(x,y,z)=sin x cos y+sin y cos z+sin z cos x with z = layer depth + time; thin-sheet |g|<ε glows as nebula filaments; bass thickens the sheets. Makes the name true without a raymarch.
2. **Depth-strata nebula tint** (native) — each layer is tinted along a hot-core→cold-rim nebula ramp by its layer depth before averaging, so the zoom tunnel reads as receding gas strata instead of grey copies.
Over-relaxed sphere tracing (pre-assigned) does not apply: there is no march. Not used.

## bioluminescent-bloom (first-pass Ideas; older `Upgraded: 2026-07-26 (batch 16)`)
HEAD reality: **does not compile** — `__finalRGB` (identifier starting with `__`) and `let aspect` redeclared in the same scope. Draws nothing at HEAD.
With a compile-only fix (scratch): idle meanL 0.081 meanA 0.002 — colony dead (Gray-Scott v starts at 0 and nothing seeds it without treble>0.75), only dotted tendril nodes + full-frame clock rings; audio 0.8/0.5/0.9 → meanL 0.88, frame saturated cyan-white (treble flash seeds 25 % hash noise into v everywhere).
Defects:
- R1 compile (`__finalRGB`, `aspect` redeclare).
- R2 colony never seeds idle → seed v.
- R3 treble flash = whole-frame noise → sparse spore cells.
- R4 `plasmaBuffer[(ti%8)+1]` out of range → per-tendril band from bass/mid/treble mix.
- R5 `dataTextureC` sampled with filtering sampler → exact `textureLoad`.
- extraBuffer[133..137] spring never persists (re-uploaded 0) → acts as a snap; left as-is, noted.
Ideas (3):
1. **Tendril spore shedding** (native) — glowing tendril nodes deposit v (spores) into the Gray-Scott field, so the colony grows out of the tendrils (also the R2 seed path).
2. **Photophore halos** (Soft inverse-square bloom, §12.2) — tendril nodes get a 1/(1+(d/r)²) halo instead of only a hard smoothstep dot; Glow Radius scales r.
3. **Quorum front rim** (native) — |∇v| from the four neighbour loads lights the advancing colony front in a hotter teal-violet rim.
