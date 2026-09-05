// ----------------------------------------------------------------
// Bioluminescent Neural Lattice
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

// --- CONSTANTS ---
const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.01;
const TAU: f32 = 6.28318530718;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Voronoi edges (cellular noise variation)
fn voronoi_edges(p: vec3<f32>, t: f32) -> f32 {
    let n = floor(p);
    let f = fract(p);

    var res = 8.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + b);

                // Animate points
                let anim_o = 0.5 + 0.5 * sin(t + 6.2831 * o);
                let r = b - f + anim_o;

                let d = dot(r, r);
                if (d < res) {
                    res = d;
                }
            }
        }
    }

    // Convert to distance field from edges (approximation)
    // Actually we want distance to points, but smoothed out
    return sqrt(res);
}

// --- SDF ---
fn map(p_in: vec3<f32>, time: f32, audio_data: f32, u_zoom: vec4<f32>) -> vec2<f32> {
    var p = p_in;
    let synapse_density = u_zoom.x;
    let pulse_speed = u_zoom.y;

    // Mouse attraction
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.y *= -1.0;

    // Simple projection of mouse into scene space at some depth
    let mouse_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 3.0);

    // Warp space towards mouse slightly
    let dist_to_mouse = length(p - mouse_pos);
    let influence = exp(-dist_to_mouse * 0.5);
    p = mix(p, mouse_pos, influence * 0.2);

    // Space repetition
    p = p * synapse_density;

    // Base time for movement
    let t = time * pulse_speed * 0.2;

    // Create the lattice from voronoi
    // We invert it so the points become the empty space and the edges become the solid structure
    let d1 = voronoi_edges(p, t);
    let d2 = voronoi_edges(p + vec3<f32>(1.5, 0.5, -0.5), t * 1.1);

    // Combine and scale back
    let combined = smin(d1, d2, 0.5);

    // Distance to network structure
    // We want a thick lattice, so subtract a radius
    var base_dist = (0.7 - combined) / synapse_density;

    // Audio perturbation (pulsing along the network)
    // We'll use position and time to create waves
    let wave = sin(p.x * 2.0 + p.y * 1.5 + p.z * 0.5 - time * pulse_speed * 5.0);
    base_dist -= wave * audio_data * 0.1 / synapse_density;

    return vec2<f32>(base_dist, combined);
}

// Branchless cosine palette
fn palette(t: f32, color_shift: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    // Deep cyan to electric blue/magenta
    let c = vec3<f32>(1.0, 1.0, 0.5);
    let d = vec3<f32>(0.00, 0.33, 0.67) + color_shift;

    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let id = vec2<i32>(global_id.xy);
    let dims_i32 = vec2<i32>(dimensions);

    if (id.x >= dims_i32.x || id.y >= dims_i32.y) {
        return;
    }

    let time = u.config.x;
    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let base_uv = vec2<f32>(id) / res;
    let uv = (vec2<f32>(id) - 0.5 * res) / res.y;

    // Params
    let u_zoom = u.zoom_params;
    let glow_intensity = u_zoom.z;
    let color_shift = u_zoom.w;

    // Audio Reactivity (low frequencies)
    let audio_low = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.1, 0.5), 0.0).r;
    let audio_mid = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(0.5, 0.5), 0.0).r;
    let audio_val = audio_low * 2.0 + audio_mid * 0.5;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -1.0 + time * 0.5);
    var ta = ro + vec3<f32>(0.0, 0.0, 1.0);

    // Very slight camera shake from audio
    ro += vec3<f32>(sin(time * 10.0), cos(time * 11.0), 0.0) * audio_val * 0.02;

    // Camera matrix
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = cross(cu, cw);
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var d0 = 0.0;
    var p = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);
    var min_dist = 100.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * d0;
        let map_res = map(p, time, audio_val, u_zoom);
        let d = map_res.x;

        // Track minimum distance for glow
        if (d < min_dist) {
            min_dist = d;
        }

        // Volumetric accumulation
        // The closer we are to the surface, the more it glows
        let glow_factor = exp(-d * 4.0);

        // Base color maps to the structure value (map_res.y)
        var col_val = palette(map_res.y * 2.0 + time * 0.1, color_shift);

        // Audio adds energy pulses
        let pulse = sin(p.z * 10.0 - time * 20.0) * 0.5 + 0.5;
        col_val += vec3<f32>(0.2, 0.5, 1.0) * pulse * audio_val * 2.0;

        glow += col_val * glow_factor * 0.03 * glow_intensity;

        // Step forward
        // We step slightly slower to gather more volume
        d0 += max(d * 0.8, 0.01);

        if (d < SURF_DIST || d0 > MAX_DIST) {
            break;
        }
    }

    // Background: dark oceanic void
    var bg_col = vec3<f32>(0.01, 0.05, 0.1);

    // Depth fog
    let fog = 1.0 - exp(-d0 * 0.1);

    // Final composite
    var col = mix(glow, bg_col, fog);

    // Add ambient glow from closest approach
    let ambient = palette(min_dist, color_shift) * exp(-min_dist * 2.0) * glow_intensity;
    col += ambient * 0.2;

    // Tone mapping (simple exposure/ACES fit approx)
    col = col * 1.5;
    col = col / (1.0 + col);

    textureStore(writeTexture, id, vec4<f32>(col, 1.0));
}
