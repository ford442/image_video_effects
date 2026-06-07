// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Description: Orientational director field inspired by liquid crystals.
//  Audio frequencies drive topological defect creation, motion, and
//  annihilation. Mouse can pin or create defects. Iridescent oil-slick coloring.
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Director field angle from a collection of topological defects
// Each defect is defined by position and charge (+1/2 or -1/2)
fn directorAngle(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                 mousePos: vec2<f32>, defectDensity: f32, defectSpeed: f32) -> f32 {
    var angle = 0.0;
    let numDefects = i32(clamp(defectDensity * 8.0 + 2.0, 2.0, 12.0));

    for (var i = 0; i < numDefects; i++) {
        let fi = f32(i);
        let seed = hash22(vec2<f32>(fi, fi * 1.7 + 3.1));

        // Defects orbit and drift — speed modulated by audio band
        let orbitRadius = 0.2 + seed.x * 0.3;
        let orbitSpeed = defectSpeed * (0.5 + fi * 0.13);
        let audioMod = mix(bass, treble, fi / f32(numDefects));
        let px = seed.x * 0.6 + 0.2 + orbitRadius * cos(t * orbitSpeed + seed.y * TAU + audioMod * 0.5);
        let py = seed.y * 0.6 + 0.2 + orbitRadius * sin(t * orbitSpeed * 0.7 + seed.x * TAU + audioMod * 0.3);

        let defectPos = vec2<f32>(px, py);

        // Alternate +1/2 and -1/2 charges to allow annihilation
        let charge = select(-0.5, 0.5, (i % 2) == 0);

        let delta = uv - defectPos;
        let defectAngle = atan2(delta.y, delta.x) * charge;
        angle += defectAngle;
    }

    // Mouse-pinned defect: strong +1/2 defect at cursor
    let mouseDelta = uv - mousePos;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = exp(-mouseDist * mouseDist * 20.0);
    let mouseDefectAngle = atan2(mouseDelta.y, mouseDelta.x) * 0.5;
    angle += mouseDefectAngle * mouseInfluence * (1.0 + mids * 2.0);

    return angle;
}

// Iridescent color from orientation angle (thin-film-like)
fn iridescent(angle: f32, dist: f32, mids: f32, treble: f32) -> vec3<f32> {
    let norm = fract(angle / PI);
    let r = 0.5 + 0.5 * cos(norm * TAU + mids * 2.0);
    let g = 0.5 + 0.5 * cos(norm * TAU + 2.094 + treble * 1.5);
    let b = 0.5 + 0.5 * cos(norm * TAU + 4.189 + mids * 1.0);
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / res.y;
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let defectDensity = u.zoom_params.x;           // 0..1 -> number of defects
    let defectSpeed   = u.zoom_params.y * 0.8 + 0.1; // 0.1..0.9
    let irisIntensity = u.zoom_params.z * 1.5 + 0.5; // 0.5..2.0
    let flowStrength  = u.zoom_params.w * 2.0 + 0.5;  // 0.5..2.5

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);

    // Compute director field angle at this pixel
    let theta = directorAngle(uvA, t, bass, mids, treble,
                               mousePos, defectDensity, defectSpeed);

    // Flow field: directional vector from angle
    let dir = vec2<f32>(cos(theta), sin(theta));

    // Sample angle at a small offset to detect defect singularities
    let eps = 0.008;
    let thetaDx = directorAngle(uvA + vec2<f32>(eps, 0.0), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed);
    let thetaDy = directorAngle(uvA + vec2<f32>(0.0, eps), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed);

    // Topological charge density (approximated via angle divergence)
    let dTheta = vec2<f32>(thetaDx - theta, thetaDy - theta) / eps;
    let defectStrength = length(dTheta) * 0.15;

    // Base painterly flowing field
    let irisColor = iridescent(theta, length(uvA - 0.5), mids, treble);

    // Background: dark with subtle directional tint
    var color = irisColor * (0.12 + bass * 0.08);

    // Flowing stripes along director
    let stripe = sin(dot(uvA, dir) * 30.0 * flowStrength + t * 0.5) * 0.5 + 0.5;
    color += irisColor * stripe * (0.25 + mids * 0.15) * irisIntensity;

    // Defect singularity highlight — bright cores
    let defectGlow = smoothstep(0.3, 0.0, defectStrength - 0.5);
    color += vec3<f32>(1.0, 0.8, 0.4) * defectGlow * (0.5 + treble * 0.5);

    // Intense singular cores (defect centers)
    let singularCore = pow(clamp(defectStrength * 2.0, 0.0, 1.0), 3.0);
    color += vec3<f32>(1.0, 1.0, 0.9) * singularCore * 2.0;

    // Oil-slick shimmer: second-order oscillation
    let shimmer = sin(theta * 4.0 + t * 2.0 + bass * PI) * 0.5 + 0.5;
    color += irisColor * shimmer * treble * 0.3;

    // Vignette
    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5));
    color *= v;

    // Depth for alpha modulation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Semantic alpha: presence-based with depth modulation
    let presence = clamp(length(color) * 1.5, 0.0, 1.0);
    let alpha = clamp(presence * (0.7 + depth * 0.3), 0.2, 0.95);

    // Chromatic aberration
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES tone mapping
    color = acesToneMap(color * 1.1);

    // Temporal feedback blend
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let decay = 0.97;
    color = mix(prev.rgb * decay, color, 0.2 + bass * 0.1);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
}
