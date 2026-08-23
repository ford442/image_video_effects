// Flowing Silk Ribbons — layered anisotropic fabric streams
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>, // x=Ribbon Count, y=Flow Speed, z=Silk Width, w=Iridescence
    ripples: array<vec4<f32>, 50>,
};

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.22, 0.47)));
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 91.17) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (gid.x >= dims.x || gid.y >= dims.y) { return; }
    let coord = vec2<i32>(gid.xy);
    let res = vec2<f32>(dims);
    let uv = (vec2<f32>(gid.xy) + vec2<f32>(0.5)) / res;
    let aspect = res.x / max(res.y, 1.0);
    let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let ribbonCount = i32(3.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 9.0);
    let flowSpeed = mix(0.12, 1.7, clamp(u.zoom_params.y, 0.0, 1.0));
    let silkWidth = mix(0.018, 0.12, clamp(u.zoom_params.z, 0.0, 1.0));
    let iridescence = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);

    var coverage = 0.0;
    var highlight = 0.0;
    var hueAccum = 0.0;
    var depth = 0.0;
    for (var i = 0; i < 12; i++) {
        if (i >= ribbonCount) { break; }
        let fi = f32(i);
        let lane = (fi - 0.5 * f32(ribbonCount - 1)) * (1.65 / max(f32(ribbonCount), 1.0));
        let phase = time * flowSpeed * (0.45 + fi * 0.025) + hash11(fi) * 6.28318;
        let primary = sin(p.x * (1.8 + fi * 0.08) - phase) * (0.13 + audio.x * 0.035);
        let secondary = sin(p.x * 5.5 + phase * 0.63 + fi) * (0.025 + audio.y * 0.018);
        let comb = (mouse.y - lane) * exp(-abs(p.x - mouse.x) * 4.5) * held * 0.42;
        let center = lane + primary + secondary + comb;
        let slope = cos(p.x * (1.8 + fi * 0.08) - phase) * (0.24 + audio.x * 0.06);
        let width = silkWidth * (0.72 + 0.4 * sin(phase + fi));
        let d = abs(p.y - center);
        let ribbon = smoothstep(width, width * 0.15, d);
        let sheen = pow(max(1.0 - d / max(width, 0.001), 0.0), 7.0) * (0.35 + abs(slope));
        coverage += ribbon * (1.0 - coverage * 0.18);
        highlight += sheen;
        hueAccum += (ribbon + sheen) * (fi / max(f32(ribbonCount), 1.0) + slope * 0.15);
        depth = max(depth, ribbon * (1.0 - fi / max(f32(ribbonCount), 1.0) * 0.55));
    }

    var clickWave = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickWave += exp(-abs(distance(p, center) - age * 0.24) * 68.0) * exp(-age * 1.4);
        }
    }

    let hue = hueAccum / max(coverage + highlight, 0.001) + time * 0.018 + audio.y * 0.16;
    let baseSilk = mix(vec3<f32>(0.16, 0.025, 0.08), palette(hue), 0.3 + iridescence * 0.7);
    var hdrColor = vec3<f32>(0.006, 0.008, 0.018) + baseSilk * coverage * (0.8 + audio.x * 0.5);
    hdrColor += palette(hue + 0.2) * highlight * (0.18 + iridescence * 0.85 + audio.z * 0.35);
    hdrColor += vec3<f32>(0.45, 0.7 + audio.y * 0.4, 1.15 + audio.z * 0.5) * clickWave * 0.32;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.06 + audio.x * 0.065), vec3<f32>(0.0), vec3<f32>(7.0));
    let mapped = acesToneMap(hdrColor * 1.08);
    let alpha = clamp(coverage * 0.7 + highlight * 0.12 + clickWave * 0.1, 0.02, 0.98);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(depth, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
