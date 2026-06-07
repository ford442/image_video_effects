// ═══════════════════════════════════════════════════════════════════
//  Alpha Depth Fog Volumetric
//  Category: visual-effects
//  Features: depth-aware, mouse-driven, rgba-data-channel
//  Complexity: Medium
//  RGBA Channels:
//    R = Fogged scene red
//    G = Fogged scene green
//    B = Fogged scene blue
//    A = Optical depth / transmittance (0 = opaque fog, 1 = clear)
//  Why f32: Optical depth uses Beer-Lambert law with exp() of
//  continuous density. 8-bit would create visible banding in fog.
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

// ═══ CHUNK: hash12 (from chunk-library.md / gen_grid.wgsl) ═══
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // === READ DEPTH ===
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // === PARAMETERS ===
    let fogDensity = mix(0.2, 3.0, u.zoom_params.x);
    let fogHeight = u.zoom_params.y; // Vertical fog gradient
    let turbulence = u.zoom_params.z;

    // === VOLUMETRIC NOISE ===
    let noiseUV = uv * 3.0 + vec2<f32>(time * 0.02, time * 0.015);
    let fogNoise = fbm2(noiseUV, 4) * turbulence + (1.0 - turbulence);

    // === BEER-LAMBERT LAW ===
    // Optical depth increases with distance (1 - depth) and fog density
    let distFactor = (1.0 - depth);
    let heightFactor = 1.0 - uv.y * fogHeight;
    let opticalDepth = fogDensity * distFactor * heightFactor * fogNoise * 3.0;
    let transmittance = exp(-opticalDepth);

    // === FOG COLOR (depth-dependent) ===
    // Warm near, cool far
    let nearFog = vec3<f32>(0.85, 0.75, 0.55);   // Warm sand
    let farFog = vec3<f32>(0.25, 0.35, 0.6);     // Cool blue
    let fogColor = mix(nearFog, farFog, distFactor);

    // === MOUSE CLEARS FOG ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseClear = smoothstep(0.2, 0.0, mouseDist) * mouseDown;
    let modifiedTransmittance = mix(transmittance, 1.0, mouseClear);

    // === RIPPLE FOg SWIRL ===
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleDisturbance = 0.0;
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rDist < 0.2) {
            rippleDisturbance += smoothstep(0.2, 0.0, rDist) * max(0.0, 1.0 - age * 0.5) * 0.3;
        }
    }
    let finalTransmittance = mix(modifiedTransmittance, modifiedTransmittance * 0.5, rippleDisturbance);

    // === SCENE COMPOSITE ===
    let sceneColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let foggedColor = sceneColor * finalTransmittance + fogColor * (1.0 - finalTransmittance);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(foggedColor, finalTransmittance));

    // === WRITE DISPLAY ===
    textureStore(writeTexture, coord, vec4<f32>(foggedColor, finalTransmittance));

    // Depth pass-through
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
