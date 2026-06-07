// ═══════════════════════════════════════════════════════════════════
//  fluid-grid-rgba-fluid
//  Category: advanced-hybrid
//  Features: fluid-simulation, grid-distortion, rgba-state-machine, mouse-driven
//  Complexity: Very High
//  Chunks From: fluid-grid.wgsl, alpha-fluid-simulation-paint.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A quantized grid where tile displacement is driven by a live
//  Navier-Stokes fluid simulation. Velocity advects grid offsets,
//  pressure creates bulges, and dye density tints the tile edges.
//  The fluid state is stored in dataTextureA for temporal evolution.
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

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let h = hsv.x * 6.0;
    let s = hsv.y;
    let v = hsv.z;
    let c = v * s;
    let x = c * (1.0 - abs(h - floor(h / 2.0) * 2.0 - 1.0));
    let m = v - c;
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3(x, 0.0, c); }
    else { rgb = vec3(c, 0.0, x); }
    return rgb + vec3(m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let ps = 1.0 / resolution;
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let time = u.config.x;

    let gridSize = 10.0 + u.zoom_params.x * 90.0;
    let viscosity = u.zoom_params.y;
    let dyeIntensity = u.zoom_params.z;
    let decayRate = mix(0.990, 0.999, u.zoom_params.w);

    // Read previous fluid state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var density = prevState.a;

    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // Semi-Lagrangian advection
    let dt = 0.016;
    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = textureSampleLevel(dataTextureC, u_sampler, backtraceUV, 0.0);
    vel = advected.rg;
    density = advected.a;

    // Diffusion
    let visc = viscosity * 0.001 + 0.0001;
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    vel += visc * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

    // Single Jacobi pressure projection
    let pL = left.b; let pR = right.b; let pD = down.b; let pU = up.b;
    let divergence = ((pR - pL) / (2.0 * ps.x) + (pU - pD) / (2.0 * ps.y));
    pressure = (pL + pR + pD + pU - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);
    vel -= vec2<f32>((pR - pL) / (2.0 * ps.x), (pU - pD) / (2.0 * ps.y)) * 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // Mouse force
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
    let mouseForce = normalize(uv - mousePos + vec2<f32>(0.0001)) * mouseInfluence * -0.3 * mouseDown;
    vel += mouseForce * dt * 15.0;

    // Ripple dye injection
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rippleDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
            density += inject * 0.5;
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            vel += dir * inject * 0.1;
        }
    }

    // Decay
    density *= decayRate;
    density = clamp(density, 0.0, 5.0);

    // Store fluid state
    textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, density));

    // Grid distortion driven by fluid velocity
    let aspect = resolution.x / resolution.y;
    let tileUV = floor(uv * gridSize) / gridSize;
    let tileCenter = tileUV + vec2<f32>(0.5 / gridSize, 0.5 / gridSize);

    // Sample fluid at tile center for displacement
    let fluidAtTile = textureSampleLevel(dataTextureC, u_sampler, tileCenter, 0.0);
    let tileVel = fluidAtTile.rg;
    let tilePressure = fluidAtTile.b;

    // Displace tile by fluid velocity + pressure bulge
    let push = length(tileVel) * 0.3 + abs(tilePressure) * 0.1;
    let offsetDir = normalize(tileVel + vec2<f32>(0.0001));
    let uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push;

    let sampleUV = uv - uvOffset;
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    // Grid lines tinted by fluid dye
    let gridLine = fract(uv * gridSize);
    let lineWeight = 0.05 * (1.0 - viscosity);
    let speed = length(tileVel);
    let hue = atan2(tileVel.y, tileVel.x) / 6.283185307 + 0.5;
    let sat = smoothstep(0.0, 0.02, speed) * 0.8;
    let val = min(density * dyeIntensity * 1.5 + 0.15, 1.0);
    let dyeColor = hsv2rgb(vec3<f32>(hue, sat, val));

    if (gridLine.x < lineWeight || gridLine.y < lineWeight) {
        color = mix(color, vec4<f32>(dyeColor, 1.0), 0.5);
    }

    textureStore(writeTexture, coord, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
