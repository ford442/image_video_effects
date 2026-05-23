// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Description: Strange attractor density accumulation via per-pixel
//    Monte Carlo orbit integration. Each pixel seeds a short Lorenz
//    trajectory near one of the two equilibrium points; Gaussian
//    kernel splatting onto the x-z projection builds the butterfly.
//    Temporal blending converges to the full attractor over frames.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=sigma(8–14), y=rho_mod(0–14), z=glow_radius, w=decay

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=sigma, y=rho_mod, z=glowR, w=decay
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn lorenz_step(p: vec3<f32>, s: f32, r: f32, b: f32) -> vec3<f32> {
    let dt = 0.010;
    return p + vec3<f32>(s * (p.y - p.x), p.x * (r - p.z) - p.y, p.x * p.y - b * p.z) * dt;
}

// Cosine palette — blue → cyan → white → gold
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.25, 0.60);
    return clamp(a + b * cos(6.28318 * (c * t + d)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Lorenz parameters — bass widens rho for more chaotic spread
    let sigma  = 8.0 + u.zoom_params.x * 6.0;
    let rho    = 24.0 + u.zoom_params.y * 12.0 * (1.0 + bass * 0.5);
    let beta   = 8.0 / 3.0;

    let glowR  = max(0.5 + u.zoom_params.z * 1.8 + mids * 0.4, 0.1);
    let decay  = 0.960 + u.zoom_params.w * 0.030;

    // Mouse pans the x-z view window
    let mouse  = u.zoom_config.yz;
    let panX   = (mouse.x - 0.5) * 24.0;
    let panZ   = (mouse.y - 0.5) * 24.0;

    // Pixel → Lorenz x-z projection space: x∈[-25,25], z∈[-2,48]
    let viewX = (uv.x - 0.5) * 50.0 + panX;
    let viewZ =  uv.y         * 50.0 -  2.0 + panZ;

    // Seed starting near one equilibrium lobe C± = (±√(β(ρ-1)), ±…, ρ-1)
    let sq   = sqrt(beta * max(rho - 1.0, 0.1));
    let seed = hash22(uv * 73.1 + vec2<f32>(fract(time * 0.04 + 0.13), fract(time * 0.06)));
    let side = select(-1.0, 1.0, seed.x > 0.5);
    var p    = vec3<f32>(
        side * sq + (seed.x - 0.5) * 7.0,
        side * sq + (seed.y - 0.5) * 7.0,
        rho  - 1.0 + (seed.y - 0.5) * 5.0,
    );

    // Burn-in: 20 steps to move away from the fixed point onto the manifold
    for (var i = 0u; i < 20u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
    }

    // Trace: 52 steps; accumulate Gaussian glow at this pixel
    var contrib = 0.0;
    let invR2   = 1.0 / (glowR * glowR);
    for (var i = 0u; i < 52u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
        let dx = p.x - viewX;
        let dz = p.z - viewZ;
        contrib += exp(-(dx * dx + dz * dz) * invR2);
    }
    contrib *= (1.0 / 52.0);

    // Temporal accumulation: blend new contribution with previous frame's density
    let prevDensity = textureLoad(dataTextureC, coord, 0).r;
    let accumulated = mix(contrib, prevDensity, clamp(decay, 0.0, 0.999));

    // Color by accumulated density; treble adds a subtle shimmer layer
    let shimmer  = treble * 0.08 * sin(accumulated * 40.0 + time * 3.0);
    let density  = clamp(accumulated * 7.0 + shimmer, 0.0, 1.0);
    let col      = palette(density);
    let alpha    = clamp(density * 0.9 + bass * 0.08, 0.0, 1.0);
    let finalOut = vec4<f32>(col, alpha);

    // Write state for next frame
    textureStore(dataTextureA, coord, vec4<f32>(accumulated, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, finalOut);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
