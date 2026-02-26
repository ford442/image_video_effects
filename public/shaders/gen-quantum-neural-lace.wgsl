// ═══════════════════════════════════════════════════════════════
//  Quantum Neural Lace - Generative Shader
//  Category: generative
//  Description: A mesmerizing 3D visualization of a hyper-advanced neural interface.
//               Crystalline lattice of quantum nodes connected by pulsating,
//               organic fiber-optic strands.
//  Features: raymarched, mouse-driven
//  Tags: cyber, network, 3d, raymarching, scifi, glowing, lattice
// ═══════════════════════════════════════════════════════════════

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
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Density, y=PulseSpeed, z=Distortion, w=Glow
    ripples: array<vec4<f32>, 50>,
};

// --- SDF Primitives ---

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

// --- Helper Functions ---

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // Parameters
    let density = mix(2.0, 6.0, u.zoom_params.x); // Node spacing
    let distortion = u.zoom_params.z;             // Sine wave amplitude

    // 1. Domain Repetition
    let cell_size = 8.0 / density;
    let half_cell = cell_size * 0.5;

    let id = floor((p + half_cell) / cell_size);
    let local_p = (fract((p + half_cell) / cell_size) - 0.5) * cell_size;

    // 2. Nodes (Octahedrons)
    let node_size = cell_size * 0.15;
    // Rotate octahedron slightly over time for dynamic feel
    var p_rot = local_p;
    p_rot.xz = rotate2D(p_rot.xz, u.config.x * 0.5);
    p_rot.xy = rotate2D(p_rot.xy, u.config.x * 0.3);

    let d_node = sdOctahedron(p_rot, node_size);

    // 3. Strands (Connecting Cylinders)
    // We need connections along X, Y, Z axes to neighbors.
    // In a simple repetition, the "connections" are just infinite cylinders passing through the centers?
    // No, standard opRep makes localized objects.
    // To connect them, we can place cylinders that span the cell.

    // Axis X cylinder
    // Add distortion
    let wave = sin(p.z * 2.0 + u.config.x) * distortion * 0.2;
    let d_cyl_x = length(local_p.yz + vec2<f32>(wave, 0.0)) - node_size * 0.3;

    // Axis Y cylinder
    let d_cyl_y = length(local_p.xz) - node_size * 0.3;

    // Axis Z cylinder
    let d_cyl_z = length(local_p.xy) - node_size * 0.3;

    // Union cylinders
    let d_strands = min(d_cyl_x, min(d_cyl_y, d_cyl_z));

    // Smooth blend nodes and strands
    let d_struct = smin(d_node, d_strands, 0.2);

    // Material ID: 1.0 = Structure
    // We can vary material based on proximity to center for glow logic later
    var mat = 1.0;

    // Check if we are "inside" a pulse zone
    // Pulse travels along the grid
    // Use world position `id` to determine pulse state?
    // Or just simple sine waves

    return vec2<f32>(d_struct, mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat = 0.0;
    for(var i=0; i<128; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }
    return vec2<f32>(t, mat);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera Setup
    let mouse = u.zoom_config.yz; // 0..1
    let time = u.config.x;

    // Orbit controls
    let radius = 8.0;
    let yaw = (mouse.x - 0.5) * 6.28;
    let pitch = (mouse.y - 0.5) * 3.14;

    // Limit pitch to avoid flipping
    let safe_pitch = clamp(pitch, -1.5, 1.5);

    let cam_pos = vec3<f32>(
        radius * cos(safe_pitch) * sin(yaw),
        radius * sin(safe_pitch),
        radius * cos(safe_pitch) * cos(yaw)
    );

    // Add forward movement
    let forward_speed = 1.0;
    let cam_offset = vec3<f32>(0.0, 0.0, time * forward_speed);

    let ro = cam_pos + cam_offset;
    let target = cam_offset; // Look at point ahead

    let forward = normalize(target - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    let rd = normalize(forward + right * uv.x + up * uv.y);

    // Raymarching
    let res = raymarch(ro, rd);
    let t = res.x;

    var color = vec3<f32>(0.0);
    let bg_color = vec3<f32>(0.0, 0.02, 0.05); // Deep cyber blue

    if (t < 100.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let light_dir = normalize(vec3<f32>(0.5, 0.8, -0.5));

        // Base Lighting (Blinn-Phong)
        let diff = max(dot(n, light_dir), 0.0);

        let view_dir = normalize(ro - p);
        let halfway = normalize(light_dir + view_dir);
        let spec = pow(max(dot(n, halfway), 0.0), 32.0);

        // Material Colors
        let base_col = vec3<f32>(0.1, 0.15, 0.2); // Dark metallic

        // Emission / Pulse Logic
        // Pulse moves along the structure
        let pulse_speed = u.zoom_params.y * 5.0;
        let pulse_freq = 0.5;
        // Distance from some origin or just world coordinate waves
        let pulse_wave = sin(length(p) * pulse_freq - time * pulse_speed);
        let pulse_mask = smoothstep(0.8, 1.0, pulse_wave);

        let glow_intensity = u.zoom_params.w;
        let glow_col = vec3<f32>(0.0, 0.8, 1.0); // Cyan glow

        // Add "data packet" bright spots
        let packet = pow(pulse_mask, 8.0) * 2.0;

        color = base_col * (diff * 0.5 + 0.1) + vec3<f32>(spec);
        color += glow_col * packet * glow_intensity;

        // Rim lighting
        let rim = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);
        color += vec3<f32>(0.5, 0.0, 0.8) * rim * 0.5; // Purple rim

        // Fog
        let fog_amount = 1.0 - exp(-t * 0.08);
        color = mix(color, bg_color, fog_amount);

    } else {
        // Background with digital dust?
        color = bg_color;
    }

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
