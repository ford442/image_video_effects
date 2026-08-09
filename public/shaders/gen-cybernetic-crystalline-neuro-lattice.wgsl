// ----------------------------------------------------------------
// Cybernetic Crystalline Neuro-Lattice
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotate 3D space
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Organic gyroid base
fn sdGyroid(p: vec3<f32>, scale: f32) -> f32 {
    let q = p * scale;
    return abs(dot(sin(q), cos(q.zxy)) / scale) - 0.05;
}

// Crystalline IFS folding
fn ifsCrystals(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.5, 0.5);
        p = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), PI * 0.25) * p;
        p = abs(p) - vec3<f32>(0.2, 0.2, 0.2);
    }
    return p;
}

// Main SDF
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction: localized data surge/bending
    let mouse = u.zoom_config.yz; // (0..1, 0..1)
    let mouse_pos = vec3<f32>((mouse.x - 0.5) * 10.0, (0.5 - mouse.y) * 10.0, 0.0);

    // Bend towards mouse if close
    let dist_to_mouse = length(p - mouse_pos);
    let bend_factor = smoothstep(5.0, 0.0, dist_to_mouse) * 1.5;

    if (u.zoom_config.w > 0.0) { // mouse down
        p = p + normalize(p - mouse_pos) * sin(u.config.x * 20.0 - dist_to_mouse * 5.0) * 0.2 * bend_factor;
    }

    // Audio reactivity - slight scaling based on a data ripple (if any are active)
    var audioReact = 0.0;
    if (u.config.y > 0.0) {
        audioReact = u.ripples[0].w;
    }
    let time = u.config.x + audioReact * 0.1;
    let growthSpeed = u.zoom_params.y; // 0.0 to 1.0

    // Rotate overall structure slowly
    p = rot3D(normalize(vec3<f32>(0.2, 0.8, 0.5)), time * growthSpeed) * p;

    // Infinite domain repetition
    let density = u.zoom_params.x * 5.0 + 1.0; // 1.0 to 6.0
    let cell_size = 8.0 / density;
    let q = p % cell_size - (cell_size * 0.5);

    // Crystalline details
    let c = ifsCrystals(q);

    // Gyroid network
    let d_gyroid = sdGyroid(q, 1.5 + sin(time) * 0.5);

    // Box SDF for the crystals
    let d_crystal = length(max(abs(c) - vec3<f32>(0.3, 0.3, 0.3), vec3<f32>(0.0))) - 0.05;

    // Smoothmin between organic network and crystals
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (d_gyroid - d_crystal) / k, 0.0, 1.0);
    let d_combined = mix(d_gyroid, d_crystal, h) - k * h * (1.0 - h);

    // Material ID: 0.0 for crystal/nodes, 1.0 for gyroid connections
    let mat = mix(1.0, 0.0, h);

    return vec2<f32>(d_combined * 0.5, mat);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * resolution) / resolution.y;

    let ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat = 0.0;
    var d = 0.0;

    // Raymarching
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        mat = res.y;

        if (d < 0.001 || t > 30.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.02, 0.02, 0.04); // Dark obsidian background
    let glitch = u.zoom_params.z; // 0.0 to 1.0
    let hueShift = u.zoom_params.w * PI * 2.0; // 0.0 to 2PI

    if (t < 30.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;
        let r = reflect(rd, n);

        // Basic lighting
        let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, -2.0));

        let diff1 = max(dot(n, l1), 0.0);
        let diff2 = max(dot(n, l2), 0.0);
        let spec = pow(max(dot(r, l1), 0.0), 32.0);

        // Base color
        var baseCol = vec3<f32>(0.05, 0.05, 0.05); // Obsidian

        // Neon emission
        if (mat < 0.5) {
            // Nodes (Crystal)
            var neonCol = vec3<f32>(0.0, 1.0, 1.0); // Cyan base
            // Rotate Hue
            neonCol = neonCol * cos(hueShift) + cross(vec3<f32>(1.0, 1.0, 1.0) / sqrt(3.0), neonCol) * sin(hueShift) + vec3<f32>(1.0, 1.0, 1.0) / 3.0 * dot(vec3<f32>(1.0, 1.0, 1.0) / sqrt(3.0), neonCol) * (1.0 - cos(hueShift));

            // Subsurface scattering / glow effect based on depth & time
            let sss = smoothstep(0.0, 1.0, map(p + n * 0.1).x * 10.0);
            let emission = (1.0 - sss) * 2.0;

            baseCol = mix(baseCol, neonCol, 0.8) + neonCol * emission;
        } else {
            // Gyroid connections
            let t_val = u.config.x * 2.0 + length(p) * 2.0;
            let pulse = sin(t_val) * 0.5 + 0.5;
            var edgeCol = vec3<f32>(1.0, 0.0, 1.0); // Magenta base

            // Glitch chromatic aberration on edges based on curvature/normal derivative
            if (glitch > 0.0) {
                 edgeCol.r += glitch * sin(t_val * 5.0) * 0.5;
                 edgeCol.b += glitch * cos(t_val * 7.0) * 0.5;
            }

            baseCol += edgeCol * pulse * 0.5;
        }

        col = baseCol * (diff1 * 0.6 + diff2 * 0.4) + vec3<f32>(1.0) * spec;

        // Fog
        col = mix(col, vec3<f32>(0.02, 0.02, 0.04), 1.0 - exp(-0.02 * t * t));
    }

    // Mouse down shockwave post-process
    if (u.zoom_config.w > 0.0) {
        let center = vec2<f32>(0.5, 0.5);
        let dist = length(uv);
        let shock = sin(dist * 50.0 - u.config.x * 20.0) * exp(-dist * 5.0);
        col += vec3<f32>(shock * glitch, shock * glitch * 0.5, shock * glitch * 0.2);
    }

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
