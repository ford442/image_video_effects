// ═══════════════════════════════════════════════════════════════════════════
//  Deep-Workgroup Multi-Effect Blend
//  Category: advanced-hybrid
//  Features: deep-workgroup, shared-memory, workgroup-barrier
//  Complexity: High
//  Requires: maxComputeInvocationsPerWorkgroup >= 1024 (16×16×4)
//
//  Uses a 16×16×4 workgroup (1024 invocations) where the four Z-layers
//  compute four independent effects on the same tile in parallel:
//    Z=0  Edge detection  (Sobel gradient)
//    Z=1  Bloom           (bright-pass + local spread via shared memory)
//    Z=2  Hue shift       (HSV rotation keyed to time + param)
//    Z=3  Phosphor glow   (green phosphor scanline + decay)
//
//  After all four lanes finish their per-pixel work they write into a
//  shared memory tile.  A single workgroupBarrier() ensures all writes
//  are visible before Z=0 reads all four results and blends them into the
//  final output pixel.
//
//  NOTE: This shader will only be loaded on GPUs that report
//  maxComputeInvocationsPerWorkgroup >= 1024 (Apple M1/M2/M3, NVIDIA RTX,
//  AMD RDNA2+).  The JSON entry carries "requiresDeepWorkgroup": true.
// ═══════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// ── Uniforms ─────────────────────────────────────────────────────────────────
struct Uniforms {
    config      : vec4<f32>,  // x=time, y=clickCount, z=resX, w=resY
    zoom_config : vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
    zoom_params : vec4<f32>,  // x=blend, y=hueSpeed, z=bloomThresh, w=phosphorAmt
    ripples     : array<vec4<f32>, 50>,
}

// ── Shared memory tile ───────────────────────────────────────────────────────
// Layout: shared[z][y][x]  — 4 effect lanes × 16 × 16 = 1024 vec4 entries
var<workgroup> shared_tile: array<array<array<vec4<f32>, 16>, 16>, 4>;

// ── Helpers ──────────────────────────────────────────────────────────────────

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// RGB → HSV
fn rgb_to_hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = select(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), c.b < c.g);
    let q = select(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), p.x < c.r);
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV → RGB
fn hsv_to_rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

// ── Main entry point ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 4)
fn main(
    @builtin(global_invocation_id)   gid: vec3<u32>,
    @builtin(local_invocation_id)    lid: vec3<u32>,
    @builtin(workgroup_id)           wgid: vec3<u32>,
) {
    let resX = u32(u.config.z);
    let resY = u32(u.config.w);

    // Guard: discard out-of-bounds threads
    if (gid.x >= resX || gid.y >= resY) {
        shared_tile[lid.z][lid.y][lid.x] = vec4<f32>(0.0);
        workgroupBarrier();
        return;
    }

    let time        = u.config.x;
    let uv          = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(f32(resX), f32(resY));
    let texelSize   = vec2<f32>(1.0) / vec2<f32>(f32(resX), f32(resY));

    // Parameters
    let blendMix    = clamp(u.zoom_params.x, 0.0, 1.0);   // 0=original..1=full effect
    let hueSpeed    = u.zoom_params.y * 2.0;               // hue rotation speed
    let bloomThresh = 0.3 + u.zoom_params.z * 0.6;        // bloom threshold
    let phosphorAmt = u.zoom_params.w;                     // phosphor intensity

    // Base colour for this pixel
    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    var lane_result = vec4<f32>(0.0);

    // ── Z=0  Sobel edge detection ────────────────────────────────────────────
    if (lid.z == 0u) {
        // Sample 3×3 neighbourhood
        let tl = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>(-1.0, -1.0), 0.0).rgb);
        let tc = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 0.0, -1.0), 0.0).rgb);
        let tr = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 1.0, -1.0), 0.0).rgb);
        let ml = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>(-1.0,  0.0), 0.0).rgb);
        let mr = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 1.0,  0.0), 0.0).rgb);
        let bl = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>(-1.0,  1.0), 0.0).rgb);
        let bc = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 0.0,  1.0), 0.0).rgb);
        let br = luminance(textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 1.0,  1.0), 0.0).rgb);

        let gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
        let gy = -tl - 2.0*tc - tr  + bl + 2.0*bc + br;
        let edge = clamp(sqrt(gx*gx + gy*gy) * 3.0, 0.0, 1.0);

        // Colour edges with a neon cyan tint
        let edgeColour = vec3<f32>(0.0, edge, edge * 0.8);
        lane_result = vec4<f32>(mix(base.rgb, edgeColour, edge * blendMix), base.a);
    }

    // ── Z=1  Bloom (bright-pass + local average) ─────────────────────────────
    if (lid.z == 1u) {
        // 5-tap cross blur (approximates bloom spread)
        let c0 = textureSampleLevel(readTexture, u_sampler, uv,                                           0.0).rgb;
        let c1 = textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 2.0,  0.0), 0.0).rgb;
        let c2 = textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>(-2.0,  0.0), 0.0).rgb;
        let c3 = textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 0.0,  2.0), 0.0).rgb;
        let c4 = textureSampleLevel(readTexture, u_sampler, uv + texelSize * vec2<f32>( 0.0, -2.0), 0.0).rgb;
        let blurred = (c0 + c1 + c2 + c3 + c4) / 5.0;

        // Keep only bright parts (bright-pass filter)
        let bright = max(vec3<f32>(0.0), blurred - bloomThresh) / (1.0 - bloomThresh);
        let bloom  = base.rgb + bright * 1.5;
        lane_result = vec4<f32>(mix(base.rgb, clamp(bloom, vec3<f32>(0.0), vec3<f32>(1.2)), blendMix), base.a);
    }

    // ── Z=2  Hue shift ───────────────────────────────────────────────────────
    if (lid.z == 2u) {
        var hsv = rgb_to_hsv(base.rgb);
        hsv.x = fract(hsv.x + time * hueSpeed * 0.05);
        let shifted = hsv_to_rgb(hsv);
        lane_result = vec4<f32>(mix(base.rgb, shifted, blendMix), base.a);
    }

    // ── Z=3  Phosphor scanline glow ──────────────────────────────────────────
    if (lid.z == 3u) {
        // Scanline: brighten even rows, dim odd rows
        let scanline = select(0.75, 1.0, (gid.y & 1u) == 0u);

        // Green channel boost (classic green phosphor)
        let phosphor = vec3<f32>(
            base.r * 0.3,
            base.g * 1.4,
            base.b * 0.3
        ) * scanline;

        // Add faint horizontal scan glow
        let glow = vec3<f32>(0.0, 0.05 * scanline, 0.0) * luminance(base.rgb);
        let result = clamp(phosphor + glow, vec3<f32>(0.0), vec3<f32>(1.5));
        lane_result = vec4<f32>(mix(base.rgb, result, phosphorAmt * blendMix), base.a);
    }

    // Write this lane's result into shared memory
    shared_tile[lid.z][lid.y][lid.x] = lane_result;

    // ── Synchronise all lanes ─────────────────────────────────────────────────
    workgroupBarrier();

    // ── Z=0 blends all four results and writes the final pixel ───────────────
    if (lid.z == 0u) {
        let edge_out     = shared_tile[0][lid.y][lid.x];
        let bloom_out    = shared_tile[1][lid.y][lid.x];
        let hue_out      = shared_tile[2][lid.y][lid.x];
        let phosphor_out = shared_tile[3][lid.y][lid.x];

        // Equal-weight blend of the four lanes
        let blended = (edge_out + bloom_out + hue_out + phosphor_out) * 0.25;

        // Composite over original using blendMix
        let final_colour = vec4<f32>(
            mix(base.rgb, blended.rgb, blendMix),
            base.a
        );

        textureStore(writeTexture, vec2<i32>(gid.xy), final_colour);
    }
}
