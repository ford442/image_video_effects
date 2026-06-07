// ═══════════════════════════════════════════════════════════════════
//  4D Projection Dream Weavers
//  Category: generative
//  Features: 4d-fractal, smooth-navigation, mouse-4d-control, audio-parameter, dream-like,
//            temporal-persistence, chromatic-dimension-separation, bass-detail, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Chunks From: 4D noise projection techniques
//  Created: 2026-05-31
//  Upgraded: 2026-06-06
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
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


fn hash13(p: vec3<f32>) -> f32 {
    var p4 = fract(vec4<f32>(p.xyz, 0.0) * 0.1031);
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.x + p4.y) * (p4.z + p4.w));
}

fn noise4D(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = hash13(i.xyz);
    let b = hash13(i.xyz + vec3<f32>(1.0, 0.0, 0.0));
    let c = hash13(i.xyz + vec3<f32>(0.0, 1.0, 0.0));
    let d = hash13(i.xyz + vec3<f32>(1.0, 1.0, 0.0));
    let e = hash13(i.xyz + vec3<f32>(0.0, 0.0, 1.0));
    let f2 = hash13(i.xyz + vec3<f32>(1.0, 0.0, 1.0));
    let g = hash13(i.xyz + vec3<f32>(0.0, 1.0, 1.0));
    let h = hash13(i.xyz + vec3<f32>(1.0, 1.0, 1.0));

    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f2, u.x), mix(g, h, u.x), u.y),
        u.z
    );
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.2;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;

    let w = (mouse.x - 0.5) * 4.0;
    let z = (mouse.y - 0.5) * 4.0;

    let scale = 1.8 + mids * 1.4;
    let speed = 0.6 + bass * 0.8;
    let detail = 0.7 + treble * 1.2;

    let p4 = vec4<f32>(uv * scale, z, w);

    // Chromatic dimension separation: sample at different 4D offsets per channel
    let n_r = noise4D(p4 * 1.0 + time * speed + vec4<f32>(bass * 0.1, 0.0, 0.0, 0.0));
    let n_g = noise4D(p4 * 1.0 + time * speed);
    let n_b = noise4D(p4 * 1.0 + time * speed - vec4<f32>(treble * 0.1, 0.0, 0.0, 0.0));
    let n2 = noise4D(p4 * 2.3 - time * speed * 0.7) * 0.5;
    let n3 = noise4D(p4 * 4.7 + time * speed * 1.3) * 0.25;

    let fractal_r = n_r + n2 + n3;
    let fractal_g = n_g + n2 + n3;
    let fractal_b = n_b + n2 + n3;

    // Temporal persistence for dream-like trails
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let fractal_col = vec3<f32>(fractal_r, fractal_g, fractal_b);
    let temporal = mix(fractal_col, prev * 0.92, 0.12 + bass * 0.05);

    let col = mix(
        vec3<f32>(0.1, 0.15, 0.25),
        vec3<f32>(0.9, 0.85, 0.7),
        temporal * 0.6 + 0.4
    );

    let extraColor = vec3<f32>(abs(z) * 0.1, abs(w) * 0.08, (z + w) * 0.05);
    let finalCol = col + extraColor;

    let alpha = clamp((fractal_r + fractal_g + fractal_b) * 0.25 + 0.4 + bass * 0.05, 0.25, 1.0);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, applyGenerativePrimaryControls(vec4<f32>(finalCol, a)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(finalCol, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>((fractal_r + fractal_g + fractal_b) * 0.2 + 0.3, 0.0, 0.0, 0.0));
}
