// ═══════════════════════════════════════════════════════════════════
//  Lorenz Attractor
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            chromatic-lobes, audio-decay-modulation, depth-output
//  Complexity: High
//  Description: Strange attractor density accumulation via per-pixel
//    Monte Carlo orbit integration. Each pixel seeds a short Lorenz
//    trajectory near one of the two equilibrium points; Gaussian
//    kernel splatting onto the x-z projection builds the butterfly.
//    Temporal blending converges to the full attractor over frames.
//  Upgraded: 2026-06-06
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
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
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

fn palette(t: f32, hueOff: f32) -> vec3<f32> {
    let h = fract(t + hueOff);
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.25, 0.60);
    return clamp(a + b * cos(6.28318 * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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

    let sigma  = 8.0 + u.zoom_params.x * 6.0;
    let rho    = 24.0 + u.zoom_params.y * 12.0 * (1.0 + bass * 0.5);
    let beta   = 8.0 / 3.0;

    let glowR  = max(0.5 + u.zoom_params.z * 1.8 + mids * 0.4, 0.1);
    let decay  = 0.960 + u.zoom_params.w * 0.030 + bass * 0.005;

    let mouse  = u.zoom_config.yz;
    let panX   = (mouse.x - 0.5) * 24.0;
    let panZ   = (mouse.y - 0.5) * 24.0;

    let viewX = (uv.x - 0.5) * 50.0 + panX;
    let viewZ =  uv.y         * 50.0 -  2.0 + panZ;

    let sq   = sqrt(beta * max(rho - 1.0, 0.1));
    let seed = hash22(uv * 73.1 + vec2<f32>(fract(time * 0.04 + 0.13), fract(time * 0.06)));
    let side = select(-1.0, 1.0, seed.x > 0.5);
    var p    = vec3<f32>(
        side * sq + (seed.x - 0.5) * 7.0,
        side * sq + (seed.y - 0.5) * 7.0,
        rho  - 1.0 + (seed.y - 0.5) * 5.0,
    );

    for (var i = 0u; i < 20u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
    }

    var contribR = 0.0;
    var contribB = 0.0;
    let invR2   = 1.0 / (glowR * glowR);
    for (var i = 0u; i < 52u; i = i + 1u) {
        p = lorenz_step(p, sigma, rho, beta);
        let dx = p.x - viewX;
        let dz = p.z - viewZ;
        let d2 = dx * dx + dz * dz;
        let g = exp(-d2 * invR2);
        // Chromatic lobe separation: right lobe → R, left lobe → B
        contribR += g * smoothstep(0.0, 2.0, p.x);
        contribB += g * smoothstep(0.0, 2.0, -p.x);
    }
    contribR *= (1.0 / 52.0);
    contribB *= (1.0 / 52.0);

    let prevDensity = textureLoad(dataTextureC, coord, 0).r;
    let accumulated = mix(contribR + contribB, prevDensity, clamp(decay, 0.0, 0.999));

    let shimmer  = treble * 0.08 * sin(accumulated * 40.0 + time * 3.0);
    let density  = clamp(accumulated * 7.0 + shimmer, 0.0, 1.0);

    // Chromatic palette: warm for right lobe, cool for left
    let warmCol = palette(density, 0.0);
    let coolCol = palette(density, 0.3);
    let lobeMix = smoothstep(-5.0, 5.0, viewX - panX);
    let col = mix(coolCol, warmCol, lobeMix);

    let alpha    = clamp(density * 0.9 + bass * 0.08, 0.0, 1.0);
    let finalOut = vec4<f32>(acesToneMap(col * 1.1), alpha);

    textureStore(dataTextureA, coord, vec4<f32>(accumulated, 0.0, 0.0, 0.0));
    textureStore(writeTexture, coord, finalOut);
    let depth = clamp(density * 0.8, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
