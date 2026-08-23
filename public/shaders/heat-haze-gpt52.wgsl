// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage gpt52
//  Category: distortion
//  Features: atmospheric, mirage-refraction, thermal-source, audio-reactive,
//            upgraded-rgba, thermal-filaments, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
// ═══════════════════════════════════════════════════════════════════

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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    let a = hash(i);
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}
fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var q = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(q);
        q = rot * q * 2.02;
        a *= 0.5;
    }
    return v;
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x * 0.2;
    let texel = 1.0 / max(resolution, vec2<f32>(1.0));
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.3);
    let rise = clamp(u.zoom_params.y, 0.0, 1.0);
    let frequency = clamp(u.zoom_params.z, 0.0, 1.0);
    let chroma = clamp(u.zoom_params.w, 0.0, 1.0);
    let mouse = u.zoom_config.yz;
    let held = f32(u.zoom_config.w > 0.5);
    let dM = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let thermal = exp(-dM * dM * 6.0) * (0.5 + held * 0.5);
    let thermalCol = thermal * smoothstep(-0.1, 0.5, mouse.y - uv.y);

    let freq = mix(2.0, 8.0, frequency);
    let flow = vec2<f32>(0.0, -time * mix(0.2, 1.0, rise) * (1.0 + thermalCol * 1.2));
    let n1 = fbm(uv * freq * 2.0 + vec2<f32>(time * 0.3, -time * 0.2) + flow);
    let n2 = fbm(uv * freq * 4.0 + vec2<f32>(-time * 0.15, time * 0.25) + flow * 1.3);
    let n3 = fbm(uv * freq * 6.0 + vec2<f32>(time * 0.5, time * 0.1) + flow * 0.7);
    let haze = (vec2<f32>(n1 - 0.5, n2 - 0.5) + vec2<f32>(n2 - 0.5, n3 - 0.5)) * 0.04 * intensity * (1.0 + thermalCol * 1.5);
    let shimmer = smoothstep(0.6, 1.0, n3) * intensity * 0.18 * (1.0 + thermalCol);
    let grad_x = fbm(uv + vec2<f32>(texel.x, 0.0) * 3.0) - fbm(uv - vec2<f32>(texel.x, 0.0) * 3.0);
    let grad_y = fbm(uv + vec2<f32>(0.0, texel.y) * 3.0) - fbm(uv - vec2<f32>(0.0, texel.y) * 3.0);
    let curl = vec2<f32>(-grad_y, grad_x) * 0.025 * intensity;
    let warp = haze + curl + vec2<f32>(0.0, sin((uv.x + time) * 6.28318) * 0.0025 * intensity);
    let dispersion = warp * (0.6 + chroma) * 0.5;

    let sampleR = clamp(uv + warp + dispersion, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleG = clamp(uv + warp, vec2<f32>(0.0), vec2<f32>(1.0));
    let sampleB = clamp(uv + warp - dispersion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, sampleR, 0.0).r * exp(-0.4 * length(dispersion) * 2.0),
        textureSampleLevel(readTexture, u_sampler, sampleG, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, sampleB, 0.0).b * exp(-0.6 * length(dispersion) * 2.0)
    );

    let filaments = smoothstep(0.08, 0.0, abs(fract(uv.x * 18.0 + n1 * 2.0 - time * (1.4 + rise * 2.0)) - 0.5));
    let packets = smoothstep(0.08, 0.0, abs(fract((1.0 - uv.y) * 10.0 - time * (2.1 + bass * 1.8) + n2) - 0.5));
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = u.config.x - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 60.0) * (1.0 - age / 1.5));
        }
    }

    let slick = hsv2rgb(vec3<f32>(fract(0.05 + n3 * 0.25 + mids * 0.2 + time * 0.15), 0.7, 1.0));
    color += vec3<f32>(0.05, 0.02, 0.01) * shimmer;
    color += vec3<f32>(0.18, 0.08, 0.02) * thermalCol * shimmer * 1.5;
    color = mix(color, color * slick * 1.25, 0.18 + treble * 0.2);
    color += slick * (filaments * 0.22 + packets * 0.24 + click * 0.5);

    let warp_mag = clamp(length(warp) * 20.0, 0.0, 1.0);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + warp_mag * 0.35 + shimmer * 0.5 + thermalCol * 0.2 + luma * 0.1 + mids * 0.1, 0.0, 1.0);
    let outCol = vec4<f32>(mix(color, prev.rgb * 0.88, 0.22), mix(alpha, prev.a * 0.88, 0.22));
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + filaments * 0.05 + click * 0.06, 0.0, 1.0), 0.0, 0.0, 0.0));
}
