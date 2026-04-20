// ═══════════════════════════════════════════════════════════════════
//  Alpha EM Field Simulation
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Electric field X (signed f32)
//    G = Electric field Y (signed f32)
//    B = Magnetic field Z / potential (signed f32)
//    A = Charge density (signed f32, positive/negative charges)
//  Why f32: EM fields oscillate with negative values; charge can be
//  positive or negative. 8-bit unsigned cannot represent this.
//  Chunks From: valueNoise, fbm2 (chunk-library.md)
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

// ═══ CHUNK: hash12 (from chunk-library.md / gen_grid.wgsl) ═══
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
    var eField = prevState.rg;
    var bField = prevState.b;
    var charge = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        eField = vec2<f32>(0.0);
        bField = 0.0;
        charge = 0.0;
        // Place a dipole in the center
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.03) {
            charge = 1.0;
        }
        let negDist = length(uv - vec2<f32>(0.55, 0.5));
        if (negDist < 0.03) {
            charge = -1.0;
        }
    }

    // Clamp fields
    eField = clamp(eField, vec2<f32>(-2.0), vec2<f32>(2.0));
    bField = clamp(bField, -2.0, 2.0);
    charge = clamp(charge, -2.0, 2.0);

    // === WAVE EQUATION UPDATE ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapE = left.rg + right.rg + down.rg + up.rg - 4.0 * eField;
    let lapB = left.b + right.b + down.b + up.b - 4.0 * bField;

    let c = 0.3; // wave speed
    let dt = 0.5;

    // Electric field update
    eField += lapE * c * c * dt;
    // Magnetic field update
    bField += lapB * c * c * dt * 0.5;

    // Charge relaxation (diffusion)
    let lapCharge = left.a + right.a + down.a + up.a - 4.0 * charge;
    charge += lapCharge * 0.1 * dt;

    // === CHARGE SOURCES ===
    // Mouse injects charge
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    let clickParity = select(-1.0, 1.0, u.config.y % 2.0 < 1.0);
    charge += mouseInfluence * clickParity * 0.5;

    // Ripples inject alternating charges
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let age = time - ripple.z;
        if (age < 1.0 && rDist < 0.05) {
            let strength = smoothstep(0.05, 0.0, rDist) * max(0.0, 1.0 - age);
            let sign = select(-1.0, 1.0, f32(i) % 2.0 < 1.0);
            charge += strength * sign * 0.3;
        }
    }

    // === DAMPING ===
    let damping = mix(0.90, 0.99, u.zoom_params.x);
    eField *= damping;
    bField *= damping * 0.95;
    charge *= 0.998;

    // Clamp again
    eField = clamp(eField, vec2<f32>(-2.0), vec2<f32>(2.0));
    bField = clamp(bField, -2.0, 2.0);
    charge = clamp(charge, -2.0, 2.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(eField, bField, charge));

    // === VISUALIZATION ===
    let eStrength = length(eField);
    let eDir = atan2(eField.y, eField.x) / 6.283185307 + 0.5;

    // Background noise field
    let noiseVal = fbm2(uv * 4.0 + time * 0.05, 4);

    // Color: E-field direction -> hue, E-field strength -> saturation
    var displayColor: vec3<f32>;
    if (eStrength > 0.01) {
        // HSV-like mapping
        let hue = eDir;
        let sat = min(eStrength * 2.0, 1.0);
        let val = min(eStrength * 3.0 + 0.1, 1.0);
        // Simple hue-to-rgb
        let h6 = hue * 6.0;
        let c = val * sat;
        let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
        let m = val - c;
        var rgb: vec3<f32>;
        if (h6 < 1.0) { rgb = vec3(c, x, 0.0); }
        else if (h6 < 2.0) { rgb = vec3(x, c, 0.0); }
        else if (h6 < 3.0) { rgb = vec3(0.0, c, x); }
        else if (h6 < 4.0) { rgb = vec3(0.0, x, c); }
        else if (h6 < 5.0) { rgb = vec3(x, 0.0, c); }
        else { rgb = vec3(c, 0.0, x); }
        displayColor = rgb + vec3(m);
    } else {
        displayColor = vec3<f32>(noiseVal * 0.05);
    }

    // Charge visualization: positive = warm, negative = cool
    let chargeVis = charge * u.zoom_params.y;
    displayColor.r += max(0.0, chargeVis) * 0.5;
    displayColor.b += max(0.0, -chargeVis) * 0.5;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // B-field adds brightness variation
    displayColor *= 1.0 + bField * u.zoom_params.z * 0.3;
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, abs(charge)));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
