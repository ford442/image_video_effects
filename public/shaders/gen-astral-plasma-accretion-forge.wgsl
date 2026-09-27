// ═══════════════════════════════════════════════════════════════════
//  Astral Plasma Accretion Forge
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: midplane dust-lane absorption (front-to-back transmittance, Core Temp sublimation radius); Keplerian shear lanes (Omega ∝ r^-1.5 two-phase flow-map); gravitational redshift of disk temperature and intensity
//  A packing: ACES display RGBA
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
  zoom_params: vec4<f32>,  // .x = Core Density, .y = Accretion Spin, .z = Flux Intensity, .w = Core Temp
  ripples: array<vec4<f32>, 50>,
};

// --- Noise Functions ---
fn hash3(p: vec3<f32>) -> f32 {
    var p2 = fract(p * 0.3183099 + 0.1);
    p2 = p2 * 17.0;
    return fract(p2.x * p2.y * p2.z * (p2.x + p2.y + p2.z));
}

fn snoise(x: vec3<f32>) -> f32 {
    let step = vec3<f32>(110.0, 241.0, 171.0);
    let i = floor(x);
    let f = fract(x);
    let n = dot(i, step);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(hash3(i + vec3<f32>(0.0,0.0,0.0)), hash3(i + vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(hash3(i + vec3<f32>(0.0,1.0,0.0)), hash3(i + vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(hash3(i + vec3<f32>(0.0,0.0,1.0)), hash3(i + vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(hash3(i + vec3<f32>(0.0,1.0,1.0)), hash3(i + vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for(var i=0; i<5; i=i+1) {
        f = f + w * snoise(pp);
        pp = pp * 2.0;
        w = w * 0.5;
    }
    return f;
}

// Rotations
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Idea 2: Keplerian shear lanes — two-phase flow-map ages so the differential
// winding stays bounded: each layer's shear age ramps 0..PERIOD and resets while
// its triangle crossfade weight is zero.
const SHEAR_PERIOD: f32 = 16.0;
fn shear_phase(time: f32) -> vec3<f32> {
    let ph = fract(time / SHEAR_PERIOD);
    return vec3<f32>(ph * SHEAR_PERIOD, fract(ph + 0.5) * SHEAR_PERIOD, 1.0 - abs(2.0 * ph - 1.0));
}

// Orbital frame: HEAD's static 1/(r+0.1) spiral twist + rigid time*spin rotation,
// plus (Idea 2) Keplerian differential rotation Omega ∝ r_xz^-1.5, normalised to 1
// at the torus centreline r_xz = 1.5, so the inner rim laps the outer rim.
// Fix: HEAD rebuilt the frame with the 3D radius as the xz radius.
fn kepler_frame(p: vec3<f32>, time: f32, spin: f32, age: f32) -> vec3<f32> {
    let r = length(p);
    let r_xz = length(p.xz);
    let theta = atan2(p.x, p.z);
    let omega = pow(1.5 / max(r_xz, 0.35), 1.5);
    let twist = theta + (1.0 / (r + 0.1)) * spin * 2.0 + time * spin + spin * (omega - 1.0) * age;
    return vec3<f32>(sin(twist) * r_xz, p.y, cos(twist) * r_xz);
}

// Distance estimation and density
fn map(p: vec3<f32>, time: f32, audio: f32, spin: f32, density: f32) -> f32 {
    // Gravitational lensing / distortion (Keplerian-sheared orbital frame, layer A)
    let sp = shear_phase(time);
    let distorted_p = kepler_frame(p, time, spin, sp.x);

    // Flatten torus for accretion disk
    let disk_p = distorted_p * vec3<f32>(1.0, 4.0, 1.0);

    // Base shape (disk)
    let d_torus = length(vec2<f32>(length(disk_p.xz) - 1.5, disk_p.y)) - 0.5;

    // Add noise for fluid/plasma
    var n = fbm(distorted_p * 2.0 - vec3<f32>(0.0, time, 0.0));
    // Idea 2: crossfade in shear layer B near the disk (far away d stays > 0.1
    // whatever the noise, so only the step length would differ).
    if (d_torus < 1.2) {
        let distorted_b = kepler_frame(p, time, spin, sp.y);
        n = mix(fbm(distorted_b * 2.0 - vec3<f32>(0.0, time, 0.0)), n, sp.z);
    }

    // Combine
    var d = d_torus + n * 0.5;
    d = d * 0.5; // slow march

    // Audio flare logic - expand density along poles
    let flare_y = abs(p.y) - audio * 2.0;
    let flare = max(flare_y, length(p.xz) - 0.2 - audio * 0.5);

    // Smooth min to combine disk and flare
    let h = clamp( 0.5 + 0.5*(flare-d)/0.5, 0.0, 1.0 );
    return mix( flare, d, h ) - 0.5*h*(1.0-h);
}

// Idea 1: dust lanes — cool midplane dust riding the same Keplerian-sheared frame.
// Azimuthally elongated (radial frequency 6 vs azimuthal 1.5) so shear winds it into
// trailing spiral lanes; sublimated inside r_sub, which the Core Temp pushes outward.
fn dust_lanes(p: vec3<f32>, time: f32, spin: f32, core_temp: f32) -> f32 {
    let sp = shear_phase(time);
    let r_xz = length(p.xz);
    let qa = kepler_frame(p, time, spin, sp.x);
    let qb = kepler_frame(p, time, spin, sp.y);
    let base = vec3<f32>(r_xz * 6.0, p.y * 14.0, 0.0);
    let na = snoise(base + qa * 1.5) * 0.65 + snoise(base * 2.0 + qa * 3.0 + vec3<f32>(5.2, 1.3, 8.7)) * 0.35;
    let nb = snoise(base + qb * 1.5) * 0.65 + snoise(base * 2.0 + qb * 3.0 + vec3<f32>(5.2, 1.3, 8.7)) * 0.35;
    let lanes = smoothstep(0.42, 0.60, mix(nb, na, sp.z));
    let midplane = 1.0 - smoothstep(0.05, 0.16, abs(p.y));
    let r_sub = 0.9 + 0.5 * core_temp;
    let sublimation = smoothstep(r_sub, r_sub + 0.25, r_xz);
    return lanes * midplane * sublimation;
}

// Idea 3: gravitational redshift g = sqrt(1 - rs/r), taken relative to the disk
// centreline (r = 1.5): g < 1 toward the well (inner rim cools and dims, the
// temperature peak lifts off the rim), g > 1 on the far outer disk. Stylised:
// intensity scales by g (not the bolometric g^4) so the inner rim stays readable.
const REDSHIFT_RS: f32 = 0.55;
fn redshift_g(r: f32) -> f32 {
    return sqrt(max(1.0 - REDSHIFT_RS / max(r, 1e-3), 0.0) / (1.0 - REDSHIFT_RS / 1.5));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Color mapping (blackbody)
fn get_color(temp: f32) -> vec3<f32> {
    let t = clamp(temp, 0.0, 1.0);
    let col = vec3<f32>(
        pow(t, 0.5) * 1.5,
        pow(t, 2.0) * 1.2,
        pow(t, 4.0) * 2.0
    );
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let uv = vec2<f32>(f32(global_id.x), f32(global_id.y)) / resolution;
    let ndc = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    var ro = vec3<f32>(0.0, 2.0, -4.0);
    var rd = normalize(vec3<f32>(ndc.x * aspect, -ndc.y, 1.5));

    // Mouse interaction (Gravitational Anomaly)
    var m = u.zoom_config.yz;
    if (u.zoom_config.w > 0.5) {
        m = (m - 0.5) * 2.0;
        let rot = rotY(m.x * 3.14) * rotX(m.y * 3.14);
        ro = rot * ro;
        rd = rot * rd;
    } else {
        let rot = rotY(u.config.x * 0.1) * rotX(-0.3);
        ro = rot * ro;
        rd = rot * rd;
    }

    // Parameters
    let core_density = u.zoom_params.x;
    let accretion_spin = u.zoom_params.y;
    let flux_intensity = u.zoom_params.z;
    let core_temp = u.zoom_params.w;

    // Audio Reactivity (plasmaBuffer bass/mids; HEAD sampled its own C history)
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let audio = clamp((bass * 0.7 + mids * 0.3) * 0.5, 0.0, 0.5);

    // Singularity Core (Black Hole) — intersected before the march so the march
    // can stop at the horizon (fix: HEAD zeroed emission in FRONT of it too).
    var dist_to_center = 999.0;
    let v_to_center = -ro;
    let b = dot(v_to_center, rd);
    let c = dot(v_to_center, v_to_center) - 0.2*0.2; // radius 0.2
    let h = b*b - c;
    if (h > 0.0) {
        dist_to_center = b - sqrt(h);
    }
    let hole_ahead = dist_to_center > 0.0 && dist_to_center < 999.0;

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var p = ro;

    var color = vec3<f32>(0.0);
    var trans = 1.0;          // Idea 1: front-to-back transmittance
    var hit_horizon = false;
    var t_surface = -1.0;

    let max_steps = 80;
    let max_dist = 10.0;

    // Raymarch for volumetric density
    for(var i=0; i<max_steps; i=i+1) {
        p = ro + rd * t;
        if (hole_ahead && t >= dist_to_center) {
            hit_horizon = true; // far side occluded by the horizon
            break;
        }
        d = map(p, u.config.x, audio, accretion_spin, core_density);

        // Volumetric accumulation
        if (d < 0.1) {
            let dens = (0.1 - d) * 10.0;

            // Temperature gradient
            let dist_to_core = length(p);
            // Idea 3: gravitational redshift — observed T *= g, intensity *= g
            let g = redshift_g(dist_to_core);
            let local_temp = ((1.0 / (dist_to_core + 0.1)) * core_temp + audio * 0.5) * g;
            // Idea 1: cool dust emits 10% and absorbs 9x (Core Density = extinction)
            let dust = dust_lanes(p, u.config.x, accretion_spin, core_temp);
            let c = get_color(local_temp) * g * (1.0 - 0.9 * dust);
            color = color + trans * c * dens * 0.05;
            trans = trans * exp(-dens * 0.05 * core_density * (1.0 + 8.0 * dust));
            if (t_surface < 0.0 && trans < 0.9) {
                t_surface = t;
            }
        }

        t = t + max(d, 0.05); // step size min to avoid getting stuck
        if (t > max_dist || trans < 0.02) {
            break;
        }
    }

    // Volumetric Bloom (Fake) — the horizon silhouette hides the part of the core
    // glow behind it (Idea 3's well emits almost nothing near the hole, so this is
    // what keeps the small black sphere readable).
    let bloom_factor = (1.0 / (length(cross(ro, rd)) + 0.1));
    let bloom_occlusion = select(1.0, 0.3, hit_horizon);
    color = color + get_color(core_temp * 0.8) * bloom_factor * 0.1 * flux_intensity * bloom_occlusion;

    // Add audio flare glow
    let flare_glow = audio * 0.5 / (length(cross(ro, rd)) + 0.1);
    color = color + vec3<f32>(0.8, 0.4, 1.0) * flare_glow;

    // ACES display + semantic alpha (plasma coverage / horizon occluder / glow)
    let display = acesToneMap(color);
    let coverage = max(1.0 - trans, select(0.0, 1.0, hit_horizon));
    let alpha = clamp(max(coverage, dot(display, vec3<f32>(0.2126, 0.7152, 0.0722))), 0.0, 1.0);
    let final_color = vec4<f32>(display, alpha);

    // Depth: first opaque-ish plasma, else the horizon; near = 1, miss = 0
    var hit_t = t_surface;
    if (hit_t < 0.0 && hit_horizon) {
        hit_t = dist_to_center;
    }
    let depth = select(0.0, 1.0 - clamp(hit_t / max_dist, 0.0, 1.0), hit_t >= 0.0);

    textureStore(writeTexture, global_id.xy, final_color);
    textureStore(dataTextureA, global_id.xy, final_color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
