// ----------------------------------------------------------------
// Luminescent Chrono-Fluid Astrolabe
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>, // x: resolution.x, y: resolution.y, z: time, w: aspect
  zoom_config: vec4<f32>, // x: mouse.x, y: mouse.y, z: is_clicking, w: audio_intensity
  zoom_params: vec4<f32>, // param1: Ring Complexity, param2: Fluidity, param3: Core Glow Intensity, param4: Rotation Speed
  ripples: array<vec4<f32>, 50>
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}


const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Simplex noise based on iq's implementation
fn hash(p: f32) -> f32 {
    let q = fract(vec3<f32>(p) * vec3<f32>(17.1705, 31.7153, 51.4881));
    return fract(q.x * q.y * q.z * 13.13);
}

fn noise3D(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_smooth = f * f * (vec3<f32>(3.0) - vec2<f32>(2.0).xxx * f);

    let n = p.x + p.y * 57.0 + 113.0 * p.z;

    let res = mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f_smooth.x),
                      mix(hash(n + 57.0), hash(n + 58.0), f_smooth.x), f_smooth.y),
                  mix(mix(hash(n + 113.0), hash(n + 114.0), f_smooth.x),
                      mix(hash(n + 170.0), hash(n + 171.0), f_smooth.x), f_smooth.y), f_smooth.z);
    return res;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    var d = MAX_DIST;
    var mat_id = 0.0;

    let time = u.config.z * u.zoom_params.w; // Rotation Speed
    let audio = u.zoom_config.w;

    // Mouse Interaction (Gravity Well)
    let mouse = u.zoom_config.xy * 2.0 - 1.0;
    let dist_to_mouse = length(p.xy - mouse * 5.0);
    let gravity_pull = 1.0 / (dist_to_mouse * dist_to_mouse + 1.0);
    p.x += mouse.x * gravity_pull * 0.5;
    p.y += mouse.y * gravity_pull * 0.5;

    // Rings
    let num_rings = i32(u.zoom_params.x); // Ring Complexity
    for (var i = 0; i < num_rings; i++) {
        let fi = f32(i);
        var rp = p;

        // Audio-Reactive Realignment
        let axis_shift = audio * 0.5 * sin(fi * 1.5 + time);

        let rpxy = rp.xy * rot(time * 0.2 + fi * 0.5 + axis_shift);
        rp.x = rpxy.x;
        rp.y = rpxy.y;
        let rpxz = rp.xz * rot(time * 0.3 + fi * 0.8 + axis_shift);
        rp.x = rpxz.x;
        rp.z = rpxz.y;

        let radius = 1.0 + fi * 0.5;
        let thickness = 0.05 + sin(time + fi) * 0.02;

        // Fluid Displacement
        let n = noise3D(rp * 2.0 + time) * u.zoom_params.y; // Fluidity
        let displaced_p = rp + rp * n * 0.2;

        let ring_d = sdTorus(displaced_p, vec2<f32>(radius, thickness));

        if (ring_d < d) {
            d = ring_d;
            mat_id = 1.0; // Ring material
        }
    }

    // Holographic Core
    let core_d = length(p) - 0.5 + sin(time * 2.0 + audio * 10.0) * 0.05;
    if (core_d < d) {
        d = core_d;
        mat_id = 2.0; // Core material
    }

    return vec2<f32>(d, mat_id);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let uv = (vec2<f32>(id.xy) * 2.0 - vec2<f32>(u.config.xy)) / u.config.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -8.0);
    let rd = normalize(vec3<f32>(uv, 1.5));

    var t = 0.0;
    var mat = 0.0;
    var hit = false;

    // Raymarching
    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        mat = res.y;

        if (d < SURF_DIST) {
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let time = u.config.z;
    let audio = u.zoom_config.w;

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));

        let diff = max(dot(n, l), 0.0);
        let view_dir = normalize(ro - p);
        let refl = reflect(-l, n);
        let spec = pow(max(dot(view_dir, refl), 0.0), 32.0);

        if (mat == 1.0) { // Ring material - Iridescent Liquid Metal
            let base_col = vec3<f32>(1.0, 0.8, 0.2); // Warm gold
            let iridescence = vec3<f32>(0.0, 1.0, 1.0) * (0.5 + 0.5 * sin(p.x * 2.0 + time));
            col = mix(base_col, iridescence, 0.5) * (diff + 0.2) + spec;
        } else if (mat == 2.0) { // Core material - Holographic Bloom
            col = vec3<f32>(0.0, 1.0, 1.0) + vec3<f32>(1.0, 0.0, 1.0) * sin(time * 3.0);
            col *= u.zoom_params.z; // Core Glow Intensity
        }
    } else {
        // Nebula Dust Interference
        let dust_noise = noise3D(vec3<f32>(uv * 10.0, time * 0.5));
        let dust_intensity = smoothstep(0.6, 1.0, dust_noise) * (1.0 + audio);
        col += vec3<f32>(0.2, 0.4, 0.8) * dust_intensity;
    }

    // Core Glow Volume Accumulation (Fake)
    let core_dist = length(uv);
    let glow = 0.05 / (core_dist * core_dist + 0.01) * u.zoom_params.z;
    col += vec3<f32>(0.0, 0.5, 1.0) * glow;

    // Output
    let final_col = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(final_col));
}
