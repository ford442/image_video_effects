# Relay Hop 6 — Polish & Final QA (`gen-relay-psychedelia`)

## Metadata
- **Shader ID**: gen-relay-psychedelia
- **Hop**: 6
- **CHUNK**: `polish` (new — see below)
- **Agent Role**: Finisher / QA
- **Status**: pending
- **Protocol**: [`agents/RELAY_PROTOCOL.md`](../../RELAY_PROTOCOL.md)

## Immutable Rules
1. This hop introduces a **new** `CHUNK: polish` containing one function:
   `fn applyPolish(color: vec3<f32>, p: vec2<f32>, time: f32) -> vec3<f32>`
   placed between the temporal-feedback chunk and the entry section.
2. Inserting its single call site in `main()` — between `applyTemporalFeedback`
   and `finalComposite` — is the **one sanctioned `main()` edit** of the relay
   and requires the human coordinator's sign-off on the PR. One line only:
   `color = applyPolish(color, p, time);` — nothing else in `main()` changes.
3. Do NOT modify bindings, `Uniforms`, utilities, `finalComposite`, or other CHUNKs.
4. **No `readTexture` / texture sampling** — the chromatic split must be computed
   on the generative color itself (offset the *field/palette phase* or split
   channels analytically), not by resampling a texture.
5. Output stays bounded pre-ACES (≤ ~4.0 per channel); `finalComposite` remains
   the sole tone-map/exposure site.
6. Run gate before marking complete:
   ```bash
   python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-relay-psychedelia.wgsl
   ```

## Task

Final glow pass + subtle chromatic character:

- **Neon glow**: port the `neonGlow(color, intensity)` pattern from
  `agents/WGSL_BUILTINS_GENERATIVE.md` *into the polish chunk* (utilities block
  is frozen — inline your own copy). Keep intensity modest (~0.3–0.6); trails
  from hop 4 already accumulate energy.
- **Chromatic split**: a small radius-dependent channel divergence — e.g. rotate
  R and B slightly around the green axis as `length(p)` grows, or phase-offset
  the channels by a few degrees of hue near the edges. Should read as lens
  character, not glitch.
- Optional vignette (multiplicative, ≥ 0.75 at corners) to seat the mandala.

## Final QA checklist (this hop owns sign-off)

- [ ] Gate passes: naga OK, bindgroup compatible
- [ ] 60 s soak: feedback stable, no white-out, no gray mud
- [ ] All four sliders (Warp Depth / Saturation / Hue Shift / Trail Echo)
      produce visible, monotonic response
- [ ] Mouse press bias (hop 1) still works
- [ ] Defaults render coherent mandala; extremes go beautifully strange
- [ ] `node scripts/generate_shader_lists.js` re-run if catalog metadata changed

## On completion

1. Add comment: `// OWNER: <agent> <date>`
2. Set `relay-queue.json` hop 6 `status` → `completed` — relay finished
3. Note any deferred ideas in the queue `notes` field for a future relay
