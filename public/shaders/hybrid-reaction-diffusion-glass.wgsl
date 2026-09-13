// ═══════════════════════════════════════════════════════════════════
//  Hybrid Reaction-Diffusion Glass
//  Category: hybrid
//  Features: hybrid, reaction-diffusion, glass-distortion, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12
//  Ideas: thickness IOR from chemistry; caustic concentrate where ∇·grad < 0
//  A packing: raw (chem, |grad|, caustic, coverage)
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

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    let ct = clamp(cosTheta, 0.0, 1.0);
    return F0 + (1.0 - F0) * pow(1.0 - ct, 5.0);
}

fn chemAt(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
    return textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
}

fn laplacian(coord: vec2<i32>, dims: vec2<i32>) -> f32 {
    var sum: f32 = 0.0;
    let kernel = array<f32, 9>(0.05, 0.2, 0.05, 0.2, -1.0, 0.2, 0.05, 0.2, 0.05);
    var k: i32 = 0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let sample = chemAt(coord + vec2<i32>(i, j), dims);
            sum += sample * kernel[k];
            k++;
        }
    }
    return sum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(resolution);
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));

    let feedRate = mix(0.01, 0.1, u.zoom_params.x) * (1.0 + audio.y * 0.15);
    let killRate = mix(0.03, 0.07, u.zoom_params.y);
    let glassDistortion = mix(0.02, 0.1, u.zoom_params.z) * (1.0 + audio.z * 0.2);
    let depthInfluence = u.zoom_params.w;

    let cur = chemAt(id, dims);
    let lap = laplacian(id, dims);

    let reaction = cur * cur * cur;
    let feed = feedRate * (1.0 - cur);
    let kill = (killRate + feedRate) * cur;

    let mouse = u.zoom_config.yz;
    let distToMouse = distance(uv, mouse);
    var newChem = cur + lap * 0.2 - reaction + feed - kill;

    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    newChem += select(0.0, 0.1 * (1.0 - distToMouse / 0.05), distToMouse < 0.05) * (0.35 + held * 0.65 + audio.x * 0.2);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = resolution.x / max(resolution.y, 1.0);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let event = u.ripples[ri];
        let age = time - event.z;
        if (age >= 0.0 && age < 1.6) {
            let d = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
            clickFront += exp(-age * 2.0) * exp(-abs(d - age * 0.22) * 70.0);
        }
    }
    newChem += clickFront * 0.08;
    newChem = clamp(newChem, 0.0, 1.0);

    let cL = chemAt(id + vec2<i32>(-1, 0), dims);
    let cR = chemAt(id + vec2<i32>(1, 0), dims);
    let cT = chemAt(id + vec2<i32>(0, -1), dims);
    let cB = chemAt(id + vec2<i32>(0, 1), dims);
    let patternGradient = vec2<f32>(cR - cL, cB - cT);
    let gradMag = length(patternGradient);

    // Idea 2 — caustic concentrate where divergence is negative (focusing)
    let divG = (cR - 2.0 * cur + cL) + (cB - 2.0 * cur + cT);
    let caustic = max(-divG, 0.0) * (1.0 + audio.x * 0.35);

    let coverage = clamp(newChem * 0.7 + gradMag * 2.0 + caustic * 1.4, 0.0, 1.0);
    textureStore(dataTextureA, id, vec4<f32>(newChem, gradMag, caustic, coverage));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    // Idea 1 — thickness IOR: thicker chemistry bends more
    let thickness = 1.0 + newChem * (1.15 + u.zoom_params.z * 0.6);
    let distortionStrength = glassDistortion * (1.0 + depth * depthInfluence) * thickness;
    let frost = fbm2(uv * 6.0 + vec2<f32>(time * 0.04, 0.0), 2) * 0.015 * (1.0 - newChem);
    let refractUV = clamp(uv + patternGradient * distortionStrength + vec2<f32>(frost, -frost), vec2<f32>(0.0), vec2<f32>(1.0));
    let bgSample = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);
    let bgColor = bgSample.rgb;

    let rdColor = palette(newChem + time * 0.05,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 0.7, 0.4),
        vec3<f32>(0.0, 0.33, 0.67)
    );

    var color = mix(bgColor, rdColor, newChem * 0.7);
    color += vec3<f32>(1.0, 0.96, 0.85) * caustic * 0.55;

    let edge = gradMag;
    let fresnel = fresnelSchlick(1.0 - clamp(edge * 5.0, 0.0, 1.0), 0.1);
    color += vec3<f32>(0.9, 0.95, 1.0) * fresnel * 0.3;
    let specular = pow(fresnel, 4.0) * 0.5;
    color += vec3<f32>(specular);

    let mapped = aces(max(color, vec3<f32>(0.0)));
    let alpha = clamp(bgSample.a * 0.2 + mix(0.6, 0.95, newChem + fresnel * 0.5) + caustic * 0.25, 0.0, 1.0);

    textureStore(writeTexture, id, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(depth * (1.0 - newChem * 0.3), 0.0, 0.0, 0.0));
}
