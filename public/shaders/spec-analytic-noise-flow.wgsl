// ═══════════════════════════════════════════════════════════════════
//  spec-analytic-noise-flow
//  Category: generative
//  Features: analytic-derivatives, flow-field, noise
//  Complexity: Medium
//  Chunks From: chunk-library (hash12)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  Noise with Analytic Derivatives for Flow Fields
//  Implements Perlin noise with analytic derivatives — gradient is
//  computed alongside noise value in a single evaluation. Creates
//  perfectly smooth flow fields without finite-difference jitter.
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

fn hash2(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash12(p), hash12(p + vec2<f32>(37.0, 17.0)));
}

// Analytic derivative noise: returns x = value, yz = gradient
fn noiseWithDerivative(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);

    // Quintic interpolation with analytic derivative
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    // Hash corners
    let a = hash2(i + vec2<f32>(0.0, 0.0));
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));

    // Value interpolation
    let k0 = a;
    let k1 = b - a;
    let k2 = c - a;
    let k4 = a - b - c + d;

    let value = k0 + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
    let derivative = vec2<f32>(
        (k1 + k4 * u.y) * du.x,
        (k2 + k4 * u.x) * du.y
    );

    return vec3<f32>(value, derivative);
}

// Multi-octave analytic noise
fn fbmAnalytic(p: vec2<f32>, octaves: i32) -> vec3<f32> {
    var value = 0.0;
    var grad = vec2<f32>(0.0);
    var amplitude = 0.5;
    var frequency = 1.0;

    for (var i: i32 = 0; i < octaves; i = i + 1) {
        let n = noiseWithDerivative(p * frequency);
        value += amplitude * n.x;
        grad += amplitude * frequency * n.yz;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return vec3<f32>(value, grad);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let flowScale = mix(1.0, 5.0, u.zoom_params.x);
    let flowSpeed = mix(0.2, 2.0, u.zoom_params.y);
    let advectionStr = mix(0.0, 0.3, u.zoom_params.z);
    let curlAmount = mix(0.0, 1.0, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Sample base image for advection source
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Analytic noise flow field
    let p = uv * flowScale + time * flowSpeed;
    let noise1 = fbmAnalytic(p, 4);
    let noise2 = fbmAnalytic(p + vec2<f32>(5.2, 1.3), 4);

    // Build velocity field from analytic gradients
    var velocity = vec2<f32>(noise1.y, noise2.y);

    // Add curl (perpendicular to gradient)
    let curl = vec2<f32>(-noise1.z, noise1.y) * curlAmount;
    velocity += curl;

    // Mouse vortex
    if (isMouseDown) {
        let toMouse = mousePos - uv;
        let dist = length(toMouse);
        let vortexStrength = exp(-dist * dist * 500.0);
        let perp = vec2<f32>(-toMouse.y, toMouse.x) / (dist + 0.001);
        velocity += perp * vortexStrength * 0.5;
    }

    // Advect sample position along flow
    let advectedUV = uv + velocity * advectionStr;
    let warpedColor = textureSampleLevel(readTexture, u_sampler, fract(advectedUV), 0.0).rgb;

    // Flow visualization: color by direction
    let flowAngle = atan2(velocity.y, velocity.x) / 6.28318 + 0.5;
    let flowColor = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * flowAngle),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.33)),
        0.5 + 0.5 * cos(6.28318 * (flowAngle + 0.67))
    );

    // Blend warped image with flow visualization
    let blendFactor = 0.6;
    var outColor = mix(warpedColor, flowColor * 0.5 + warpedColor * 0.5, blendFactor);

    // Add streamline highlight
    let streamline = smoothstep(0.0, 0.1, abs(noise1.x - 0.5));
    outColor += vec3<f32>(0.1, 0.15, 0.2) * streamline * (1.0 - curlAmount);

    textureStore(writeTexture, gid.xy, vec4<f32>(outColor, length(velocity)));
    textureStore(dataTextureA, gid.xy, vec4<f32>(velocity, noise1.x, 1.0));
}
