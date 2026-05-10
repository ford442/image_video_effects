// ═══════════════════════════════════════════════════════════════════
//  Melting Oil
//  Category: image
//  Features: gradient-flow, branchless-ripples, audio-reactive, advection
//  Complexity: Medium
//  Phase B / Optimizer
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
  zoom_params: vec4<f32>,  // x=Viscosity, y=MouseForce, z=HueShift, w=Audio
  ripples: array<vec4<f32>, 50>,
};

const PHI: f32 = 1.61803398874989484820;

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(gid.xy);
    let dim = textureDimensions(dataTextureA);
    let dimF = vec2<f32>(f32(dim.x), f32(dim.y));
    let uv = vec2<f32>(gid.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;

    let viscosity = clamp(0.85 + u.zoom_params.x * 0.13, 0.5, 0.99);
    let mouseForceK = clamp(u.zoom_params.y, 0.0, 1.0);
    let hueShiftK = clamp(u.zoom_params.z, 0.0, 1.0);
    let audioK = clamp(u.zoom_params.w * (1.0 + bass * 0.5), 0.0, 2.0);

    // Sobel: 6 texture loads via row-vec packing (vs naive 9), branchless
    let r0 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1, -1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 0, -1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1, -1), 0).r);
    let r1 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1,  0), 0).r,
        textureLoad(dataTextureC, coord, 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1,  0), 0).r);
    let r2 = vec3<f32>(
        textureLoad(dataTextureC, coord + vec2<i32>(-1,  1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 0,  1), 0).r,
        textureLoad(dataTextureC, coord + vec2<i32>( 1,  1), 0).r);

    let gx = (r0.z + 2.0 * r1.z + r2.z) - (r0.x + 2.0 * r1.x + r2.x);
    let gy = (r2.x + 2.0 * r2.y + r2.z) - (r0.x + 2.0 * r0.y + r0.z);
    let grad = vec2<f32>(gx, gy);
    let gradLen = max(length(grad), 1e-4);
    var flow_dir = grad / gradLen;

    // Branchless mouse force — Gaussian falloff, lerp into flow direction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
    let dM = length(toMouse);
    let mouseGate = exp(-dM * dM * 12.0) * (mouseForceK + mouseDown * 0.5);
    let mouseDir = toMouse / max(dM, 1e-4);
    flow_dir = normalize(mix(flow_dir, mouseDir, mouseGate));

    // Vectorized ripple stir — first 8 ripples (capped, branchless time gate)
    var stir = vec2<f32>(0.0);
    for (var i = 0; i < 8; i++) {
        let rip = u.ripples[i];
        let active = step(1e-4, rip.z);
        let age = max(time - rip.z, 0.0);
        let alive = step(age, 3.0);
        let toR = (uv - rip.xy) * vec2<f32>(aspect, 1.0);
        let dR2 = dot(toR, toR);
        let pulse = exp(-dR2 * 60.0) * (1.0 - age / 3.0) * active * alive;
        stir += vec2<f32>(-toR.y, toR.x) * 0.5 * pulse;
    }
    flow_dir = normalize(flow_dir + stir);

    // Backward-Euler advection (semi-Lagrangian) — viscosity controls trail length
    let advectStep = flow_dir * viscosity * (1.0 + audioK * 0.4);
    let last_pos = vec2<f32>(coord) - advectStep;
    let color = textureSampleLevel(readTexture, u_sampler, clamp(last_pos / dimF, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Hue rotation by gradient magnitude (faster motion → more shift)
    let hue_shift = (gradLen * 0.8 + time * 0.05) * hueShiftK * PHI;
    let hueMat = vec3<f32>(0.5 + 0.5 * sin(hue_shift),
                           0.5 + 0.5 * sin(hue_shift + 2.094),
                           0.5 + 0.5 * sin(hue_shift + 4.188));
    var shifted = mix(color.rgb, color.rgb * (0.6 + hueMat * 0.8), hueShiftK);

    // Alpha: gradient magnitude (motion intensity) + mouse interaction drives compositing
    let luma = dot(shifted, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.5 + gradLen * 0.6 + mouseGate * 0.2 + 0.1, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(shifted, alpha));
    textureStore(dataTextureB, coord, vec4<f32>(shifted, alpha));
    // Decay height field stored in dataTextureA (used by Pass-1 simulators)
    let h = textureLoad(dataTextureC, coord, 0).r * (0.99 - audioK * 0.005);
    textureStore(dataTextureA, coord, vec4<f32>(h, gradLen, 0.0, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
