// ----------------------------------------------------------------
// Bioluminescent Aether-Jellyfish Swarm
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Propulsion Speed, z=Bioluminescence Intensity, w=Tentacle Length
    ripples: array<vec4<f32>, 50>,
};

// Math and Hash Functions
const PI: f32 = 3.14159265359;

fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Simplex Noise (simplified version for organic perturbation)
fn snoise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);
    let n = p.x + p.y * 157.0 + p.z * 113.0;

    let v1 = mix(hash1(n + 0.0), hash1(n + 1.0), f_smooth.x);
    let v2 = mix(hash1(n + 157.0), hash1(n + 158.0), f_smooth.x);
    let v3 = mix(hash1(n + 113.0), hash1(n + 114.0), f_smooth.x);
    let v4 = mix(hash1(n + 270.0), hash1(n + 271.0), f_smooth.x);

    let res1 = mix(v1, v2, f_smooth.y);
    let res2 = mix(v3, v4, f_smooth.y);
    return mix(res1, res2, f_smooth.z) * 2.0 - 1.0;
}

// Rotations
fn rotX(angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

fn rotZ(angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat3x3<f32>(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

// SDF Functions
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Jellyfish Body Modeling
fn mapJellyfish(p_in: vec3<f32>, cell_id: vec3<f32>, t: f32, audio_propulsion: f32) -> f32 {
    var p = p_in;

    // Perturb points slightly to simulate organic breathing/pulse
    let noise_val = snoise(p * 2.0 + t * 0.5) * 0.05 * audio_propulsion;
    p += noise_val;

    // Bell (main body)
    let bell_sphere = sdSphere(p - vec3<f32>(0.0, 0.2, 0.0), 0.4);

    // Create the hollow underneath of the bell using a subtracted sphere
    let hollow_sphere = sdSphere(p - vec3<f32>(0.0, -0.1, 0.0), 0.35);
    let bell = max(bell_sphere, -hollow_sphere);

    // Central bioluminescent core
    let core = sdSphere(p - vec3<f32>(0.0, 0.2, 0.0), 0.15);

    // Combine bells and core softly
    var d = smin(bell, core, 0.1);

    // Simple tentacles using capsules and smin
    let tentacle_length = u.zoom_params.w;

    // Use noise to animate tentacles
    let wave = sin(p.y * 3.0 - t * 2.0 + cell_id.x * 10.0) * 0.1;
    let wave2 = cos(p.y * 2.5 - t * 1.5 + cell_id.y * 10.0) * 0.1;

    let t1 = sdCapsule(p, vec3<f32>(0.1, 0.0, 0.0), vec3<f32>(0.1 + wave, -tentacle_length, wave2), 0.02);
    let t2 = sdCapsule(p, vec3<f32>(-0.1, 0.0, 0.0), vec3<f32>(-0.1 + wave2, -tentacle_length, wave), 0.02);
    let t3 = sdCapsule(p, vec3<f32>(0.0, 0.0, 0.1), vec3<f32>(wave, -tentacle_length, -wave2), 0.02);
    let t4 = sdCapsule(p, vec3<f32>(0.0, 0.0, -0.1), vec3<f32>(-wave2, -tentacle_length, -wave), 0.02);

    let tentacles = min(min(t1, t2), min(t3, t4));

    d = smin(d, tentacles, 0.05);

    return d;
}

// Global scene mapping (Swarm domain repetition)
fn mapScene(pos: vec3<f32>, t: f32) -> vec2<f32> {
    // Determine grid size based on Swarm Density parameter
    let density = u.zoom_params.x;
    let spacing = mix(5.0, 1.5, density / 30.0); // Larger density -> smaller spacing

    // Apply a slow overarching swirl to the space
    let g_rot = rotY(t * 0.05);
    let p_space = pos * g_rot;

    // Domain repetition for swarm
    let cell_center = floor(p_space / spacing + vec3<f32>(0.5)) * spacing;
    var local_p = p_space - cell_center;

    // Unique properties per cell
    let cell_id = cell_center;
    let hash = hash33(cell_id);

    // Mouse Interaction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse.x * 5.0, -mouse.y * 5.0, 0.0);

    let dist_to_mouse = length(cell_center - mouse_pos);
    let repulse = normalize(cell_center - mouse_pos + vec3<f32>(0.001)) * (1.0 / (1.0 + dist_to_mouse * 1.5));

    // Add movement and drift
    let propulsion_speed = u.zoom_params.y;
    let audio_val = u.config.y * 0.5 + 0.5; // Audio influences pulsing

    let drift_x = sin(t * propulsion_speed + hash.x * 10.0) * 0.5;
    let drift_y = cos(t * propulsion_speed * 0.8 + hash.y * 10.0) * 0.5 + fract(t * propulsion_speed * 0.2 + hash.y) * spacing;
    let drift_z = sin(t * propulsion_speed * 1.1 + hash.z * 10.0) * 0.5;

    let drift_offset = vec3<f32>(drift_x, drift_y, drift_z) + repulse * 2.0;

    // Wrap around vertical axis to keep swarm continuous
    local_p = local_p - drift_offset;
    local_p = local_p - floor(local_p / spacing + vec3<f32>(0.5)) * spacing;

    // Rotate jelly slightly to face movement direction
    let dir = normalize(vec3<f32>(drift_x, 1.0, drift_z));

    // Evaluate geometry for this cell
    let dist = mapJellyfish(local_p, hash, t, audio_val);

    // Material ID: 1.0 for jelly
    return vec2<f32>(dist, 1.0);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, t: f32) -> vec2<f32> {
    var dO = 0.0;
    var mat_id = 0.0;
    for(var i=0; i<80; i++) {
        let p = ro + rd * dO;
        let dS = mapScene(p, t);
        dO += dS.x;
        mat_id = dS.y;
        if(dO > 50.0 || abs(dS.x) < 0.01) { break; }
    }
    if (dO > 50.0) { return vec2<f32>(-1.0, 0.0); }
    return vec2<f32>(dO, mat_id);
}

// Normals
fn getNormal(p: vec3<f32>, t: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    let n = vec3<f32>(
        mapScene(p + e.xyy, t).x - mapScene(p - e.xyy, t).x,
        mapScene(p + e.yxy, t).x - mapScene(p - e.yxy, t).x,
        mapScene(p + e.yyx, t).x - mapScene(p - e.yyx, t).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let tex_coords = vec2<i32>(id.xy);

    if (tex_coords.x >= i32(dims.x) || tex_coords.y >= i32(dims.y)) { return; }

    let res = vec2<f32>(f32(dims.x), f32(dims.y));
    let uv = (vec2<f32>(tex_coords) - 0.5 * res) / res.y;

    let time = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, 8.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    let rm = raymarch(ro, rd, time);
    let dist = rm.x;
    let mat = rm.y;

    // Background - Deep liquid abyss
    let bg_color = vec3<f32>(0.01, 0.02, 0.05) + length(uv) * 0.02;
    var final_color = bg_color;

    if (dist > 0.0) {
        let p = ro + rd * dist;
        let n = getNormal(p, time);

        let light_pos = vec3<f32>(0.0, 10.0, 10.0);
        let l = normalize(light_pos - p);
        let view_dir = normalize(ro - p);

        // Lighting
        let dif = max(dot(n, l), 0.0);

        // Subsurface scattering effect (Bioluminescence)
        let sss = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        let bio_intensity = u.zoom_params.z;
        let audio_pulse = u.config.y * 0.5 + 0.5;

        // Dynamic bioluminescent colors
        let base_col = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(0.8, 0.0, 1.0), sin(p.y + time) * 0.5 + 0.5);
        let bio_glow = base_col * sss * bio_intensity * (0.8 + 0.4 * audio_pulse);

        // Translucency (blend with background based on distance and rim lighting)
        final_color = mix(bg_color, bio_glow + vec3<f32>(dif * 0.1), sss * 0.8 + 0.2);

        // Fog/Depth fade
        final_color = mix(final_color, bg_color, clamp(dist / 30.0, 0.0, 1.0));
    } else {
        // Volumetric pass in empty space using noise to represent aether
        var v_col = vec3<f32>(0.0);
        for(var i=0; i<10; i++) {
            let p = ro + rd * f32(i) * 2.0;
            let val = snoise(p * 0.5 + time * 0.2);
            v_col += vec3<f32>(0.0, 0.5, 1.0) * max(0.0, val) * 0.01;
        }
        final_color += v_col;
    }

    // Tone mapping and gamma correction
    final_color = final_color / (final_color + vec3<f32>(1.0));
    final_color = pow(final_color, vec3<f32>(1.0/2.2));

    textureStore(writeTexture, tex_coords, vec4<f32>(final_color, 1.0));
}
