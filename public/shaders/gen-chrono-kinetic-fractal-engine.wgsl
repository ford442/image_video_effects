// ----------------------------------------------------------------
// Chrono-Kinetic Fractal Engine
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
  zoom_params: vec4<f32>,  // .x = Complexity, .y = Warp Strength, .z = Iridescence, .w = Kinetic Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Rotates in 4D (XY and ZW planes, basically handling a vec4)
fn rot4(p: vec4<f32>, a1: f32, a2: f32) -> vec4<f32> {
    var p2 = p;
    p2 = vec4<f32>(rot(a1) * p2.xy, p2.zw);
    p2 = vec4<f32>(p2.xy, rot(a2) * p2.zw);
    return p2;
}

// Distance Functions
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  var p2 = abs(p);
  let m = p2.x + p2.y + p2.z - s;
  var q: vec3<f32>;
  if (3.0 * p2.x < m) { q = p2; }
  else if (3.0 * p2.y < m) { q = vec3<f32>(p2.y, p2.z, p2.x); }
  else if (3.0 * p2.z < m) { q = vec3<f32>(p2.z, p2.x, p2.y); }
  else { return m * 0.57735027; }

  let k = clamp(0.5 * (q.z - q.y + s), 0.0, s);
  return length(vec3<f32>(q.x, q.y - s + k, q.z - k));
}


fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let t = u.config.x * u.zoom_params.w;

    // Audio Reactive element
    let audio_level = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;
    let audio_burst = audio_level * 0.5;

    // Mouse Interaction (Gravity Well / Time-dilation)
    let mouse = u.zoom_config.yz * 2.0 - vec2<f32>(1.0);
    // Remap mouse to same space as pos
    let aspect = u.config.z / u.config.w;
    let m_pos = vec3<f32>(mouse.x * aspect, -mouse.y, 0.0) * 5.0; // Scale to scene

    let dist_to_mouse = length(pos.xy - m_pos.xy);
    let warp_strength = u.zoom_params.y;
    let warp_factor = exp(-dist_to_mouse * 0.5) * warp_strength;

    // Apply Twist based on mouse proximity
    pos = vec3<f32>(rot(warp_factor * 5.0 + t) * pos.xy, pos.z);

    // Fractal space folding
    let spacing = vec3<f32>(4.0);
    pos = (pos % spacing + spacing) % spacing - spacing * 0.5; // True modulo domain repetition

    // 4D Rotation applied to 3D space with an imaginary W dimension
    var p4 = vec4<f32>(pos, 1.0);
    p4 = rot4(p4, t * 0.5, t * 0.3);
    pos = p4.xyz;

    var orbit_trap = 100.0;

    let complexity = i32(u.zoom_params.x * 5.0) + 2;
    let max_i = clamp(complexity, 2, 7);

    var d = 100.0;

    // Procedural Temporal Gears
    for(var i = 0; i < max_i; i++) {
        let fi = f32(i);
        pos = abs(pos) - vec3<f32>(0.5 + audio_burst);
        pos = vec3<f32>(rot(t * 0.2 + fi * 0.5) * pos.xy, pos.z);
        pos = vec3<f32>(pos.x, rot(t * 0.3 - fi * 0.3) * pos.yz);

        let t_d = sdTorus(pos, vec2<f32>(1.0 + sin(t+fi)*0.2, 0.1));
        let o_d = sdOctahedron(pos, 0.8);

        // Complex boolean with smin
        let step_d = smin(t_d, o_d, 0.2);
        d = smin(d, step_d, 0.3);

        orbit_trap = min(orbit_trap, length(pos));
    }

    return vec2<f32>(d, orbit_trap);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

// Cosine based palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos( 6.28318 * (c * t + d) );
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.zw);
    let coords = vec2<i32>(id.xy);

    if (f32(coords.x) >= dimensions.x || f32(coords.y) >= dimensions.y) {
        return;
    }

    var uv = (vec2<f32>(coords) - 0.5 * dimensions) / dimensions.y;

    // Jitter for AA / Chromatic Aberration
    let t = u.config.x;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0 + t * 2.0); // Moving forward
    let ta = vec3<f32>(0.0, 0.0, ro.z + 1.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);

    var col = vec3<f32>(0.0);

    // Chromatic Aberration offsets
    let offsets = array<vec2<f32>, 3>(
        vec2<f32>(0.005, 0.0), // R
        vec2<f32>(0.0, 0.0),   // G
        vec2<f32>(-0.005, 0.0) // B
    );

    let iridescence = u.zoom_params.z;

    for (var i = 0; i < 3; i++) {
        let rd_uv = uv + offsets[i] * iridescence * 0.5;
        let rd = normalize(rd_uv.x * cu + rd_uv.y * cv + 1.5 * cw);

        var dO = 0.0;
        var m = 0.0;
        var p = vec3<f32>(0.0);

        for (var i_step = 0; i_step < MAX_STEPS; i_step++) {
            p = ro + rd * dO;
            let dS = map(p);
            dO += dS.x;
            m = dS.y;
            if (dS.x < SURF_DIST || dO > MAX_DIST) {
                break;
            }
        }

        var channel_col = 0.0;

        if (dO < MAX_DIST) {
            let n = calcNormal(p);

            // Lighting
            let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let diff = max(dot(n, light_dir), 0.0);

            // Iridescent Coloring based on orbit trap and view angle
            let view_dir = normalize(ro - p);
            let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

            let pal_a = vec3<f32>(0.5, 0.5, 0.5);
            let pal_b = vec3<f32>(0.5, 0.5, 0.5);
            let pal_c = vec3<f32>(1.0, 1.0, 1.0);
            let pal_d = vec3<f32>(0.263, 0.416, 0.557) + m * 0.1 + iridescence * fresnel;

            let base_col = palette(m * 2.0 + t, pal_a, pal_b, pal_c, pal_d);

            let final_val = base_col * diff + fresnel * iridescence;
            channel_col = final_val[i];

            // Add a neon bloom mask
            channel_col += exp(-m * 5.0) * 0.5; // Glow based on orbit trap
        } else {
            // Background / Void
            channel_col = 0.01;
        }

        col[i] = channel_col;
    }

    // Tone mapping and gamma correction
    col = col / (vec3<f32>(1.0) + col);
    col = pow(col, vec3<f32>(1.0/2.2));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
