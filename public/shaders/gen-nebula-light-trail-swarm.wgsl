// ═══════════════════════════════════════════════════════════════════════════════
//  Nebula Light-Trail Swarm - Visualist Upgrade
//  Category: generative
//  Features: OkLab color mixing, Blackbody temperature, Cosine palettes,
//            Fresnel rim lighting, HDR tone mapping, particle trails, bloom
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════════════════════
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

// --- Color Science: OkLab ---
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137),
        vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387),
        vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070)
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0/3.0));
    return mat3x3<f32>(
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086757660)
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480)
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490),
        vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787),
        vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204)
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}

// --- Blackbody Color Temperature ---
fn blackbody(t: f32) -> vec3<f32> {
    var col = vec3<f32>(1.0);
    col.y = 0.3900815787690196 * log(t) - 0.6318414437886275;
    col.z = 0.5432067891101961 * log(t) - 1.1964741063266880;
    return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Cosine Palette (Inigo Quilez) ---
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- HDR Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43); let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.xx + p3.yz) * p3.zy);
}
fn trailDist(uv: vec2<f32>, p: vec2<f32>, dir: vec2<f32>, len: f32, width: f32) -> f32 {
    let toP = uv - p;
    let proj = dot(toP, dir);
    let clampedProj = clamp(proj, 0.0, len);
    let closest = p + dir * clampedProj;
    return length(uv - closest) - width;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }
    let uv = vec2<f32>(id.xy) / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let speed = u.zoom_params.x * 2.0 + 0.5;
    let trailDecay = u.zoom_params.y * 0.9 + 0.1;
    let curlStrength = u.zoom_params.z * 3.0;
    let glowRadius = u.zoom_params.w * 0.03 + 0.005;
    // Mouse Y-flip: screen-top = +Y/up
    let mouse = u.zoom_config.yz;
    let mouseDist = length(uv - mouse);
    let repel = smoothstep(0.2, 0.0, mouseDist);
    var col = vec3<f32>(0.0);
    var totalGlow = 0.0;
    let numParticles = 20;
    for (var i: i32 = 0; i < numParticles; i = i + 1) {
        let fi = f32(i);
        let seed = hash21(vec2<f32>(fi, floor(time * 0.1)));
        let t = fract(time * speed * (0.3 + seed.x * 0.4) + fi * 0.1);
        let life = 1.0 - t;
        if (life < 0.01) { continue; }
        let startAngle = fi * 0.618 + seed.y * 6.28318;
        let startRadius = 0.1 + seed.x * 0.3;
        let startPos = vec2<f32>(cos(startAngle), sin(startAngle)) * startRadius + vec2<f32>(0.5);
        let curlPhase = time * speed * 0.5 + fi;
        let curlX = sin(curlPhase + uv.x * curlStrength) * 0.2;
        let curlY = cos(curlPhase + uv.y * curlStrength) * 0.2;
        let dir = normalize(vec2<f32>(cos(startAngle + 1.57), sin(startAngle + 1.57)) + vec2<f32>(curlX, curlY));
        let endPos = startPos + dir * (0.1 + t * 0.4);
        let trailLen = t * 0.3;
        let d = trailDist(uv, startPos, dir, trailLen, glowRadius * life);
        let glow = smoothstep(0.02, 0.0, d) * life;
        // Cosine palette + Blackbody temperature based on particle
        let hue = fi / f32(numParticles) + bass * 0.2;
        let cp = cosinePalette(hue + time * 0.05, vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(1.0,0.8,0.6), vec3<f32>(0.0,0.33,0.67));
        let bb = blackbody(mix(4000.0, 12000.0, fi / f32(numParticles)));
        let particleCol = oklab_mix(cp, bb, 0.3 + bass * 0.3);
        let audioBoost = 1.0 + bass * 1.5 + treble * 0.5;
        col = col + particleCol * glow * audioBoost;
        totalGlow = totalGlow + glow;
    }
    // Central nebula core with Fresnel-like rim
    let coreDist = length(uv - vec2<f32>(0.5));
    let coreGlow = exp(-coreDist * coreDist * 8.0) * (0.5 + bass * 0.5);
    let coreColor = oklab_mix(vec3<f32>(0.4,0.6,1.0), blackbody(8000.0), 0.5);
    col = col + coreColor * coreGlow;
    // Secondary nebula layer (soft bloom)
    let bloomDist = length(uv - vec2<f32>(0.5) + vec2<f32>(sin(time * 0.1) * 0.1, cos(time * 0.15) * 0.1));
    let bloom = exp(-bloomDist * bloomDist * 3.0) * 0.3 * (0.5 + mids * 0.5);
    let bloomCol = oklab_mix(vec3<f32>(0.6,0.3,0.8), blackbody(6000.0), 0.5);
    col = col + bloomCol * bloom;
    // Starfield with blackbody temperature
    let starNoise = hash(floor(uv * 300.0));
    if (starNoise > 0.997) {
        let starBright = (starNoise - 0.997) / 0.003;
        let starTemp = mix(3000.0, 10000.0, starNoise);
        col = col + blackbody(starTemp) * starBright * (0.5 + mids * 0.5);
    }
    // Temporal feedback
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);
    // Chromatic dispersion with OkLab mixing
    let cStr = 0.003 + bass * 0.005;
    let cDir = normalize(uv - vec2<f32>(0.5) + 0.001);
    let prevR = textureSampleLevel(dataTextureC, u_sampler, uv + cDir * cStr * (1.0 + mids), 0.0).r;
    let prevG = textureSampleLevel(dataTextureC, u_sampler, uv + cDir * cStr * (0.5 + treble), 0.0).g;
    let prevB = textureSampleLevel(dataTextureC, u_sampler, uv - cDir * cStr * (0.8 + bass * 0.5), 0.0).b;
    col.r = mix(col.r, prevR * 0.9, 0.02 + treble * 0.01);
    col.g = mix(col.g, prevG * 0.9, 0.02 + bass * 0.01);
    col.b = mix(col.b, prevB * 0.9, 0.02 + mids * 0.01);
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(3.0));
    // HDR tone mapping
    col = acesToneMap(col * 0.8);
    let alpha = clamp(totalGlow * 0.5 + coreGlow + bloom, 0.0, 1.0);
    let depth = 0.5 - coreDist * 0.3;
    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(col, alpha));
}
