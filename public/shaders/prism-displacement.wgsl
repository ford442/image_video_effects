// ═══════════════════════════════════════════════════════════════════
//  Prism Displacement
//  Category: image
//  Features: audio-reactive, chromatic-aberration, upgraded-rgba,
//            temporal-lens-rotation, chromatic-angular-dispersion, depth-magnification
//  Complexity: Medium
//  Upgraded: 2026-05-31
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

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let zoomAmount = u.zoom_params.x;
    let chromaticAmount = u.zoom_params.y;
    let rotationSpeed = u.zoom_params.z;
    let depthWeight = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    var p = uv - mouse;
    p.x *= aspect;

    let len = length(p);
    let angle = atan2(p.y, p.x);

    // Temporal lens rotation memory: angle drifts slowly
    let rotAngle = angle + time * rotationSpeed * 0.5;
    let cosR = cos(rotAngle);
    let sinR = sin(rotAngle);
    var rotated = vec2<f32>(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);
    rotated.x /= aspect;
    var rotatedUV = rotated + mouse;

    // Depth-weighted magnification: deeper = more zoom
    let z = len * zoomAmount * (1.0 + depth * depthWeight * 0.5) * (1.0 + bass * 0.2);

    let zoomedUV = mouse + (rotatedUV - mouse) * (1.0 - z);

    // Chromatic angular dispersion
    let chromaShift = chromaticAmount * 0.02 * (1.0 + treble * 0.3);
    let dir = normalize(p + vec2<f32>(1e-4));
    let rUV = zoomedUV + dir * chromaShift * 1.5;
    let gUV = zoomedUV + dir * chromaShift * 0.0;
    let bUV = zoomedUV - dir * chromaShift * 1.2;

    let baseColor = textureSampleLevel(readTexture, u_sampler, clamp(zoomedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    var color = vec3<f32>(0.0);
    color.r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    color.g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    color.b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    let edgeDist = len;
    let edgeGlow = smoothstep(0.5, 0.0, edgeDist) * smoothstep(0.2, 0.5, zoomAmount);

    // Edge color shift with phase
    let phase = time + hash11(len * 100.0 + bass * 10.0) * TAU;
    let edgeColor = 0.5 + 0.5 * cos(vec3<f32>(phase, phase + 2.094, phase + 4.188));
    color = mix(color, edgeColor, edgeGlow * chromaticAmount * 0.5);

    let finalAlpha = mix(baseColor.a, 1.0, edgeGlow * 0.5 + len * 0.1);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(color, finalAlpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
