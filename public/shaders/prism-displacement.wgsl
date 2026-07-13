// ═══════════════════════════════════════════════════════════════════
//  Prism Displacement
//  Category: image
//  Features: audio-reactive, chromatic-aberration, upgraded-rgba,
//            temporal-lens-rotation, chromatic-angular-dispersion,
//            depth-magnification, spectral-wavelength-sampling,
//            lens-distortion, anamorphic-streak
//  Complexity: Medium-High
//  Upgraded: 2026-06-28
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

// ── Radial lens distortion (barrel / pincushion) ─────────────────
fn lensDistort(uv: vec2<f32>, center: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
    let d = uv - center;
    let r2 = dot(d, d);
    let factor = 1.0 + k1 * r2 + k2 * r2 * r2;
    return center + d * factor;
}

// ── Approximate wavelength → RGB (380‑780 nm) ────────────────────
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    if (lambda < 440.0) {
        return vec3<f32>(-(lambda - 440.0) / 60.0, 0.0, 1.0);
    } else if (lambda < 490.0) {
        return vec3<f32>(0.0, (lambda - 440.0) / 50.0, 1.0);
    } else if (lambda < 510.0) {
        return vec3<f32>(0.0, 1.0, -(lambda - 510.0) / 20.0);
    } else if (lambda < 580.0) {
        return vec3<f32>((lambda - 510.0) / 70.0, 1.0, 0.0);
    } else if (lambda < 645.0) {
        return vec3<f32>(1.0, -(lambda - 645.0) / 65.0, 0.0);
    } else {
        return vec3<f32>(1.0, 0.0, 0.0);
    }
}

// ── Spectral sampling with anamorphic dispersion direction ───────
fn sampleSpectral(uv: vec2<f32>, dir: vec2<f32>, dispersion: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    for (var i = 0; i < 7; i = i + 1) {
        let t = f32(i) / 6.0;
        let lambda = 380.0 + t * 400.0;
        let shift = dir * (lambda - 550.0) * dispersion;
        let sample = textureSampleLevel(readTexture, u_sampler,
                                        clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        acc = acc + sample * wavelengthToRGB(lambda);
    }
    return acc / 7.0;
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

    let nParams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let zoomAmount = nParams.x;
    let chromaticAmount = nParams.y;
    let rotationSpeed = nParams.z;
    let depthWeight = nParams.w;

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

    // Lens distortion (barrel / pincushion) tied to zoom parameter
    let k1 = (zoomAmount - 0.5) * 0.3;
    let k2 = -zoomAmount * 0.1;
    let lensedUV = lensDistort(zoomedUV, mouse, k1, k2);

    // Anamorphic dispersion direction: stretch horizontally
    var dispDir = normalize(p + vec2<f32>(1e-4));
    dispDir.x *= aspect;
    dispDir = normalize(dispDir);
    dispDir.x *= 1.0 + chromaticAmount * 3.0;

    let dispersion = chromaticAmount * 0.00005 * (1.0 + treble * 0.3);
    var color = sampleSpectral(lensedUV, dispDir, dispersion);

    let baseColor = textureSampleLevel(readTexture, u_sampler,
                                       clamp(lensedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

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
