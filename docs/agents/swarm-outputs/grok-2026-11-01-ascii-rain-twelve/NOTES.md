# Notes — ASCII / glyph / digital-rain twelve (2026-11-01)

cursor/batch-29. Second pass where a file already named ideas. New ideas are additive. Saved `params` byte-exact. No new spring. No §12.2 row: each idea is a device artifact of that file (terminal cell, LCD well, Bayer tile, wiper, rain column).

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| ascii-decode | Grid Size, Decode Radius, Matrix Speed, Effect Strength; character indices 0–6; luma quantize; decodeMask; strength mix back to the photo | ACES display RGBA. C is last frame's display, used only to hold a little matrix green behind the falling head | falling column head; cell gutter; decode rim |
| ascii-flow | Intensity, Speed, Scale, Detail; hash flow; repel and held vortex; click fronts; ink-coverage ramp; coverage blend; typed-cell wake; exact C residue | ACES display RGBA. C is colour history | flow lean; upstream streak |
| ascii-glyph | Glyph Size, Brightness, Color Amount, Density Boost; bass cell size; spring lens [133..136] now written only at (0,0); click scramble; bass swap; cross-or-dot; phosphor smear; CRT scanline | ACES display RGBA | stroke weight from luma; lens bezel |
| gen-cyber-terminal | Grid Density, Glyph Sharpness, Character Brightness, Scanline Bloom; 3×5 segment font; white-hot leader; column gaps; wrap flash; CRT bulge; raw HDR history | raw HDR display RGBA in A. ACES on writeTexture only | barrel scanlines; corner misconvergence |
| matrix-curtain | Rain Speed, Column Density, Curtain Width, Phosphor Glow; column hash; gol_state; scan at fall 0.12 and ghost at 0.35; phosphor from C one pixel up; click fronts; held vortex | raw fields in A (brightness, curtainMask, glyph, alpha). ACES on writeTexture only | tail stem; curtain hem |
| pixel-rain | Rain Speed, Glitch, Density, Trail Fade; spring [133..138]; three rainLayer sheets; glyph tail; column blank; click splash; exact-C trail | ACES display RGBA | head core; sheet stagger |
| spectral-rain | Rain Density, Chromatic Strength, Trail Length, Rain Angle Scale; spring on angle and speed [133..137] now written only at (0,0); per-column FFT trail; click splash; R/G/B split | ACES display RGBA (C unread). Display write is now ACES; A matches it | streak core; column slant |
| cyber-rain | Rain Intensity, Wet Blur, Neon Bloom, Wiper Size; spring wiper [133..138]; bass envelope in A.a; vertical blur; drop and streak hashes; EMP rings; wet trail; chromatic split | pre-ACES wet-trail RGB in A.rgb, bass envelope in A.a. ACES on writeTexture only | beaded drop; wiper lip |
| cyber-rain-interactive | Rain Speed, Density, Glitch, Trail Len; fp128 phase; 8-glyph ROM; two drops per column; depth weights; head packet; EMP; spring-free pointer; dropout; exact-C smear | ACES display RGBA | head glyph flicker; far-sheet grey |
| retro-gameboy | Pixel Size, Contrast, Grid Strength, Shadow Offset; four DMG greens; depth-scaled block; chromatic taps; shadow sample; round LCD dots; mouse contrast and brightness; mid scanline | ACES display RGBA | slow rise; unlit well |
| flip-matrix | Grid Density, Effect Radius, Flip Intensity, Tile Gap; hover arrival; held drive; click wave; projected height; back-face mirror; cam notch; bevel and specular | ACES display RGBA | hinge pin; gutter shadow |
| bayer-dither-interactive | Bit Depth, Contrast, Dither Spread, Pixel Scale Max; 8×8 Bayer; IGN mix; G/B rotation; neighbour diffusion; bass palette steps; phosphor dot and scan halo | ACES display RGBA (C unread) | error coring; tile seam |

Formula use: none. No shared white-hot leader, gutter stamp, or new spring. ascii-glyph and spectral-rain already owned springs; those writes are now single-writer at (0,0). The picture still uses the value computed from last frame's buffer.

Floor: `#include "_prelude.wgsl"` on all twelve. Pasted headers migrated on ascii-decode, gen-cyber-terminal, matrix-curtain, and cyber-rain before the idea edits. 16×16. Exact C where C is read. `x-meta.upgrade.params` added for ascii-decode and cyber-rain. Saved params unchanged. ascii-decode features gained `upgraded-rgba` to match the ACES path.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on a full catalog re-scan (1337 defs, 3 known), lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
