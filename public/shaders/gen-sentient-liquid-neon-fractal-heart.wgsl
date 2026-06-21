// ----------------------------------------------------------------
// Sentient Liquid-Neon Fractal-Heart
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
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

    // Calculate global audio spike intensity from ripples
    var audio_intensity = 0.0;
    for(var i = 0; i < 50; i++) {
        let ripple = u.ripples[i];
        if (ripple.w > 0.0) {
            let dist = distance(p.xy, ripple.xy);
            let ripple_effect = sin(dist * 10.0 - ripple.w * 5.0) * exp(-dist * 2.0);
            audio_intensity += max(0.0, ripple_effect) * ripple.z;
        }
    }

    // Smooth beat mixed with audio reactivity
    let beat_phase = fract(time * 1.5) * PI * 2.0;
    let base_beat = exp(-3.0 * fract(time * 1.5)) * sin(beat_phase) * 0.1;
    let pulse = 1.0 + (base_beat + audio_intensity * 0.05) * u.zoom_params.y;

    // Localized Defibrillator Shock / Gravity Well (Mouse Interaction)
    let mouse_pos = u.zoom_config.yz;
    let mouse_dist = distance(p.xy, mouse_pos);
    let shock_influence = smoothstep(1.5, 0.0, mouse_dist);
    let shock_scale = mix(1.0, 0.8 + 0.5 * sin(time * 20.0), shock_influence * u.zoom_config.y);
    // using zoom_config.y as a stand-in for "mouse active" or simply rapid interaction

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
    if (fractal_d < 0.1) {
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
    let time = u.config.x;

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
            glow += 0.01 / (0.01 + d * d);
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
            col = neonColor * (0.8 + 0.2 * sin(p.z * 10.0 - time * 5.0)) + spec * vec3<f32>(1.0);
        } else {
            // Tissue
            col = tissueColor * diff + spec * vec3<f32>(0.5) + fresnel * vec3<f32>(0.3, 0.1, 0.5);
            // Add subsurface scattering based on accumulated glow
            col += neonColor * glow * 0.1;
        }
    } else {
        // Void (Bioluminescent Fog)
        col = vec3<f32>(0.05, 0.0, 0.1) * glow * u.zoom_params.w;
        // Floating particles could be added here as noise
        let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        col += vec3<f32>(0.2, 0.8, 1.0) * step(0.999, noise) * u.zoom_params.w * 0.5;
    }

    // Output
    let final_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(coords), final_color);
}
