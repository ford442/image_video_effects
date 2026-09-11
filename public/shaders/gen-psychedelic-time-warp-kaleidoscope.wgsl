// ═══════════════════════════════════════════════════════════════════
//  Psychedelic Time-Warp Kaleidoscope
//  Category: generative
//  Features: kaleidoscope, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: exact-C smear along the fold; honest three-band audio
//  A packing: ACES display RGBA
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
  return vec4<f32>(controlled, color.a);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash31(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    let r = q + vec3<f32>(dot(q, q.yzx + vec3<f32>(33.33)));
    return fract((r.x + r.y) * r.z);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(
        mix(mix(hash31(i + vec3<f32>(0.0,0.0,0.0)), hash31(i + vec3<f32>(1.0,0.0,0.0)), uu.x),
            mix(hash31(i + vec3<f32>(0.0,1.0,0.0)), hash31(i + vec3<f32>(1.0,1.0,0.0)), uu.x), uu.y),
        mix(mix(hash31(i + vec3<f32>(0.0,0.0,1.0)), hash31(i + vec3<f32>(1.0,0.0,1.0)), uu.x),
            mix(hash31(i + vec3<f32>(0.0,1.0,1.0)), hash31(i + vec3<f32>(1.0,1.0,1.0)), uu.x), uu.y),
        uu.z
    );
}

fn curlNoise3D(p: vec3<f32>) -> vec2<f32> {
    let e = 0.01;
    let nx = noise3D(p + vec3<f32>(e, 0.0, 0.0)) - noise3D(p - vec3<f32>(e, 0.0, 0.0));
    let ny = noise3D(p + vec3<f32>(0.0, e, 0.0)) - noise3D(p - vec3<f32>(0.0, e, 0.0));
    let nz = noise3D(p + vec3<f32>(0.0, 0.0, e)) - noise3D(p - vec3<f32>(0.0, 0.0, e));
    return vec2<f32>(ny - nz, nz - nx);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    var center = u.zoom_config.yz * res;
    if (center.x == 0.0 && center.y == 0.0) {
        center = res * 0.5;
    }

    let norm_coords = vec2<f32>(coords) / res;
    let noise_val = curlNoise3D(vec3<f32>(norm_coords * 5.0, time * 0.2));

    let wobble = mix(0.1, 0.5, u.zoom_params.y) * (1.0 + mids * 0.55);
    let noise_intensity = mix(0.5, 2.0, u.zoom_params.z) * (1.0 + treble * 0.6);

    // Idea 2 — honest three-band: bass drives mirror count (not plasmaBuffer[index])
    let mirror_count = mix(3.0, 12.0, clamp(bass, 0.0, 1.0));
    let angle_step = 6.2831853 / max(mirror_count, 3.0);

    var foldUV = vec2<f32>(coords) - center;
    let dist = length(foldUV);
    var angle = atan2(foldUV.y, foldUV.x);

    angle += wobble * sin(dist * 0.02 - time * 2.0);

    angle = ((angle - angle_step * floor(angle / angle_step)) + angle_step);
    angle = angle - angle_step * floor(angle / angle_step);
    angle = abs(angle - angle_step / 2.0) * mix(1.0, 2.0, u.zoom_params.x);

    foldUV = vec2<f32>(cos(angle), sin(angle)) * dist;

    let dist_uv = vec2<i32>(foldUV + center + noise_val * 50.0 * noise_intensity);
    let maxCoord = vec2<i32>(res) - vec2<i32>(1);
    let clamped_uv = clamp(dist_uv, vec2<i32>(0), maxCoord);
    var color = textureLoad(readTexture, clamped_uv, 0).rgb;
    let srcA = textureLoad(readTexture, coords, 0).a;

    let glow = max(0.0, 1.0 - (dist / (res.x * 0.5))) * bass;
    color += vec3<f32>(0.2, 0.5, 1.0) * glow * (0.4 + mids * 0.4);

    // Idea 1 — exact-C smear along the fold
    let foldDir = select(vec2<f32>(0.0, 1.0), foldUV / max(dist, 0.001), dist > 0.001);
    let smearPix = clamp(coords + vec2<i32>(foldDir * 3.0), vec2<i32>(0), maxCoord);
    let prevSmear = textureLoad(dataTextureC, smearPix, 0);
    color = mix(color, prevSmear.rgb * 0.92, 0.08 + bass * 0.04);

    color.r += glow * bass * 0.35;
    color.g += glow * mids * 0.25;
    color.b += glow * treble * 0.3;

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.55 + glow * 0.25 + srcA * 0.2, 0.0, 1.0);
    var outCol = applyGenerativePrimaryControls(vec4<f32>(acesToneMap(color), alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(norm_coords, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    textureStore(writeTexture, coords, outCol);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, outCol);
}
