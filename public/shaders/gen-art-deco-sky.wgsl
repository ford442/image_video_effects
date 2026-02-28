// ═══════════════════════════════════════════════════════════════
//  Art Deco Skyscraper - Generative Shader
//  Category: Generative
//  Description: Infinite vertical ascent up a monumental Art Deco tower with gold fluting and geometric patterns.
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
    zoom_params: vec4<f32>,  // x=City Density, y=Ascent Speed, z=Gold Glow, w=Fog Density
    ripples: array<vec4<f32>, 50>,
};

// --- SDF Functions ---

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdBox2D(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}

// Equivalent to capped cylinder
fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Basic operations
fn opRepY(p: vec3<f32>, c: f32) -> vec3<f32> {
    return vec3<f32>(p.x, fract((p.y + c*0.5)/c) * c - c*0.5, p.z);
}

fn opSymXZ(p: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(abs(p.x), p.y, abs(p.z));
}

// Rotations
fn rotateY(p: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec3<f32>(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

// Noise / Hash
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// --- Scene Mapping ---

fn map(p: vec3<f32>) -> vec2<f32> {
    // Parameters
    let density = u.zoom_params.x; // 0..1
    let time = u.config.x;
    let ascentSpeed = u.zoom_params.y; // 0..5
    let y_offset = time * ascentSpeed * 5.0; // Global Y movement

    // We will apply the offset to p.y before mapping
    let pos = vec3<f32>(p.x, p.y + y_offset, p.z);

    var res_d = 1000.0;
    var res_mat = 0.0; // 1 = Black Marble, 2 = Gold, 3 = Glass Windows

    // 1. Central Tower
    var cp = pos;
    // Symmetry
    cp = opSymXZ(cp);

    // Base tower shape
    let base_width = 8.0;
    let base_depth = 8.0;

    // Stepped setbacks based on continuous Y
    let tier = floor(pos.y / 20.0);
    // Use modulo for infinite repeating setbacks if needed, or just let it be a straight tower for infinite ascent
    // Let's make repeating geometric patterns instead of a shrinking tower since it's infinite ascent

    // Core pillar
    let d_core = sdBox(cp, vec3<f32>(6.0, 1000000.0, 6.0));

    // Fluting (subtractive waves on X and Z facades)
    let fluting_freq = 2.0;
    let fluting_depth = 0.5;
    let fluting_x = cos(cp.x * fluting_freq) * fluting_depth;
    let fluting_z = cos(cp.z * fluting_freq) * fluting_depth;
    let d_fluting_facade = d_core + max(fluting_x, fluting_z) * (1.0 - smoothstep(5.0, 6.0, cp.y % 10.0));

    // Let's build a more structured repeating facade
    // Repetition period for floors/sections
    let floor_h = 10.0;
    let local_y = (fract((cp.y + floor_h * 0.5) / floor_h) - 0.5) * floor_h;

    // Main walls
    var d_walls = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(6.0, 5.0, 6.0));

    // Recessed windows
    let window_w = 4.0;
    let d_windows_cut = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(window_w, 4.0, 6.5));
    var d_windows = sdBox(vec3<f32>(cp.x, local_y, cp.z), vec3<f32>(window_w - 0.2, 3.8, 5.8));

    // Subtract windows from walls
    d_walls = max(d_walls, -d_windows_cut);

    // Add vertical columns (fluted)
    let d_col1 = sdBox(vec3<f32>(cp.x - 5.0, local_y, cp.z - 6.0), vec3<f32>(0.5, 5.0, 0.5));
    let d_col2 = sdBox(vec3<f32>(cp.x - 6.0, local_y, cp.z - 5.0), vec3<f32>(0.5, 5.0, 0.5));

    let fluted_col1 = d_col1 + cos(cp.x*10.0)*0.1 + cos(cp.z*10.0)*0.1;
    let fluted_col2 = d_col2 + cos(cp.x*10.0)*0.1 + cos(cp.z*10.0)*0.1;
    d_walls = min(d_walls, min(fluted_col1, fluted_col2));

    // Gold Trim (horizontal bands and geometric motifs)
    // Horizontal band
    let d_band = sdBox(vec3<f32>(cp.x, local_y - 4.5, cp.z), vec3<f32>(6.2, 0.5, 6.2));

    // Sunburst or stepped motif on the band
    let motif_x = sdBox(vec3<f32>(cp.x, local_y - 4.0, cp.z - 6.2), vec3<f32>(2.0 - cp.y%2.0, 1.0, 0.2));

    var d_gold = min(d_band, motif_x);

    // Decide materials
    if (d_walls < res_d) { res_d = d_walls; res_mat = 1.0; }
    if (d_windows < res_d) { res_d = d_windows; res_mat = 3.0; }
    if (d_gold < res_d) { res_d = d_gold; res_mat = 2.0; }

    // 2. Background Towers
    // Create a grid of background towers
    let cell_size = 40.0;
    let grid_xz = floor((pos.xz + cell_size * 0.5) / cell_size);
    let local_xz = (fract((pos.xz + cell_size * 0.5) / cell_size) - 0.5) * cell_size;

    let dist_to_center = length(grid_xz);
    if (dist_to_center > 0.5 && density > 0.0) {
        let h = hash(grid_xz);
        if (h < density) {
            // Build a simpler background tower
            let w = 4.0 + h * 4.0;
            // Repeating floor structure
            let bg_local_y = (fract((pos.y + 15.0 * 0.5) / 15.0) - 0.5) * 15.0;

            var d_bg_tower = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w, 7.5, w));

            // Background windows
            let d_bg_win = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w*0.8, 6.0, w+0.5));
            d_bg_tower = max(d_bg_tower, -d_bg_win);

            if (d_bg_tower < res_d) {
                res_d = d_bg_tower;
                res_mat = 1.0;
            }

            // BG interior windows
            let d_bg_win_inside = sdBox(vec3<f32>(local_xz.x, bg_local_y, local_xz.y), vec3<f32>(w*0.7, 5.0, w-0.5));
            if (d_bg_win_inside < res_d) {
                res_d = d_bg_win_inside;
                res_mat = 3.0;
            }
        }
    }

    return vec2<f32>(res_d, res_mat);
}

// --- Normals & Raymarching ---

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
    for(var i=0; i<150; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;
        if(d < 0.002 || t > 200.0) { break; }
        t += d * 0.8; // Step size slightly reduced for safety
    }
    return vec2<f32>(t, mat);
}

// Basic ambient occlusion
fn calcAO(p: vec3<f32>, n: vec3<f32>) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for(var i=0; i<5; i++) {
        let h = 0.01 + 0.12 * f32(i) / 4.0;
        let d = map(p + h * n).x;
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Parameters
    let goldGlow = u.zoom_params.z; // 0..2
    let fogDensity = u.zoom_params.w; // 0..1
    let time = u.config.x;
    let mouse = u.zoom_config.yz; // 0..1

    // Camera setup
    // Ascending with the tower (but we handle Y movement in the map function)
    // So camera stays relatively static in Y, looking around

    // Orbit camera based on mouse
    let cam_radius = 20.0 + (mouse.y - 0.5) * 10.0;
    let cam_angle = (mouse.x - 0.5) * 6.28 + time * 0.05;

    // Look slightly up
    let ro = vec3<f32>(sin(cam_angle) * cam_radius, -5.0, cos(cam_angle) * cam_radius);
    let ta = vec3<f32>(0.0, 5.0, 0.0);

    // Camera Basis
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    // Atmospheric Colors (Art Deco Night / Cyberpunk vibe)
    let fogColor = vec3<f32>(0.02, 0.05, 0.1); // Dark blueish night
    let lightColor1 = vec3<f32>(1.0, 0.8, 0.5); // Warm gold/yellow light
    let lightColor2 = vec3<f32>(0.2, 0.5, 1.0); // Cool blue fill light

    var color = fogColor;

    // Global Y offset for materials that depend on world pos
    let ascentSpeed = u.zoom_params.y;
    let y_offset = time * ascentSpeed * 5.0;

    if (t < 200.0) {
        let p = ro + rd * t;
        let world_p = vec3<f32>(p.x, p.y + y_offset, p.z);
        let n = calcNormal(p);
        let v = normalize(ro - p);

        // Material Properties
        var albedo = vec3<f32>(0.0);
        var rough = 0.5;
        var metallic = 0.0;
        var emission = vec3<f32>(0.0);

        if (mat == 1.0) {
            // Black Marble
            albedo = vec3<f32>(0.02, 0.02, 0.02);
            rough = 0.1; // highly reflective
            metallic = 0.2;
        } else if (mat == 2.0) {
            // Gold
            albedo = vec3<f32>(1.0, 0.7, 0.2);
            rough = 0.2;
            metallic = 1.0;
        } else if (mat == 3.0) {
            // Glass / Windows
            albedo = vec3<f32>(0.05, 0.05, 0.05);
            rough = 0.1;
            metallic = 0.8;

            // Window lights (randomly lit)
            // Determine grid cell for window
            let win_cell = floor(world_p.y / 1.0) * 10.0 + floor(world_p.x / 1.0) + floor(world_p.z / 1.0);
            let h = hash(vec2<f32>(win_cell, floor(world_p.y / 10.0))); // change per floor block too

            if (h > 0.6) {
                // Lit window
                emission = vec3<f32>(1.0, 0.8, 0.4) * goldGlow * 1.5;
                // Add some flickering
                emission *= 0.8 + 0.2 * sin(time * 5.0 + h * 100.0);
            }
        }

        // Lighting
        // Light 1: Directional Moon/City
        let l1_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff1 = max(dot(n, l1_dir), 0.0);
        let h1 = normalize(l1_dir + v);
        let spec1 = pow(max(dot(n, h1), 0.0), 128.0 * (1.0 - rough));

        // Light 2: Upward city glow
        let l2_dir = normalize(vec3<f32>(-1.0, -1.0, -0.5));
        let diff2 = max(dot(n, l2_dir), 0.0);

        let ao = calcAO(p, n);

        // Combine lighting
        var diffuse = (diff1 * lightColor1 + diff2 * lightColor2 * 0.5 + 0.1) * albedo;
        var specular = (spec1 * lightColor1) * (1.0 - rough) * (metallic * 0.5 + 0.5);

        // Fake reflections for metallic/smooth surfaces (mat 1 and 2)
        if (metallic > 0.1 || rough < 0.2) {
            let ref = reflect(-v, n);
            // Sample a fake env map (just use directional light and sky color)
            let env_spec = pow(max(dot(ref, l1_dir), 0.0), 32.0);
            // Add vertical gradient to reflection for sky/city
            let env_color = mix(fogColor, lightColor1 * 0.5, ref.y * 0.5 + 0.5);
            specular += (env_spec * lightColor1 + env_color * 0.2) * (1.0 - rough) * metallic;

            // If it's gold, tint reflection
            if (mat == 2.0) {
                specular *= albedo;
            }
        }

        color = (diffuse + specular) * ao + emission;

        // Add some glowing gold effect globally to gold material
        if (mat == 2.0) {
             color += albedo * goldGlow * 0.3 * ao;
        }

        // Distance Fog
        let fog_amount = 1.0 - exp(-t * (0.01 + fogDensity * 0.05));
        color = mix(color, fogColor, fog_amount);

        // Height Fog / City Glow
        // Simulate glow from the city below
        let height_fog = exp(-p.y * 0.1) * 0.5;
        color += lightColor1 * height_fog * fogDensity;
    } else {
        // Sky / Void
        // Add a vertical gradient for city glow
        let sky_glow = exp(-rd.y * 4.0) * 0.5;
        color += lightColor1 * sky_glow * fogDensity;
    }

    // Post processing / Vignette
    let vign = 1.0 - length(uv) * 0.5;
    color = color * vign;

    // Tone mapping (simple exposure/ACES fit approx)
    color = color / (color + vec3<f32>(1.0));
    color = pow(color, vec3<f32>(1.0 / 2.2)); // Gamma correction

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 200.0, 0.0, 0.0, 0.0));
}