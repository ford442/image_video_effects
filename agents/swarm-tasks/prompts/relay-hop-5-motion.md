# Relay Hop 5 — Motion Modulation (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 5
- **CHUNK**: `motion-modulation`
- **Agent Role**: LFO / Audio Reactivity Specialist
- **Status**: completed (cursor-hop-5 2026-07-19)
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. Edit **only** `MotionState` and `motionModulate` inside the `CHUNK: motion-modulation` block.
2. Do NOT modify bindings, `Uniforms`, utilities, or other CHUNKs.
3. Read audio via `plasmaBuffer[0].xyz` (bass/mids/treble) — may read treble inside `motionModulate` even if `main()` only passes bass/mids.
4. Return bounded values — avoid runaway warp or exposure blowout.
5. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Upgrade spine motion to **multi-LFO audio stack** that pushes warp and palette past legibility on peaks:

| Output | Drives |
|--------|--------|
| `warpStrength` | `applyDomainWarp` |
| `timeScale` | `animTime` → field + palette + feedback |
| `pulse` | `finalComposite` exposure |
| `saturationBoost` | palette saturation multiplier |
| `hueDrift` | additive hue offset |

Goals:
- **Stacked incommensurate LFOs** (slow/mid/fast/spark) — avoid short-loop repetition
- **Bass** surges warp depth + exposure thump
- **Mids** accelerate time scale + saturation pump
- **Treble** adds hue wobble + exposure sparkle
- Visible chaos at default params with audio present; still bounded without audio

## Wiring note

`main()` applies `motion.saturationBoost` and `motion.hueDrift` to `applyPalette` args — minimal orchestration only.

## Current CHUNK (replace struct + function)

```wgsl
struct MotionState {
    warpStrength: f32,
    timeScale: f32,
    pulse: f32,
}

fn motionModulate(time: f32, bass: f32, mids: f32) -> MotionState {
    let pulse = 0.85 + 0.15 * sin(time * (1.2 + bass * 0.5));
    let warpStrength = mix(0.12, 0.38, clamp(u.zoom_params.x, 0.0, 1.0)) * pulse;
    let timeScale = 1.0 + mids * 0.15;
    return MotionState(warpStrength, timeScale, pulse);
}
```

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 5 `status` → `completed`, hop 6 → `pending`
3. Do not touch hop 6+ chunks
