// ═══════════════════════════════════════════════════════════════════
//  Superformula Spirograph Spiral
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, spirograph,
//            superformula, feedback-warp
//  Upgraded: 2026-05-23
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

const TAU: f32 = 6.283185307179586;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn superformula(phi: f32, m: f32, n1: f32, n2: f32, n3: f32) -> f32 {
    let t1 = pow(abs(cos(m * phi * 0.25)), n2);
    let t2 = pow(abs(sin(m * phi * 0.25)), n3);
    return pow(max(t1 + t2, 0.0001), -1.0 / max(n1, 0.0001));
}

fn spiroCenter(phi: f32, time: f32, speed: f32, intensity: f32, bass: f32) -> vec2<f32> {
    var center = vec2<f32>(0.0);
    var radius = mix(0.22, 0.36, intensity);
    for (var i: i32 = 0; i < 4; i = i + 1) {
        let harmonic = f32(i + 1);
        let a = phi * harmonic + time * speed * (0.9 + harmonic * 0.35) * (1.0 + bass * 0.25);
        center = center + vec2<f32>(cos(a), sin(a)) * radius;
        radius = radius * 0.52;
    }
    return center;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = mix(0.2, 1.35, u.zoom_params.x);
    let spinSpeed = mix(0.2, 2.8, u.zoom_params.y);
    let petalCount = mix(3.0, 12.0, u.zoom_params.z);
    let feedback = u.zoom_params.w;

    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv - 0.5;
    p.x = p.x * aspect;

    let mouseOffset = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
    p = p - mouseOffset * 0.55;

    let orbit = spiroCenter(atan2(p.y, p.x) + length(p) * 6.0, time, spinSpeed, intensity, bass);
    let q = p - orbit * mix(0.08, 0.22, intensity);
    let dist = length(q);
    let angle = atan2(q.y, q.x);

    let n1 = mix(0.25, 1.4, 0.5 + 0.5 * sin(time * 0.2 + mids * 2.0));
    let n2 = 1.2 + intensity * 4.5;
    let n3 = 1.0 + treble * 7.0;
    let superR = superformula(angle + time * spinSpeed * 0.18, petalCount + bass * 4.0, n1, n2, n3);
    let shapeRadius = superR * mix(0.12, 0.42, intensity);

    let band = smoothstep(0.08, 0.0, abs(dist - shapeRadius));
    let spokes = 0.5 + 0.5 * cos(angle * (petalCount * 2.0) - dist * 28.0 + time * spinSpeed * 4.0);
    let swirl = 0.5 + 0.5 * sin(length(p) * 24.0 - angle * (petalCount * 1.5) - time * spinSpeed * 3.0);
    let halo = smoothstep(0.35, 0.0, abs(dist - shapeRadius * 1.18));
    let pattern = band * (0.6 + 0.4 * spokes) + pow(swirl, 3.0) * 0.25 + halo * 0.18;

    let hue = fract(angle / TAU + time * 0.12 * spinSpeed + spokes * 0.18 + length(p) * 0.2 + mids * 0.1);
    let saturation = clamp(0.72 + treble * 0.18, 0.0, 1.0);
    let value = pattern * mix(0.85, 2.6, intensity);
    var color = hsv2rgb(vec3<f32>(hue, saturation, value));

    let rot = 0.015 + spinSpeed * 0.01;
    let c = cos(rot);
    let s = sin(rot);
    var historyP = vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
    historyP = historyP * (0.985 - feedback * 0.08);
    var historyUV = historyP;
    historyUV.x = historyUV.x / aspect;
    historyUV = historyUV + 0.5 + mouseOffset * 0.15;

    let prev = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let feedbackMix = mix(0.12, 0.78, feedback);
    color = mix(color, prev, feedbackMix * (0.42 + band * 0.28));

    let edgeFade = 1.0 - smoothstep(0.35, 0.82, length(p));
    let presence = clamp(pattern * edgeFade, 0.0, 1.0);
    let finalColor = mix(inputColor.rgb, color, presence * 0.9);
    let finalAlpha = max(inputColor.a, presence * 0.9);
    let finalDepth = mix(inputDepth, clamp(shapeRadius + halo * 0.25, 0.0, 1.0), presence * 0.85);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(color, presence));
}
