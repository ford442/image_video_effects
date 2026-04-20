// ═══════════════════════════════════════════════════════════════════
//  Alpha Aurora Bands
//  Category: lighting-effects
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Emission at 557.7nm (green oxygen)
//    G = Emission at 630.0nm (red oxygen)
//    B = Emission at 427.8nm (blue nitrogen)
//    A = Altitude/layer index (continuous, determines dominance)
//  Why f32: Emission lines have Gaussian distributions that overlap
//  subtly. 8-bit would make aurora bands posterize into 3 discrete
//  colors instead of smooth spectral gradients.
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

// ═══ CHUNK: hash12, valueNoise, fbm2 (from chunk-library.md) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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

fn auroraEmission(altitude: f32, particleEnergy: f32) -> vec3<f32> {
    // Oxygen green line: 100-200 km altitude (normalized 0.3-0.6)
    let greenLine = exp(-pow((altitude - 0.45) / 0.12, 2.0)) * particleEnergy;
    // Oxygen red line: 200-400 km altitude (normalized 0.6-0.9)
    let redLine = exp(-pow((altitude - 0.75) / 0.18, 2.0)) * particleEnergy * 0.6;
    // Nitrogen blue line: 80-100 km altitude (normalized 0.1-0.3)
    let blueLine = exp(-pow((altitude - 0.2) / 0.1, 2.0)) * particleEnergy * 0.4;
    return vec3<f32>(redLine, greenLine, blueLine);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // === PARAMETERS ===
    let intensity = mix(0.3, 2.0, u.zoom_params.x);
    let curtainFrequency = mix(2.0, 8.0, u.zoom_params.y);
    let turbulence = u.zoom_params.z;
    let speed = mix(0.05, 0.3, u.zoom_params.w);

    // === MOUSE SOLAR WIND ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let windDir = normalize(vec2<f32>(mousePos.x - 0.5, 0.0) + vec2<f32>(0.3, 0.0));
    let windStrength = length(vec2<f32>(mousePos.x - 0.5, mousePos.y - 0.5)) * 2.0 + 0.5;

    // === AURORA CURTAINS ===
    var totalEmission = vec3<f32>(0.0);
    var totalAltitude = 0.0;

    let layerCount = 5;
    for (var layer = 0; layer < layerCount; layer = layer + 1) {
        let layerF = f32(layer);
        let baseAltitude = 0.2 + layerF * 0.15;

        // Curtain shape using noise
        let noiseUV = vec2<f32>(
            uv.x * curtainFrequency + time * speed * windDir.x * windStrength + layerF * 3.0,
            uv.y * 2.0 + time * speed * 0.3
        );
        let curtainNoise = fbm2(noiseUV, 4);

        // Ripple disturbance
        let rippleCount = min(u32(u.config.y), 50u);
        var rippleEnergy = 0.0;
        for (var i = 0u; i < rippleCount; i = i + 1u) {
            let ripple = u.ripples[i];
            let rDist = length(uv - ripple.xy);
            let age = time - ripple.z;
            if (age < 3.0 && rDist < 0.3) {
                let substorm = smoothstep(0.3, 0.0, rDist) * max(0.0, 1.0 - age * 0.33);
                rippleEnergy += substorm;
            }
        }

        // Curtain intensity varies across X
        let curtainX = sin(uv.x * curtainFrequency * 3.14159 + layerF * 1.5) * 0.5 + 0.5;
        let curtainMask = smoothstep(0.3, 0.7, curtainNoise * curtainX + turbulence * 0.2);

        // Altitude variation within curtain
        let altitudeVar = baseAltitude + sin(uv.y * 10.0 + time * 0.2 + layerF) * 0.08;
        let altitude = clamp(altitudeVar, 0.0, 1.0);

        // Particle energy enhanced by mouse and ripples
        let particleEnergy = curtainMask * intensity * (1.0 + rippleEnergy * 2.0 + mouseDown * 0.5);

        let emission = auroraEmission(altitude, particleEnergy);
        totalEmission += emission;
        totalAltitude += altitude * particleEnergy;
    }

    totalEmission = clamp(totalEmission, vec3<f32>(0.0), vec3<f32>(3.0));

    // Average altitude weighted by energy
    let avgAltitude = totalAltitude / (length(totalEmission) + 0.001);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(totalEmission, avgAltitude));

    // === VISUALIZATION ===
    // Read background (source image or dark sky)
    let bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * 0.3;

    // Soft tone map for HDR emission
    let displayColor = bgColor + totalEmission / (1.0 + totalEmission * 0.5);
    let finalColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(finalColor, avgAltitude));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
