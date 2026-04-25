// ═══════════════════════════════════════════════════════════════════
//  Alpha Fluid Simulation Paint
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = velocity.x (signed f32, left/right flow)
//    G = velocity.y (signed f32, up/down flow)
//    B = pressure (signed f32, negative = suction)
//    A = dye density (0.0 = clear, 1.0+ = saturated)
//  Why f32: velocity and pressure require negative values and
//  sub-pixel precision; 8-bit would collapse to [0,1] and break
//  incompressibility.
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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hsv2rgb (from agent-4c spec) ═══
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

    // Read previous simulation state from dataTextureC
    let prevState = textureLoad(dataTextureC, coord, 0);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var density = prevState.a;

    // Clamp velocity to prevent divergence
    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === ADVECTION (semi-Lagrangian backtrace) ===
    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = textureSampleLevel(dataTextureC, u_sampler, backtraceUV, 0.0);
    vel = advected.rg;
    density = advected.a;

    // === DIFFUSION (viscosity) ===
    let viscosity = u.zoom_params.x * 0.001 + 0.0001;
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    vel += viscosity * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

    // === PRESSURE PROJECTION (single Jacobi step) ===
    let pL = left.b;
    let pR = right.b;
    let pD = down.b;
    let pU = up.b;
    let divergence = ((pR - pL) / (2.0 * ps.x) + (pU - pD) / (2.0 * ps.y));
    pressure = (pL + pR + pD + pU - divergence * ps.x * ps.x * 4.0) * 0.25;
    pressure = clamp(pressure, -2.0, 2.0);

    // Subtract pressure gradient from velocity
    vel -= vec2<f32>((pR - pL) / (2.0 * ps.x), (pU - pD) / (2.0 * ps.y)) * 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === VORTICITY CONFINEMENT ===
    let vortL = left.rg.y;
    let vortR = right.rg.y;
    let vortD = down.rg.x;
    let vortU = up.rg.x;
    let curl = (vortR - vortL) - (vortU - vortD);
    let vorticityStrength = u.zoom_params.z * 0.005;
    vel += vec2<f32>(abs(curl) * sign(curl) * vorticityStrength) * vec2<f32>(1.0, -1.0);
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === MOUSE FORCE ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
    let mouseForce = normalize(uv - mousePos + vec2<f32>(0.0001)) * mouseInfluence * -0.3 * mouseDown;
    vel += mouseForce * dt * 15.0;

    // === RIPPLE DYE INJECTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        let age = u.config.x - ripple.z;
        if (age < 2.0 && rippleDist < 0.08) {
            let inject = smoothstep(0.08, 0.0, rippleDist) * max(0.0, 1.0 - age * 0.5);
            density += inject * 0.5;
            // Inject velocity from ripple center
            let dir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
            vel += dir * inject * 0.1;
        }
    }

    // === DECAY ===
    let decayRate = mix(0.990, 0.999, u.zoom_params.w);
    density *= decayRate;
    density = clamp(density, 0.0, 5.0);

    // === STORE SIMULATION STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(vel, pressure, density));

    // === VISUALIZATION (state -> display color) ===
    let speed = length(vel);
    let hue = atan2(vel.y, vel.x) / 6.283185307 + 0.5;
    let sat = smoothstep(0.0, 0.02, speed) * 0.8;
    let val = density * u.zoom_params.y * 1.5 + 0.15;
    let displayColor = hsv2rgb(vec3<f32>(hue, sat, min(val, 1.0)));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, density));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
