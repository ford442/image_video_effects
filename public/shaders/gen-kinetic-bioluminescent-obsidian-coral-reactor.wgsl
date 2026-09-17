// ----------------------------------------------------------------
// Kinetic Bioluminescent Obsidian-Coral Reactor
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
    zoom_params: vec4<f32>,  // .x = Color Shift, .y = Coral Density, .zw unused
    speed_params: vec4<f32>, // .x = Fluid Speed, .y = Lattice Complexity, .zw unused
    extra_params: vec4<f32>, // .x = Glow Intensity, .y = Void Darkness, .zw unused
    ripples: array<vec4<f32>, 50>,
};

// Math and constants
const PI = 3.14159265359;
const MAX_STEPS = 100;
const SURF_DIST = 0.005;
const MAX_DIST = 50.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Polynomial smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// 3D noise (value noise)
fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.,0.,0.)), f - vec3<f32>(0.,0.,0.)),
                dot(hash3(i + vec3<f32>(1.,0.,0.)), f - vec3<f32>(1.,0.,0.)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.,1.,0.)), f - vec3<f32>(0.,1.,0.)),
                dot(hash3(i + vec3<f32>(1.,1.,0.)), f - vec3<f32>(1.,1.,0.)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.,0.,1.)), f - vec3<f32>(0.,0.,1.)),
                dot(hash3(i + vec3<f32>(1.,0.,1.)), f - vec3<f32>(1.,0.,1.)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.,1.,1.)), f - vec3<f32>(0.,1.,1.)),
                dot(hash3(i + vec3<f32>(1.,1.,1.)), f - vec3<f32>(1.,1.,1.)), u.x), u.y), u.z);
}

// FBM
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        f += amp * noise3D(q);
        q *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Distance to Obsidian Lattice and Coral
fn map(p: vec3<f32>, mouse_pos: vec3<f32>, audio_bass: f32) -> vec2<f32> {
    var d_obj = 0.0; // Material ID

    // Domain repetition for brutalist tunnel
    let c = vec3<f32>(8.0);
    var q = p;
    q.x = (fract(q.x / c.x + 0.5) - 0.5) * c.x;
    q.y = (fract(q.y / c.y + 0.5) - 0.5) * c.y;

    // Base geometry: Menger-like structure
    var d_obsidian = sdBox(q, vec3<f32>(3.0));

    // Subtractions for lattice holes, using Lattice Complexity parameter
    let complexity = max(1.0, u.speed_params.y);
    for (var i = 0.0; i < 3.0; i += 1.0) {
        if (i >= complexity) { break; }
        let s = pow(3.0, i);
        var sub_q = (fract(p * s) - 0.5) / s;
        let sub_box = sdBox(sub_q, vec3<f32>(0.35 / s));
        d_obsidian = max(d_obsidian, -sub_box);
    }

    // Hollow out a central tunnel
    d_obsidian = max(d_obsidian, -sdBox(p, vec3<f32>(2.0, 2.0, MAX_DIST)));

    // Coral Growth SDF
    let coral_density = u.zoom_params.y;
    let fluid_speed = u.speed_params.x;
    let noise_val = fbm(p * 0.5 + vec3<f32>(0.0, 0.0, -u.config.x * fluid_speed));

    // Audio pushes the coral outward
    let audio_push = audio_bass * 0.5;

    // Coral grows along the obsidian, slightly offset
    let d_coral = d_obsidian + 0.2 - noise_val * coral_density - audio_push;

    // Combine them with smooth min for blending
    let d = smin(d_obsidian, d_coral, 0.8);

    // Mouse influence (perturbs surface when close)
    let mouse_dist = length(p - mouse_pos);
    let mouse_influence = smoothstep(3.0, 0.0, mouse_dist);
    let final_d = d - mouse_influence * 0.1;

    // Material logic
    if (d_coral < d_obsidian + 0.1) {
        d_obj = 1.0; // Coral
    } else {
        d_obj = 0.0; // Obsidian
    }

    return vec2<f32>(final_d, d_obj);
}

// Calculate normal
fn calcNormal(p: vec3<f32>, mouse_pos: vec3<f32>, audio_bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, mouse_pos, audio_bass).x - map(p - e.xyy, mouse_pos, audio_bass).x,
        map(p + e.yxy, mouse_pos, audio_bass).x - map(p - e.yxy, mouse_pos, audio_bass).x,
        map(p + e.yyx, mouse_pos, audio_bass).x - map(p - e.yyx, mouse_pos, audio_bass).x
    ));
}

// Cosine palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(2.0 * PI * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let base_uv = vec2<f32>(coords) / vec2<f32>(dims);
    var uv = base_uv * 2.0 - 1.0;
    let aspect = f32(dims.x) / f32(dims.y);
    uv.x *= aspect;

    let time = u.config.x;

    // Audio Reactivity
    let bass = extraBuffer[0];
    let treble = extraBuffer[133];

    // Mouse Interaction
    var mouse_pos = vec3<f32>(0.0, 0.0, -100.0); // Default far away
    if (u.zoom_config.w > 0.5) { // Mouse down
        let muv = u.zoom_config.yz * 2.0 - 1.0;
        mouse_pos = vec3<f32>(muv.x * 5.0, -muv.y * 5.0, 2.0 + time * u.speed_params.x);
    }

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -2.0 + time * u.speed_params.x); // Camera moves forward
    // Mild sway based on time
    ro.x += sin(time * 0.5) * 0.5;
    ro.y += cos(time * 0.4) * 0.5;

    // Look-at setup
    let target = vec3<f32>(0.0, 0.0, ro.z + 5.0);
    let ww = normalize(target - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    // Mild chromatic aberration for ray directions
    let shift = 0.01;
    var final_color = vec3<f32>(0.0);

    // Trace 3 rays for RGB split (chromatic aberration on periphery)
    let lens_dist = length(uv);
    let r_shift = lens_dist * shift;

    let offsets = array<f32, 3>(-r_shift, 0.0, r_shift);

    for (var c = 0; c < 3; c++) {
        var rd = normalize(uv.x * uu + uv.y * vv + (1.5 + offsets[c]) * ww);

        var t = 0.0;
        var p = ro;
        var mat_id = 0.0;
        var dist_to_coral = 0.0;

        // Raymarch
        for (var i = 0; i < MAX_STEPS; i++) {
            p = ro + rd * t;
            let res = map(p, mouse_pos, bass);
            let d = res.x;

            if (res.y > 0.5) {
                // Keep track of how close we get to the coral for subsurface glow
                dist_to_coral += exp(-d * 2.0);
            }

            if (abs(d) < SURF_DIST || t > MAX_DIST) {
                mat_id = res.y;
                break;
            }
            t += d;
        }

        var col = vec3<f32>(0.0);
        let void_darkness = u.extra_params.y; // 0.8 default

        if (t < MAX_DIST) {
            let n = calcNormal(p, mouse_pos, bass);

            // Mouse Light (Lantern effect)
            var light_pos = ro + vec3<f32>(0.0, 0.0, 2.0); // Default headlight
            if (u.zoom_config.w > 0.5) {
                light_pos = mouse_pos;
            }

            let l = normalize(light_pos - p);
            let dif = max(dot(n, l), 0.0);
            let view_dir = normalize(ro - p);
            var refl = reflect(-l, n); // Switched from reserved keyword ref

            // Treble causes local micro-fractures in obsidian normal
            if (mat_id < 0.5) { // Obsidian
                let fracture = fbm(p * 20.0) * treble * 0.1;
                refl = reflect(-normalize(l + fracture), normalize(n + fracture));
            }

            let spec = pow(max(dot(view_dir, refl), 0.0), 64.0);

            let ao = clamp(map(p + n * 0.5, mouse_pos, bass).x * 2.0, 0.0, 1.0);

            if (mat_id < 0.5) {
                // Obsidian material
                let base = vec3<f32>(0.02);
                col = base * dif * ao + vec3<f32>(spec) * 2.0 * ao;
            } else {
                // Coral Material
                let color_shift = u.zoom_params.x; // 0.5 default
                let a = vec3<f32>(0.5, 0.5, 0.5);
                let b = vec3<f32>(0.5, 0.5, 0.5);
                let cx = vec3<f32>(1.0, 1.0, 1.0);
                let dx = vec3<f32>(0.00, 0.33, 0.67) + color_shift;
                let coral_color = palette(fbm(p) + time * 0.1, a, b, cx, dx);

                // Emissive glowing
                let glow_intensity = u.extra_params.x;
                let emission = coral_color * glow_intensity * (1.0 + bass);

                col = emission * ao;
            }
        }

        // Volumetric glowing from coral
        let glow = dist_to_coral * 0.02 * u.extra_params.x;
        let color_shift = u.zoom_params.x;
        let glow_color = palette(time * 0.2, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(1.0), vec3<f32>(0.0, 0.33, 0.67) + color_shift);

        col += glow * glow_color;

        // Fog based on void darkness
        col = mix(col, vec3<f32>(0.0, 0.0, 0.05) * (1.0 - void_darkness), smoothstep(0.0, MAX_DIST, t));

        if (c == 0) { final_color.r = col.r; }
        if (c == 1) { final_color.g = col.g; }
        if (c == 2) { final_color.b = col.b; }
    }

    // Vignette
    final_color *= 1.0 - length(uv) * 0.5;

    // Tonemapping (ACES-like)
    final_color = (final_color * (2.51 * final_color + 0.03)) / (final_color * (2.43 * final_color + 0.59) + 0.14);

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
}
