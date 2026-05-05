# Shader Optimization Patterns

## 1. Early Exit Optimization

**Purpose:** Skip expensive computations for pixels where the effect is minimal or off-screen.

### Before
```wgsl
fn expensiveFunction(uv: vec2<f32>) -> vec3<f32> {
    // ... 100 lines of math ...
    return result;
}
```

### After
```wgsl
fn expensiveFunction(uv: vec2<f32>, effectMask: f32) -> vec3<f32> {
    // Early exit for off-screen or simple cases
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec3<f32>(0.0);
    }
    
    // Check if effect applies to this region
    if (effectMask < 0.01) {
        return textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }
    
    // ... expensive computation only when needed ...
    return result;
}
```

**Impact:** 10-30% performance improvement for localized effects.

---

## 2. Distance-Based LOD (Level of Detail)

**Purpose:** Reduce computation for distant or less important pixels.

### Noise LOD
```wgsl
// Calculate distance from center of interest
let dist = length(uv - center);

// Reduce octaves based on distance
let octaves = i32(mix(8.0, 2.0, smoothstep(0.0, 0.5, dist)));
let noise = fbmLOD(uv, octaves);
```

### Raymarch LOD
```wgsl
// Fewer steps for distant objects
let dist = length(rayOrigin - cameraPos);
let steps = i32(mix(100.0, 30.0, smoothstep(0.0, 10.0, dist)));
```

**Impact:** 20-40% performance improvement for large view distances.

---

## 3. Loop Unrolling and Optimization

**Purpose:** Reduce loop overhead and enable compiler optimizations.

### Before
```wgsl
for (var i = 0; i < 3; i++) {
    let layerDepth = f32(i) * 0.33;
    // ... compute layer ...
}
```

### After
```wgsl
// Unroll small fixed loops manually
// Layer 0
let d0 = computeLayer(uv, 0.0);

// Layer 1  
let d1 = computeLayer(uv, 0.33);

// Layer 2
let d2 = computeLayer(uv, 0.66);

let result = (d0 + d1 + d2) * 0.333;
```

**Impact:** 5-15% improvement for small loops.

---

## 4. Precompute Constants

**Purpose:** Move computations outside of loops.

### Before
```wgsl
for (var i = 0; i < 100; i++) {
    let angle = f32(i) * 6.28318 / 100.0 + time;
    // ... use angle ...
}
```

### After
```wgsl
// Precompute outside loop
let invCount = 1.0 / 100.0;
let twoPiInv = 6.28318 * invCount;

for (var i = 0; i < 100; i++) {
    let angle = f32(i) * twoPiInv + time;
    // ... use angle ...
}
```

**Impact:** 5-10% improvement for loop-heavy code.

---

## 5. Branchless Code

**Purpose:** Avoid GPU branch divergence using WGSL's `select()` and `mix()`.

### Before (Branching)
```wgsl
var color: vec3<f32>;
if (condition) {
    color = colorA;
} else {
    color = colorB;
}
```

### After (Branchless)
```wgsl
// Using mix
let color = mix(colorB, colorA, f32(condition));

// Or using select (WGSL built-in)
let color = select(colorB, colorA, condition);
```

### Complex Branching
```wgsl
// Before
if (x < 0.0) {
    result = a;
} else if (x < 0.5) {
    result = b;
} else {
    result = c;
}

// After
let isA = step(x, 0.0);
let isB = step(x, 0.5) * (1.0 - isA);
let isC = 1.0 - isA - isB;
let result = a * isA + b * isB + c * isC;
```

**Impact:** 10-20% improvement on GPUs with SIMD execution.

---

## 6. Texture Cache Optimization

**Purpose:** Improve texture cache hit rates.

### Coherent Sampling
```wgsl
// Group texture samples together
let sample1 = textureSampleLevel(tex, sampler, uv + offset1, 0.0);
let sample2 = textureSampleLevel(tex, sampler, uv + offset2, 0.0);
let sample3 = textureSampleLevel(tex, sampler, uv + offset3, 0.0);

// Then process
let result = process(sample1, sample2, sample3);
```

### Mip Level Selection
```wgsl
// Use appropriate mip level based on sampling frequency
let mipLevel = log2(length(fwidth(uv) * textureSize));
let color = textureSampleLevel(tex, sampler, uv, mipLevel);
```

**Impact:** Variable, can be 50%+ for texture-heavy shaders.

---

## 7. Approximate Expensive Functions

**Purpose:** Use faster approximations for complex math.

### Pow Approximation
```wgsl
// Fast pow for common exponents
fn fastPow2(x: f32) -> f32 {
    return x * x;
}

fn fastPow3(x: f32) -> f32 {
    return x * x * x;
}
```

### Smoothstep vs Step
```wgsl
// Use step when smooth transition not needed
let hardEdge = step(threshold, value);

// Use smoothstep only when needed
let softEdge = smoothstep(edge0, edge1, value);
```

### Inverse Square Root
```wgsl
// Fast normalization (if precision allows)
fn fastNormalize(v: vec3<f32>) -> vec3<f32> {
    let lenSq = dot(v, v);
    let invLen = inverseSqrt(lenSq);  // GPU intrinsic
    return v * invLen;
}
```

**Impact:** 5-15% improvement depending on usage.

---

## 8. Caching Intermediate Results

**Purpose:** Avoid recomputing values used multiple times.

### Eigenvalue Caching (Tensor Flow)
```wgsl
// Compute once
let eigen = tensorEigen(tA, tB, tD);

// Reuse multiple times
let warp1 = eigen.vec_pos * eigen.lam_pos * flowAmp;
let warp2 = eigen.vec_neg * eigen.lam_neg * flowAmp;
let sColor = stressColor(eigen.lam_pos, eigen.lam_neg, t);
let sBlend = length(tensorWarp) * 4.0 * (1.0 - detailPreserve) * 0.5;
```

### Hyperbolic Coordinate Caching
```wgsl
// Cache hyperbolic coordinates
let hyperDist = hyperbolicDist(centered * curvature);
let translated = hyperbolicTranslate(centered, t);
// Reuse translated coordinates instead of recomputing
```

**Impact:** 15-30% for computation-heavy functions.

---

## 9. Reduce Overdraw with Depth Testing

**Purpose:** Skip computation for occluded pixels.

```wgsl
// Sample depth early
let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

// Skip if occluded or too far
if (depth > 0.99 || depth < 0.01) {
    textureStore(writeTexture, gid.xy, backgroundColor);
    return;
}
```

**Impact:** Variable based on scene depth complexity.

---

## 10. Parameter Randomization Safety

**Purpose:** Ensure shaders remain stable with randomized parameters.

```wgsl
// Clamp parameters to safe ranges
let safeScale = clamp(u.zoom_params.x, 0.01, 10.0);
let safeIntensity = clamp(u.zoom_params.y, 0.0, 1.0);

// Use epsilon to avoid division by zero
let invValue = 1.0 / max(value, 0.0001);

// Check for NaN/Inf (some GPUs)
let isValid = !isNan(value) && !isInf(value);
let safeValue = select(0.0, value, isValid);
```

---

## Summary: Optimization Priority

| Priority | Technique | Typical Impact |
|----------|-----------|----------------|
| 1 | Early Exit | 10-30% |
| 2 | Distance LOD | 20-40% |
| 3 | Caching | 15-30% |
| 4 | Branchless | 10-20% |
| 5 | Loop Unroll | 5-15% |
| 6 | Precompute | 5-10% |
| 7 | Function Approx | 5-15% |
| 8 | Texture Cache | Variable |
| 9 | Depth Test | Variable |
| 10 | Safety | Stability |

Apply optimizations in order of impact, measuring after each change.
