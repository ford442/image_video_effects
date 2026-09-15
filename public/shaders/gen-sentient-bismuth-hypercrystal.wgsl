// ═══════════════════════════════════════════════════════════════════
//  Sentient Bismuth Hypercrystal
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: recursive hopper terraces; crystallographic oxide zoning
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>,  // .x = Growth, .y = Audio React, .z = Twist, .w = Iridescence
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// 1. Rotation Matrix Helper
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

var<private> g_hopper: f32 = 0.0;
var<private> g_facet: f32 = 0.0;

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// 2. Map Function (SDF)
fn map(p_in: vec3<f32>, time: f32, audio: f32, mouse_pos: vec3<f32>) -> f32 {
    var p = p_in;

    // Twist / gravity well based on mouse position
    let twist_strength = u.zoom_params.z; // Twist
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < 3.0) {
        let twist_angle = twist_strength * (3.0 - dist_to_mouse) / 3.0;
        let r_xy = rot(twist_angle);
        let xy = r_xy * p.xy;
        p = vec3<f32>(xy, p.z);
    }

    // Growth and animation
    let growth = u.zoom_params.x; // Growth
    let audio_react = u.zoom_params.y; // Audio React

    let base_scale = 1.0 + 0.2 * sin(time * 0.5) + audio * 0.5 * audio_react;

    var d = 1000.0; // Init high distance

    // Base shape
    var q = p;
    var scale = 1.0;

    // Menger sponge like folding
    for (var i = 0; i < 4; i++) {
        // Folding
        q = abs(q) - vec3<f32>(1.5, 1.0, 1.2) * growth / scale;

        // Rotation based on time and audio, gated by Audio React
        let ax = audio * audio_react;
        let rx = rot(time * 0.1 + ax * 0.1);
        let ry = rot(time * 0.15 - ax * 0.2);

        let qz = q.z;
        let q_xy = rx * q.xy;
        q = vec3<f32>(q_xy, qz);

        let qx = q.x;
        let q_yz = ry * q.yz;
        q = vec3<f32>(qx, q_yz);

        scale *= 1.5;
    }

    // Cuboid SDF
    let b = vec3<f32>(1.0, 1.0, 1.0) * base_scale / scale;
    d = sdBox(q, b);

    // Recursive hopper terraces: nested square cavities on the folded cuboid
    let aq = abs(q);
    let dominant = max(aq.x, max(aq.y, aq.z));
    g_facet = dominant;
    var hopper = 0.0;
    for (var k = 0; k < 3; k++) {
        let band = 0.22 + f32(k) * 0.22;
        let cavity = 0.55 - f32(k) * 0.12;
        let inner = sdBox(q, b * cavity);
        let lip = abs(dominant / max(b.x, 0.001) - band);
        hopper = max(hopper, (cavity * 0.08 - inner) * (1.0 - smoothstep(0.0, 0.08, lip)));
    }
    g_hopper = hopper;
    d = d + hopper * 0.35;

    return d;
}

// 3. Normal Calculation
fn getNormal(p: vec3<f32>, time: f32, audio: f32, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, mouse_pos) - map(p - e.xyy, time, audio, mouse_pos),
        map(p + e.yxy, time, audio, mouse_pos) - map(p - e.yxy, time, audio, mouse_pos),
        map(p + e.yyx, time, audio, mouse_pos) - map(p - e.yyx, time, audio, mouse_pos)
    );
    return normalize(n);
}

// 4. Color / Iridescence Mapping
// Cosine palette for thin film interference
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.10, 0.20);
    return a + b * cos(2.0 * PI * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 5. Main Compute Entry Point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let ndc = (uv * 2.0 - 1.0) * vec2<f32>(resolution.x / resolution.y, 1.0);

    // Safety check for out-of-bounds
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;

    // Three-band audio; Audio React slider gates modulation
    let audio_react = u.zoom_params.y;
    let audio_val = (plasmaBuffer[0].x * 0.5 + plasmaBuffer[0].y * 0.3 + plasmaBuffer[0].z * 0.2) * audio_react;

    // Mouse setup
    let mouse_ndc = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x / resolution.y, -1.0);
    // Project mouse onto a plane in 3D space roughly where the object is
    let mouse_pos = vec3<f32>(mouse_ndc * 5.0, 0.0);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    // Subtle camera movement
    ro.x += sin(time * 0.2) * 1.0;
    ro.y += cos(time * 0.15) * 1.0;

    var ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cp = vec3<f32>(0.0, 1.0, 0.0);
    let cu = normalize(cross(cw, cp));
    let cv = normalize(cross(cu, cw));

    // View ray
    let rd = normalize(ndc.x * cu + ndc.y * cv + 1.5 * cw);

    // Raymarching
    var dO = 0.0;
    var p = ro;
    var hit = false;
    var steps_taken = 0;
    for (var i = 0; i < MAX_STEPS; i++) {
        steps_taken = i;
        p = ro + rd * dO;
        let dS = map(p, time, audio_val, mouse_pos);
        if (dS < SURF_DIST) {
            hit = true;
            break;
        }
        if (dO > MAX_DIST) {
            break;
        }
        dO += dS;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p, time, audio_val, mouse_pos);
        let v = -rd; // View direction

        // Lighting
        let light_dir = normalize(vec3<f32>(sin(time), 1.0, cos(time)));
        let diff = max(dot(n, light_dir), 0.0);
        let amb = 0.1;

        // Iridescence
        let iridescence_strength = u.zoom_params.w;
        let ndotv = max(dot(n, v), 0.0);
        // Crystallographic oxide zoning: thickness follows dominant facet + hopper band
        let hitD = map(p, time, audio_val, mouse_pos);
        let facetTerm = g_facet * 0.35;
        let hopperBand = g_hopper * 2.4;
        let film_thickness = ndotv * 0.55 + facetTerm + hopperBand
            + audio_val * 0.25 + sin(p.x * 2.0 + p.y * 3.0 + p.z * 1.5 + time) * 0.1
            + clamp(hitD, -0.05, 0.05) * 0.02;
        let irid_col = palette(film_thickness * iridescence_strength);

        // Fresnel
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        // Combine lighting and iridescence
        col = irid_col * (diff + amb) + vec3<f32>(1.0) * fresnel * 0.5;

        // Specular
        let r_dir = reflect(-light_dir, n);
        let spec = pow(max(dot(v, r_dir), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec;

        // Fake SSS or ambient occlusion based on step count
        let ao = 1.0 - f32(steps_taken) / f32(MAX_STEPS);
        col *= ao;

    } else {
        // Background - alien nebula feel
        let bg_color = vec3<f32>(0.05, 0.01, 0.1) * (1.0 - length(ndc) * 0.5);
        col = bg_color;
    }

    // TAA / Accumulation (simple temporal blend if previous frame exists)
    let base_uv = vec2<f32>(global_id.xy) / resolution; // Use original UV for texture fetch
    let prev_color = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;

    // Blend current frame with previous for TAA effect
    let blend_factor = 0.8; // High blend for slow mutation feel
    col = mix(col, prev_color, blend_factor);

    // Tonemapping
    col = acesToneMap(col);

    let luma = dot(col, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(select(0.12, 0.42, hit) + luma * 0.45 + f32(hit) * 0.15, 0.08, 0.96);
    let depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit);
    let outCol = vec4<f32>(col, alpha);
    let pix = vec2<i32>(global_id.xy);
    textureStore(writeTexture, pix, outCol);
    textureStore(writeDepthTexture, pix, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pix, outCol);
}
