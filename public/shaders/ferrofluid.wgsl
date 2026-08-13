// ═══════════════════════════════════════════════════════════════════
//  Ferrofluid
//  Category: image
//  Features: mouse-driven, audio-reactive, ferrofluid
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SpikeScale, y=AttractionStr, z=Viscosity, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash21(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)),
                   hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)),
                   hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let bass = plasmaBuffer[0].x;

    // Params — bass intensifies magnetic spike formation
    let spikeScale = mix(10.0, 50.0, u.zoom_params.x);
    let attractionStrength = u.zoom_params.y * (1.0 + bass * 0.4);
    let viscosity = clamp(u.zoom_params.z, 0.0, 1.0);
    let colorShift = u.zoom_params.w;

    let mouse = u.zoom_config.yz;
    let mouseDown = step(0.5, u.zoom_config.w);

    // Vector to mouse
    let toMouse = (mouse - uv);
    let dist = length(toMouse * vec2<f32>(aspect, 1.0));

    // Normalized direction (handle zero length)
    var dir = vec2<f32>(0.0);
    if (length(toMouse) > 0.001) {
        dir = normalize(toMouse);
    }

    // Spike pattern: based on angle towards mouse
    let angle = atan2(dir.y, dir.x);
    // Rotating magnetic domains and outward-running droplets stay continuous.
    let mobility = mix(1.45, 0.35, viscosity);
    let domainPhase = angle * (7.0 + spikeScale * 0.12) - time * (5.0 + mobility * 4.0);
    let spikeNoise = noise(vec2<f32>(domainPhase, dist * spikeScale - time * mobility * 2.0));
    let domainRunner = pow(max(0.0, sin(domainPhase * 1.7 + dist * spikeScale * 1.3)), 12.0);
    let dropletRunner = pow(max(0.0, sin(dist * spikeScale * 2.4 - time * (12.0 + mobility * 5.0) + angle * 3.0)), 14.0);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += smoothstep(0.025, 0.0, abs(length(delta) - age * 0.42)) * exp(-age * 1.5);
        }
    }

    // Displace UVs towards mouse, modulated by spikes
    let force = smoothstep(0.5, 0.0, dist) * attractionStrength * mix(0.55, 1.0, mouseDown); // Stronger near a held mouse
    let spikeForce = force * (0.38 + 0.42 * spikeNoise + domainRunner * 0.2) + clickFront * attractionStrength * 0.35;

    // Viscosity adds "lag" or smoothing (simulated by blurring the noise domain in real sim, here just intensity)
    let tangent = vec2<f32>(-dir.y, dir.x);
    let finalDisplacement = (dir * spikeForce + tangent * dropletRunner * force * 0.25) * 0.2 * mobility;

    let distortedUV = clamp(uv - finalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));

    let baseColor = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Ferrofluid look: Metallic, dark, shiny highlights
    // Desaturate
    let gray = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Make it dark
    var fluidColor = vec3<f32>(gray * 0.5);

    // Add specular highlights on "ridges" (where noise gradient is high)
    let ridge = clamp(smoothstep(0.6, 0.8, spikeNoise) * force + domainRunner * force * 0.45 + clickFront * 0.3, 0.0, 1.5);
    fluidColor += vec3<f32>(ridge);

    // Mix with original based on distance (effect fades out far away)
    let effectMask = smoothstep(0.6, 0.3, dist);

    var finalColor = mix(baseColor.rgb, fluidColor, clamp(effectMask + clickFront * 0.35, 0.0, 1.0));

    // Color shift param
    if (colorShift > 0.0) {
        finalColor = mix(finalColor, vec3<f32>(finalColor.b, finalColor.r, finalColor.g), colorShift);
    }

    // Alpha: preserve input transparency, blend toward opaque based on effect intensity
    let finalAlpha = mix(baseColor.a, 1.0, effectMask * 0.7);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(4.0)), finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(spikeForce, ridge, dist, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0, 0, 0.0));
}
