// ----------------------------------------------------------------
// Neuro-Kinetic Liquid-Gold Lotus
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
    zoom_params: vec4<f32>,  // x=Bloom Radius, y=Plasma Intensity, z=Gold Smoothness, w=unused
    ripples: array<vec4<f32>, 50>,
};

fn rotX(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// 3D Noise for fluid/plasma
fn hash(p: vec3<f32>) -> vec3<f32> {
    var p_temp = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                           dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                           dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p_temp) * 43758.5453123) * 2.0 - vec3<f32>(1.0);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(dot(hash(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                       dot(hash(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(dot(hash(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                       dot(hash(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(dot(hash(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                       dot(hash(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(dot(hash(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                       dot(hash(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for(var i=0; i<4; i++) {
        f += w * noise(pp);
        pp *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn opSmoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(d2 - d1)/k, 0.0, 1.0);
    return mix(d2, d1, h) - k*h*(1.0-h);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdLotusPetals(p: vec3<f32>, time: f32, bloom: f32) -> f32 {
    var p_w = p;

    // Unfurling animation
    let num_petals = 8.0;
    let angle = atan2(p_w.x, p_w.z);
    let r = length(p_w.xz);

    // Domain repetition
    let a = angle * num_petals / (2.0 * 3.14159265);
    let id = floor(a);
    let af = fract(a) - 0.5;

    // Reconstruct position based on repetition
    let a_mod = (id + 0.5) * (2.0 * 3.14159265) / num_petals;
    let c = cos(a_mod);
    let s = sin(a_mod);
    p_w = vec3<f32>(p.x*c + p.z*s, p.y, -p.x*s + p.z*c);

    // Petal shape
    p_w.x = abs(p_w.x) - 0.2;
    p_w.y -= 0.5 * r * r - bloom * 0.5;

    let base = sdSphere(p_w, 0.4);

    // Add liquid perturbation
    let n = fbm(p * 2.0 + vec3<f32>(0.0, time * 0.5, 0.0)) * 0.1;

    return base + n;
}

fn map(p: vec3<f32>, time: f32, audio_val: f32, bloom: f32) -> f32 {
    let core = sdSphere(p, 0.5 + audio_val * 0.3) + fbm(p * 3.0 - vec3<f32>(0.0, time, 0.0)) * 0.2;
    let petals = sdLotusPetals(p, time, bloom);
    return opSmoothUnion(core, petals, 0.4);
}

fn getNormal(p: vec3<f32>, time: f32, audio_val: f32, bloom: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio_val, bloom) - map(p - e.xyy, time, audio_val, bloom),
        map(p + e.yxy, time, audio_val, bloom) - map(p - e.yxy, time, audio_val, bloom),
        map(p + e.yyx, time, audio_val, bloom) - map(p - e.yyx, time, audio_val, bloom)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;
    let audio_val = u.config.y; // Simplified audio metric

    let bloom_radius = u.zoom_params.x;
    let plasma_int = u.zoom_params.y;
    let gold_smooth = u.zoom_params.z;

    // Mouse Interaction: Bending ray direction
    let mx = (u.zoom_config.y / res.x) * 2.0 - 1.0;
    let my = -(u.zoom_config.z / res.y) * 2.0 + 1.0;

    let ro = vec3<f32>(0.0, 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Apply mouse rotation
    rd = rotX(my * 1.5) * rd;
    rd = rotY(-mx * 1.5) * rd;
    var ro_rot = rotX(my * 1.5) * ro;
    ro_rot = rotY(-mx * 1.5) * ro_rot;

    // Raymarching
    var t = 0.0;
    var p = ro_rot;
    var d = 0.0;

    for(var i=0; i<80; i++) {
        p = ro_rot + rd * t;
        // Gravity well distortion near center
        let dist = length(p.xy);
        let bend = exp(-dist * dist * 0.5) * 0.2;
        p += vec3<f32>(bend * rd.xy, 0.0);

        d = map(p, time, audio_val, bloom_radius);
        if(d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.02, 0.02, 0.05); // Background

    if (d < 0.001) {
        let n = getNormal(p, time, audio_val, bloom_radius);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let v = normalize(ro_rot - p);
        let h = normalize(l + v);

        // Base liquid-gold color
        let base_gold = vec3<f32>(1.0, 0.7, 0.2);

        // Lighting
        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 64.0 * gold_smooth);
        let rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        // Plasma veins logic using fbm
        let vein_noise = fbm(p * 5.0 + vec3<f32>(time * 2.0));
        let plasma_factor = smoothstep(0.4, 0.6, vein_noise) * audio_val * plasma_int;
        let plasma_col = vec3<f32>(0.0, 1.0, 1.0) * plasma_factor; // Cyan plasma
        let plasma_col2 = vec3<f32>(1.0, 0.0, 1.0) * plasma_factor; // Magenta plasma
        let mixed_plasma = mix(plasma_col, plasma_col2, sin(time)*0.5+0.5);

        // Combine lighting and material
        col = base_gold * (diff * 0.5 + 0.2) + vec3<f32>(1.0) * spec + base_gold * rim * 0.5;

        // Overlay plasma
        col = mix(col, mixed_plasma * 2.0, plasma_factor);
    }

    // Atmospheric perspective (fog)
    col = mix(col, vec3<f32>(0.02, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
