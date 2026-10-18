// ═══════════════════════════════════════════════════════════════════
//  Mouse Ink Bleed
//  Category: interactive-mouse
//  Features: upgraded-rgba, mouse-driven, audio-reactive, ink-diffusion,
//            organic, domain-warp, temporal-feedback, depth-aware,
//            gravity-well, click-shockwave, paper-wicking, tide-line, emergent-feedback,
//            aces-tone-map, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
//  Updated: 2026-07-12 (retry expansion)
//  Upgraded: 2026-10-04
//  Ideas: paper-fibre wicking of a wet-ink field; tide-line pigment rim at the drying front
//  A packing: (trail rgb, wet-ink amount) — HEAD stored a per-pixel bass envelope in .a
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
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;


fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i++) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    let f = fract(sin(dot(p, vec2<f32>(17.0, 43.0))) * 144.7);
    return fract(f * 0.5 + 0.5);
}
fn safeNormalize(v: vec2<f32>) -> vec2<f32> {
    let len = length(v);
    return select(v / len, vec2<f32>(0.0), len < 0.0001);
}
fn shockwave(uv: vec2<f32>, clickPos: vec2<f32>, age: f32) -> vec2<f32> {
    let radius = age * 0.5;
    let delta = uv - clickPos;
    let dRing = length(delta);
    let arg = (dRing - radius) * 14.0;
    let ring = exp(-arg * arg);
    let strength = ring * (1.0 - age * 0.833) * 0.06;
    return safeNormalize(delta) * strength;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }
    let pixel = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let isPress = u.zoom_config.w;

    let spread = mix(0.01, 0.5, clamp(u.zoom_params.x, 0.0, 1.0));
    let turbulence = clamp(u.zoom_params.y, 0.0, 1.0);
    let decay = mix(0.85, 0.995, clamp(u.zoom_params.z, 0.0, 1.0));
    let colorIntensity = clamp(u.zoom_params.w, 0.0, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let maxPx = vec2<i32>(res) - vec2<i32>(1);
    let prev = textureLoad(dataTextureC, pixel, 0);
    // Stateless audio envelope (A.a now carries wet ink, not a per-pixel bass copy).
    let env = clamp(bass * 0.85 + mids * 0.15, 0.0, 1.5);

    // Floor fix: HEAD kept spring/click state in extraBuffer[0..7], written by every
    // thread and re-uploaded each frame, with config.y (ripple count) used as dt — the
    // well sat near the top-left corner. The well now centres on the cursor and the
    // shockwave follows the newest live click in u.ripples.
    let smoothMouse = mouse;
    var clickTime = -10.0;
    var clickPos = mouse;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let r = u.ripples[ri];
        if (r.z > clickTime && r.z <= time) {
            clickTime = r.z;
            clickPos = r.xy;
        }
    }

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let dist = length(uv - mouse);
    let activeBrush = smoothstep(spread * 0.6, spread * 0.08, dist) * (0.6 + isPress * 1.2);
    let inkRadius = activeBrush * (0.7 + env * 0.5);

    let warpUv = domainWarp(uv * (3.0 + turbulence * 5.0) + vec2<f32>(time * 0.05), turbulence * (1.0 + treble), 3);
    let gradX = fbm(warpUv + vec2<f32>(0.02, 0.0), 3) - fbm(warpUv - vec2<f32>(0.02, 0.0), 3);
    let gradY = fbm(warpUv + vec2<f32>(0.0, 0.02), 3) - fbm(warpUv - vec2<f32>(0.0, 0.02), 3);
    var displacement = vec2<f32>(gradX, gradY) * inkRadius * spread * 2.5;

    // ---- mouse gravity well (smooth, lagging center) ----
    let toWell = smoothMouse - uv;
    let wellDist = length(toWell);
    let gravityRadius = spread * 1.6;
    let gravityStrength = smoothstep(gravityRadius, 0.0, wellDist) * (0.04 + env * 0.03 + bass * 0.02);
    let angle = atan2(toWell.y, toWell.x);
    let vortex = vec2<f32>(-sin(angle), cos(angle)) * gravityStrength * (0.5 + isPress * 0.8);
    displacement = displacement + toWell * gravityStrength * 3.0 + vortex;

    // ---- click shockwave ----
    let age = time - clickTime;
    var shockStrength = 0.0;
    if (age < 1.2) {
        displacement = displacement + shockwave(uv, clickPos, age) * (1.0 + env);
        let radius = age * 0.5;
        let delta = uv - clickPos;
        let dRing = length(delta);
        let arg = (dRing - radius) * 14.0;
        shockStrength = exp(-arg * arg) * (1.0 - age * 0.833) * 2.5;
    }

    // ---- emergent feedback loop: previous color energy warps current ink ----
    let feedbackEnergy = length(prev.rgb);
    displacement = displacement + safeNormalize(displacement) * feedbackEnergy * 0.015 * (1.0 + mids);

    let displacedUV = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let inkTint = vec3<f32>(0.18, 0.12, 0.28) + vec3<f32>(0.1, 0.05, 0.12) * env;
    let inkColor = mix(vec3<f32>(luminance), color * inkTint, 0.4 + mids * 0.2);
    color = mix(color, inkColor, inkRadius * colorIntensity);

    let edgeGlow = smoothstep(0.1, 0.6, inkRadius) * (1.0 - smoothstep(0.4, 0.9, inkRadius));
    color = color + vec3<f32>(0.06, 0.03, 0.1) * edgeGlow * colorIntensity * (0.8 + mids * 0.4);

    // ---- shockwave ink splash ----
    color = color + inkTint * shockStrength * colorIntensity * (0.8 + treble);

    // ---- Idea 1: paper-fibre wicking ----
    // Wet ink (A.a) diffuses into its 4 neighbours weighted by alignment with a local fibre
    // direction, faster along fibre strands; the stored trail pigment is carried with it,
    // so ink creeps out in hairline feathers like ink on rice paper.
    let cR = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(1, 0), vec2<i32>(0), maxPx), 0);
    let cL = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(1, 0), vec2<i32>(0), maxPx), 0);
    let cD = textureLoad(dataTextureC, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), maxPx), 0);
    let cU = textureLoad(dataTextureC, clamp(pixel - vec2<i32>(0, 1), vec2<i32>(0), maxPx), 0);
    let fibreAngle = valueNoise(uv * vec2<f32>(14.0, 11.0)) * TAU;
    let fibre = vec2<f32>(cos(fibreAngle), sin(fibreAngle));
    let wX = 0.2 + 0.8 * fibre.x * fibre.x;
    let wY = 0.2 + 0.8 * fibre.y * fibre.y;
    let strandCoord = vec2<f32>(dot(uv, fibre), dot(uv, vec2<f32>(-fibre.y, fibre.x))) * vec2<f32>(60.0, 900.0);
    let strand = smoothstep(0.45, 0.8, valueNoise(strandCoord));
    let wetNbr = ((cR.a + cL.a) * wX + (cD.a + cU.a) * wY) / (2.0 * (wX + wY));
    let pigmentNbr = ((cR.rgb + cL.rgb) * wX + (cD.rgb + cU.rgb) * wY) / (2.0 * (wX + wY));
    let wick = (0.25 + 0.65 * strand) * (0.6 + turbulence * 0.3);
    let dryRate = mix(0.975, 0.996, clamp(u.zoom_params.z, 0.0, 1.0));
    let prevWet = clamp(prev.a, 0.0, 1.0);
    let wetSpread = prevWet + (wetNbr - prevWet) * wick;
    let newWet = clamp(max(wetSpread * dryRate, inkRadius * 0.9 + shockStrength * 0.15), 0.0, 1.0);

    var trail = mix(prev.rgb * decay, color, 0.08 + inkRadius * 0.25);
    let carry = wick * smoothstep(0.02, 0.25, wetNbr) * step(prevWet, wetNbr) * 0.5;
    trail = mix(trail, pigmentNbr, carry);
    color = mix(color, trail, 0.55);
    color = mix(color, color * inkTint * 2.2, newWet * colorIntensity * 0.45);

    // ---- Idea 2: tide-line rim ----
    // Where the wet front is steep and the ink is part-dry, pigment piles up at the edge
    // (coffee-ring deposit) — a darker rim that is also written into the trail so it stays.
    let wetGrad = length(vec2<f32>(cR.a - cL.a, cD.a - cU.a));
    let rim = smoothstep(0.03, 0.18, wetGrad) * smoothstep(0.04, 0.25, newWet) * (1.0 - smoothstep(0.55, 0.9, newWet));
    color = color * (1.0 - rim * 0.5 * colorIntensity);
    trail = mix(trail, trail * 0.55, rim * 0.25);

    let fog = 1.0 - exp(-depth * 2.5);
    color = mix(color, color * 0.65 + vec3<f32>(0.02), fog * 0.35);

    color = acesToneMap(color * (0.95 + env * 0.15));
    color = color + (ign(vec2<f32>(global_id.xy)) - 0.5) * 0.006;

    let effect = inkRadius * 0.7 + edgeGlow * 0.5 + shockStrength * 0.4 + newWet * 0.3 + rim * 0.3;
    let semantic_alpha = clamp(baseColor.a * (0.5 + effect * 0.6), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(color, semantic_alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(trail, newWet));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
