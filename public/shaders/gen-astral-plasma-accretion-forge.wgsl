// ----------------------------------------------------------------
// Astral Plasma Accretion Forge
// Category: generative
// ----------------------------------------------------------------
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

// Distance estimation and density
fn map(p: vec3<f32>, time: f32, audio: f32, spin: f32, density: f32) -> f32 {
    // Gravitational lensing / distortion
    let r = length(p);
    let theta = atan2(p.x, p.z);

    // Twist based on radius and spin
    let twist = theta + (1.0 / (r + 0.1)) * spin * 2.0 + time * spin;
    let distorted_p = vec3<f32>(sin(twist)*r, p.y, cos(twist)*r);

    // Flatten torus for accretion disk
    let disk_p = distorted_p * vec3<f32>(1.0, 4.0, 1.0);

    // Base shape (disk)
    let d_torus = length(vec2<f32>(length(disk_p.xz) - 1.5, disk_p.y)) - 0.5;

    // Add noise for fluid/plasma
    let n = fbm(distorted_p * 2.0 - vec3<f32>(0.0, time, 0.0));

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

    // Audio Reactivity
    let audio_sample = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.1, 0.5), 0.0).r;
    let audio = audio_sample * 0.5;

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var p = ro;

    var color = vec3<f32>(0.0);
    var density_accum = 0.0;

    let max_steps = 80;
    let max_dist = 10.0;

    // Raymarch for volumetric density
    for(var i=0; i<max_steps; i=i+1) {
        p = ro + rd * t;
        d = map(p, u.config.x, audio, accretion_spin, core_density);

        // Volumetric accumulation
        if (d < 0.1) {
            let dens = (0.1 - d) * 10.0;
            density_accum = density_accum + dens * 0.05 * core_density;

            // Temperature gradient
            let dist_to_core = length(p);
            let local_temp = (1.0 / (dist_to_core + 0.1)) * core_temp + audio * 0.5;
            let c = get_color(local_temp);
            color = color + c * dens * 0.05;
        }

        t = t + max(d, 0.05); // step size min to avoid getting stuck
        if (t > max_dist || density_accum > 1.0) {
            break;
        }
    }

    // Singularity Core (Black Hole)
    var dist_to_center = 999.0;
    let v_to_center = -ro;
    let b = dot(v_to_center, rd);
    let c = dot(v_to_center, v_to_center) - 0.2*0.2; // radius 0.2
    let h = b*b - c;
    if (h > 0.0) {
        dist_to_center = b - sqrt(h);
    }

    if (dist_to_center > 0.0 && dist_to_center < t) {
        color = vec3<f32>(0.0); // Black hole is black
    }

    // Volumetric Bloom (Fake)
    let bloom_factor = (1.0 / (length(cross(ro, rd)) + 0.1));
    color = color + get_color(core_temp * 0.8) * bloom_factor * 0.1 * flux_intensity;

    // Add audio flare glow
    let flare_glow = audio * 0.5 / (length(cross(ro, rd)) + 0.1);
    color = color + vec3<f32>(0.8, 0.4, 1.0) * flare_glow;

    // HDR Tonemapping
    let final_color = vec4<f32>(color / (color + vec3<f32>(1.0)), 1.0);

    textureStore(writeTexture, global_id.xy, final_color);
}
