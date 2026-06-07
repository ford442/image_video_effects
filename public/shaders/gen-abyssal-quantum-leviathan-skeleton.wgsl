// ----------------------------------------------------------------
// Abyssal Quantum-Leviathan Skeleton
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Bone Density, y=Marrow Glow, z=Current Turbulence, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Hash function for noise
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

// 3D Noise for Aether Currents
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u_f = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u_f.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u_f.x), u_f.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u_f.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u_f.x), u_f.y), u_f.z);
}

// SDF for the leviathan skeleton
fn map(pos_in: vec3<f32>) -> vec2<f32> {
    var p = pos_in;

    let bone_density = u.zoom_params.x; // 0.5 default
    let audio_react = u.zoom_params.w * u.config.y; // 1.0 default

    // Apply mouse interaction as a gravity well
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 10.0, (u.zoom_config.z - 0.5) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < 5.0) {
        let pull = smoothstep(5.0, 0.0, dist_to_mouse) * 2.0;
        p = mix(p, mouse_pos, pull * 0.1);
    }

    // Spine (along Z axis, curved with sine waves)
    p.x += sin(p.z * 0.2 + u.config.x * 0.5) * 2.0;
    p.y += cos(p.z * 0.15 + u.config.x * 0.3) * 1.5;

    // Spine core
    let spine_dist = length(p.xy) - 0.5 * bone_density;
    var d = spine_dist;
    var material = 1.0; // 1.0 for bone

    // Ribs (domain repetition along Z)
    let rib_spacing = 1.5 / bone_density;
    let p_z_mod = p.z - rib_spacing * floor(p.z / rib_spacing) - rib_spacing * 0.5;
    var p_rib = vec3<f32>(p.x, p.y, p_z_mod);

    // Rib shape (arcing outwards from spine)
    p_rib.x = abs(p_rib.x) - 1.0; // mirror symmetry
    p_rib.y -= 0.5;

    // Audio reactivity bulges the ribs
    let bulge = sin(u.config.x * 2.0 + p.z * 0.5) * audio_react * 0.2;
    let rib_thickness = 0.2 * bone_density + bulge;

    // Torus-like ribs curving downwards
    let q = vec2<f32>(length(p_rib.xy) - 3.0, p_rib.z);
    let rib_dist = length(q) - rib_thickness;

    d = smin(d, rib_dist, 0.8);

    return vec2<f32>(d, material);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dimensions = textureDimensions(writeTexture);
    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);

    // Camera setup
    let time = u.config.x;
    var ro = vec3<f32>(sin(time * 0.2) * 12.0, sin(time * 0.1) * 5.0, cos(time * 0.2) * 12.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));

    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    var max_d = 40.0;
    var hit = false;
    var res = vec2<f32>(0.0);
    var p = ro;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        res = map(p);
        if (res.x < 0.01) {
            hit = true;
            break;
        }
        if (t > max_d) {
            break;
        }
        t += res.x * 0.8;
    }

    var color = vec3<f32>(0.0);
    let marrow_glow_param = u.zoom_params.y; // 0.8 default
    let turb_param = u.zoom_params.z; // 0.6 default

    if (hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;

        // Base bone color
        color = vec3<f32>(0.2, 0.4, 0.5) * diff + vec3<f32>(0.05, 0.1, 0.15) * amb;

        // Rim light
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        color += vec3<f32>(0.1, 0.8, 1.0) * pow(rim, 3.0);

        // Marrow glow inside bones
        let dist_to_center = length(p.xy);
        let marrow_intensity = smoothstep(2.0, 0.0, dist_to_center) * marrow_glow_param;
        let audio_pulse = sin(time * 5.0 + p.z) * 0.5 + 0.5;
        color += vec3<f32>(0.5, 0.0, 1.0) * marrow_intensity * (1.0 + audio_pulse * u.config.y);

        // Simple fog
        color = mix(color, vec3<f32>(0.0, 0.02, 0.05), smoothstep(10.0, max_d, t));
    } else {
        // Background volumetric deep-sea aether currents
        var vol_acc = 0.0;
        var vol_t = 0.0;
        let step_size = 0.5;
        for(var i=0; i<30; i++) {
            let vp = ro + rd * vol_t;
            let n_val = noise3(vp * turb_param + vec3<f32>(0.0, 0.0, time * 0.5));
            // Accumulate density
            vol_acc += smoothstep(0.4, 0.6, n_val) * 0.05;
            vol_t += step_size;
            if(vol_t > max_d) { break; }
        }
        let bg_color = vec3<f32>(0.0, 0.05, 0.1);
        let aether_color = vec3<f32>(0.0, 0.5, 0.8) + vec3<f32>(0.3, 0.1, 0.6) * sin(time);
        color = bg_color + aether_color * vol_acc;
    }

    textureStore(writeTexture, coords, vec4<f32>(color, 1.0));
}