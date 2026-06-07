// ═══════════════════════════════════════════════════════════════════
//  Kaleidoscope Chromatic
//  Category: hybrid
//  Features: kaleidoscope, chromatic-aberration, symmetry, color-fringing
//  Complexity: High
//  Created: 2026-05-31
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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    let segments = u.zoom_params.x * 10.0 + 3.0;
    let rotationSpeed = u.zoom_params.y * 0.5;
    let chromaticAmount = u.zoom_params.z * 0.04;
    let zoom = u.zoom_params.w * 0.5 + 0.5;

    var mouse = u.zoom_config.yz;

    // Center UV
    var centered = uv - vec2<f32>(0.5);
    centered.x *= aspect;

    // Convert to polar
    let r = length(centered);
    var theta = atan2(centered.y, centered.x);

    // Kaleidoscope symmetry
    let segAngle = TAU / segments;
    theta = mod(theta + time * rotationSpeed, segAngle);
    if (theta > segAngle * 0.5) {
        theta = segAngle - theta;
    }

    // Convert back to Cartesian for sampling
    var kaleidUV = vec2<f32>(cos(theta), sin(theta)) * r;
    kaleidUV.x /= aspect;
    kaleidUV = kaleidUV / zoom + vec2<f32>(0.5);

    // Mouse offset shifts the kaleidoscope center
    var mouseShift = (mouse - vec2<f32>(0.5)) * 0.2;
    kaleidUV += mouseShift;

    kaleidUV = clamp(kaleidUV, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic aberration: different radial offset per channel
    let chromaticR = chromaticAmount * (1.0 + r);
    let chromaticB = chromaticAmount * (1.0 + r * 0.5);

    var radialR = (kaleidUV - vec2<f32>(0.5)) * (1.0 + chromaticR);
    radialR += vec2<f32>(0.5);
    var radialB = (kaleidUV - vec2<f32>(0.5)) * (1.0 - chromaticB);
    radialB += vec2<f32>(0.5);

    radialR = clamp(radialR, vec2<f32>(0.0), vec2<f32>(1.0));
    radialB = clamp(radialB, vec2<f32>(0.0), vec2<f32>(1.0));

    let redChannel = textureSampleLevel(readTexture, u_sampler, radialR, 0.0).r;
    let greenChannel = textureSampleLevel(readTexture, u_sampler, kaleidUV, 0.0).g;
    let blueChannel = textureSampleLevel(readTexture, u_sampler, radialB, 0.0).b;

    var color = vec3<f32>(redChannel, greenChannel, blueChannel);

    // Rainbow fringing at segment boundaries
    let boundaryDist = abs(theta - segAngle * 0.5) / (segAngle * 0.5);
    let boundaryGlow = smoothstep(0.0, 0.1, boundaryDist) * smoothstep(0.3, 0.0, boundaryDist);
    let hue = fract(theta / TAU + time * 0.05);
    let rainbow = vec3<f32>(
        0.5 + 0.5 * cos(hue * 6.283 + 0.0),
        0.5 + 0.5 * cos(hue * 6.283 + 2.094),
        0.5 + 0.5 * cos(hue * 6.283 + 4.189)
    );
    color += rainbow * boundaryGlow * chromaticAmount * 10.0;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
