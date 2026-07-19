// ----------------------------------------------------------------
// Radiant Cyber-Plasma Astro-Griffin
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Warp Intensity, y=Wing Span, z=Fractal Depth, w=Plasma Glow
    ripples: array<vec4<f32>, 50>,
};

// --- UTILITIES ---
const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Simplex noise approximation
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + vec3<f32>(33.33));
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- SDF FUNCTIONS ---

// Wing feathers using domain repetition
fn wingFeathers(p: vec3<f32>, span: f32) -> f32 {
    var q = p;
    // Repeat on X/Z for feathers
    q.x = (fract(q.x * 2.0) - 0.5) / 2.0;
    q.z = (fract(q.z * 2.0) - 0.5) / 2.0;

    // Scale span
    let width = 0.1 + span * 0.1;
    let length = 0.5 + span * 0.5;

    // Simple elongated box for feather
    let d = abs(q) - vec3<f32>(width, 0.02, length);
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Griffin core body
fn griffinBody(p: vec3<f32>) -> f32 {
    var q = p;
    // Lion hindquarters / Eagle forequarters combo (ellipsoids)
    let bodyScale = vec3<f32>(0.5, 0.4, 0.8);
    let bodyDist = length(q / bodyScale) - 1.0;
    return bodyDist * min(min(bodyScale.x, bodyScale.y), bodyScale.z);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;

    // Mouse warp implementation
    let mouse = u.zoom_config.yz;
    let anomaly_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    p_warp -= anomaly_pos;

    let warp_intensity = u.zoom_params.x;
    let dist_to_anomaly = length(p_warp);
    let twist_amount = warp_intensity * (1.0 / (dist_to_anomaly + 0.1));

    let tmp_x = p_warp.x * cos(twist_amount) - p_warp.z * sin(twist_amount);
    let tmp_z = p_warp.x * sin(twist_amount) + p_warp.z * cos(twist_amount);
    p_warp.x = tmp_x;
    p_warp.z = tmp_z;

    // Animated flight/flapping
    let t = u.config.x * 2.0;

    // Wings
    var wing_p = p_warp;
    // Wing flapping
    let flap = sin(t) * 0.5;
    wing_p.y -= abs(wing_p.x) * flap;
    // Mirror wings on X
    wing_p.x = abs(wing_p.x) - 1.0;
    let wing_span = u.zoom_params.y;
    let wing_dist = wingFeathers(wing_p, wing_span);

    // Body
    var body_p = p_warp;
    // Body bobbing
    body_p.y += sin(t * 1.5) * 0.2;
    let body_dist = griffinBody(body_p);

    // Noise displacement for "shattered chrono-prism" look
    let fractal_depth = u.zoom_params.z;
    let displacement = sin(p_warp.x * 10.0) * sin(p_warp.y * 10.0) * sin(p_warp.z * 10.0) * 0.05 * fractal_depth;

    let combined_dist = smin(wing_dist, body_dist, 0.2) + displacement;

    // Material ID (0 for void, 1 for griffin)
    return vec2<f32>(combined_dist, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d.x;
    }
    if (t > 20.0) { t = -1.0; }
    return vec2<f32>(t, mat_id);
}

// Background rift (volumetric accumulation)
fn getBackgroundRift(rd: vec3<f32>, time: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0, 0.0, 0.0);
    var p = rd * 5.0;
    for (var i = 1; i <= 4; i++) {
        let fi = f32(i);
        let tmp_x = p.x * cos(time*0.1) - p.z * sin(time*0.1);
        let tmp_z = p.x * sin(time*0.1) + p.z * cos(time*0.1);
        p.x = tmp_x;
        p.z = tmp_z;
        let noise_val = sin(p.x * fi + time) * cos(p.y * fi) * sin(p.z * fi);
        col += vec3<f32>(0.1, 0.2, 0.5) * max(0.0, noise_val) / fi;
    }
    // Audio reactive background bass
    let bass = plasmaBuffer[0].x;
    col *= (1.0 + bass * 0.5);
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;
    let time = u.config.x;

    var ro = vec3<f32>(0.0, 0.0, 3.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    // Audio Reactivity
    let bass = plasmaBuffer[0].x;
    let midHigh = plasmaBuffer[1].x;
    let plasma_glow_multiplier = u.zoom_params.w;

    let hit = raymarch(ro, rd);
    let t = hit.x;

    var col = vec3<f32>(0.0, 0.0, 0.0);

    if (t > 0.0) {
        // Hit Griffin
        let p = ro + rd * t;
        let n = calcNormal(p);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);

        // Base cyber-blue / purple gradient
        var baseCol = mix(vec3<f32>(0.1, 0.2, 0.8), vec3<f32>(0.5, 0.1, 0.8), p.y + 0.5);

        // Plasma gold/magenta wingtips (based on x distance)
        let wingGlow = smoothstep(0.5, 1.5, abs(p.x));
        let glowCol = mix(vec3<f32>(1.0, 0.8, 0.1), vec3<f32>(1.0, 0.2, 0.8), sin(time * 2.0) * 0.5 + 0.5);

        baseCol = mix(baseCol, glowCol, wingGlow);

        // Shading with audio-reactive bioluminescence
        col = baseCol * diff * (0.5 + 0.5 * midHigh * plasma_glow_multiplier);

        // Bloom / sub-surface glow approx
        let rim = 1.0 - max(dot(n, -rd), 0.0);
        col += glowCol * pow(rim, 3.0) * plasma_glow_multiplier;

        // Distance fog
        col = mix(col, vec3<f32>(0.0, 0.0, 0.0), 1.0 - exp(-0.05 * t * t));

    } else {
        // Background Rift
        col = getBackgroundRift(rd, time);
    }

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(col, 1.0));
}
