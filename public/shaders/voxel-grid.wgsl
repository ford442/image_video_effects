// ═══════════════════════════════════════════════════════════════════
//  Voxel Grid
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, domain-warp, curl-noise,
//            temporal-feedback, depth-aware, aces-tone-map,
//            chromatic-aberration, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-14
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash & noise ─────────────────────────────────────────────────
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
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0; a *= 0.5;
    }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Geometry ─────────────────────────────────────────────────────
fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle); let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}
fn sdBox2(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

// ── Color ────────────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(value), smoothRgb * value, saturation);
}
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift = vec2<f32>(cos(angle), sin(angle)) * strength;
    return vec3<f32>(color.r * (1.0 + shift.x * 0.8), color.g, color.b * (1.0 - shift.y * 0.5));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let uv   = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    let grid_density = u.zoom_params.x;
    let touch_radius = u.zoom_params.y;
    let rotation_strength = u.zoom_params.z;
    let cell_gap = u.zoom_params.w;

    // Organic flow field warps the grid
    let warpUv = domainWarp(uv * 2.0 + vec2<f32>(time * 0.07, time * 0.05), 0.35 + mids * 0.2, 4);
    let curl = curl2D(warpUv * 3.0 + vec2<f32>(time * 0.11, -time * 0.08));

    // Grid cell lookup with warped coordinates
    let gridCoord = uv01 + curl * 0.02 + bass * 0.01;
    let gridId = floor(gridCoord * grid_density);
    let gridFract = fract(gridCoord * grid_density);
    let cellCenter = (gridId + 0.5) / grid_density;

    // Mouse proximity influence
    let aspect = res.x / res.y;
    let distVec = (cellCenter - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let influence = smoothstep(touch_radius, 0.0, dist);

    // Rotation driven by curl + mouse + audio
    let angle = rotation_strength * (influence * PI + dot(curl, vec2<f32>(1.0)) * 0.5 + bass * 0.4);
    let local = rot2(angle) * (gridFract - 0.5);

    // SDF cell with audio pop
    let scale = 0.5 - cell_gap * 0.5;
    let pop = influence * 0.25 + bass * 0.12 + mids * 0.06;
    let box = sdBox2(local, vec2<f32>(scale + pop));

    // Voxel dome normal
    let n2 = local / max(scale + pop, 0.001);
    let nz = sqrt(max(0.0, 1.0 - dot(n2, n2)));
    let normal = normalize(vec3<f32>(n2, nz));

    // Lighting
    let keyDir = normalize(vec3<f32>(-0.5, 0.7, 0.5));
    let fillDir = normalize(vec3<f32>(0.6, 0.2, 0.4));
    let keyLit = max(dot(normal, keyDir), 0.0);
    let fillLit = max(dot(normal, fillDir), 0.0) * 0.35;
    let fresnel = pow(1.0 - max(dot(normal, vec3<f32>(0.0, 0.0, 1.0)), 0.0), 3.0);

    // Color: sampled image + psychedelic audio-reactive palette
    let cellColor = textureSampleLevel(readTexture, u_sampler, clamp(cellCenter, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    let palette = psychedelicPalette(time * 0.08 + influence + fbm(uv * 4.0, 3) + u.zoom_params.x * 0.2);
    let base = mix(cellColor, palette, 0.35 + influence * 0.35 + bass * 0.15);
    let lit = base * (keyLit * 1.2 + fillLit * 0.6) + fresnel * vec3<f32>(0.4, 0.7, 1.0) * (0.5 + treble * 0.5);
    var color = lit * (1.3 + influence * 0.7 + bass * 0.4 + treble * 0.2);

    // Soft-edged mask from SDF
    let edgeWidth = 0.004 + cell_gap * 0.01;
    let mask = 1.0 - smoothstep(-edgeWidth, edgeWidth, box);

    // Temporal feedback trail
    let decay = 0.96 - cell_gap * 0.04;
    color = mix(prev.rgb * decay, color, 0.18 + influence * 0.12 + bass * 0.08);

    // Chromatic aberration + ACES
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    color = genChromaticShift(color, uv01, caStr);
    color = acesToneMap(color * (0.95 + mids * 0.15));

    // Semantic alpha: luminance * influence * depth blend
    let alpha = clamp(luma(color) * 1.4 + influence * 0.35 + bass * 0.15, 0.15, 0.95) * (0.75 + depth * 0.25);
    let maskedAlpha = alpha * mask;
    let outColor = vec4<f32>(color * maskedAlpha, maskedAlpha);

    textureStore(writeTexture, pixel, outColor);
    textureStore(dataTextureA, pixel, outColor);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
