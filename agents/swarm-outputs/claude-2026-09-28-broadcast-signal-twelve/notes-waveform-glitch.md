# waveform-glitch — implementer notes (card #7)

Files: `public/shaders/waveform-glitch.wgsl`, `shader_definitions/retro-glitch/waveform-glitch.json`.

## Kept verbatim
UV quantisation (`signalAliasing`, `mix(200,20,z) + treble*50`), sine wobble (`waveX`/`waveY` with the same
50/40 spatial frequencies and 0.05/0.03 amplitudes), horizontal R/B split (`0.01 * vhsIntensity`), 64-step
Lissajous SDF (same freq/phase mapping from mids/bass/treble, same thickness), alternating scanlines
(`sin(uv.y*res.y*PI)*0.2+0.8`), blanking bar, C trail mix (`persistence = mix(0.15,0.55,z)`, `0.55 + bass*0.15`),
held burst (×1.3 on wave, mouse pull), capped click ripples, slider roles (x wave, y vhs, z alias rate + trail
+ block glitch, w scope brightness).

## A packing
Pre-ACES linear display RGB + semantic alpha. C is read back as that linear colour for the phosphor trail
(clamped to [0,4]). ACES only on `writeTexture`. HEAD stored ACES'd colour in A and re-tone-mapped it through the
trail; that compounding is gone.

## Ideas (WGSL line ranges)
1. **Waveform-monitor trace** — lines 146-165. Per pixel: luma of the SOURCE at `(uv.x, mouseY)` and its two
   horizontal neighbours (3 taps). Plot y = 0.90 − luma·0.80 (screen y down). Slope-aware pixel distance
   `|dy|/sqrt(1+slope²)` gives an anti-aliased line with a soft halo, plus a faint cursor-row marker so the
   operator sees which row is being scanned. Green, scaled by the w slider, treble brightens.
2. **Beam-dwell brightness** — `lissajous()` lines 42-63 returns `(glow, normalised beam speed at the nearest
   sample)`; lines 140-143 apply `dwell = clamp(0.42/(speed+0.28), 0.45, 1.5)` so slow lobes burn bright and fast
   crossings go faint. Normalised so the average brightness stays near HEAD.
3. **Block glitch** — lines 110-118. Cells are the quantisation cells (`floor(uv*sampleRate)`); a per-cell-row hash
   re-rolled 8×/s selects ~half the rows, treble (`smoothstep(0.35,0.9,treble)`) gates the shift, and the shift
   amplitude is `hash·z·0.12`. A sparse silent burst (6 % of ticks per row, 0.6 gain) keeps the slider alive
   without audio.

## Floor fixes
- Scope is aspect-corrected (line 134): `scopeP = (uv*2-1)*(aspect,1)/min(aspect,1)`; Lissajous is a true figure
  on wide canvases and fits the shorter axis.
- `plasmaBuffer[bandBin]` (bins 1..8, never written) → three-band `plasmaBuffer[0].xyz` tint bars, lines 170-173.
- `beatFreq = time*(1+bass*2)` → `time + bass*0.6` (line 121): no phase jumps on transients.
- extraBuffer spring removed; pointer = `zoom_config.yz` directly (line 85). No extraBuffer writes remain.
- Pre-ACES in A (line 185), ACES on display only (line 186). Audio clamped to [0,2].
- Alpha stays HEAD's semantic form (source alpha reduced by wobble, raised by scope glow/ripple), now including
  the waveform trace.

## Deviations from the card
- Idea 3 has a small silent burst so "Block Glitch Size" is not audio-only; the card said "treble spikes". Gated
  low (≈6 % of 1/8 s ticks per cell row, 0.6 gain) so the treble path dominates when audio is present.
- Scanlines kept as HEAD's `sin(uv.y*res.y*PI)` — at texel centres this alternates ±1 per row (it is the
  "alternating scanlines" the card lists under KEEP), not the dead constant seen in crt-scanline-damage.

## JSON
- `params` byte-exact (python diff of the parsed array and of the raw text block: identical).
- `updatedParams` already aligned with `params`; unchanged.
- `description` names the three ideas. `features`: `spring-cursor` removed (no spring), `click-ripples` →
  `click-reactive`, `upgraded-rgba` kept (ACES + ideas), `mouse-driven`/`audio-reactive`/`held-drag` true.
- Added `feedbackPacking` note (pre-ACES linear A/C).

## Gates
- `wgsl_precommit_gate.py --files public/shaders/waveform-glitch.wgsl`: naga OK, bindgroup compatible, 0
  extraBuffer violations.
- `audit_extrabuffer.py --files …`: AUDIT PASS (0 violations).
- `audit_dead_sliders.py --files waveform-glitch`: AUDIT PASS (0 new dead sliders).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- The trace samples the source with the filtering sampler at `traceRow` — if the UI reports the pointer as
  (0,0) before the first move, the trace plots the top row; harmless but worth a look.
- Trail now mixes linear (pre-ACES) history, so the default look is slightly less crushed than HEAD; the
  `clamp(…,4.0)` bounds runaway.
- Beam-dwell normalisation (0.42/(s+0.28)) was chosen analytically; if the figure reads too dim overall, raise
  the 0.42 constant.
