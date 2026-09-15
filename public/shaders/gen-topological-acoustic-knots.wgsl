// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: opposite-charge pair annihilation; Schlieren brushes from |∇θ|
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Orientational director field inspired by liquid crystals.
//  Audio frequencies drive topological defect creation, motion, and
//  annihilation. Mouse can pin or create defects. Iridescent oil-slick coloring.

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
  config: vec4<f32>,       // x=Time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Defect Density, y=Defect Speed, z=Iridescence, w=Flow Strength
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn defectOrbit(fi: f32, t: f32, bass: f32, treble: f32, numDefects: f32, defectSpeed: f32) -> vec2<f32> {
    let seed = hash22(vec2<f32>(fi, fi * 1.7 + 3.1));
    let orbitRadius = 0.2 + seed.x * 0.3;
    let orbitSpeed = defectSpeed * (0.5 + fi * 0.13);
    let audioMod = mix(bass, treble, fi / max(numDefects, 1.0));
    let px = seed.x * 0.6 + 0.2 + orbitRadius * cos(t * orbitSpeed + seed.y * TAU + audioMod * 0.5);
    let py = seed.y * 0.6 + 0.2 + orbitRadius * sin(t * orbitSpeed * 0.7 + seed.x * TAU + audioMod * 0.3);
    return vec2<f32>(px, py);
}

fn directorAngle(uv: vec2<f32>, t: f32, bass: f32, mids: f32, treble: f32,
                 mousePos: vec2<f32>, defectDensity: f32, defectSpeed: f32) -> f32 {
    var angle = 0.0;
    let numDefects = i32(clamp(defectDensity * 8.0 + 2.0, 2.0, 12.0));
    let nF = f32(numDefects);

    for (var i = 0; i < numDefects; i++) {
        let fi = f32(i);
        let defectPos = defectOrbit(fi, t, bass, treble, nF, defectSpeed);

        // Idea 1 — pair annihilation: opposite-charge neighbors fade when close.
        let partnerIdx = select(i + 1, i - 1, (i % 2) == 1);
        let unpaired = (i == numDefects - 1) && ((numDefects % 2) == 1);
        let partnerPos = defectOrbit(f32(partnerIdx), t, bass, treble, nF, defectSpeed);
        let live = select(smoothstep(0.04, 0.16, length(defectPos - partnerPos)), 1.0, unpaired);

        let charge = select(-0.5, 0.5, (i % 2) == 0) * live;
        let delta = uv - defectPos;
        angle += atan2(delta.y, delta.x) * charge;
    }

    let mouseDelta = uv - mousePos;
    let mouseDist = length(mouseDelta);
    let mouseInfluence = exp(-mouseDist * mouseDist * 20.0);
    let mouseDefectAngle = atan2(mouseDelta.y, mouseDelta.x) * 0.5;
    angle += mouseDefectAngle * mouseInfluence * (1.0 + mids * 2.0);

    return angle;
}

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
    let coord = vec2<i32>(global_id.xy);

    let uv = vec2<f32>(global_id.xy) / res;
    let aspect = res.x / max(res.y, 1.0);
    let uvA = vec2<f32>(uv.x * aspect, uv.y);

    let t = u.config.x;
    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let defectDensity = u.zoom_params.x;
    let defectSpeed   = u.zoom_params.y * 0.8 + 0.1;
    let irisIntensity = u.zoom_params.z * 1.5 + 0.5;
    let flowStrength  = u.zoom_params.w * 2.0 + 0.5;

    let mousePos = vec2<f32>(u.zoom_config.y * aspect, u.zoom_config.z);

    let theta = directorAngle(uvA, t, bass, mids, treble,
                               mousePos, defectDensity, defectSpeed);
    let dir = vec2<f32>(cos(theta), sin(theta));

    let eps = 0.008;
    let thetaDx = directorAngle(uvA + vec2<f32>(eps, 0.0), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed);
    let thetaDy = directorAngle(uvA + vec2<f32>(0.0, eps), t, bass, mids, treble,
                                  mousePos, defectDensity, defectSpeed);

    let dTheta = vec2<f32>(thetaDx - theta, thetaDy - theta) / eps;
    let defectStrength = length(dTheta) * 0.15;

    let irisColor = iridescent(theta, length(uvA - 0.5), mids, treble);
    var color = irisColor * (0.12 + bass * 0.08);

    let stripe = sin(dot(uvA, dir) * 30.0 * flowStrength + t * 0.5) * 0.5 + 0.5;
    color += irisColor * stripe * (0.25 + mids * 0.15) * irisIntensity;

    let defectGlow = smoothstep(0.3, 0.0, defectStrength - 0.5);
    color += vec3<f32>(1.0, 0.8, 0.4) * defectGlow * (0.5 + treble * 0.5);

    let singularCore = pow(clamp(defectStrength * 2.0, 0.0, 1.0), 3.0);
    color += vec3<f32>(1.0, 1.0, 0.9) * singularCore * 2.0;

    let shimmer = sin(theta * 4.0 + t * 2.0 + bass * PI) * 0.5 + 0.5;
    color += irisColor * shimmer * treble * 0.3;

    // Idea 2 — Schlieren brushes from |∇θ| along the director.
    let schlieren = abs(sin(theta * 2.0)) * smoothstep(0.08, 0.45, defectStrength);
    color = color * (1.0 - schlieren * 0.4) + irisColor * schlieren * 0.12;

    let v = 1.0 - smoothstep(0.3, 0.8, length(uv - 0.5));
    color *= v;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let presence = clamp(length(color) * 1.5, 0.0, 1.0);
    let alpha = clamp(presence * (0.7 + depth * 0.3) + schlieren * 0.15, 0.2, 0.95);

    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
    color = acesToneMap(color * 1.1);

    let prev = textureLoad(dataTextureC, coord, 0);
    color = mix(prev.rgb * 0.97, color, 0.2 + bass * 0.1);

    let outCol = vec4<f32>(color, alpha);
    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
