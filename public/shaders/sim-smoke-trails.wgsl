// ═══════════════════════════════════════════════════════════════════
//  Sim: Smoke Trails
//  Category: simulation
//  Features: simulation, volumetric-smoke, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: vorticity confinement; altitude cooling
//  A packing: density, temp, vel.xy (raw). Display ACES RGB.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    return vec2<f32>((n4 - n3) / (2.0 * eps), (n1 - n2) / (2.0 * eps));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(gid.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let dims = vec2<i32>(resolution);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let densityScale = mix(0.5, 2.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let turbulence = mix(0.0, 2.0, u.zoom_params.y);
    let riseSpeed = mix(0.5, 3.0, u.zoom_params.z);
    let dissipation = mix(0.95, 0.995, u.zoom_params.w);

    let prevSmoke = stateAt(pixel, dims);
    var smokeDensity = prevSmoke.r;
    var smokeTemp = prevSmoke.g;
    var velX = prevSmoke.b;
    var velY = prevSmoke.a;

    let buoyancy = smokeTemp * riseSpeed * 0.01;
    velY += buoyancy;

    let curl = curlNoise(uv * 3.0 + time * 0.1);
    velX += curl.x * turbulence * 0.01;
    velY += curl.y * turbulence * 0.005;

    // Idea 1 — vorticity confinement: keep billow spin
    let left = stateAt(pixel + vec2<i32>(-1, 0), dims);
    let right = stateAt(pixel + vec2<i32>(1, 0), dims);
    let up = stateAt(pixel + vec2<i32>(0, -1), dims);
    let down = stateAt(pixel + vec2<i32>(0, 1), dims);
    let vort = (right.a - left.a) - (down.b - up.b);
    let vortL = abs((right.a - stateAt(pixel + vec2<i32>(-2, 0), dims).a) - (down.b - up.b));
    let vortR = abs((stateAt(pixel + vec2<i32>(2, 0), dims).a - left.a) - (down.b - up.b));
    let vortU = abs((right.a - left.a) - (down.b - stateAt(pixel + vec2<i32>(0, -2), dims).b));
    let vortD = abs((right.a - left.a) - (stateAt(pixel + vec2<i32>(0, 2), dims).b - up.b));
    var nGrad = vec2<f32>(vortR - vortL, vortD - vortU);
    let nLen = max(length(nGrad), 0.0001);
    nGrad = nGrad / nLen;
    // 2D N × omega (out of plane) → in-plane force
    velX += nGrad.y * vort * 0.015 * turbulence;
    velY += -nGrad.x * vort * 0.015 * turbulence;

    let advPx = pixel - vec2<i32>(vec2<f32>(velX, velY) * 3.0);
    let advectedSmoke = stateAt(advPx, dims);
    smokeDensity = advectedSmoke.r * dissipation;
    smokeTemp = advectedSmoke.g * dissipation;

    // Idea 2 — altitude cooling (fire tint dies as smoke rises)
    smokeTemp *= mix(1.0, 0.90, clamp(uv.y, 0.0, 1.0));

    let bottomSource = smoothstep(0.05, 0.0, uv.y) * hash12(vec2<f32>(uv.x * 10.0, time * 0.5)) * densityScale;
    smokeDensity += bottomSource * 0.05;
    smokeTemp += bottomSource * 0.1;

    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let mouseDist = length(uv - mousePos);
    let mouseSource = smoothstep(0.08, 0.0, mouseDist) * 0.2 * (1.0 + u.zoom_config.w * 0.8);
    smokeDensity += mouseSource;
    smokeTemp += mouseSource * 1.5;

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        if (ripple.z > 0.0) {
            let rippleAge = time - ripple.z;
            if (rippleAge > 0.0 && rippleAge < 4.0) {
                let rippleDist = length(uv - ripple.xy);
                let rippleSource = smoothstep(0.06, 0.0, rippleDist) * (1.0 - rippleAge / 4.0);
                smokeDensity += rippleSource * 0.3;
                smokeTemp += rippleSource * 0.5;
            }
        }
    }

    smokeDensity = clamp(smokeDensity, 0.0, 1.0);
    smokeTemp = clamp(smokeTemp, 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(smokeDensity, smokeTemp, velX * 0.99, velY * 0.99));

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let smokeGray = vec3<f32>(0.7, 0.7, 0.75);
    let fireColor = vec3<f32>(1.0, 0.4, 0.1);
    let smokeColor = mix(smokeGray, fireColor, smokeTemp * 0.7);
    let alphaVol = 1.0 - exp(-smokeDensity * 3.0);
    var hdr = mix(baseColor.rgb, smokeColor, alphaVol * 0.8);
    let glow = smokeTemp * smokeDensity * 0.3 * (1.0 + treble * 0.4);
    hdr += vec3<f32>(glow * 1.2, glow * 0.5, glow * 0.2);
    let mapped = aces(hdr);
    let alpha = clamp(baseColor.a * 0.4 + alphaVol * 0.6, 0.0, 1.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth * (1.0 - smokeDensity * 0.3), 0.0, 0.0, 0.0));
}
