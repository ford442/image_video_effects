// ═══════════════════════════════════════════════════════════════════
//  Ink Bleed Fluid
//  Category: advanced-hybrid
//  Features: fluid-simulation, ink-diffusion, physical-media, temporal,
//            mouse-driven
//  Complexity: Very High
//  Chunks From: ink-bleed, alpha-fluid-simulation-paint
//  Created: 2026-04-18
//  By: Agent CB-26
// ═══════════════════════════════════════════════════════════════════
//  Ink that flows according to Navier-Stokes fluid dynamics. Mouse
//  injects ink and velocity; fluid advection carries pigment across
//  the canvas. Paper texture still absorbs ink differentially.
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

// ═══ CHUNK: paperTexture (from ink-bleed) ═══
fn paperTexture(uv: vec2<f32>) -> f32 {
    let noise = fract(sin(dot(uv * 100.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    return 0.9 + 0.1 * noise;
}

// ═══ CHUNK: hsv2rgb (from alpha-fluid-simulation-paint) ═══
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
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let dt = 0.016;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Parameters
    let inkHue = u.zoom_params.x;
    let viscosity = u.zoom_params.y * 0.001 + 0.0001;
    let spreadSpeed = u.zoom_params.z;
    let density = u.zoom_params.w;
    let fadeSpeed = 0.005;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = res.x / res.y;

    // Read previous fluid+ink state from dataTextureC
    // RG = fluid velocity, B = pressure, A = ink density
    let prevState = textureLoad(dataTextureC, coord, 0);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var inkDensity = prevState.a;

    // Clamp velocity
    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === FLUID ADVECTION ===
    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = textureSampleLevel(dataTextureC, u_sampler, backtraceUV, 0.0);
    vel = advected.rg;
    inkDensity = advected.a;

    // === DIFFUSION (viscosity + ink spread) ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    vel += viscosity * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

    // === PRESSURE PROJECTION ===
    let divergence = ((right.b - left.b) / (2.0 * ps.x) + (up.b - down.b) / (2.0 * ps.y));
    pressure = (left.b + right.b + down.b + up.b - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);
    vel -= vec2<f32>((right.b - left.b) / (2.0 * ps.x), (up.b - down.b) / (2.0 * ps.y)) * 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === VORTICITY CONFINEMENT ===
    let curl = (right.rg.y - left.rg.y) - (up.rg.x - down.rg.x);
    let vorticityStrength = spreadSpeed * 0.005;
    vel += vec2<f32>(abs(curl) * sign(curl) * vorticityStrength) * vec2<f32>(1.0, -1.0);
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === MOUSE INK INJECTION ===
    let d = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let brushSize = 0.05;
    var newInk = 0.0;
    if (mouseDown > 0.5 && d < brushSize) {
        newInk = smoothstep(brushSize, 0.0, d);
        let mouseForce = normalize(uv - mouse + vec2<f32>(0.0001)) * smoothstep(0.15, 0.0, d) * -0.3;
        vel += mouseForce * dt * 15.0;
    }

    // === RIPPLE INK INJECTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 2.0 && rippleDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
            inkDensity += inject * 0.5;
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            vel += dir * inject * 0.1;
        }
    }

    inkDensity = min(inkDensity + newInk, 1.0);

    // === INK DIFFUSION (paper-based) ===
    let avgInk = (left.a + right.a + down.a + up.a) * 0.25;
    inkDensity = mix(inkDensity, avgInk, spreadSpeed * 0.1);

    // Fade
    inkDensity *= (1.0 - fadeSpeed);
    if (inkDensity < 0.001) { inkDensity = 0.0; }
    inkDensity = clamp(inkDensity, 0.0, 5.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, inkDensity));

    // === RENDER ===
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Ink color from hue
    let inkColorRGB = hsv2rgb(vec3<f32>(inkHue, 0.8, 0.25));
    let paperTex = paperTexture(uv);

    let inkThickness = inkDensity * density;
    let dilution = 1.0 - density * 0.5;
    var inkAlpha = inkThickness * (0.9 - dilution * 0.4) + 0.1;
    let absorption = mix(0.7, 1.0, paperTex);
    inkAlpha *= absorption;
    let feather = smoothstep(0.0, 0.3, inkThickness);
    inkAlpha *= feather;

    var finalRGB = mix(videoColor, inkColorRGB * videoColor, inkThickness);
    let paperColor = vec3<f32>(0.98, 0.97, 0.95) * paperTex;
    finalRGB = mix(paperColor, finalRGB, inkAlpha);

    // Fluid visualization overlay (subtle velocity coloring)
    let speed = length(vel);
    let velHue = atan2(vel.y, vel.x) / 6.283185307 + 0.5;
    let velColor = hsv2rgb(vec3<f32>(velHue, smoothstep(0.0, 0.02, speed) * 0.3, 0.1));
    finalRGB += velColor * speed * 2.0;

    textureStore(writeTexture, coord, vec4<f32>(finalRGB, inkAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
