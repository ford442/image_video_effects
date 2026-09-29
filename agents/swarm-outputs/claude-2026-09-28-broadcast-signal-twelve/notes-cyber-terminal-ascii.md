# cyber-terminal-ascii — implementer notes (2026-09-28)

Files: `public/shaders/cyber-terminal-ascii.wgsl`, `shader_definitions/retro-glitch/cyber-terminal-ascii.json` (Idea Card #11).

## Kept verbatim
The 9 SDF glyphs (`getCharacter`), luma → glyph index (`pow(luma,1.2)*8`), density `mix(10,200,p)`, aspect grid, scroll rate `0.08 + bass*0.12 + mids*0.05`, lens with held widen (`*1.35`), lens packet-loss blink (`rand > 0.95 - treble*0.05`), click burst (capped loop, `age = time - z`), phosphor/colour mix, HEAD's 3-column blinking cursor, radial vignette, scanline, `0.08*charMask` C blend, slider roles (x density, y colour mode, z glow, w decoder radius).

## A packing
`A.rgb` = pre-ACES linear display RGB (clamped `[0,8]`), `A.a` = glyph coverage alpha. C read back as colour at lines 196-198: HEAD's soft blend inside the glyph plus `max(out, prev*(0.35,0.5,0.38))` after-image. ACES only on `writeTexture` (line 214).

## Ideas (line ranges)
1. **Hex-dump decode** — font + lookup lines 67-93 (`hexGlyph`: 16 u32 constants, 6 rows × 4 bits, `hexDumpCell` splits the cell into two halves for high/low nibble of `i32(luma*255+0.5)`), used inside the lens at lines 154-157. HEAD's random 0/1 `getBinaryChar` is replaced; the packet-loss blink is kept.
2. **Typewriter row entry** — lines 162-173 (+ block cursor colour at line 185). The row with `cellId.y >= bottomRow` (the one sliding in at the bottom edge) shows only columns `< scroll*(1.3 + bass*2)*cols`; a blinking block cursor sits at the typing position. Bass raises the rate so the line lands early on a beat.
3. **Bit-error flicker** — lines 136-146 (per-frame hash `< treble²*0.12 + 0.002` flips the glyph index ±1) and line 182-183 (flipped glyphs flash 2.5×); the after-image at line 198 lets the wrong glyph linger green for ~3 frames.

## Floor fixes
- Scroll units: `cellCenter = (cellId + 0.5 - (0, scroll)) / gridDims` (line 126). HEAD subtracted `scroll` in whole-screen UV units, so the sampled image and the lens drifted a full screen per cycle.
- Decoder radius double mapping: `decoderRadius = clamp(p, 0.05, 0.4) * (0.155/0.3)` (line 118). HEAD's `mix(0.05, 0.4, 0.3)` gave 0.155 at the default; this single linear mapping reproduces exactly that at p=0.3 and stays monotonic over the saved range (0.026 .. 0.207).
- Spring removed: `mouse = zoom_config.yz` (line 107); no extraBuffer access.
- Pre-ACES in A; ACES on display only. Scanline moved to integer `coord.y*0.5` (same frequency as HEAD's `uv.y*res.y*0.5`).
- `pow` base guarded (`max(luma, 0)`).

## Deviations from the card / task
- The task brief quoted HEAD's effective default radius as "~0.1275"; I could not derive that number. HEAD computes `mix(0.05, 0.4, 0.3) = 0.155`, so 0.155 is what the new mapping reproduces. If 0.1275 was the intended target, change the constant on line 118 to `0.1275/0.3`.
- Typewriter progress is a function of `scroll` (no persistent state exists), so bass changes the rate instantaneously rather than accumulating.

## JSON
`params` byte-exact (python diff vs HEAD: True). `updatedParams` unchanged (already aligned). Description rewritten to name the ideas. Features: `click-ripples` → `click-reactive`, `spring-cursor` removed; `mouse-driven`, `audio-reactive`, `held-drag`, `aces-tone-map`, `temporal-feedback`, `upgraded-rgba` kept.

## Gates
- `wgsl_precommit_gate.py --files public/shaders/cyber-terminal-ascii.wgsl`: naga OK, bindgroup compatible, 0 extraBuffer violations.
- `audit_extrabuffer.py`: PASS. `audit_dead_sliders.py --files cyber-terminal-ascii`: PASS (0 dead).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- The 4×6 font is nearest-sampled inside a half-cell; at default density (105 rows) each glyph is ~5×7 px at 1080p and will be blocky/aliased at lower resolutions. Increase `density` minimum or add bilinear smoothing if illegible.
- The generic `max(out, prev*0.5)` after-image applies to all glyphs, so moving video content also gets a short green tail — intended as phosphor persistence but untested.
- Bottom-row typing uses `bottomRow = floor(((res.y-0.5)/res.y)*gridDims.y + scroll)`; at scroll≈0 the entering row is the partially visible one, which is the intent, but the row above it does not retype.
