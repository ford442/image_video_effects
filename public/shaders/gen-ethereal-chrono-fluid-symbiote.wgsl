// ----------------------------------------------------------------
// Ethereal Chrono-Fluid Symbiote
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
    config: vec4<f32>,       // x=Time, y=RippleCount, zw=Res
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Density, y=Fluid Viscosity, z=Chrono Warp, w=Symbiote Glow
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;
const PI: f32 = 3.14159265359;

// Rotate 2D vector
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise function based on hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>( dot(p,vec3<f32>(127.1,311.7, 74.7)),
                        dot(p,vec3<f32>(269.5,183.3,246.1)),
                        dot(p,vec3<f32>(113.5,271.9,124.6)));
    return -1.0 + 2.0*fract(sin(p2)*43758.5453123);
}

// 3D Simplex noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p + dot(p, vec3<f32>(0.3333333)));
    let x0 = p - i + dot(i, vec3<f32>(0.1666667));

    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);

    let x1 = x0 - i1 + 0.1666667;
    let x2 = x0 - i2 + 0.3333333;
    let x3 = x0 - 1.0 + 0.5;

    var n = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    n = n*n;
    n = n*n;

    let d = vec4<f32>( dot(hash3(i+0.0), x0),
                       dot(hash3(i+i1), x1),
                       dot(hash3(i+i2), x2),
                       dot(hash3(i+1.0), x3) );
    return dot(n, d) * 31.316;
}

// Fractal Brownian Motion for the fluid structure
fn fbm(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for(var i = 0; i < octaves; i++) {
        value += amp * noise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// Signed Distance Function for the scene
fn map(p: vec3<f32>, time: f32) -> f32 {
    var p_warp = p;

    let density = u.zoom_params.x;
    let viscosity = u.zoom_params.y;
    let chrono_warp = u.zoom_params.z;

    // Audio Reactivity (bass and treble from extraBuffer)
    let bass = extraBuffer[0];
    let high = extraBuffer[100];
    let audio_mod = bass * 0.5 + high * 0.2;

    // Apply Symbiotic Gravity Well (Mouse Interaction)
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
        // Map mouse UV (screen space) to world space approximation for the well
        let well_pos = vec3<f32>(mouse_uv.x * 3.0, -mouse_uv.y * 3.0, 0.0);
        let dist_to_well = length(p - well_pos);

        let pull = 1.0 / (dist_to_well * dist_to_well + 0.1);
        let pulse = sin(time * 5.0 - dist_to_well * 10.0) * 0.5 + 0.5;
        p_warp -= normalize(p - well_pos) * pull * pulse * 0.2;
    }

    // Domain warping based on time, audio, and chrono warp parameter
    let warp_time = time * chrono_warp + audio_mod;

    p_warp.x += fbm(p_warp + vec3<f32>(warp_time, 0.0, 0.0), 3) * density;
    p_warp.y += fbm(p_warp + vec3<f32>(0.0, warp_time, 0.0), 3) * density;
    p_warp.z += fbm(p_warp + vec3<f32>(0.0, 0.0, warp_time), 3) * density;

    // Base shape is a combination of spheres and planes, distorted by the fluid noise
    let sphere_dist = length(p_warp) - 1.5;

    // Add viscous tendrils
    let tendril_noise = fbm(p_warp * 3.0 - vec3<f32>(0.0, time, 0.0), 4);
    let tendril_dist = tendril_noise * viscosity;

    // Combine for final SDF
    return sphere_dist + tendril_dist;
}

// Calculate normals for lighting
fn get_normal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time) - map(p - e.xyy, time),
        map(p + e.yxy, time) - map(p - e.yxy, time),
        map(p + e.yyx, time) - map(p - e.yyx, time)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, 4.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.0));

    // Raymarching
    var p = ro;
    var t = 0.0;
    var hit = false;
    var steps: i32 = 0;
    var min_dist = 1000.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        steps = i;
        p = ro + rd * t;
        let d = map(p, time);
        min_dist = min(min_dist, d);
        if (abs(d) < SURF_DIST) {
            hit = true;
            break;
        }
        t += d * 0.5; // Step multiplier for fluid smoothness
        if (t > MAX_DIST) {
            break;
        }
    }

    // Shading
    var col = vec3<f32>(0.01, 0.01, 0.02); // Deep void background
    let glow_param = u.zoom_params.w;

    // Audio driven glow
    let bass = extraBuffer[0];

    // Subsurface scattering / Bloom (glow around the object even if not hit)
    let glow_intensity = 0.05 / (min_dist + 0.01) * glow_param * (1.0 + bass);
    let glow_color = vec3<f32>(0.1, 0.6, 0.8) * glow_intensity;
    col += glow_color;

    if (hit) {
        let n = get_normal(p, time);
        let l = normalize(vec3<f32>(1.0, 2.0, 3.0)); // Main light
        let l2 = normalize(vec3<f32>(-2.0, -1.0, -1.0)); // Back light

        let diff = max(dot(n, l), 0.0);
        let diff2 = max(dot(n, l2), 0.0);

        // Ethereal color palette
        let base_col = vec3<f32>(0.2, 0.8, 0.7); // Teal
        let highlight_col = vec3<f32>(0.7, 0.2, 0.9); // Purple

        // Fluid shading
        var mat_col = mix(base_col, highlight_col, sin(p.y * 2.0 + time) * 0.5 + 0.5);

        // Rim lighting (subsurface proxy)
        let view_dir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        // Fake Ambient Occlusion based on steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        col = mat_col * (diff * 0.7 + 0.3) * ao;
        col += vec3<f32>(0.4, 0.9, 0.5) * diff2 * 0.4 * ao; // Bioluminescent backlighting
        col += vec3<f32>(1.0) * fresnel * 0.8 * glow_param; // Shiny rim

        // Add crystalline metallic sheen based on noise
        let sheen = noise(p * 10.0) * 0.5 + 0.5;
        col += vec3<f32>(1.0) * pow(diff, 16.0) * sheen; // Specular
    }

    // Output
    let out_color = vec4<f32>(col, 1.0);

    textureStore(writeTexture, vec2<i32>(fragCoord), out_color);

    // Write standard auxiliary data to prevent regressions
    let depth_val = t / MAX_DIST;
    textureStore(writeDepthTexture, vec2<i32>(fragCoord), vec4<f32>(depth_val));
    var out_n = vec3<f32>(0.0, 1.0, 0.0); if (hit) { out_n = get_normal(p, time); } textureStore(dataTextureA, vec2<i32>(fragCoord), vec4<f32>(out_n * 0.5 + 0.5, 1.0));
}
