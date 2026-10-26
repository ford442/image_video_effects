# Parallel Slot Groups - Inter-Shader Parallelization

## Overview

By default, Pixelocity's 6 shader slots (`PHYSICAL_SLOT_LIMIT`, `slot_limits.json`) run **chained** (sequentially):
- Slot 0 output → Slot 1 input → Slot 1 output → Slot 2 input → …
- This is correct for layered effects (e.g., liquid → distortion)

With **parallel slot groups**, independent effects can run concurrently on the GPU:
- Parallel slots all read from the same input texture
- The GPU driver can overlap their execution
- 20-50% FPS boost for independent overlays

## Slot Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `chained` | Output feeds next slot | Layered effects (liquid → distortion → glow) |
| `parallel` | All read from same input | Independent overlays (background + particles + UI) |

## Usage

### TypeScript API

```typescript
// Set slot 0 as chained base effect
renderer.setSlotShader(0, 'liquid-gold');
renderer.setSlotMode(0, 'chained');

// Set slots 1 & 2 as parallel overlays
renderer.setSlotShader(1, 'particle-dreams');
renderer.setSlotMode(1, 'parallel');

renderer.setSlotShader(2, 'neon-pulse');
renderer.setSlotMode(2, 'parallel');

// Check current state
const state = renderer.getSlotState(1);
// { shaderId: 'particle-dreams', enabled: true, mode: 'parallel' }
```

### React UI Integration

```tsx
function SlotControl({ slotIndex }: { slotIndex: number }) {
  const renderer = useRenderer();
  const state = renderer.getSlotState(slotIndex);
  
  return (
    <div>
      <select 
        value={state?.mode || 'chained'}
        onChange={(e) => renderer.setSlotMode(slotIndex, e.target.value as SlotMode)}
      >
        <option value="chained">⛓️ Chained (layered)</option>
        <option value="parallel">⚡ Parallel (overlay)</option>
      </select>
    </div>
  );
}
```

## Execution Order

```
Frame Render:
  ┌─────────────────────────────────────────────────────────┐
  │  1. Source Image → readTex                              │
  │                                                         │
  │  2. PARALLEL SLOTS (driver can overlap)                 │
  │     ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
  │     │  Slot 1     │  │  Slot 2     │  │  Slot 3     │  │
  │     │  (parallel) │  │  (parallel) │  │  (parallel) │  │
  │     │  readTex→   │  │  readTex→   │  │  readTex→   │  │
  │     │  writeTex   │  │  writeTex   │  │  writeTex   │  │
  │     └─────────────┘  └─────────────┘  └─────────────┘  │
  │     (Last one wins, or the layer compositor, below)     │
  │                                                         │
  │  3. Copy writeTex → readTex                             │
  │                                                         │
  │  4. CHAINED SLOTS (sequential, in order)                │
  │     Slot A (chained) → copy → Slot B (chained) → copy   │
  │                                                         │
  │  5. Blit to canvas                                      │
  └─────────────────────────────────────────────────────────┘
```

## Performance

### Expected Gains

| Scenario | Sequential | Parallel | Gain |
|----------|------------|----------|------|
| 1 background + 2 overlays | ~38ms | ~22ms | **+42%** |
| Video + 2 effects | ~52ms | ~31ms | **+40%** |
| 3 chained liquid effects | ~45ms | ~45ms | 0% (correct!) |

### When to Use Parallel

✅ **Good for parallel:**
- Background effect + mouse reactive overlay
- Base image + particle system + post-processing
- Any effects that don't depend on each other's output

❌ **Not for parallel:**
- Liquid → distortion (distortion needs liquid's output)
- Blur → edge detection (edges need blurred input)
- Any shader that modifies the image for the next shader

## GPU Profiling

Check if parallelization is working:

```typescript
// Get GPU timing data (requires timestamp-query support)
const timings = renderer.getGPUTimings();

if (timings.available) {
  console.log(`Parallel slots: ${timings.parallelTime.toFixed(2)}ms`);
  console.log(`Chained slots: ${timings.chainedTime.toFixed(2)}ms`);
  console.log(`Total GPU time: ${timings.totalTime.toFixed(2)}ms`);
  
  // If parallelTime < sum(individual times), overlap is working!
}
```

## Implementation Details

### WebGPU Command Encoder

```typescript
const encoder = device.createCommandEncoder();

// All parallel slots in same encoder (driver can overlap)
for (const slot of parallelSlots) {
  const pass = encoder.beginComputePass();
  pass.setPipeline(pipeline);
  pass.dispatchWorkgroups(...);
  pass.end();  // No barrier between parallel passes
}

// One copy after all parallel slots finish
encoder.copyTextureToTexture(writeTex, readTex, ...);

// Chained slots (must wait for copy)
for (const slot of chainedSlots) {
  const pass = encoder.beginComputePass();
  pass.setPipeline(pipeline);
  pass.dispatchWorkgroups(...);
  pass.end();
  
  encoder.copyTextureToTexture(writeTex, readTex, ...);  // Serial dependency
}

device.queue.submit([encoder.finish()]);
```

### Limitations

1. **Compositing is opt-in per slot**: with every output on *Replace* (the default) parallel slots write the same texture and the last one wins, exactly as before. Give a slot a blend mode, opacity or mask (below) and the group is composited instead.

2. **Same input**: All parallel slots read from `readTex` at the start of the parallel group
   - They don't see each other's output
   - Good for independent overlays, bad for layered effects

3. **Driver dependent**: Actual overlap depends on GPU driver scheduling
   - NVIDIA/AMD discrete GPUs: Good overlap
   - Integrated/Apple Silicon: Moderate overlap
   - Mobile: Limited by tile-based rendering

## Layer compositor (#1512)

Each slot has an **output** (`SlotOutput`, `src/renderer/slotOutput.ts`). It only matters in a parallel group:

| Field | Values | Default |
|-------|--------|---------|
| `mode` | `replace` (the layer covers what is below), `blend`, `mask` (never drawn: a matte for another slot) | `replace` |
| `blend` | `normal`, `add`, `screen`, `multiply`, `overlay`, `soft-light`, `difference`, `luma-key`, `depth-key` | `normal` |
| `opacity` | 0–1 | 1 |
| `mask` | `none`, `luma` (the layer's own luma), `depth` (the depth map), `slot<n>` (slot n's alpha; a `mask`-mode slot gives its luma × alpha) | `none` |
| `maskInvert` | boolean | false |
| `feather` | 0–1 (0–32 working-size texels of blur) | 0 |
| `keyThreshold` | 0–1, the luma-key / depth-key threshold (±0.08 smoothstep) | 0.5 |

When any slot of a group is not `replace`, the frame plan (`framePlan.ts`) adds a `layerCopy` after each slot of the group, which copies writeTex into that slot's layer of a 2D-array texture. After the group, one `composite` op runs:

1. Every mask the layers ask for is drawn into an r8unorm texture per slot (`_compositor/mask.wgsl`), with a separable blur when feathered (`feather.wgsl`).
2. **One compute pass** (`_compositor/composite.wgsl`) starts from the group's input and applies the layers in slot order. A `replace` layer overwrites; a `blend` layer mixes `blend(base, layer)` in by `opacity × mask` (× the key ramp).

Then the usual writeTex → readTex copy runs. All math is in linear light and in the internal format (rgba16float / rgba32float), so HDR values survive. Screen and soft-light keep values above 1.0 rather than clipping them. Chained slots are untouched, and an all-`replace` group compiles to exactly the old ops. The GPU side (`slotCompositor.ts` and its WGSL) is the lazy `compositor` chunk, loaded the first time a group composites, so the main bundle carries only the planner. Until the chunk arrives (a frame or two) that group renders last-one-wins. If the compositor cannot allocate (OOM scope) it reports `error` in `getCompositorStats()` and the group falls back to last-one-wins the same way.

**Where to set it:**

- **UI:** the layer strip under each slot in the slot stack panel (`SlotLayerStrip`): chained/parallel, layer mode, opacity, mask, feather, key threshold and an audio band for opacity.
- **API:** `renderer.setSlotOutput(i, patch)` / `getSlotOutput(i)` (worker: sent with the next `frameInput`), and `__pixelocity__.setSlotOutput` in test mode.
- **Automation:** opacity is a binding target (`setSlotOpacity`, MIDI / gamepad), an OSC address (`/pixelocity/slot/{n}/opacity`), and can follow an audio band.
- **Persistence:** project files v2 and chain URLs carry it (b= blend or `mask`, o= opacity, m= mask with `~` for inverted, f= feather, k= key; see [VJ_STUDIO.md](./VJ_STUDIO.md)). Device-loss recovery replays it ([RENDER_WORKER.md](./RENDER_WORKER.md#device-loss)).

The CPU reference `compositeReference.ts` mirrors the shader. The unit tests pin it, and the golden-frame suite checks the GPU against it on SwiftShader and on the GPU runner ([GPU_RUNNER.md](./GPU_RUNNER.md)).

```typescript
// Two parallel slots: plasma screened over aurora at 50 %, only where plasma is bright.
renderer.setSlotShader(0, 'gen-aurora-silk');
renderer.setSlotShader(1, 'plasma');
renderer.setSlotMode(0, 'parallel');
renderer.setSlotMode(1, 'parallel');
renderer.setSlotOutput(1, { mode: 'blend', blend: 'screen', opacity: 0.5, mask: 'luma', feather: 0.25 });
```

## Best Practices

1. **Slot 0 as chained**: Usually your base effect (liquid, distortion, etc.)
2. **Slots 1-2 as parallel**: Overlays that enhance but don't modify base
3. **Test both modes**: Some shaders may surprise you with dependencies
4. **Use GPU timings**: Verify the overlap is actually happening
5. **Fallback to chained**: If visual output differs, stick with chained

## Examples

### Liquid Background + Particles + Glow
```typescript
// Base liquid effect (modifies image)
renderer.setSlotShader(0, 'liquid-gold');
renderer.setSlotMode(0, 'chained');

// Particle overlay (reads liquid output, adds sparkles)
renderer.setSlotShader(1, 'particle-dreams');
renderer.setSlotMode(1, 'parallel');  // Can overlap with glow

// Glow overlay (reads liquid output, adds bloom)
renderer.setSlotShader(2, 'neon-pulse');
renderer.setSlotMode(2, 'parallel');  // Can overlap with particles
```

### Video + Reaction-Diffusion + Distortion
```typescript
// Video stays intact as base
renderer.setSlotShader(0, 'passthrough');
renderer.setSlotMode(0, 'chained');

// RD effect reads video, creates patterns
renderer.setSlotShader(1, 'reaction-diffusion');
renderer.setSlotMode(1, 'parallel');

// Distortion reads video, warps it
renderer.setSlotShader(2, 'lens-distort');
renderer.setSlotMode(2, 'parallel');
// Result: the distorted video (last one wins) — unless slot 2 blends:
renderer.setSlotOutput(2, { mode: 'blend', blend: 'overlay', opacity: 0.6 });
// Result: RD patterns with the distorted video overlaid at 60 %
```
