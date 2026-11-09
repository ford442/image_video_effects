# Fork D notes

## gen-glass-mosaic-liquid-refraction
- Ideas in diff: `// ── Idea 3: antique reams`, `// ── Idea 4: backlit window`.
- Rescues: refractOffset sampled neighbours at time 0/bass 0 vs centre at live time → non-gradient full-height offsets that clamped refraction to the frame edge (washed white panes). Now heightGrad() at live time/bass, computed once (also cheaper). causticPattern(uv*facetCount) aliased to per-pixel speckle on bass → uv*(1+facets*0.12).
- Remaining: at 160px with bass 0.8 the edge caustic `sin(edgeDist*50 + w.y*10)^8` still speckles (HEAD term, likely fine at full res) — real-GPU check.
- JSON: added mouse-driven, audio-reactive tags (both true). Params byte-exact. A packing unchanged.

## spec-cooperative-edge-linking
- Ideas in diff: `// ── Idea 4: chain terminals`, `// ── Idea 5: chain pick` (new workgroup atomic array chainPicked, reset with chainCount, written before the existing count barrier — no new barriers).
- Terminals skip tile-border pixels (else every 16px seam reads as an open end).
- Params byte-exact, A packing unchanged. No HEAD bug found.
