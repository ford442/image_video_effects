// ═══════════════════════════════════════════════════════════════════
//  Data Slicer Interactive — May 2026 Batch D Upgrade
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, glitch, upgraded-rgba
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2(0.0,0.0)), hash12(i + vec2(1.0,0.0)), u.x),
               mix(hash12(i + vec2(0.0,1.0)), hash12(i + vec2(1.0,1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i: i32 = 0; i < 4; i = i + 1) {
        s += a * noise(p * f);
        f *= 2.1;
        a *= 0.5;
    }
    return s;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Params
    let sliceCountBase = mix(4.0, 32.0, u.zoom_params.x);
    let sliceCount = sliceCountBase * (1.0 + bass * 0.5);
    let sliceWidth = mix(0.005, 0.08, u.zoom_params.y);
    let fbmWarpAmt = u.zoom_params.z * 0.06;
    let colorShift = u.zoom_params.w * 0.1;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Gravity well: pull slices toward mouse
    let distMouse = length(uv - mouse);
    let gravity = 1.0 - smoothstep(0.0, 0.35, distMouse);

    let sliceIndex = floor(uv.y * sliceCount);
    let sliceY = sliceIndex / sliceCount;
    let nextSliceY = (sliceIndex + 1.0) / sliceCount;

    // FBM warp on slice edges for torn/organic look
    let edgeNoise = fbm(vec2<f32>(uv.x * 8.0, sliceY * 4.0 + time * 0.3));
    let warpedSliceWidth = sliceWidth + edgeNoise * fbmWarpAmt;

    let distToSlice = min(abs(uv.y - sliceY), abs(uv.y - nextSliceY));
    // strength naturally 0 outside boundary — no branch needed
    let strength = 1.0 - smoothstep(0.0, max(warpedSliceWidth, 0.001), distToSlice);

    // Click-triggered slice bursts — branchless
    var burst = 0.0;
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let rDist = length(uv - rp.xy);
        let rAge = time - rp.z;
        let rRad = rAge * 0.5;
        let rBand = abs(rDist - rRad);
        let rippleActive = select(0.0, 1.0, rBand < 0.04 && rAge >= 0.0 && rAge < 1.2);
        let rippleDecay = clamp(1.0 - rAge / 1.2, 0.0, 1.0);
        burst += rippleActive * rippleDecay * 0.15 * sin(rDist * 50.0 - rAge * 20.0);
    }

    // Quantized jitter modulated by mids
    let quant = mix(20.0, 70.0, mids);
    let quantY = floor(uv.y * quant) / quant;
    let t = time * 3.0 * (1.0 + treble);
    let n = noise(vec2<f32>(quantY * 10.0, t));

    var offset = (n - 0.5) * 0.3 * strength + burst * strength;
    var split = colorShift * strength * (1.0 + bass * 2.0);
    let alphaMod = 1.0 - strength * 0.35;

    // Gravity deformation on offset
    offset += gravity * 0.02 * sin(uv.x * 20.0 + time);

    // Depth-driven parallax on RGB split
    split *= 1.0 + depth * 0.5;

    // RGB channel sampling with displacement
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset + split, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset, 0.0), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(offset - split, 0.0), 0.0).b;

    // Temporal feedback from previous frame
    let feedbackUV = uv + vec2(offset * 0.3, 0.0);
    let prev = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0);
    let fbAmt = 0.12 * strength + mouseDown * 0.25;
    var color = vec4<f32>(r, g, b, src.a * alphaMod);
    color = mix(color, prev, fbAmt);

    // Treble sparkle additive
    color.r += treble * strength * 0.25;
    color.g += treble * strength * 0.15;
    color.b += treble * strength * 0.1;

    // Depth-aware intensity boost
    color = mix(color, color * 1.3, depth * strength * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
