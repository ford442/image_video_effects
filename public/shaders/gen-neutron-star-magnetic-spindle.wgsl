// ----------------------------------------------------------------
// Neutron-Star Magnetic Spindle
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
  zoom_params: vec4<f32>,  // .x = Core Density, .y = Spin Rate, .z = Jet Intensity, .w = Disk Scale
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Rotates a 2D vector by an angle
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Spherical SDF
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Torus SDF for the accretion disk
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// fBM for volumetric noise in disk and jets
fn hash3(p: vec3<f32>) -> f32 {
    let q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q.x + sin(q.y) + sin(q.z)) * 43758.5453);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - 2.0 * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f2.x),
                   mix(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
               mix(mix(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f2.x),
                   mix(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y), f2.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i = 0; i < 4; i = i + 1) {
        f += w * noise3(x);
        x = x * 2.0;
        w *= 0.5;
    }
    return f;
}

// Maps distances to the scene objects
fn map(p: vec3<f32>, time: f32, core_density: f32, spin_rate: f32, disk_scale: f32, audio_pulse: f32) -> vec2<f32> {
    // Distance to core
    let r = length(p);

    // Twist space based on inverse distance (frame dragging effect)
    let twist_amount = spin_rate * (1.0 / (r + 0.5)) + time;
    var p_twisted = p;
    p_twisted.x = p.x * cos(twist_amount) - p.z * sin(twist_amount);
    p_twisted.z = p.x * sin(twist_amount) + p.z * cos(twist_amount);

    // Singularity Core (object ID 1.0)
    let core_radius = 0.5 * core_density + audio_pulse * 0.1;
    let d_core = sdSphere(p, core_radius);

    // Accretion Disk (object ID 2.0)
    let d_disk = sdTorus(p_twisted, vec2<f32>(1.5 * disk_scale, 0.1)) + fbm(p_twisted * 5.0 - vec3<f32>(0.0, time*2.0, 0.0)) * 0.2;

    // Polar Jets (object ID 3.0)
    // Cylinder-like SDF along Y axis, tapering off
    let jet_radius = 0.1 * (1.0 + abs(p.y) * 0.5) * (1.0 + audio_pulse);
    let d_jet = length(p_twisted.xz) - jet_radius;
    let jet_bounded = max(d_jet, abs(p.y) - 4.0); // Bound height

    var res = vec2<f32>(d_core, 1.0);

    // Smooth min between disk and core
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (res.x - d_disk) / k, 0.0, 1.0);
    let d_smooth_disk = mix(res.x, d_disk, h) - k * h * (1.0 - h);
    if (d_smooth_disk < res.x) {
        res = vec2<f32>(d_smooth_disk, 2.0);
    }

    if (jet_bounded < res.x) {
        res = vec2<f32>(jet_bounded, 3.0);
    }

    return res;
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32, core_density: f32, spin_rate: f32, disk_scale: f32, audio_pulse: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, core_density, spin_rate, disk_scale, audio_pulse).x - map(p - e.xyy, time, core_density, spin_rate, disk_scale, audio_pulse).x,
        map(p + e.yxy, time, core_density, spin_rate, disk_scale, audio_pulse).x - map(p - e.yxy, time, core_density, spin_rate, disk_scale, audio_pulse).x,
        map(p + e.yyx, time, core_density, spin_rate, disk_scale, audio_pulse).x - map(p - e.yyx, time, core_density, spin_rate, disk_scale, audio_pulse).x
    ));
}

// Blackbody palette approximation
fn blackbody(temp: f32) -> vec3<f32> {
    let t = temp * 4.0;
    var c = vec3<f32>(
        min(1.0, max(0.0, (t - 0.0) * 1.5)),
        min(1.0, max(0.0, (t - 1.0) * 1.5)),
        min(1.0, max(0.0, (t - 2.0) * 1.5))
    );
    // Add blueish core for extreme temps
    c += vec3<f32>(0.1, 0.2, 1.0) * max(0.0, t - 3.0);
    return c;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    let uv = vec2<f32>(coords) / resolution;
    let base_uv = uv; // Keep for texture sampling if needed

    // Audio Reactivity
    let audio_data = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(uv.x, 0.5), 0.0).r;
    let audio_pulse = audio_data * 2.0; // Scale it

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_ang_x = (mouse.x - 0.5) * PI * 2.0;
    let mouse_ang_y = (mouse.y - 0.5) * PI;

    // Parameters
    let time = u.config.x;
    let core_density = u.zoom_params.x; // (1.0, 0.1, 5.0, 0.1)
    let spin_rate = u.zoom_params.y;    // (1.0, 0.0, 3.0, 0.1)
    let jet_intensity = u.zoom_params.z;// (1.5, 0.0, 5.0, 0.1)
    let disk_scale = u.zoom_params.w;   // (1.0, 0.5, 3.0, 0.1)

    // Ray setup
    let clip_uv = (uv - 0.5) * 2.0;
    let aspect = resolution.x / resolution.y;
    let p_ndc = vec2<f32>(clip_uv.x * aspect, clip_uv.y);

    var ro = vec3<f32>(0.0, 0.0, 5.0); // Camera pos
    var rd = normalize(vec3<f32>(p_ndc, -1.5));

    // Apply mouse rotation
    let rot_x = rot(-mouse_ang_x); // orbit
    let rot_y = rot(mouse_ang_y);  // tilt

    ro = vec3<f32>(rot_x * ro.xz, ro.y).xzy;
    rd = vec3<f32>(rot_x * rd.xz, rd.y).xzy;

    ro = vec3<f32>(ro.x, rot_y * ro.yz).xzy;
    rd = vec3<f32>(rd.x, rot_y * rd.yz).xzy;


    // Raymarching
    var t = 0.0;
    var obj_id = 0.0;
    let max_steps = 128;
    let max_dist = 20.0;

    var p = ro;

    // Volumetric accumulators
    var v_density = 0.0;
    var v_color = vec3<f32>(0.0);

    for (var i = 0; i < max_steps; i = i + 1) {
        p = ro + rd * t;
        let res = map(p, time, core_density, spin_rate, disk_scale, audio_pulse);
        let d = res.x;

        // Volumetric integration for jets and disk aura
        if (d < 1.0) { // Near objects
            let r = length(p);

            // Accretion disk volumetric
            if (abs(p.y) < 0.5 && r > 0.5 && r < 3.0 * disk_scale) {
               let den = fbm(p * 2.0 - vec3<f32>(0.0, time, 0.0));
               let heat = 1.0 / (r * r) * (1.0 + audio_pulse * 0.5); // hotter near core
               v_density += 0.02 * den;
               v_color += blackbody(heat * 0.8) * 0.02 * den;
            }

            // Polar Jet volumetric
            let jet_d = length(p.xz);
            if (jet_d < 0.5 * jet_intensity && abs(p.y) > 0.5) {
                let den = fbm(p * vec3<f32>(2.0, 0.5, 2.0) - vec3<f32>(0.0, time * 5.0 * sign(p.y), 0.0));
                let heat = jet_intensity * (1.0 / (abs(p.y) + 1.0)) * (1.0 + audio_pulse);
                v_density += 0.03 * den;
                v_color += blackbody(heat * 0.9) * 0.03 * den;
            }
        }

        if (d < 0.001) {
            obj_id = res.y;
            break;
        }
        if (t > max_dist) {
            break;
        }

        // Gravity Lensing (bend ray towards center)
        let G = 0.1 * core_density;
        let r_sq = dot(p, p);
        if (r_sq > 0.1) {
            let force = -normalize(p) * (G / r_sq);
            rd = normalize(rd + force * 0.05); // Step-wise bending
        }

        t += d * 0.7; // Under-step for volume/bending
    }

    var final_color = vec3<f32>(0.0);

    if (t < max_dist) {
        let hit = ro + rd * t;
        let n = calcNormal(hit, time, core_density, spin_rate, disk_scale, audio_pulse);

        if (obj_id == 1.0) {
            // Singularity Core (Black hole / super dense star)
            // Relativistic Doppler beaming effect approximation
            let v_rot = cross(vec3<f32>(0.0, 1.0, 0.0), hit); // velocity vector (rough)
            let doppler = dot(rd, normalize(v_rot)) * spin_rate;

            let temp = 0.5 + doppler * 0.5 + audio_pulse;
            final_color = mix(vec3<f32>(0.1, 0.0, 0.2), vec3<f32>(1.0, 1.0, 1.0), clamp(temp, 0.0, 1.0));

            // Rim lighting
            let rim = 1.0 - max(0.0, dot(-rd, n));
            final_color += vec3<f32>(0.5, 0.2, 1.0) * pow(rim, 4.0);
        } else if (obj_id == 2.0) {
            // Solid part of Accretion Disk (if hit)
            let heat = 1.0 / length(hit);
            final_color = blackbody(heat);
        }
    }

    // Add volumetric accumulation
    final_color += v_color;

    // Tone mapping and gamma correction
    final_color = final_color / (1.0 + final_color); // Reinhard tone mapping
    final_color = pow(final_color, vec3<f32>(1.0 / 2.2));

    // Vignette
    let uv_c = uv - 0.5;
    let vignette = 1.0 - dot(uv_c, uv_c) * 1.5;
    final_color *= max(0.0, vignette);

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
}
