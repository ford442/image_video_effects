// ----------------------------------------------------------------
// Sentient Bismuth Hypercrystal
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
  zoom_params: vec4<f32>,  // .x = Growth, .y = Audio React, .z = Twist, .w = Iridescence
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn boxSDF(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0)));
}

fn map(p_in: vec3<f32>, time: f32, audio: f32) -> f32 {
    var p = p_in;

    let twist = u.zoom_params.z;
    p = vec3<f32>(p.x * cos(p.y * twist) - p.z * sin(p.y * twist),
                  p.y,
                  p.x * sin(p.y * twist) + p.z * cos(p.y * twist));

    // Mouse gravity well
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(2.0, -2.0) * vec2<f32>(u.config.z/u.config.w, 1.0);
    let mouse_pos = vec3<f32>(mouse * 2.0, -1.0);
    if (u.zoom_config.w > 0.0) {
        let d2 = length(p.xy - mouse_pos.xy);
        let pull = exp(-d2 * 2.0) * 0.5;
        p.z -= pull;
    }

    let growth = u.zoom_params.x;
    let audio_react = u.zoom_params.y * audio;

    var s = 1.0;
    var d = boxSDF(p, vec3<f32>(1.0));

    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        p = abs(p) - vec3<f32>(0.5 + sin(time * 0.2 + fi) * 0.1 * growth);

        let r1 = rot(time * 0.1 + audio_react);
        let pyz = r1 * vec2<f32>(p.y, p.z);
        p = vec3<f32>(p.x, pyz.x, pyz.y);

        let r2 = rot(0.2);
        let pxz = r2 * vec2<f32>(p.x, p.z);
        p = vec3<f32>(pxz.x, p.y, pxz.y);

        s *= 2.0;
        let b = boxSDF(p, vec3<f32>(1.2 - 0.2 * audio_react));
        d = max(d, -b / s); // Menger sponge style subtraction
        d = min(d, boxSDF(p, vec3<f32>(0.1)) / s); // Add some structures back
    }
    return d;
}

fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio) - map(p - e.xyy, time, audio),
        map(p + e.yxy, time, audio) - map(p - e.yxy, time, audio),
        map(p + e.yyx, time, audio) - map(p - e.yyx, time, audio)
    );
    return normalize(n);
}

// Thin film iridescence palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let base_uv = vec2<f32>(global_id.xy) / resolution;
    let uv = (base_uv - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let time = u.config.x;

    let audio = textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(base_uv.x, 0.5), 0.0).r;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, 3.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    var dO = 0.0;
    var p = ro;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = map(p, time, audio);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = getNormal(p, time, audio);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let dif = clamp(dot(n, lightDir), 0.0, 1.0);

        // Iridescence based on view angle and audio
        let viewDir = normalize(ro - p);
        let ndotv = clamp(dot(n, viewDir), 0.0, 1.0);
        let iridescence = u.zoom_params.w;

        // Base color shift with iridescence and audio
        let filmThickness = (ndotv + audio * 0.5) * iridescence;
        let iridCol = palette(filmThickness + time * 0.1);

        // Specular
        let refl = reflect(-lightDir, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        col = iridCol * dif + vec3<f32>(1.0) * spec;

        // Depth fog
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.05 * dO));
    }

    // TAA / Temporal blend (simplified)
    let history = textureSampleLevel(readTexture, non_filtering_sampler, base_uv, 0.0).rgb;
    col = mix(history, col, 0.2); // Very basic trailing

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
