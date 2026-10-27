# Parallel Slot Groups - Inter-Shader Parallelization

## Overview

Pixelocity has **6 physical shader slots** (`maxPhysicalSlots` in
[`src/contracts/slot_limits.json`](../src/contracts/slot_limits.json), `PHYSICAL_SLOT_LIMIT` in TS,
`MAX_SHADER_SLOTS` in C++). The performance tier's `maxActiveSlots` (1–3) is a separate, lower
soft cap on how many run at once. By default slots run **chained** (sequentially):
- Slot 0 output → Slot 1 input → Slot 1 output → Slot 2 input → … → Slot 5
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
  │     (Last wins, unless a slot has a blend layer: then   │
  │      one composite pass blends the group, #1512)        │
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

1. **Compositing is opt-in per slot**: with every slot on the default *replace* layer, parallel slots write to the same output texture and the last one wins.
   - Give a slot a blend layer (blend mode, opacity, mask) in the Slot stack row and the group is captured and blended in one pass at internal precision. See [COMPOSITOR.md](COMPOSITOR.md).
   - A chained slot with a blend layer is mixed over its own input the same way.

2. **Same input**: All parallel slots read from `readTex` at the start of the parallel group
   - They don't see each other's output
   - Good for independent overlays, bad for layered effects

3. **Driver dependent**: Actual overlap depends on GPU driver scheduling
   - NVIDIA/AMD discrete GPUs: Good overlap
   - Integrated/Apple Silicon: Moderate overlap
   - Mobile: Limited by tile-based rendering

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
// Result: RD patterns AND distorted video overlaid (last wins; give slot 3 a blend layer to mix them)
```
