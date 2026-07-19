# Relay Hop 5 — Motion Modulation (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 5
- **CHUNK**: `motion-modulation`
- **Agent Role**: Motion/Audio Specialist
- **Status**: pending
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** the `MotionState` struct and `motionModulate` inside the
   `CHUNK: motion-modulation` block.
2. Do NOT modify bindings, `Uniforms`, `main()`, utilities, or other CHUNKs.
3. `motionModulate(time: f32, bass: f32, mids: f32) -> MotionState` signature stays.
4. `main()` is frozen and consumes exactly `warpStrength`, `timeScale`, `pulse` —
   you may add fields to `MotionState` only if they are consumed by *your own*
   logic inside this chunk; unread fields are dead weight, prefer not to.
5. Output bounds (downstream chunks were tuned against these):
   - `warpStrength` ∈ [0.0, ~0.6]
   - `timeScale` ∈ [~0.5, ~2.0]
   - `pulse` ∈ [~0.6, ~1.3] (multiplies exposure — above ~1.3 risks clipping)
6. Audio: `bass`/`mids` are already read from `plasmaBuffer[0].xy` in `main()`.
   You may read further `plasmaBuffer` slots inside this chunk if needed
   (treble, energy), but clamp everything — audio data can spike.
7. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Replace the single sine pulse with **layered LFOs + audio reactivity**:

- 2–3 LFOs at incommensurate rates (e.g. 0.13 Hz, 0.047 Hz, golden-ratio
  detune) summed into `warpStrength` so motion never visibly loops.
- Slow breathing on `timeScale` (period ~20–40 s) so the whole piece
  accelerates and relaxes.
- `bass` drives transient pushes of `warpStrength` and `pulse`;
  `mids` biases `timeScale`. Smooth response beats twitchy response — this
  shader has feedback trails, spikes will smear.
- At the top of the Warp Depth slider the image is allowed to go *past
  legibility* (per CREATIVE_VISION) — but the default (~0.55) must stay coherent.

Goals:
- Motion feels organic and non-repeating over a 2-minute watch
- Audible music visibly modulates the piece without strobing
- Defaults still render the hop-4 look, just more alive

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 5 `status` → `completed`, hop 6 → `pending`
3. Do not touch the hop 6 (polish) work
