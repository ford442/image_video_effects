// ═══════════════════════════════════════════════════════════════════
//  Depth-Refracted Liquid Stained Glass
//  Category: generative
//  Features: facet-refraction, depth-aware, chromatic-aberration, upgraded-rgba,
//            temporal-rotation, audio-refraction, chromatic-edge-dispersion
//  Complexity: High
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


fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));

    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let aspect = f32(res.x) / f32(res.y);
    var uv = vec2<f32>(coords) / vec2<f32>(res);
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    let center = u.zoom_config.yz * 2.0 - 1.0;
    var centered_p = p - vec2<f32>(center.x * aspect, center.y);

    let facetCount = max(3.0, floor(u.zoom_params.x));
    let angleStep = 3.14159 * 2.0 / facetCount;

    var a = atan2(centered_p.y, centered_p.x);
    let r = length(centered_p);

    // Temporal rotation: slow facet spin
    a += u.config.x * 0.2 + u.config.y * 0.5;

    a = (a / angleStep % 1.0 + 1.0) % 1.0;
    a = abs(a - 0.5) * angleStep;

    var folded_p = vec2<f32>(cos(a), sin(a)) * r;

    folded_p.x /= aspect;
    var sample_uv = folded_p * 0.5 + 0.5;
    sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let depth_val = textureSampleLevel(readDepthTexture, u_sampler, sample_uv, 0.0).r;

    let texSize = vec2<f32>(textureDimensions(readDepthTexture));
    let eps = vec2<f32>(1.0 / texSize.x, 1.0 / texSize.y) * u.zoom_params.y;

    let d_dx = textureSampleLevel(readDepthTexture, u_sampler, sample_uv + vec2<f32>(eps.x, 0.0), 0.0).r - depth_val;
    let d_dy = textureSampleLevel(readDepthTexture, u_sampler, sample_uv + vec2<f32>(0.0, eps.y), 0.0).r - depth_val;
    let normal = normalize(vec3<f32>(d_dx, d_dy, 0.1));

    // Audio-reactive refraction strength
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth_mod = sin(u.config.x * 2.0 + u.config.y * 3.0) * 0.5 + 0.5;
    let ref_str = 0.1 * depth_mod * (1.0 + bass * 0.3);

    let offset = normal.xy * ref_str * (1.0 - depth_val);

    // Chromatic edge dispersion: R and B refract at different angles near facet edges
    let edgeDist = min(min(a, angleStep - a), r * 0.5);
    let edgeFactor = smoothstep(0.05, 0.0, edgeDist);
    let r_offset = plasmaBuffer[0].xy * 0.02 + vec2<f32>(edgeFactor * 0.01 * treble, 0.0);
    let g_offset = plasmaBuffer[1].xy * 0.02;
    let b_offset = plasmaBuffer[2].xy * 0.02 - vec2<f32>(edgeFactor * 0.01 * bass, 0.0);

    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + r_offset, 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + g_offset, 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, sample_uv + offset + b_offset, 0.0).b;

    let tint = plasmaBuffer[3].rgb;
    col *= (vec3<f32>(1.0) + tint * 0.5);

    let edge = length(vec2<f32>(d_dx, d_dy)) * 50.0;
    col += vec3<f32>(smoothstep(0.1, 0.5, edge)) * 0.5;

    // Temporal color rotation via dataTextureC tint blend
    let prevTint = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    col = mix(col, prevTint * 0.9, 0.04 + mids * 0.02);

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.8 + luma * 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeDepthTexture, coords, vec4<f32>(luma, 0.0, 0.0, 1.0));
    textureStore(writeTexture, coords, applyGenerativePrimaryControls(vec4<f32>(col, alpha)));
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
