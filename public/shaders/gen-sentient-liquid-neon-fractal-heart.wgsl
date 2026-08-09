// ----------------------------------------------------------------
// Sentient Liquid-Neon Fractal-Heart
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Fractal Complexity, y=Pulse Intensity, z=Neon Saturation, w=Bioluminescent Fog
    ripples: array<vec4<f32>, 50>,
};

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

const PI: f32 = 3.14159265359;

var<private> g_audio: vec3<f32>;
var<private> g_mouse: vec2<f32>;
var<private> g_clickShock: f32;
var<private> g_mouseDown: f32;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D rotation matrix around Y
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

// 3D rotation matrix around Z
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat3x3<f32>(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Heartbeat cycle
    let time = u.config.x;

    // Smooth contraction with real plasma bands and one precomputed click shock.
    let beat_phase = fract(time * (1.25 + g_audio.x * 0.2)) * PI * 2.0;
    let base_beat = exp(-3.0 * fract(time * 1.25)) * sin(beat_phase) * 0.1;
    let pulse = 1.0 + (base_beat + g_audio.x * 0.11 + g_clickShock * 0.08) * u.zoom_params.y;

    // Localized Defibrillator Shock / Gravity Well (Mouse Interaction)
    let mouse_dist = distance(p.xy, g_mouse * vec2<f32>(1.8, 1.2));
    let shock_influence = smoothstep(1.5, 0.0, mouse_dist);
    let shock_scale = mix(1.0, 0.88 + 0.22 * sin(time * 20.0), shock_influence * g_mouseDown);

    // Apply scaling
    p = p / (pulse * shock_scale);

    // Fractal structure
    var d = length(p) - 1.5; // Base sphere

    let iterations = i32(1.0 + u.zoom_params.x * 6.0);
    var s = 1.0;
    var fractal_d = d;

    for (var i = 0; i < iterations; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.3, 0.4) * s;
        p = rotZ(0.5) * p;
        p = rotY(0.2) * p;

        // Fold space
        if (p.x < p.y) { p = p.yxz; }
        if (p.x < p.z) { p = p.zyx; }
        if (p.y < p.z) { p = p.xzy; }

        let sub_box = length(max(abs(p) - vec3<f32>(0.2, 0.5, 0.1) * s, vec3<f32>(0.0))) - 0.05 * s;
        fractal_d = smin(fractal_d, sub_box, 0.2 * s);
        s *= 0.6;
    }

    // Material ID: 1.0 for tissue, 2.0 for glowing arteries
    var mat_id = 1.0;
    let arteryWave = sin(atan2(p.y, p.x) * 7.0 + p.z * 8.0 - time * (9.0 + g_audio.y * 2.0));
    if (arteryWave > 0.58) {
        mat_id = 2.0;
    }

    // Correct distance scale back
    let final_d = fractal_d * pulse * shock_scale;
    return vec2<f32>(final_d, mat_id);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coords.x >= res.x || coords.y >= res.y) {
        return;
    }

    let uv = (coords - 0.5 * res) / res.y;
    let screenUV = coords / res;
    let time = u.config.x;

    g_audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
    g_mouse = (u.zoom_config.yz - 0.5) * 2.0;
    g_mouseDown = select(0.0, 1.0, u.zoom_config.w > 0.5);

    // Process click fronts once per pixel, outside every map/normal evaluation.
    g_clickShock = 0.0;
    let aspectFix = vec2<f32>(res.x / res.y, 1.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let front = abs(length((screenUV - ripple.xy) * aspectFix) - age * 0.74);
        g_clickShock += exp(-front * 62.0) * (1.0 - age * 0.5);
    }

    // Camera setup
    let camPos = vec3<f32>(0.0, 0.0, -4.0);
    let camTarget = vec3<f32>(0.0, 0.0, 0.0);
    let fwd = normalize(camTarget - camPos);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rayDir = normalize(fwd + uv.x * right + uv.y * up);

    // Raymarching loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var d_min = 1000.0;
    var hit_mat = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = camPos + rayDir * t;
        let d_mat = map(p);
        let d = d_mat.x;

        // Volumetric accumulation (Bioluminescent fog and subsurface scattering)
        if (d < 0.2) {
            glow += min(0.1, 0.006 / (0.01 + d * d));
        }

        d_min = min(d_min, d);

        if (d < 0.001) {
            hit_mat = d_mat.y;
            break;
        }
        if (t > 10.0) {
            break;
        }

        t += d;
    }

    // Shading
    if (t < 10.0) {
        let p = camPos + rayDir * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(sin(time), 1.0, -cos(time)));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(camPos - p);
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(n, halfDir), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 4.0);

        // Base Colors
        let tissueColor = vec3<f32>(0.2, 0.0, 0.4); // Deep violet
        let neonColor = vec3<f32>(1.0, 0.0, 0.8) * u.zoom_params.z; // Magenta / Cyan liquid neon

        if (hit_mat == 2.0) {
            // Arteries
            let arteryRunner = pow(max(0.0, sin(p.z * 14.0 + atan2(p.y, p.x) * 6.0 - time * (16.0 + g_audio.y * 2.0))), 8.0);
            col = neonColor * (0.65 + arteryRunner * (0.45 + g_audio.z * 0.35)) + spec * vec3<f32>(1.0);
        } else {
            // Tissue
            col = tissueColor * diff + spec * vec3<f32>(0.5) + fresnel * vec3<f32>(0.3, 0.1, 0.5);
            // Add subsurface scattering based on accumulated glow
            col += neonColor * min(glow, 4.0) * 0.1;
        }
    } else {
        // Void (Bioluminescent Fog)
        col = vec3<f32>(0.05, 0.0, 0.1) * min(glow, 4.0) * u.zoom_params.w;
        // Floating particles could be added here as noise
        let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        col += vec3<f32>(0.2, 0.8, 1.0) * step(0.999, noise) * u.zoom_params.w * 0.5;
    }

    col += vec3<f32>(0.1, 0.65, 1.0) * g_clickShock * (0.35 + u.zoom_params.y * 0.25);

    // Arterial flow advects the bounded A/C display history and keeps neon
    // plasma motion visible without unbounded HDR accumulation.
    let radial = normalize(uv + vec2<f32>(0.0001));
    let tangent = vec2<f32>(-radial.y, radial.x);
    let historyUV = clamp(screenUV - tangent * 0.008 - radial * 0.003, vec2<f32>(0.002), vec2<f32>(0.998));
    let previous = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let temporal = clamp(max(col, previous * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));
    let hit = t < 10.0 && hit_mat > 0.0;
    let depth = select(1.0, clamp(t / 10.0, 0.0, 0.995), hit);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, vec2<i32>(coords), vec4<f32>(temporal, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
