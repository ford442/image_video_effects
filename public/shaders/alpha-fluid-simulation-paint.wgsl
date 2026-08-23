// ═══════════════════════════════════════════════════════════════════
//  Alpha Fluid Simulation Paint
//  Category: simulation
//  Features: mouse-as-brush, audio-viscosity, depth-paint-thickness, pressure-dynamics, temporal
//  Complexity: High
//  RGBA Channels:
//    R = velocity.x (signed f32, left/right flow)
//    G = velocity.y (signed f32, up/down flow)
//    B = pressure (signed f32, negative = suction)
//    A = dye density (0.0 = clear, 1.0+ = saturated)
//  Why f32: velocity and pressure require negative values and
//  sub-pixel precision; 8-bit would collapse to [0,1] and break
//  incompressibility.
//  Updated: 2026-05-31 — Grok (audio viscosity seasons + depth-as-paint-thickness)
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

fn loadState(p: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
    let hi = vec2<i32>(res) - vec2<i32>(1);
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn loadStateLinear(uv: vec2<f32>, res: vec2<f32>) -> vec4<f32> {
    let p = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * res - 0.5;
    let i = vec2<i32>(floor(p));
    let f = fract(p);
    let a = mix(loadState(i, res), loadState(i + vec2<i32>(1, 0), res), f.x);
    let b = mix(loadState(i + vec2<i32>(0, 1), res), loadState(i + vec2<i32>(1, 1), res), f.x);
    return mix(a, b, f.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let prevState = loadState(coord, res);
    var vel = prevState.rg;
    var pressure = prevState.b;
    var density = prevState.a;

    // Clamp velocity to prevent divergence
    let maxVel = 0.5;
    vel = clamp(vel, vec2<f32>(-maxVel), vec2<f32>(maxVel));

    // === ADVECTION (semi-Lagrangian backtrace) ===
    let backtraceUV = clamp(uv - vel * dt, vec2<f32>(0.0), vec2<f32>(1.0));
    let advected = loadStateLinear(backtraceUV, res);
    vel = advected.rg;
    density = advected.a;

    // === DIFFUSION (viscosity now seasonal) ===
    // bass = thicker fluid (honey), treble = thinner (water)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let visc = mix(0.0008f, 0.0022f, u.zoom_params.x) * (0.6 + bass * 0.7 - treble * 0.4);
    let left = loadState(coord + vec2<i32>(-1, 0), res);
    let right = loadState(coord + vec2<i32>(1, 0), res);
    let down = loadState(coord + vec2<i32>(0, -1), res);
    let up = loadState(coord + vec2<i32>(0, 1), res);
    vel += visc * (left.rg + right.rg + down.rg + up.rg - 4.0 * vel);

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
    let aspect = res.x / res.y;
    let mouseDist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let mouseInfluence = smoothstep(0.15, 0.0, mouseDist);
    let mouseForce = normalize(uv - mousePos + vec2<f32>(0.0001)) * mouseInfluence * -0.3;
    vel += mouseForce * dt * (2.0 + mouseDown * 13.0) * (1.0 + mids * 0.5);
    density += mouseInfluence * (0.004 + mouseDown * 0.08) * (1.0 + bass * 0.4);

    // === RIPPLE DYE INJECTION ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        let age = u.config.x - ripple.z;
        if (age >= 0.0 && age < 2.0 && rippleDist < 0.16) {
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
    let val = density * u.zoom_params.y * (1.5 + bass * 0.5) + 0.15;
    var displayColor = hsv2rgb(vec3<f32>(fract(hue + mids * 0.08), sat, val));
    displayColor += vec3<f32>(0.25, 0.65, 1.0) * abs(curl) * treble * 0.25;
    displayColor = acesToneMap(displayColor);

    let sourceAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    let alpha = clamp(sourceAlpha * 0.35 + 1.0 - exp(-density * 1.4), 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(displayColor, alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
