// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage
//  Category: image
//  Features: audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Chunks From: noise.wgsl
//  Created: 2026-05-30
//  Upgraded: 2026-05-31
// ═══════════════════════════════════════════════════════════════════
//  Vertical heat shimmer driven by a rising hot-air column. A
//  time-varying noise field is advected upward, displacing the UV
//  sample. Temporal feedback (dataTextureC) stores the accumulated
//  heat state and slowly cools. Bass injects fresh heat bursts.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=HeatIntensity, y=RiseSpeed, z=WavyScale, w=ChromaShift
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash3 (from noise.wgsl) ═══
fn hash3(p: vec2f) -> vec3f {
  let q = vec3f(dot(p, vec2f(127.1, 311.7)),
                dot(p, vec2f(269.5, 183.3)),
                dot(p, vec2f(419.2, 371.9)));
  return fract(sin(q) * 43758.5453);
}
// ════════════════════════════════════════

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash3(i).x,                       hash3(i + vec2<f32>(1.0, 0.0)).x, u.x),
        mix(hash3(i + vec2<f32>(0.0, 1.0)).x, hash3(i + vec2<f32>(1.0, 1.0)).x, u.x),
        u.y
    ) * 2.0 - 1.0;
}

fn fbm2(p: vec2<f32>) -> vec2<f32> {
    let n1 = vnoise(p);
    let n2 = vnoise(p + vec2<f32>(5.2, 1.3));
    return vec2<f32>(n1, n2);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;

    // Audio — read from plasmaBuffer[0].xyz as vec3f(bass, mids, treble)
    let audio = plasmaBuffer[0].xyz;
    let bass   = audio.x;
    let mid    = audio.y;
    let treble = audio.z;

    // Params
    let heatIntensity = mix(0.0, 0.025, u.zoom_params.x) * (1.0 + bass * 2.0);
    let riseSpeed     = mix(0.1, 1.5,   u.zoom_params.y);
    let wavyScale     = mix(2.0, 12.0,  u.zoom_params.z);
    let chromaShift   = mix(0.0, 0.008, u.zoom_params.w);

    // Heat column: stronger at bottom of screen (y~0), rises upward
    let heatBase  = smoothstep(1.0, 0.0, uv.y) * 0.5 + 0.5; // more heat at bottom
    // Also mouse can be a heat source
    let mouse     = u.zoom_config.yz;
    let mDist     = length(uv - mouse);
    let mouseHeat = smoothstep(0.25, 0.0, mDist) * u.zoom_config.w;

    let heatFactor = heatBase + mouseHeat;

    // Rising displacement field
    let risingUV  = vec2<f32>(uv.x * wavyScale, uv.y * wavyScale - time * riseSpeed);
    let disp      = fbm2(risingUV) * heatIntensity * heatFactor;

    // Vertical bias: haze mostly shifts horizontally (shimmer), slight vertical
    let heatDisp  = vec2<f32>(disp.x, disp.y * 0.3);

    // Chromatic shift: red slightly ahead, blue slightly behind (mirage)
    let rUV = clamp(uv + heatDisp + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + heatDisp,                                vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + heatDisp - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let a = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).a;

    // Atmospheric haze: slight brightness boost + warm tint at heat zones
    let warmTint   = vec3<f32>(1.04, 1.01, 0.97) * (1.0 + heatFactor * 0.1);
    var col        = vec3<f32>(r, g, b) * warmTint;

    // Heat shimmer glow (subtle)
    let glowMask   = heatFactor * heatIntensity * 50.0;
    col += vec3<f32>(0.05, 0.03, 0.01) * glowMask * (1.0 + mid);

    // Temporal accumulate haze state
    let prev     = textureLoad(dataTextureC, coord, 0);
    let hazeAcc  = mix(vec4<f32>(col, a), prev, 0.85);

    let outColor = vec4<f32>(clamp(col, vec3<f32>(0.0), vec3<f32>(1.3)), a);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(heatFactor, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, hazeAcc);
    textureStore(dataTextureB, coord, vec4<f32>(heatDisp, heatFactor, bass));
}
