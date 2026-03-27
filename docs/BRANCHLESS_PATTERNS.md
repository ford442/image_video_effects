# Branchless GPU Programming Patterns for WGSL

This guide shows how to reduce divergence (branch misprediction) in WGSL shaders using branchless techniques.

## Why Branchless?

GPUs execute threads in lockstep (warps/wavefronts of 32-64 threads). When threads take different branches:
- **Divergence**: GPU must execute both branches and mask results
- **Performance**: ~2x penalty for simple if/else, worse for nested branches
- **Solution**: Use masks, mix(), select(), and other branchless operations

## Pattern 1: If/Else with mix()

### Before (Divergent)
```wgsl
if (backgroundFactor > 0.01) {
    newHeight = h_curr + velocity * dt;
} else {
    newHeight = h_curr;
}
```

### After (Branchless)
```wgsl
let mask = f32(backgroundFactor > 0.01);
newHeight = mix(h_curr, h_curr + velocity * dt, mask);
```

Or using arithmetic:
```wgsl
let mask = f32(backgroundFactor > 0.01);
newHeight = h_curr + velocity * dt * mask;
```

## Pattern 2: If with Early Exit (Partially Branchless)

When you need early exit for bounds checking only:

```wgsl
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // Bounds check is OK - threads at edges all take same branch
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }
    
    // Main computation should be branchless...
}
```

## Pattern 3: Nested If Flattening

### Before (Nested Divergence)
```wgsl
for (var i = 0u; i < rippleCount; i++) {
    let timeSince = currentTime - ripples[i].time;
    if (timeSince > 0.0 && timeSince < 3.0) {
        let dist = length(uv - ripples[i].pos);
        if (dist > 0.001) {
            // Compute ripple
        }
    }
}
```

### After (Flattened)
```wgsl
for (var i = 0u; i < rippleCount; i++) {
    let timeSince = currentTime - ripples[i].time;
    let dist = length(uv - ripples[i].pos);
    
    // Create masks for each condition
    let timeMask = f32(timeSince > 0.0 && timeSince < 3.0);
    let distMask = f32(dist > 0.001);
    let contribMask = timeMask * distMask;
    
    // Compute unconditionally, mask the result
    let ripple = computeRipple(dist, timeSince) * contribMask;
    sum += ripple;
}
```

## Pattern 4: select() for Type-Safe Branching

```wgsl
// For integers
let index = select(0i, 1i, condition);  // 0 if false, 1 if true

// For floats
let value = select(0.0, 1.0, condition);

// For vectors
let color = select(vec3(0.0), vec3(1.0), pixelActive);
```

## Pattern 5: Boolean-to-Float Masks

```wgsl
// Convert bool to float for arithmetic masking
let mask = f32(someCondition);        // 1.0 if true, 0.0 if false
let inverted = f32(!someCondition);   // 0.0 if true, 1.0 if false

// Use for conditional accumulation
result += computedValue * mask;
```

## Pattern 6: Smooth Masking

For smoother transitions (no hard edges):

```wgsl
// Smoothstep mask (0.0 -> 1.0 with smooth transition)
let softMask = smoothstep(0.0, 0.1, backgroundFactor);

// Mix based on soft mask
result = mix(bgValue, fgValue, softMask);
```

## Pattern 7: Workgroup-Level Reduction (For Atomics)

When you need atomic operations, use workgroup-level reduction first:

```wgsl
var<workgroup> localHistogram: array<atomic<u32>, 256>;
var<workgroup> globalOffset: u32;

@compute @workgroup_size(256, 1, 1)
fn reduce(
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(workgroup_id) wid: vec3<u32>
) {
    // Each thread accumulates to local memory (fast!)
    atomicAdd(&localHistogram[myBin], 1u);
    
    workgroupBarrier();
    
    // Thread 0 does the global atomic (single atomic per workgroup)
    if (lid.x == 0u) {
        for (var i = 0u; i < 256u; i++) {
            let localCount = atomicLoad(&localHistogram[i]);
            if (localCount > 0u) {
                atomicAdd(&globalHistogram[i], localCount);
            }
        }
    }
}
```

## Pattern 8: Pre-compute Masks

When using the same condition multiple times:

```wgsl
// Pre-compute masks at start
let isBackground = f32(depth > 0.5);
let isLiquid = f32(depth < 0.3);
let isInterface = 1.0 - isBackground - isLiquid;  // Assumes mutually exclusive

// Use masks throughout shader
heightUpdate *= isBackground;
liquidColor *= isLiquid;
interfaceBlend *= isInterface;
```

## Pattern 9: Loop Unrolling with Masks

For small fixed loops, unroll with masks:

```wgsl
// Instead of: for (var i=0; i<4; i++) { if (i < count) { ... } }

// Unroll with masks
let c0 = f32(count > 0u) * compute(0u);
let c1 = f32(count > 1u) * compute(1u);
let c2 = f32(count > 2u) * compute(2u);
let c3 = f32(count > 3u) * compute(3u);
result = c0 + c1 + c2 + c3;
```

## Performance Comparison

| Pattern | Divergent | Branchless | Speedup |
|---------|-----------|------------|---------|
| Simple if/else | 2x exec | 1x exec | 1.5-2x |
| Nested ifs | 4x+ exec | 1x exec | 3-4x |
| Loop with if | Warp divergence | Uniform | 2-8x |
| Atomic per thread | Memory thrashing | Workgroup reduce | 10-100x |

## When to Keep Branches

Not all ifs are bad:

1. **Bounds checks**: All threads take same branch at edges - keep them
2. **Early exit for performance**: `if (pixelOccluded) return;` can help
3. **Texture sampling conditionals**: Avoid sampling if result is masked
4. **Complex computation guards**: Skip heavy math if mask is 0

Example of good early exit:
```wgsl
// OK: Skip expensive computation when not needed
if (contribMask == 0.0) {
    continue;  // Skip to next iteration
}
```

## Testing Branchless Code

Visual comparison to ensure correctness:

```typescript
// Compare branchless vs divergent output
const divergentShader = loadShader('liquid');
const branchlessShader = loadShader('liquid-optimized');

// Should produce identical output
const testCanvas = compareShaders(divergentShader, branchlessShader);
assert(pixelDifference(testCanvas) < 0.001);
```

## Migration Checklist

- [ ] Identify hot loops with nested ifs
- [ ] Replace if/else with mix() or select()
- [ ] Flatten nested conditions into masks
- [ ] Pre-compute common masks at start of shader
- [ ] Use smoothstep() for soft transitions
- [ ] Keep bounds checks (uniform divergence)
- [ ] Test visual output matches original
- [ ] Profile FPS improvement
