// Classic Fractal Flame — affine variation distance traps
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
    zoom_params: vec4<f32>, // x=Iterations, y=Variation Mix, z=Flame Zoom, w=Palette Cycle
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.0, 0.10, 0.24)));
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

    let iterationCount = i32(12.0 + clamp(u.zoom_params.x, 0.0, 1.0) * 36.0);
    let variationMix = clamp(u.zoom_params.y, 0.0, 1.0);
    let flameZoom = mix(0.75, 2.2, clamp(u.zoom_params.z, 0.0, 1.0));
    let paletteCycle = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    p = p * flameZoom - mouse * held * 0.22;

    var z = p;
    var density = 0.0;
    var edgeTrap = 0.0;
    var hueMoment = 0.0;
    for (var i = 0; i < 48; i++) {
        if (i >= iterationCount) { break; }
        let fi = f32(i);
        let r = max(length(z), 0.001);
        let theta = atan2(z.y, z.x);
        let swirl = vec2<f32>(z.x * sin(r * r) - z.y * cos(r * r),
                              z.x * cos(r * r) + z.y * sin(r * r));
        let horseshoe = vec2<f32>((z.x - z.y) * (z.x + z.y), 2.0 * z.x * z.y) / r;
        let polar = vec2<f32>(theta / 3.14159265, r - 1.0);
        let firstMix = mix(swirl, horseshoe, variationMix);
        let varied = mix(firstMix, polar, 0.22 + audio.y * 0.12);
        let affine = rot(0.38 + sin(time * 0.12) * 0.07) * varied * (0.62 + audio.x * 0.035);
        z = affine + vec2<f32>(-0.12 + sin(fi * 2.1) * 0.025, 0.16);
        let trap = exp(-abs(length(z) - 0.48) * (12.0 + audio.z * 8.0));
        let center = exp(-length(z) * 4.5);
        density += (trap * 0.08 + center * 0.06) / (1.0 + fi * 0.025);
        edgeTrap += exp(-abs(z.x) * 26.0) * exp(-abs(z.y) * 2.0) * 0.018;
        hueMoment += (trap + center) * fi;
    }

    var clickFlame = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickFlame += exp(-abs(distance(p / flameZoom, center) - age * 0.22) * 72.0) * exp(-age * 1.45);
        }
    }

    let flame = min(density + edgeTrap, 5.0);
    let hue = hueMoment / max(density * 12.0, 0.001) * 0.002 + time * (0.015 + paletteCycle * 0.06) + audio.y * 0.12;
    let classicWarm = vec3<f32>(1.3, 0.18, 0.015);
    let spectral = palette(hue);
    var hdrColor = vec3<f32>(0.006, 0.002, 0.008) + mix(classicWarm, spectral, paletteCycle * 0.72) * flame * (1.1 + audio.x * 0.8);
    hdrColor += vec3<f32>(1.2, 0.65 + audio.y * 0.25, 0.08 + audio.z * 0.25) * edgeTrap * 1.4;
    hdrColor += vec3<f32>(1.0, 0.28, 0.08 + audio.z * 0.35) * clickFlame * 0.38;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.05 + audio.x * 0.065), vec3<f32>(0.0), vec3<f32>(8.0));
    let mapped = acesToneMap(hdrColor);
    let alpha = clamp(flame * 0.46 + edgeTrap * 0.2 + clickFlame * 0.1, 0.02, 0.98);
    let depth = clamp(density * 0.3 + edgeTrap * 0.12, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
