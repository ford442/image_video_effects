// ═══════════════════════════════════════════════════════════════════
//  Magnetic Field Warp
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-14
//  Ideas: Larmor gyration of the sampling point (ω_c ∝ |B|, r_L ∝ 1/|B|); synchrotron emission tint (j ∝ B^1.75, ν_c ∝ γ²B, polarization ⊥ B)
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Warp Strength, .y = Plasma Mix, .z = Turbulence, .w = Attractor Mix
  ripples: array<vec4<f32>, 50>,
};

const PHI = 1.618033988749895;

fn valueNoise(p: vec2<f32>) -> f32 {
    let ip = floor(p);
    let fp = fract(p);
    let u = fp * fp * (3.0 - 2.0 * fp);
    let h = vec4<f32>(dot(ip, vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(1.0, 0.0), vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(0.0, 1.0), vec2<f32>(127.1, 311.7)),
                      dot(ip + vec2<f32>(1.0, 1.0), vec2<f32>(127.1, 311.7)));
    let n = fract(sin(h) * 43758.5453123);
    return mix(mix(n.x, n.y, u.x), mix(n.z, n.w, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5;
    var s = 0.0;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02;
        a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0 * r);
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.005;
    let dx = warpedFBM(p + vec2<f32>(eps, 0.0), t) - warpedFBM(p - vec2<f32>(eps, 0.0), t);
    let dy = warpedFBM(p + vec2<f32>(0.0, eps), t) - warpedFBM(p - vec2<f32>(0.0, eps), t);
    return vec2<f32>(dy, -dx) / (2.0 * eps + 1e-6);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y));
}

// ── IDEA 2 helper: synchrotron spectrum colour ──
// Maps the critical frequency ν_c (normalised 0..1) of an electron population
// to a colour: low ν_c glows ember-red (radio-like), rising through magenta
// to blue-white for hard, strong-field emission.
fn synchrotronColor(nuC: f32) -> vec3<f32> {
    let x = clamp(nuC, 0.0, 1.0);
    let lo = vec3<f32>(1.0, 0.28, 0.08);
    let mid = vec3<f32>(0.95, 0.25, 0.85);
    let hi = vec3<f32>(0.55, 0.8, 1.35);
    return select(mix(mid, hi, (x - 0.5) * 2.0), mix(lo, mid, x * 2.0), x < 0.5);
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
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    let uv = vec2<f32>(coords) / vec2<f32>(res);
    let time = u.config.x;
    let aspect = u.config.z / max(u.config.w, 1.0);

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);

    // Domain-warped FBM turbulence on UV
    let warp = warpedFBM(uv * 3.0, time * 0.3);
    let turbUV = uv + (warp - 0.5) * 0.2 * u.zoom_params.z;

    // Mouse dipole field (held = energised coil)
    let mouse = u.zoom_config.yz;
    let delta = turbUV - mouse;
    let dist = length(delta);
    let safe_dist = max(dist, 0.001);
    let field_dir = select(vec2<f32>(0.0, 0.0), delta / safe_dist, dist > 0.001);
    let warp_strength = u.zoom_params.x * 2.5 * (1.0 + bass * 0.45) * (1.0 + held * 1.2);
    let dipole = field_dir * (warp_strength / (safe_dist * safe_dist + 0.05));

    // Divergence-free curl-noise vorticity
    let curl = curl2D(uv * 4.0 + time * 0.2, time) * 0.3 * (1.0 + bass * 0.35);

    // Clifford strange-attractor modulation
    let ca = 1.5 + bass * 0.5;
    let cd = -1.5 + sin(time * 0.1) * 0.3;
    let attractor = clifford(uv * 6.2831853, ca, -1.8, 1.2, cd);
    let a_weight = 0.12 * u.zoom_params.w;

    // Click ripples launch Alfvén waves: a transverse kink travelling outward
    // that shakes the field perpendicular to the propagation direction.
    var alfven = vec2<f32>(0.0);
    var alfvenEnergy = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.0) {
            let rd = (uv - rp.xy) * vec2<f32>(aspect, 1.0);
            let rl = max(length(rd), 0.0001);
            let front = rl - age * 0.45;
            let ring = exp(-front * front * 900.0) * exp(-age * 1.6);
            let perp = vec2<f32>(-rd.y, rd.x) / rl;
            alfven += perp * ring * sin(front * 120.0) * (1.0 + mids * 0.4);
            alfvenEnergy = max(alfvenEnergy, ring);
        }
    }

    let field = dipole + curl + attractor * a_weight + alfven * 3.0;
    let bMag = length(field);

    // ── IDEA 1: Larmor gyration ──
    // A charged particle in B circles its guiding centre at the cyclotron
    // frequency ω_c = qB/m with Larmor radius r_L = v⊥/ω_c. The sample point
    // gyrates the same way: strong-field regions spin tight and fast, weak-field
    // gaps swing in wide lazy loops. Warp Strength sets v⊥; treble heats it.
    let omegaC = 1.5 + clamp(bMag, 0.0, 12.0) * 1.1;
    let vPerp = (0.004 + u.zoom_params.x * 0.012) * (1.0 + treble * 0.6);
    let rL = clamp(vPerp * 6.0 / omegaC, 0.0, 0.03);
    let gyroPhase = time * omegaC + warp * 6.2831853;
    let gyro = vec2<f32>(cos(gyroPhase), sin(gyroPhase)) * rL;

    let warped_uv = uv + field * 0.04 + gyro;

    let safe_uv = clamp(warped_uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let maxCoord = res - vec2<i32>(1);
    let read_coords = clamp(vec2<i32>(safe_uv * vec2<f32>(res)), vec2<i32>(0), maxCoord);
    let color = textureLoad(readTexture, read_coords, 0);

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // ── IDEA 2: synchrotron emission (replaces the out-of-range plasma lookup) ──
    // Emissivity for a power-law electron population (p≈2.5): j ∝ B^((p+1)/2).
    // Critical frequency ν_c ∝ γ²B sets the colour; bass pumps the Lorentz
    // factor γ. Emission is linearly polarised ⊥ B — a slowly rotating
    // polariser (mids) reveals the field direction as cos² fringes.
    let bNorm = clamp(bMag * 0.35, 0.0, 1.0);
    let gamma2 = 1.0 + bass * 2.5;
    let emissivity = pow(bNorm, 1.75) * (0.6 + luma * 0.8);
    let nuC = clamp(bNorm * gamma2 * 0.55, 0.0, 1.0);
    let bAngle = atan2(field.y, field.x);
    let polariser = time * (0.15 + mids * 0.4);
    let polCos = cos(bAngle + 1.5707963 - polariser);
    let polarisation = 0.45 + 0.55 * polCos * polCos;
    let synchrotron = synchrotronColor(nuC) * emissivity * polarisation * 2.2
                    + vec3<f32>(0.6, 0.9, 1.3) * alfvenEnergy * 0.8;

    let mix_factor = clamp(u.zoom_params.y, 0.0, 1.0);
    let mixed_rgb = mix(color.rgb, color.rgb * 0.35 + synchrotron, mix_factor);

    // Alpha = radiated field energy: field strength, attractor weight,
    // synchrotron emissivity and Alfvén wavefronts.
    let energy = clamp(bMag * 0.25 + length(attractor) * a_weight * 3.0, 0.0, 1.0);
    let final_alpha = clamp(0.22 + energy * 0.4 + emissivity * mix_factor * 0.3 + alfvenEnergy * 0.25 + rL * 8.0, 0.0, 1.0);

    let finalColor = vec4<f32>(acesToneMap(mixed_rgb * (1.1 + bass * 0.15)), final_alpha);
    let outDepth = clamp(depth * (1.0 - energy * 0.15) + emissivity * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
