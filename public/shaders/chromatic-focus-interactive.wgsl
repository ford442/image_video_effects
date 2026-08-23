// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Focus Interactive
//  Category: visual-effects
//  Features: depth-of-field, chromatic-aberration, wavelength-dependent-alpha,
//            audio-reactive, upgraded-rgba, aperture-blades, held-drag,
//            bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
// ═══════════════════════════════════════════════════════════════════════════════

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
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const WAVELENGTH_RED: f32 = 650.0;
const WAVELENGTH_GREEN: f32 = 550.0;
const WAVELENGTH_BLUE: f32 = 450.0;

fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    if (gid.x >= u32(u.config.z) || gid.y >= u32(u.config.w)) { return; }

    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / max(dims.y, 1.0);
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);
    let mouse = u.zoom_config.yz;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strength = u.zoom_params.x * 0.05 * (1.0 + bass * 0.35);
    let blurAmt = u.zoom_params.y;
    let focusRad = u.zoom_params.z * (1.0 - held * 0.12);
    let hardness = u.zoom_params.w * 5.0 + 1.0;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let dir = select(vec2<f32>(0.0), distVec / max(dist, 0.0001), dist > 0.0001);
    var amount = pow(smoothstep(focusRad, focusRad + 0.5, dist), 1.0 / hardness);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + dir * amount * strength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - dir * amount * strength, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    var color = vec3<f32>(r, g, b) * (1.0 - amount * 0.3);

    let ang = atan2(distVec.y, distVec.x) + time * (0.35 + mids * 0.4);
    let blades = abs(sin(ang * 6.0));
    let iris = smoothstep(0.12, 0.0, abs(dist - focusRad)) * (0.35 + blades * 0.65);
    let packets = smoothstep(0.09, 0.0, abs(fract(dist * 12.0 - time * (2.0 + bass * 1.8)) - 0.5));
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 64.0) * (1.0 - age / 1.5));
        }
    }
    let slick = hsv2rgb(vec3<f32>(fract(ang / 6.28318 + time * 0.1 + treble * 0.2), 0.7, 1.0));
    color = mix(color, color * slick * 1.25, 0.2 + blurAmt * 0.2);
    color += slick * (iris * 0.45 + packets * 0.22 + click * 0.5 + held * 0.08);

    let blurThickness = amount * 5.0 + blurAmt * 2.0;
    let alphaR = calculateChannelAlpha(blurThickness, WAVELENGTH_RED);
    let alphaG = calculateChannelAlpha(blurThickness, WAVELENGTH_GREEN);
    let alphaB = calculateChannelAlpha(blurThickness, WAVELENGTH_BLUE);
    let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + click * 0.08, 0.0, 1.0);
    let finalColor = vec3<f32>(color.r * alphaR, color.g * alphaG, color.b * alphaB);
    let outCol = vec4<f32>(mix(finalColor, prev.rgb * 0.88, 0.2), mix(finalAlpha, prev.a * 0.88, 0.2));
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + iris * 0.06 + click * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
}
