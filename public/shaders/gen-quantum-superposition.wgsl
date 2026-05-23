// ═══════════════════════════════════════════════════════════════════
//  Quantum Superposition Lattice
//  Category: generative
//  Features: mouse-driven, audio-reactive, audio-driven, upgraded-rgba
//  Complexity: High
//  Created: 2026-03-14
//  Upgraded: 2026-05-23
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;
const PHI: f32 = 1.61803398874989484820;

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = fract(h) * 6.0;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    let rgb0 = vec3<f32>(c, x, 0.0);
    let rgb1 = vec3<f32>(x, c, 0.0);
    let rgb2 = vec3<f32>(0.0, c, x);
    let rgb3 = vec3<f32>(0.0, x, c);
    let rgb4 = vec3<f32>(x, 0.0, c);
    let rgb5 = vec3<f32>(c, 0.0, x);
    var rgb = rgb0;
    rgb = select(rgb, rgb1, h6 >= 1.0 && h6 < 2.0);
    rgb = select(rgb, rgb2, h6 >= 2.0 && h6 < 3.0);
    rgb = select(rgb, rgb3, h6 >= 3.0 && h6 < 4.0);
    rgb = select(rgb, rgb4, h6 >= 4.0 && h6 < 5.0);
    rgb = select(rgb, rgb5, h6 >= 5.0);
    return rgb + (v - c);
}

fn snoise_q(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    let n00 = fract(sin(dot(i,                   vec2<f32>(127.1, 311.7))) * 43758.5);
    let n10 = fract(sin(dot(i + vec2<f32>(1,0),  vec2<f32>(127.1, 311.7))) * 43758.5);
    let n01 = fract(sin(dot(i + vec2<f32>(0,1),  vec2<f32>(127.1, 311.7))) * 43758.5);
    let n11 = fract(sin(dot(i + vec2<f32>(1,1),  vec2<f32>(127.1, 311.7))) * 43758.5);
    return mix(mix(n00, n10, u2.x), mix(n01, n11, u2.x), u2.y);
}

fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }
fn hash2v(n: f32) -> vec2<f32> { return vec2<f32>(hash1(n), hash1(n + 57.3)); }

fn lissajousPos(t: f32, a: f32, b: f32, delta: f32, scale: f32, offset: vec2<f32>) -> vec2<f32> {
    return offset + vec2<f32>(cos(a * t + delta), sin(b * t)) * scale;
}

fn quantumGaussian(p: vec2<f32>, center: vec2<f32>, sigma: f32, phase: f32) -> vec2<f32> {
    let d2  = dot(p - center, p - center);
    let amp = exp(-d2 / (2.0 * sigma * sigma));
    return vec2<f32>(amp * cos(phase), amp * sin(phase));
}

fn standingWave(p: vec2<f32>, t: f32, freq: f32, speed: f32) -> f32 {
    return sin(p.x * freq - t * speed) * cos(p.y * freq * 0.7 + t * speed * 0.6);
}

fn collapseWeight(p: vec2<f32>, collapseCenter: vec2<f32>, r: f32) -> f32 {
    let d2 = dot(p - collapseCenter, p - collapseCenter);
    return 1.0 - exp(-d2 / (r * r));
}

fn fbm_qs(p: vec2<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 3; i++) {
        v += a * snoise_q(pp);
        pp = pp * 2.0 + vec2<f32>(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

fn zenoFactor(p: vec2<f32>, observeCenter: vec2<f32>, observeRadius: f32, t: f32) -> f32 {
    let d = length(p - observeCenter);
    let obs = exp(-d * d / (observeRadius * observeRadius * 4.0));
    return 1.0 - obs * 0.6 * abs(sin(t * 2.0));
}

fn heisenbergFog(prob: f32, sigma: f32) -> f32 {
    let posUncertainty = sigma;
    let momUncertainty = 1.0 / (posUncertainty * 50.0 + 0.1);
    return clamp(momUncertainty * 0.08, 0.0, 0.3);
}

fn fringeColor(pathDiff: f32, t: f32) -> vec3<f32> {
    let phase  = pathDiff * 12.0;
    let bright = pow(cos(phase) * 0.5 + 0.5, 3.0);
    return hsv2rgb(fract(phase * 0.08 + t * 0.05), 0.9, bright);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let res    = u.config.zw;
    let uv     = vec2<f32>(global_id.xy) / res;
    let t      = u.config.x;
    let mouse  = u.zoom_config.yz;

    let numParticles = i32(u.zoom_params.x * 7.0 + 1.5);
    let decoherence  = u.zoom_params.y * 0.08 + 0.005;
    let waveSpeed    = u.zoom_params.z * 2.0 + 0.3;
    let waveOpacity  = u.zoom_params.w * 1.5 + 0.2;

    let aspect = res.x / res.y;
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    let audioModSpeed = waveSpeed * (1.0 + bass * 0.3);
    let audioDecoherence = decoherence * (1.0 + mids * 0.2);
    let trebleSparkle = treble * 0.15;

    var totalRe    = 0.0;
    var totalIm    = 0.0;
    var totalProb  = 0.0;
    var colorAccum = vec3<f32>(0.0);

    for (var i = 0; i < numParticles; i++) {
        let seed = f32(i) * 17.3;
        let a    = hash1(seed)       * 3.0 + 1.0;
        let b    = hash1(seed + 1.0) * 3.0 + 1.0;
        let dlt  = hash1(seed + 2.0) * 6.28318;
        let scl  = hash1(seed + 3.0) * 0.3 + 0.15;
        let off  = (hash2v(seed + 4.0) - 0.5) * 0.3 * vec2<f32>(aspect, 1.0);

        let numGhosts  = 5;
        let ghostSpread = audioDecoherence * 3.0;

        for (var g = 0; g < numGhosts; g++) {
            let ghostT   = t * audioModSpeed * 0.2 + f32(g) * 6.28318 / f32(numGhosts);
            let basePos  = lissajousPos(ghostT, a, b, dlt, scl, off);
            let jitter   = bass * 0.04;
            let jitterOffset = vec2<f32>(
                sin(t * 3.0 + f32(g) * 1.3) * jitter,
                cos(t * 2.5 + f32(g) * 1.7) * jitter
            );
            let ghostPos = basePos + jitterOffset;
            let ghostPh  = t * audioModSpeed + f32(i) * 2.094 + f32(g) * 1.257;
            let sigma    = ghostSpread * (1.0 + hash1(seed + f32(g) * 7.7) * 0.5);

            let psi  = quantumGaussian(p, ghostPos, sigma, ghostPh);
            totalRe += psi.x;
            totalIm += psi.y;

            let prob = psi.x * psi.x + psi.y * psi.y;
            totalProb  += prob;

            let hue = fract(f32(i) / f32(max(numParticles, 1)) + 0.1);
            colorAccum += hsv2rgb(hue, 0.8, 1.0) * prob;
        }
    }

    let interference = standingWave(p * 12.0, t, 1.0, audioModSpeed * 0.15) * 0.15;

    let mPos     = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
    let collapse = collapseWeight(p, mPos, audioDecoherence * 8.0);
    let collapsedProb = totalProb * collapse;

    let ripCount = u32(u.config.y);
    var rippleCollapse = 1.0;
    for (var i: u32 = 0u; i < ripCount; i = i + 1u) {
        let r   = u.ripples[i];
        let age = t - r.z;
        let rippleActive = f32(age >= 0.0 && age <= 2.0);
        let rp = (r.xy - 0.5) * vec2<f32>(aspect, 1.0);
        let cr = audioDecoherence * 4.0 * (1.0 + age * 3.0);
        let rippleFactor = 1.0 - exp(-dot(p - rp, p - rp) / (cr * cr)) * exp(-age * 2.0);
        rippleCollapse *= mix(1.0, rippleFactor, rippleActive);
    }

    let normalizedProb = collapsedProb * rippleCollapse;
    let probColor = colorAccum / max(totalProb, 0.0001);
    let intColor = hsv2rgb(fract(t * 0.07 + 0.5), 0.6, 1.0) * (interference + 0.5) * 0.3;

    let vacuum = snoise_q(p * 20.0 + t * 0.1) * 0.03;
    let bg = hsv2rgb(fract(t * 0.03 + length(p) * 0.5), 0.4, 0.04 + vacuum);

    var col = bg + probColor * clamp(normalizedProb * 4.0, 0.0, 1.5) + intColor;

    let zeno = zenoFactor(p, mPos, audioDecoherence * 6.0, t);
    let zenoBright = (1.0 - zeno) * normalizedProb;
    col += hsv2rgb(fract(t * 0.08 + 0.15), 0.6, zenoBright * 0.5);

    let hFog = heisenbergFog(totalProb, audioDecoherence * 2.0);
    let fogColor = hsv2rgb(fract(t * 0.04 + 0.5 + length(p) * 0.3), 0.5, 1.0);
    col += fogColor * hFog;

    let hasFringes = f32(numParticles >= 2);
    let seed0 = 0.0; let seed1 = 17.3;
    let a0 = hash1(seed0) * 3.0 + 1.0; let b0 = hash1(seed0 + 1.0) * 3.0 + 1.0;
    let a1 = hash1(seed1) * 3.0 + 1.0; let b1 = hash1(seed1 + 1.0) * 3.0 + 1.0;
    let pos0 = lissajousPos(t * audioModSpeed * 0.2, a0, b0, hash1(seed0+2.0)*6.28, hash1(seed0+3.0)*0.3+0.15, (hash2v(seed0+4.0)-0.5)*0.3*vec2<f32>(aspect,1.0));
    let pos1 = lissajousPos(t * audioModSpeed * 0.2, a1, b1, hash1(seed1+2.0)*6.28, hash1(seed1+3.0)*0.3+0.15, (hash2v(seed1+4.0)-0.5)*0.3*vec2<f32>(aspect,1.0));
    let pathDiff = length(p - pos0) - length(p - pos1);
    let fringe = fringeColor(pathDiff, t);
    let fringeAmp = exp(-min(length(p-pos0), length(p-pos1)) * 3.0) * 0.3;
    col += fringe * fringeAmp * collapse * hasFringes;

    let vacEnergy = fbm_qs(p * 8.0 + t * 0.05) * 0.04;
    col += hsv2rgb(fract(t * 0.06 + length(p)), 0.4, vacEnergy);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let alpha = clamp(normalizedProb * 4.0 * waveOpacity + trebleSparkle, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
