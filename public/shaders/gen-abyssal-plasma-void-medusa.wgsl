// ----------------------------------------------------------------
// Abyssal Plasma Void-Medusa
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
  zoom_params: vec4<f32>,  // .x = parameter1, .y = parameter2, .z = parameter3, .w = parameter4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
	var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                       dot(hash33(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(dot(hash33(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                       dot(hash33(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                       dot(hash33(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(dot(hash33(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                       dot(hash33(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pp);
        pp *= 2.0;
        a *= 0.5;
    }
    return v;
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
  return length(p) - s;
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
  return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

struct MapResult {
    d: f32,
    mat_id: f32, // 0 for background, 1 for bell, 2 for tentacles
    emission: f32
}

fn map(p_in: vec3<f32>, time: f32, audio_val: f32) -> MapResult {
    var p = p_in;

    // Domain distortion
    let fluid_dist = u.zoom_params.y; // 0 to 1
    let n = fbm(p * 1.5 - vec3<f32>(0.0, time * 0.5, 0.0)) * fluid_dist * 0.5;
    p += vec3<f32>(n, n, n);

    // Mouse warp (Gravitational)
    let mouse = u.zoom_config.yz;
    let m_active = u.zoom_config.w;
    if (m_active > 0.0) {
        let m_dir = normalize(vec3<f32>(mouse.x - 0.5, mouse.y - 0.5, 0.0));
        let dist_to_m = length(p.xy - (mouse - vec2<f32>(0.5)) * 4.0);
        let pull = exp(-dist_to_m * dist_to_m);
        p.x -= pull * m_dir.x * 2.0;
        p.y -= pull * m_dir.y * 2.0;
    }

    // Bell
    var bell_p = p;
    bell_p.y += 0.5;
    let bell_h = 1.0;
    let bell_r = 1.2 + audio_val * 0.3 * u.zoom_params.x; // Pulse with audio

    // Inverted hemisphere approximation for bell
    var d_bell = sdSphere(bell_p, bell_r);
    var d_bell_inner = sdSphere(bell_p - vec3<f32>(0.0, -0.2, 0.0), bell_r - 0.1);
    d_bell = max(d_bell, -d_bell_inner);
    d_bell = max(d_bell, -bell_p.y); // cut off bottom

    // Smooth edges of the bell
    let edge_torus = length(vec2<f32>(length(bell_p.xz) - bell_r + 0.1, bell_p.y)) - 0.1;
    d_bell = smin(d_bell, edge_torus, 0.2);

    // Tentacles
    var tent_p = p;
    tent_p.y -= 1.0;

    var d_tentacles = 100.0;
    let num_tents = 6;
    let tent_length = u.zoom_params.z * 4.0;
    for (var i = 0; i < num_tents; i++) {
        let a = f32(i) * TAU / f32(num_tents) + time * 0.2;
        var tp = tent_p;
        tp.x -= cos(a) * 0.6;
        tp.z -= sin(a) * 0.6;

        // Sine wave modulation along length
        tp.x += sin(tp.y * 2.0 - time * 2.0 + f32(i)) * 0.3 * fluid_dist;
        tp.z += cos(tp.y * 1.5 - time * 1.8 + f32(i)) * 0.3 * fluid_dist;

        // Cap length
        let t_y = clamp(tp.y, 0.0, tent_length);
        var t = length(tp - vec3<f32>(0.0, t_y, 0.0)) - 0.05 * (1.0 - t_y/tent_length);

        d_tentacles = smin(d_tentacles, t, 0.3);
    }

    // Combine
    var res: MapResult;
    if (d_bell < d_tentacles) {
        res.d = smin(d_bell, d_tentacles, 0.5);
        res.mat_id = 1.0;
        res.emission = max(0.0, 1.0 - abs(bell_p.y)) * audio_val * u.zoom_params.x;
    } else {
        res.d = smin(d_bell, d_tentacles, 0.5);
        res.mat_id = 2.0;
        res.emission = (sin(p.y * 5.0 - time * 5.0) * 0.5 + 0.5) * audio_val * u.zoom_params.x;
    }

    return res;
}

fn calcNormal(p: vec3<f32>, time: f32, audio_val: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, time, audio_val).d;
    let n = vec3<f32>(
        map(p + e.xyy, time, audio_val).d - d,
        map(p + e.yxy, time, audio_val).d - d,
        map(p + e.yyx, time, audio_val).d - d
    );
    return normalize(n);
}

// Generate color from hue
fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.zw);
    let coords = vec2<i32>(global_id.xy);

    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Audio Reactivity
    // Sample from dataTextureC
    let audio_val = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Gentle camera sway
    let sway_x = sin(time * 0.2) * 0.5;
    let sway_y = cos(time * 0.3) * 0.5;
    ro.x += sway_x;
    ro.y += sway_y;

    // Look at origin
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var res: MapResult;
    var v_bloom = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        res = map(p, time, audio_val);
        d = res.d;

        // Volumetric accumulation
        v_bloom += res.emission * 0.05 / (1.0 + abs(d) * 10.0);

        if (d < 0.001 || t > 20.0) {
            break;
        }
        t += d;
    }

    // Shading
    var col = vec3<f32>(0.01, 0.02, 0.05); // Deep oceanic void
    col += v_bloom * hsv2rgb(vec3<f32>(u.zoom_params.w, 0.8, 1.0));

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, audio_val);

        // Lighting
        let lig = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let dif = max(dot(n, lig), 0.0);
        let amb = 0.2 + 0.8 * max(n.y, 0.0);

        // Material
        var mat_col = vec3<f32>(0.0);
        if (res.mat_id == 1.0) {
            mat_col = vec3<f32>(0.1, 0.3, 0.5); // Bell color
        } else if (res.mat_id == 2.0) {
            mat_col = vec3<f32>(0.2, 0.1, 0.4); // Tentacle color
        }

        col = mat_col * (dif + amb);

        // Subsurface scattering approx / Rim light
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        col += rim * hsv2rgb(vec3<f32>(u.zoom_params.w + 0.1, 0.8, 1.0)) * 0.5 * u.zoom_params.x;

        // Fog
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    // Store texture requirement for compatibility
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
