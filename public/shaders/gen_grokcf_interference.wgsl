// ═══════════════════════════════════════════════════════════════════
//  Chladni Plate Cymatics v2 - Audio-reactive modal synthesis
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural,
//            organic, animated
//  Scientific basis: Chladni figures from vibrating plate standing waves
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: Fibonacci spiral self-organization on high audio,
//                      iridescent oil-slick interference on plate surface
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

const MODES: array<vec4<f32>, 8> = array<vec4<f32>, 8>(
    vec4<f32>(1.0, 1.0, 1.0, 0.0),
    vec4<f32>(2.0, 1.0, 0.8, 0.5),
    vec4<f32>(1.0, 2.0, 0.8, 0.3),
    vec4<f32>(2.0, 2.0, 0.6, 0.7),
    vec4<f32>(3.0, 1.0, 0.5, 0.2),
    vec4<f32>(1.0, 3.0, 0.5, 0.9),
    vec4<f32>(3.0, 2.0, 0.4, 0.4),
    vec4<f32>(2.0, 3.0, 0.4, 0.6)
);

fn hash2(p: vec2<f32>) -> f32 {
    let k = vec2<f32>(0.3183099, 0.3678794);
    let x = p * k + k.yx;
    return fract(16.0 * k.x * fract(x.x * x.y * (x.x + x.y)));
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uS = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i + vec2<f32>(0.0, 0.0)), hash2(i + vec2<f32>(1.0, 0.0)), uS.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), uS.x),
        uS.y
    );
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Audio reactivity from plasmaBuffer
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Domain-specific parameters
    let sweepBase = u.zoom_params.x * 2.0 + 0.1;
    let sweepSpeed = sweepBase * (1.0 + bass * 0.8);          // Sweep Speed (bass-driven)
    let numModes = i32(clamp(u.zoom_params.y * 8.0 + 1.0, 1.0, 8.0));  // Mode Count
    let sharpness = u.zoom_params.z * 3.0 + 0.5;              // Pattern Sharpness
    let particleDensityBase = u.zoom_params.w;
    let particleDensity = clamp(particleDensityBase + mids * 0.25, 0.0, 1.0); // Sand Density (mids)

    let plateUV = (uv - 0.5) * 2.0;
    let x = plateUV.x;
    let y = plateUV.y;

    let baseFreq = 3.14159265 * (1.0 + sin(time * sweepSpeed * 0.2) * 0.5);

    var displacement = 0.0;
    for (var i: i32 = 0; i < 8; i = i + 1) {
        if (i >= numModes) { break; }
        let mode = MODES[i];
        let m = mode.x;
        let n = mode.y;
        let amp = mode.z;
        let phase = mode.w * 6.28318;

        let kx = m * baseFreq;
        let ky = n * baseFreq;

        let modeOscillation = cos(time * sweepSpeed + phase + f32(i) * 0.5);
        let modeDisplacement = sin(kx * x) * sin(ky * y) * modeOscillation * amp;
        displacement = displacement + modeDisplacement;
    }
    displacement = displacement / max(f32(numModes), 1.0);

    // Mouse disturbance
    let mouseDist = length(plateUV - (mouse - 0.5) * 2.0);
    let mouseInfluence = exp(-mouseDist * 8.0) * sin(time * 10.0 + mouseDist * 20.0);
    displacement = displacement + mouseInfluence * 0.3;

    // ─── Creative addition: Fibonacci spiral self-organization at high audio ───
    let totalAudio = (bass + mids + treble) / 3.0;
    let phyllotaxis = smoothstep(0.55, 0.95, totalAudio);
    if (phyllotaxis > 0.001) {
        let r = length(plateUV);
        let theta = atan2(plateUV.y, plateUV.x);
        let goldenAngle = 2.39996323;
        let spiralPhase = theta - r * 12.0 + time * 0.6;
        let spiral = cos(spiralPhase * (goldenAngle * 2.0));
        displacement = mix(displacement, displacement + spiral * 0.4, phyllotaxis);
    }

    let nodeMask = 1.0 - smoothstep(0.0, 0.15 / sharpness, abs(displacement));
    let vibrationEnergy = abs(displacement);
    let particleSettling = 1.0 - smoothstep(0.0, 0.3, vibrationEnergy);

    let sandNoise = noise2(uv * 400.0 + time * 0.1);
    let sandDetail = noise2(uv * 150.0 - time * 0.05);
    // Treble adds high-frequency shimmer to the sand texture
    let shimmer = noise2(uv * 1200.0 + time * 6.0) * treble * 0.35;

    let particleThreshold = 0.6 - particleDensity * 0.4;
    let particleMask = step(particleThreshold, particleSettling + sandNoise * 0.15 + shimmer * 0.5);

    let sandColor = vec3<f32>(0.85, 0.78, 0.65) * (0.8 + sandDetail * 0.4 + shimmer);
    let plateColor = vec3<f32>(0.15, 0.12, 0.10) * (1.0 + vibrationEnergy * 0.5);

    let patternHue = sin(displacement * 10.0 + time * 0.5) * 0.5 + 0.5;
    let interferenceColor = mix(
        vec3<f32>(0.9, 0.85, 0.7),
        vec3<f32>(0.6, 0.7, 0.8),
        patternHue * 0.3
    );

    var color = mix(plateColor, sandColor * interferenceColor, particleMask);

    // ─── Creative: iridescent oil-slick interference (mouse-shifted) ───
    let oilPhase = vibrationEnergy * 18.0 + length(plateUV - (mouse - 0.5) * 2.0) * 6.0 + time * 0.4;
    let oilSlick = vec3<f32>(
        0.5 + 0.5 * cos(oilPhase),
        0.5 + 0.5 * cos(oilPhase + 2.094),
        0.5 + 0.5 * cos(oilPhase + 4.188)
    );
    let oilMask = (1.0 - particleMask) * 0.18;
    color = color + oilSlick * oilMask;

    // Nodal line glow
    let nodeGlow = nodeMask * 0.3 * (0.5 + sandNoise * 0.5);
    color = color + vec3<f32>(nodeGlow * 0.9, nodeGlow * 0.85, nodeGlow * 0.7);

    let highlight = pow(1.0 - vibrationEnergy, 3.0) * 0.2;
    color = color + vec3<f32>(highlight);

    let edgeDist = length(plateUV);
    let vignette = 1.0 - smoothstep(0.7, 1.0, edgeDist);
    color = color * (0.7 + vignette * 0.3);

    let boundary = smoothstep(0.98, 1.0, edgeDist);
    color = mix(color, vec3<f32>(0.3, 0.25, 0.2), boundary * 0.5);

    // Tone map
    color = acesToneMapping(color);

    // Sample input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let opacity = 0.9;

    // Edge-detection alpha for "stained glass" — nodal lines get high alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let lumaAlpha = mix(0.7, 1.0, luma);
    let edgeAlpha = max(nodeMask, particleMask * 0.6);
    let generatedAlpha = max(lumaAlpha, edgeAlpha);

    let finalColor = mix(inputColor.rgb, color, generatedAlpha * opacity);
    let finalAlpha = max(inputColor.a, generatedAlpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));

    let depthValue = mix(inputDepth, vibrationEnergy * 0.5 + 0.5, generatedAlpha * opacity);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthValue, 0.0, 0.0, 0.0));

    // Write displacement field state to dataTextureA for downstream multi-pass shaders
    // R = displacement (signed, remapped), G = vibrationEnergy, B = nodeMask, A = particleMask
    textureStore(dataTextureA, coord, vec4<f32>(
        displacement * 0.5 + 0.5,
        vibrationEnergy,
        nodeMask,
        particleMask
    ));
}
