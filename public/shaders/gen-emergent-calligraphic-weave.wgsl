// Emergent Calligraphic Weave — layered ink-flow filaments
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
    zoom_params: vec4<f32>, // x=Stroke Density, y=Flow Speed, z=Ink Width, w=Chromatic Bloom
    ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(1.0) * t + vec3<f32>(0.02, 0.31, 0.58)));
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
    var p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let time = u.config.x;
    let audio = plasmaBuffer[0].xyz;

    let strokeCount = i32(3.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 7.0);
    let flowSpeed = mix(0.12, 1.5, clamp(u.zoom_params.y, 0.0, 1.0));
    let inkWidth = mix(0.008, 0.055, clamp(u.zoom_params.z, 0.0, 1.0));
    let chroma = clamp(u.zoom_params.w, 0.0, 1.0);

    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let toMouse = p - mouse;
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    p += normalize(toMouse + vec2<f32>(0.0001)) * sin(length(toMouse) * 16.0 - time * 4.0) * held * 0.07;

    var ink = 0.0;
    var fineInk = 0.0;
    var hueMoment = 0.0;
    for (var i = 0; i < 10; i++) {
        if (i >= strokeCount) { break; }
        let fi = f32(i);
        let lane = (fi - 0.5 * f32(strokeCount - 1)) * 0.16;
        let phase = time * flowSpeed * (0.42 + fi * 0.035) + hash21(vec2<f32>(fi, 3.7)) * 6.28318;
        let warp = (noise2(vec2<f32>(p.x * 1.8 + fi, time * 0.08)) - 0.5) * 0.22;
        let curve = lane + sin(p.x * (2.2 + fi * 0.13) + phase) * (0.10 + audio.y * 0.045) +
                    sin(p.x * 6.0 - phase * 0.7) * 0.025 + warp;
        let derivative = cos(p.x * (2.2 + fi * 0.13) + phase);
        let nib = inkWidth * mix(0.55, 1.6, abs(derivative));
        let d = abs(p.y - curve);
        let stroke = exp(-d * d / max(nib * nib, 0.000001));
        let hairline = exp(-abs(d - nib * 1.8) * 180.0) * 0.25;
        ink += stroke;
        fineInk += hairline;
        hueMoment += (stroke + hairline) * (fi / max(f32(strokeCount), 1.0));
    }

    var clickInk = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.2) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickInk += exp(-abs(distance(p, center) - age * 0.2) * 75.0) * exp(-age * 1.35);
        }
    }

    let paper = vec3<f32>(0.012, 0.009, 0.02) + vec3<f32>(noise2(p * 80.0)) * 0.012;
    let hue = hueMoment / max(ink + fineInk, 0.001) + time * 0.025 + audio.y * 0.12;
    let inkColor = palette(hue) * (0.5 + chroma * 1.6 + audio.x * 0.7);
    let bloom = min(ink + fineInk * 0.5, 3.0);
    var hdrColor = paper + inkColor * bloom;
    hdrColor += palette(hue + 0.2) * clickInk * (0.35 + audio.z * 0.8);
    hdrColor += vec3<f32>(0.35, 0.65, 1.1) * fineInk * chroma * (0.25 + audio.z);

    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.05 + audio.x * 0.07), vec3<f32>(0.0), vec3<f32>(6.0));
    let mapped = acesToneMap(hdrColor * 1.08);
    let alpha = clamp(bloom * 0.48 + fineInk * 0.3 + clickInk * 0.12, 0.02, 0.98);
    let depth = clamp(bloom * 0.38 + fineInk * 0.16, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
