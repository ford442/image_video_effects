// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Void-Whale
// Category: generative
// A colossal, slow-moving biomechanical space leviathan swimming gracefully through a dense volumetric plasma-ocean.
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plasma Density, y=Temporal Glitch, z=Refraction Index, w=Core Bloom
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Basic Signed Distance Functions
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D Noise for volume
fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    let a = hash3(i + vec3<f32>(0.0, 0.0, 0.0));
    let b = hash3(i + vec3<f32>(1.0, 0.0, 0.0));
    let c = hash3(i + vec3<f32>(0.0, 1.0, 0.0));
    let d = hash3(i + vec3<f32>(1.0, 1.0, 0.0));
    let e = hash3(i + vec3<f32>(0.0, 0.0, 1.0));
    let f_ = hash3(i + vec3<f32>(1.0, 0.0, 1.0));
    let g = hash3(i + vec3<f32>(0.0, 1.0, 1.0));
    let h_ = hash3(i + vec3<f32>(1.0, 1.0, 1.0));

    return mix(
        mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
        mix(mix(e, f_, u.x), mix(g, h_, u.x), u.y),
        u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var p_shift = p;
    for(var i=0; i<4; i++) {
        v += a * noise3(p_shift);
        p_shift = p_shift * 2.0;
        a *= 0.5;
    }
    return v;
}

struct MapResult {
    dist: f32,
    mat: f32, // 1.0 = bone/ribs, 2.0 = core, 3.0 = temporal stream
}

// The Whale SDF
fn map(p: vec3<f32>, time: f32, glitch: f32) -> MapResult {
    var res = MapResult(1000.0, 0.0);

    // Temporal distortion
    var tp = p;
    if (glitch > 0.0) {
        let glitch_offset = sin(time * 10.0 + p.y * 5.0) * glitch * 0.1;
        tp.x += glitch_offset;
    }

    // Core (Audio reactive blooming heart)
    let core_pulse = sin(time * 2.0) * 0.1 + u.config.y * 0.5;
    let d_core = sdSphere(tp - vec3<f32>(0.0, 0.0, 0.5), 0.8 + core_pulse);

    // Main spine
    let spine_bend = sin(tp.z * 0.5 - time) * 0.3;
    var spine_p = tp;
    spine_p.y += spine_bend;
    let d_spine = sdCapsule(spine_p, vec3<f32>(0.0, 0.0, -3.0), vec3<f32>(0.0, 0.0, 4.0), 0.3);

    // Ribs
    var d_ribs = 1000.0;
    for (var i = 0; i < 8; i++) {
        let z_pos = -2.0 + f32(i) * 0.7;
        let rib_size = 1.0 - abs(z_pos) * 0.2;
        var rp = spine_p;
        rp.z -= z_pos;

        // Curve ribs downwards
        let rib_d = sdTorus(rp.xzy, vec2<f32>(1.2 * rib_size, 0.1));
        // Cut torus to make ribs open at bottom
        let cut = rp.y + 0.5 * rib_size;
        let rib_final = max(rib_d, cut);

        d_ribs = smin(d_ribs, rib_final, 0.1);
    }

    // Combine bone structure
    let d_bone = smin(d_spine, d_ribs, 0.2);

    // Temporal Streams (Energy around the whale)
    let stream_noise = fbm(p * 2.0 - vec3<f32>(0.0, 0.0, time * 2.0));
    let d_stream = sdCapsule(p, vec3<f32>(0.0, 0.0, -4.0), vec3<f32>(0.0, 0.0, 5.0), 2.5) + stream_noise - 1.0;

    if (d_core < d_bone && d_core < d_stream) {
        res.dist = d_core;
        res.mat = 2.0;
    } else if (d_bone < d_stream) {
        res.dist = d_bone;
        res.mat = 1.0;
    } else {
        res.dist = d_stream;
        res.mat = 3.0;
    }

    // Mouse interaction - repel streams
    let mx = u.zoom_config.y * 2.0 - 1.0;
    let my = u.zoom_config.z * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mx * 5.0, my * 5.0, 0.0);
    let d_mouse = length(p - mouse_pos);
    if (d_mouse < 2.0 && res.mat == 3.0) {
        res.dist += (2.0 - d_mouse) * 0.5; // push away
    }

    return res;
}

fn calcNormal(p: vec3<f32>, time: f32, glitch: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, glitch).dist - map(p - e.xyy, time, glitch).dist,
        map(p + e.yxy, time, glitch).dist - map(p - e.yxy, time, glitch).dist,
        map(p + e.yyx, time, glitch).dist - map(p - e.yyx, time, glitch).dist
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<f32>(u.config.z, u.config.w);
    if (gid.x >= u32(size.x) || gid.y >= u32(size.y)) { return; }

    let uv = (vec2<f32>(gid.xy) - 0.5 * size) / size.y;
    let time = u.config.x;

    let plasmaDensity = u.zoom_params.x;
    let temporalGlitch = u.zoom_params.y;
    let refractionIndex = u.zoom_params.z;
    let coreBloom = u.zoom_params.w;

    // Camera setup
    let mx = (u.zoom_config.y - 0.5) * 6.28;
    let my = (u.zoom_config.z - 0.5) * 3.14;

    var ro = vec3<f32>(0.0, 0.0, -8.0);
    // Orbit camera based on mouse
    let new_yz = rot(my) * ro.yz;
    ro.y = new_yz.x;
    ro.z = new_yz.y;

    let new_xz = rot(mx) * ro.xz;
    ro.x = new_xz.x;
    ro.z = new_xz.y;

    var ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var p = ro;
    var t = 0.0;
    var hit = false;
    var m = MapResult(0.0, 0.0);

    var vol_plasma = 0.0;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        m = map(p, time, temporalGlitch);

        // Volumetric accumulation for plasma ocean
        let ocean_density = fbm(p * 0.5 + vec3<f32>(time * 0.1));
        vol_plasma += ocean_density * plasmaDensity * 0.02;

        if (m.dist < 0.01) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += m.dist * 0.8;
    }

    var col = vec3<f32>(0.01, 0.03, 0.1); // Deep abyss background
    col += vec3<f32>(0.1, 0.5, 0.8) * vol_plasma; // Add volumetric plasma

    if (hit) {
        let n = calcNormal(p, time, temporalGlitch);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(-rd);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        if (m.mat == 1.0) {
            // Bone / Ribs
            var bone_col = vec3<f32>(0.2, 0.4, 0.5);
            bone_col *= diff * 0.5 + 0.5;
            // Simulated Subsurface scattering / Refraction
            bone_col += vec3<f32>(0.1, 0.8, 1.0) * fresnel * refractionIndex;
            col = mix(col, bone_col, 0.9);
        } else if (m.mat == 2.0) {
            // Core
            var core_col = vec3<f32>(1.0, 0.2, 0.8); // Neon purple/pink
            core_col += vec3<f32>(1.0, 1.0, 1.0) * pow(diff, 8.0);
            core_col *= coreBloom * 2.0;
            col = mix(col, core_col, 0.9);

            // Bloom glow effect around core (distance based)
            let core_dist = length(p - vec3<f32>(0.0, 0.0, 0.5));
            col += vec3<f32>(1.0, 0.2, 0.8) * (1.0 / (1.0 + core_dist * core_dist * 5.0)) * coreBloom;

        } else if (m.mat == 3.0) {
            // Temporal Streams
            var stream_col = vec3<f32>(0.0, 1.0, 0.8); // Cyan
            stream_col *= fresnel * 1.5;
            // Glitchy noise on streams
            let stream_glitch = fract(sin(dot(p.xy, vec2<f32>(12.9898, 78.233)) + time) * 43758.5453);
            if (temporalGlitch > 0.5 && stream_glitch > 0.9) {
                stream_col = vec3<f32>(1.0, 0.0, 1.0); // Glitch flash
            }
            // Additive blending for streams
            col += stream_col * 0.5;
        }
    }

    // Ripple effect
    for (var i=0; i<20; i++) {
        let r = u.ripples[i];
        if (r.w > 0.0) {
            let r_uv = uv * size.y + 0.5 * size;
            let d = length(r_uv / size - r.xy);
            if (d < 0.1) {
                col += vec3<f32>(0.2, 0.5, 1.0) * (0.1 - d) * 10.0 * r.z;
            }
        }
    }

    // Fog fading into background
    col = mix(col, vec3<f32>(0.01, 0.03, 0.1), smoothstep(10.0, 20.0, t));

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    let finalColor = vec4<f32>(col, 1.0);
    textureStore(writeTexture, gid.xy, finalColor);
}
