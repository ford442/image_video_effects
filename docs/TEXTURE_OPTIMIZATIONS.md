# Texture & Buffer Optimizations for WebGPU

## Texture Usage Flags

### Optimized Usage Patterns

```typescript
// SOURCE TEXTURES (images, video input)
const USAGE_SOURCE = 
  GPUTextureUsage.TEXTURE_BINDING |  // Sampled by shaders
  GPUTextureUsage.COPY_DST |          // Upload from CPU
  GPUTextureUsage.COPY_SRC;           // Blit to canvas (optional)

// INTERMEDIATE TEXTURES (ping-pong buffers, compute-only)
const USAGE_INTERMEDIATE = 
  GPUTextureUsage.TEXTURE_BINDING |   // Read in next pass
  GPUTextureUsage.STORAGE_BINDING |   // Written as storage
  GPUTextureUsage.TRANSIENT_ATTACHMENT; // Tile memory hint (Chrome 146+)

// DEPTH TEXTURES
const USAGE_DEPTH = 
  GPUTextureUsage.TEXTURE_BINDING |   // Sampled for depth-aware effects
  GPUTextureUsage.COPY_DST;           // Upload depth from CPU
```

### What to Avoid

```typescript
// DON'T: Intermediate textures with unnecessary flags
const BAD_INTERMEDIATE = 
  GPUTextureUsage.TEXTURE_BINDING |
  GPUTextureUsage.STORAGE_BINDING |
  GPUTextureUsage.COPY_SRC |        // ❌ Not needed for ping-pong
  GPUTextureUsage.RENDER_ATTACHMENT; // ❌ Compute-only, no rendering

// DON'T: Source textures with render attachment if not needed
const BAD_SOURCE = 
  GPUTextureUsage.TEXTURE_BINDING |
  GPUTextureUsage.COPY_DST |
  GPUTextureUsage.RENDER_ATTACHMENT; // ❌ Only if rendering TO this texture
```

## TRANSIENT_ATTACHMENT (Chrome 146+, Feb 2026)

Keeps intermediate textures in tile memory instead of VRAM:

```typescript
// Check support
const supportsTransient = 'TRANSIENT_ATTACHMENT' in GPUTextureUsage;

// Apply to compute-only textures
const transientUsage = supportsTransient
  ? GPUTextureUsage.TEXTURE_BINDING | 
    GPUTextureUsage.STORAGE_BINDING |
    GPUTextureUsage.TRANSIENT_ATTACHMENT
  : GPUTextureUsage.TEXTURE_BINDING | 
    GPUTextureUsage.STORAGE_BINDING;
```

**Benefits:**
- 2-4x bandwidth reduction for ping-pong textures
- No VRAM traffic for intermediate results
- Automatic on Apple Silicon, NVIDIA Ada, AMD RDNA3+

## textureLoad vs textureSample

### When to Use Each

| Function | Coordinates | Sampler | Speed | Use Case |
|----------|-------------|---------|-------|----------|
| `textureLoad(tex, coord, mip)` | Integer pixels | No | ⭐⭐⭐ Fastest | Exact pixel reads, tile loading |
| `textureSampleLevel(tex, samp, uv, 0)` | Normalized UV | Yes | ⭐⭐ Fast | No filtering, LOD 0 |
| `textureSample(tex, samp, uv)` | Normalized UV | Yes | ⭐ Normal | Bilinear filtering |

### Examples

```wgsl
// ✅ GOOD: Integer coordinates = textureLoad
let pixel = textureLoad(readTexture, vec2<i32>(global_id.xy), 0);

// ✅ GOOD: UV coordinates with filtering = textureSample  
let blurred = textureSample(readTexture, linearSampler, uv);

// ⚠️ OKAY: UV with explicit LOD 0
let exact = textureSampleLevel(readTexture, nearestSampler, uv, 0.0);

// ❌ SLOW: textureSample with nearest sampler is same as textureLoad
let slow = textureSample(readTexture, nearestSampler, uv); // Use textureLoad instead
```

### Shared Memory Loading (Optimized)

```wgsl
// Before: UV conversion + sampler
let uv = vec2<f32>(pixelCoord) / resolution;
let value = textureSampleLevel(tex, sampler, uv, 0.0).r;

// After: Direct integer load (10-20% faster)
let value = textureLoad(tex, pixelCoord, 0).r;
```

## Buffer Optimizations

### Uniform Buffer Packing

Pack multiple parameters into vec4s for better cache utilization:

```wgsl
// ❌ Wasteful: Multiple scalar uniforms
struct BadUniforms {
  time: f32,
  mouseX: f32,
  mouseY: f32,
  param1: f32,
  param2: f32,
  // ... padding wastes space
};

// ✅ Efficient: vec4 packing
struct GoodUniforms {
  config: vec4<f32>,       // time, mouseX, mouseY, unused
  params: vec4<f32>,       // param1, param2, param3, param4
};
```

### Storage Buffer Alignment

```wgsl
// Ensure 16-byte alignment for vec3/f32 arrays
struct Particle {
  position: vec3<f32>,  // 12 bytes
  _pad: f32,            // 4 bytes padding
  velocity: vec3<f32>,  // 12 bytes
  mass: f32,            // 4 bytes (no padding needed at end)
};  // Total: 32 bytes (aligned)
```

## Migration Checklist

- [ ] Remove `COPY_SRC` from textures not used as copy sources
- [ ] Remove `RENDER_ATTACHMENT` from compute-only textures
- [ ] Add `TRANSIENT_ATTACHMENT` to intermediate textures (if supported)
- [ ] Replace `textureSampleLevel(..., 0.0)` with `textureLoad` for integer coords
- [ ] Use `textureSample` (not Level) when you want filtering
- [ ] Pack uniforms into vec4s
- [ ] Verify 16-byte alignment on storage buffer structs
- [ ] Test on target hardware (transient attachment is GPU-specific)

## Performance Impact

| Optimization | Typical Speedup | When Applied |
|--------------|-----------------|--------------|
| Minimal usage flags | 5-10% | Always |
| TRANSIENT_ATTACHMENT | 20-50% | Chrome 146+, mobile GPUs |
| textureLoad vs Sample | 10-20% | Integer coordinate paths |
| Uniform packing | 5-15% | High uniform update rate |
| Buffer alignment | 0-5% | Large storage buffers |
