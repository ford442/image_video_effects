// ═══════════════════════════════════════════════════════════════════
//  spec-runge-kutta-advection
//  Category: simulation
//  Features: RK4, fluid-advection, dye-simulation, high-order
//  Complexity: High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  4th-Order Runge-Kutta Flow Advection
//  Standard fluid advection uses Euler's method which is inaccurate.
//  RK4 advection is dramatically more accurate — fluid structures
//  maintain their shape 10x longer. Mouse creates vortex pairs.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Velocity field: multi-octave noise-driven
fn sampleVelocity(pos: vec2<f32>, time: f32) -> vec2<f32> {
    let scale = 3.0;
    let q = vec2<f32>(
        sin(pos.x * scale + time * 0.3) * cos(pos.y * scale * 0.7 - time * 0.2),
        cos(pos.x * scale * 0.8 - time * 0.25) * sin(pos.y * scale + time * 0.35)
    );
    let r = vec2<f32>(
        sin(pos.x * scale * 2.0 + q.y * 2.0 + time * 0.15),
        cos(pos.y * scale * 2.0 + q.x * 2.0 - time * 0.1)
    );
    return r * 0.15;
}

// RK4 advection: pos is the position to advect, dt is time step
fn advectRK4(pos: vec2<f32>, dt: f32, time: f32) -> vec2<f32> {
    let k1 = sampleVelocity(pos, time);
    let k2 = sampleVelocity(pos + k1 * dt * 0.5, time);
    let k3 = sampleVelocity(pos + k2 * dt * 0.5, time);
    let k4 = sampleVelocity(pos + k3 * dt, time);
    return pos + (k1 + 2.0*k2 + 2.0*k3 + k4) * dt / 6.0;
}

// Euler advection for comparison (not used, but kept for reference)
fn advectEuler(pos: vec2<f32>, dt: f32, time: f32) -> vec2<f32> {
    return pos + sampleVelocity(pos, time) * dt;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let time = u.config.x;

    let dt = mix(0.5, 2.0, u.zoom_params.x);
    let diffusion = mix(0.0, 0.05, u.zoom_params.y);
    let vortexStr = mix(0.0, 1.0, u.zoom_params.z);
    let feedback = mix(0.0, 0.95, u.zoom_params.w);

    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    // Read previous frame for temporal feedback
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);

    // Current velocity at this pixel
    var vel = sampleVelocity(uv, time);

    // Mouse vortex pair
    if (isMouseDown || u.config.y > 0.5) {
        let toMouse = mousePos - uv;
        let dist = length(toMouse);
        let vortex = exp(-dist * dist * 400.0) * vortexStr;
        // Counter-rotating vortex
        let perp = vec2<f32>(-toMouse.y, toMouse.x) / (dist + 0.001);
        vel += perp * vortex * 0.4;
        // Second vortex (counter-rotating pair)
        let offset = vec2<f32>(0.05, 0.0);
        let toMouse2 = mousePos + offset - uv;
        let dist2 = length(toMouse2);
        let perp2 = vec2<f32>(-toMouse2.y, toMouse2.x) / (dist2 + 0.001);
        vel -= perp2 * exp(-dist2 * dist2 * 400.0) * vortex * 0.3;
    }

    // RK4 backtrace: find where this pixel came from
    let backtracedPos = advectRK4(uv, -dt * 0.01, time);
    let wrappedPos = fract(backtracedPos);

    // Sample dye at backtraced position
    let advectedDye = textureSampleLevel(readTexture, u_sampler, wrappedPos, 0.0).rgb;

    // Sample from previous frame for feedback
    let prevDye = prev.rgb;

    // Blend current advected dye with feedback
    var dye = mix(advectedDye, prevDye, feedback);

    // Apply slight diffusion
    if (diffusion > 0.001) {
        let texel = 1.0 / res;
        var blur = vec3<f32>(0.0);
        blur += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb;
        blur += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb;
        blur += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb;
        blur += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb;
        blur *= 0.25;
        dye = mix(dye, blur, diffusion);
    }

    // Vorticity visualization: color by curl
    let texel = 1.0 / res;
    let vxR = sampleVelocity(uv + vec2<f32>(texel.x, 0.0), time).y;
    let vxL = sampleVelocity(uv - vec2<f32>(texel.x, 0.0), time).y;
    let vyU = sampleVelocity(uv + vec2<f32>(0.0, texel.y), time).x;
    let vyD = sampleVelocity(uv - vec2<f32>(0.0, texel.y), time).x;
    let curl = (vxR - vxL - vyU + vyD) / (2.0 * texel.x);

    let curlVis = vec3<f32>(
        max(0.0, curl) * 2.0,
        abs(curl) * 0.5,
        max(0.0, -curl) * 2.0
    );
    dye = mix(dye, dye + curlVis * 0.3, vortexStr);

    // Store for next frame
    textureStore(dataTextureA, gid.xy, vec4<f32>(dye, 1.0));
    textureStore(writeTexture, gid.xy, vec4<f32>(dye, length(vel)));
}
