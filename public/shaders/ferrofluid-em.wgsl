// ═══════════════════════════════════════════════════════════════════
//  ferrofluid-em
//  Category: advanced-hybrid
//  Features: ferrofluid-distortion, em-field-visualization, mouse-driven
//  Complexity: High
//  Chunks From: ferrofluid.wgsl, alpha-em-field-simulation.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Magnetic ferrofluid spikes that respond to an underlying EM field.
//  The electric field direction drives spike orientation while charge
//  density modulates spike height. Creates an organic metallic fluid
//  that feels alive with electromagnetic energy.
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let spikeScale = mix(10.0, 50.0, u.zoom_params.x);
    let attractionStrength = u.zoom_params.y;
    let emInfluence = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    var mouse = u.zoom_config.yz;
    let toMouse = (mouse - uv);
    let dist = length(toMouse * vec2<f32>(aspect, 1.0));

    // EM field simulation (stateless approximation for hybrid)
    let emUV = uv * 4.0 + time * 0.05;
    let eFieldX = fbm2(emUV + vec2<f32>(time * 0.1, 0.0), 4) * 2.0 - 1.0;
    let eFieldY = fbm2(emUV + vec2<f32>(0.0, time * 0.1), 4) * 2.0 - 1.0;
    let eStrength = length(vec2<f32>(eFieldX, eFieldY));
    let eDir = atan2(eFieldY, eFieldX);

    // Blend mouse direction with EM field direction
    var dir = vec2<f32>(0.0);
    if (length(toMouse) > 0.001) {
        dir = normalize(toMouse);
    }
    let emDir = vec2<f32>(cos(eDir), sin(eDir));
    dir = normalize(mix(dir, emDir, emInfluence * 0.5));

    // Spike pattern modulated by EM field strength
    let angle = atan2(dir.y, dir.x);
    let spikeNoise = fbm2(vec2<f32>(angle * 10.0, dist * spikeScale - time), 4);

    // Force stronger near mouse and where EM field is intense
    let force = smoothstep(0.5, 0.0, dist) * attractionStrength;
    let emBoost = 1.0 + eStrength * emInfluence;
    let spikeForce = force * (0.5 + 0.5 * spikeNoise) * emBoost;

    let finalDisplacement = dir * spikeForce * 0.2;
    let distortedUV = uv - finalDisplacement;

    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Ferrofluid metallic look
    let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
    var fluidColor = vec3<f32>(gray * 0.5);

    // Specular ridges enhanced by EM field
    let ridge = smoothstep(0.6, 0.8, spikeNoise) * force * emBoost;
    fluidColor += vec3<f32>(ridge);

    // EM field color overlay: E-field direction -> hue
    let hue = eDir / 6.283185307 + 0.5;
    let h6 = hue * 6.0;
    let c = 0.6 * eStrength * emInfluence;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var emColor: vec3<f32>;
    if (h6 < 1.0) { emColor = vec3(c, x, 0.0); }
    else if (h6 < 2.0) { emColor = vec3(x, c, 0.0); }
    else if (h6 < 3.0) { emColor = vec3(0.0, c, x); }
    else if (h6 < 4.0) { emColor = vec3(0.0, x, c); }
    else if (h6 < 5.0) { emColor = vec3(x, 0.0, c); }
    else { emColor = vec3(c, 0.0, x); }

    fluidColor += emColor * smoothstep(0.5, 0.0, dist);

    let effectMask = smoothstep(0.6, 0.3, dist);
    var finalColor = mix(color.rgb, fluidColor, effectMask);

    if (colorShift > 0.0) {
        finalColor = mix(finalColor, vec3<f32>(finalColor.b, finalColor.r, finalColor.g), colorShift);
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
