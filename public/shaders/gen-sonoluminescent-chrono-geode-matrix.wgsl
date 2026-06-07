// ----------------------------------------------------------------
// Sonoluminescent Chrono-Geode Matrix
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>, // x: resolution.x, y: resolution.y, z: time, w: aspect
  zoom_config: vec4<f32>, // x: mouse.x, y: mouse.y, z: is_clicking, w: audio_intensity
  zoom_params: vec4<f32>, // param1: Fracture Intensity, param2: Core Glow, param3: Geode Rotation, param4: Temporal Shift
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
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// 3D rotation helper
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let a = normalize(axis);
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * a.x * a.x + c,           oc * a.x * a.y - a.z * s,  oc * a.z * a.x + a.y * s,
        oc * a.x * a.y + a.z * s,     oc * a.y * a.y + c,        oc * a.y * a.z - a.x * s,
        oc * a.z * a.x - a.y * s,     oc * a.y * a.z + a.x * s,  oc * a.z * a.z + c
    );
}

// 4D Rotation matrix helper
fn rot4D(theta: f32) -> mat2x2<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Value Noise
fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn vnoise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    return mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453), fract(sin(n + 1.0) * 43758.5453), f2.x),
            mix(fract(sin(n + 157.0) * 43758.5453), fract(sin(n + 158.0) * 43758.5453), f2.x), f2.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453), fract(sin(n + 114.0) * 43758.5453), f2.x),
            mix(fract(sin(n + 270.0) * 43758.5453), fract(sin(n + 271.0) * 43758.5453), f2.x), f2.y), f2.z);
}

// SDF for geode shell
fn sdGeodeShell(p: vec3<f32>, scale: f32) -> f32 {
    var q = p;
    let s = 2.0;
    for (var i = 0; i < 4; i = i + 1) {
        q = abs(q) - vec3<f32>(0.5) * scale;
        let rot = rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), 0.5);
        q = rot * q;
        q = q * s;
    }
    return (length(q) - 1.0 * scale) / pow(s, 4.0);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    // Distance to geode
    var p_rot = p;
    let t = u.config.z * u.zoom_params.w; // Temporal shift

    // Geode rotation
    let rotY = rot3D(vec3<f32>(0.0, 1.0, 0.0), u.config.z * u.zoom_params.z);
    p_rot = rotY * p_rot;

    // Mouse interaction (repel shards)
    var explode_offset = vec3<f32>(0.0);
    if (u.zoom_config.z > 0.0) {
        // Mouse click repels
        let mouse_pos = vec2<f32>((u.zoom_config.x - 0.5) * 2.0 * u.config.w, (0.5 - u.zoom_config.y) * 2.0);
        let dir = normalize(p - vec3<f32>(mouse_pos, 0.0));
        let dist = length(p - vec3<f32>(mouse_pos, 0.0));
        let force = exp(-dist * 2.0) * 2.0;
        explode_offset = dir * force;
    }

    // Audio fracture
    let fracture = u.zoom_params.x * u.zoom_config.w * vnoise3(p * 5.0 + vec3<f32>(t));
    let explode = explode_offset + normalize(p_rot) * fracture;

    let geode_dist = max(sdGeodeShell(p_rot - explode, 1.5), length(p_rot) - 1.0);

    // Plasma core
    let core_noise = vnoise3(p * 3.0 - vec3<f32>(0.0, t * 2.0, 0.0));
    let core_dist = length(p) - 0.8 + core_noise * 0.3;

    if (geode_dist < core_dist) {
        return vec2<f32>(geode_dist, 1.0); // 1.0 = geode material
    } else {
        return vec2<f32>(core_dist, 2.0); // 2.0 = core material
    }
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= u32(u.config.x) || id.y >= u32(u.config.y)) {
        return;
    }

    let uv = vec2<f32>(f32(id.x) / u.config.x, f32(id.y) / u.config.y);
    let p = vec2<f32>((uv.x - 0.5) * 2.0 * u.config.w, (0.5 - uv.y) * 2.0);

    let ro = vec3<f32>(0.0, 0.0, 4.0);
    let rd = normalize(vec3<f32>(p, -1.5));

    var d0: f32 = 0.0;
    var mat_id: f32 = 0.0;
    var col = vec3<f32>(0.0);
    var plasma_acc = 0.0;

    for (var i = 0; i < MAX_STEPS; i = i + 1) {
        let p_march = ro + rd * d0;
        let dS = map(p_march);

        if (dS.y == 2.0) {
            // Accumulate plasma
            plasma_acc = plasma_acc + 0.05 * exp(-dS.x * 5.0);
        }

        if (dS.x < SURF_DIST) {
            mat_id = dS.y;
            break;
        }

        d0 = d0 + dS.x * 0.5; // slow march for volumetric

        if (d0 > MAX_DIST) {
            break;
        }
    }

    if (mat_id == 1.0) {
        // Geode material (iridescent)
        let p_surf = ro + rd * d0;
        let n = calcNormal(p_surf);
        let l = normalize(vec3<f32>(1.0, 1.0, 2.0));

        let diff = max(dot(n, l), 0.0);
        let view_dir = normalize(-rd);
        let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        // Iridescence based on viewing angle
        let iridescence = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.0, 4.0) + fresnel * 5.0);

        col = diff * vec3<f32>(0.2) + fresnel * iridescence;

        // Reflection of the plasma core
        let r = reflect(rd, n);
        let core_refl = max(0.0, dot(r, normalize(vec3<f32>(0.0, 0.0, 0.0) - p_surf)));
        col = col + core_refl * vec3<f32>(0.2, 0.5, 1.0) * u.zoom_params.y;
    }

    // Add plasma glow
    let core_glow_color = vec3<f32>(0.1, 0.6, 1.0) * u.zoom_params.y * u.zoom_config.w;
    col = col + plasma_acc * core_glow_color;

    // Background
    col = mix(vec3<f32>(0.01, 0.02, 0.05), col, min(1.0, plasma_acc + select(0.0, 1.0, mat_id == 1.0)));

    col = pow(col, vec3<f32>(0.4545)); // gamma correction
    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(vec4<f32>(col, 1.0)));
}
