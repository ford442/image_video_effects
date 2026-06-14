// ═══════════════════════════════════════════════════════════════════
//  Directional Glitch
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, temporal-feedback,
//            chromatic-aberration, depth-aware, hdr, tonemapped
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
const PHI: f32 = 1.61803398875;

// ── Canonical hash / noise ────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}

// Divergence-free velocity field for organic glitch drift
fn curl2D(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.001;
    let nx = fbm(p + vec2<f32>(0.0, eps), 3) - fbm(p - vec2<f32>(0.0, eps), 3);
    let ny = fbm(p + vec2<f32>(eps, 0.0), 3) - fbm(p - vec2<f32>(eps, 0.0), 3);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Color / tone mapping ──────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    let r_high = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
    let r = mix(1.0, r_high, step(66.0, t));
    let g_low = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
    let g_high = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
    let g = mix(g_low, g_high, step(66.0, t));
    let b_mid = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0);
    let b = mix(mix(0.0, b_mid, step(19.0, t)), 1.0, step(66.0, t));
    return vec3<f32>(r, g, b);
}

fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01 = vec2<f32>(pixel) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;

    let intensity = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let scatter = u.zoom_params.z;
    let angle_bias = u.zoom_params.w;

    // Mouse-distance mask with depth awareness
    let aspect = res.x / max(res.y, 1.0);
    let uv_c = vec2<f32>(uv01.x * aspect, uv01.y);
    let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uv_c, mouse_c);
    let mask = smoothstep(radius, 0.0, dist) * (0.5 + 0.5 * clamp(depth, 0.0, 1.0));

    // Directional + divergence-free displacement
    let angle = atan2(uv01.y - mouse.y, uv01.x - mouse.x) + angle_bias * TAU;
    let radial = vec2<f32>(cos(angle), sin(angle));
    let curl = curl2D(uv01 * 6.0 + mouse * 2.0 + vec2<f32>(time * 0.1));
    let dir = normalize(mix(radial, curl, 0.35 * intensity) + vec2<f32>(0.0001));

    // Domain-warped FBM drives the glitch blocks
    let noiseScale = 8.0 + scatter * 64.0;
    let warp = domainWarp(uv01 * noiseScale + vec2<f32>(time * 0.3), intensity * 0.5, 3);
    let field = fbm(warp + bass * 0.5, 4);
    let glitchMask = step(1.0 - scatter * 0.7, field);

    let disp = glitchMask * intensity * mask * (0.04 + bass * 0.03);
    let caAmount = disp * 3.0 + depth * 0.001 + bass * 0.001;

    // Sample input with chromatic separation along the displacement vector
    let aberrated = chromaticAberration(uv01, caAmount);
    var glitch = aberrated * (1.0 + disp * 12.0);

    // Audio-reactive blackbody color and sparkle
    let temp = mix(2200.0, 14000.0, clamp(bass * 0.7 + field * 0.4, 0.0, 1.0));
    glitch *= blackbodyRGB(temp);
    let spark = hash21(uv01 * 300.0 + vec2<f32>(time * 15.0));
    glitch += vec3<f32>(spark * mask * intensity * 0.5 * (1.0 + bass));

    // Blend with original based on glitch strength
    let original = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
    let mixFactor = clamp(mask * glitchMask * intensity, 0.0, 1.0);
    var color = mix(original, glitch, mixFactor);

    // Temporal feedback trail
    let prev = textureLoad(dataTextureC, pixel, 0);
    let decay = 0.97 - intensity * 0.03;
    color = mix(prev.rgb * decay, color, 0.2 + bass * 0.1);

    // Tone map and semantic alpha
    color = acesToneMap(color * (0.9 + mids * 0.25));
    let alpha = clamp(mixFactor * (0.8 + depth * 0.25) + bass * 0.05, 0.15, 0.95);

    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
    textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
