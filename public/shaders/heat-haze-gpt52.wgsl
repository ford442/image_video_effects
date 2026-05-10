// ═══════════════════════════════════════════════════════════════════
//  Heat Haze Mirage gpt52
//  Category: distortion
//  Features: atmospheric, mirage-refraction, thermal-source, audio-reactive, fbm-rot
//  Complexity: Medium
//  Phase B / Algorithmist
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=Rise, z=Frequency, w=Chroma
  ripples: array<vec4<f32>, 50>,
};

const PI:  f32 = 3.14159265358979323846;
const PHI: f32 = 1.61803398874989484820;

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

// 4-octave FBM with golden-angle rotation between octaves (avoids axis bias)
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coords = vec2<i32>(global_id.xy);

    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(1.0));
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x * 0.2;
    let texel = 1.0 / max(resolution, vec2<f32>(1.0));
    let bass = plasmaBuffer[0].x;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0) * (1.0 + bass * 0.3);
    let rise      = clamp(u.zoom_params.y, 0.0, 1.0);
    let frequency = clamp(u.zoom_params.z, 0.0, 1.0);
    let chroma    = clamp(u.zoom_params.w, 0.0, 1.0);

    // Mouse acts as thermal source — heat fountain in front of it (Beer-Lambert falloff)
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let dM = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let thermal = exp(-dM * dM * 6.0) * (0.5 + mouseDown * 0.5);
    // Heat rises — apply upward stretch in thermal field by warping query coords
    let thermalRise = (mouse.y - uv.y);                    // positive when uv above mouse
    let thermalCol = thermal * smoothstep(-0.1, 0.5, thermalRise);

    let freq = mix(2.0, 8.0, frequency);
    let flow = vec2<f32>(0.0, -time * mix(0.2, 1.0, rise) * (1.0 + thermalCol * 1.2));

    // Two-octave FBM with rotation; thermal column biases the lookup
    let n1 = fbm(uv * freq * 2.0 + vec2<f32>(time * 0.3, -time * 0.2) + flow);
    let n2 = fbm(uv * freq * 4.0 + vec2<f32>(-time * 0.15, time * 0.25) + flow * 1.3);
    let n3 = fbm(uv * freq * 6.0 + vec2<f32>(time * 0.5,  time * 0.1)  + flow * 0.7);

    // Mirage refraction (Snell-like): warp = curl of noise gradient
    let haze = (vec2<f32>(n1 - 0.5, n2 - 0.5) + vec2<f32>(n2 - 0.5, n3 - 0.5))
             * 0.04 * intensity * (1.0 + thermalCol * 1.5);
    let shimmer = smoothstep(0.6, 1.0, n3) * intensity * 0.18 * (1.0 + thermalCol);
    let grad_x = fbm(uv + vec2<f32>(texel.x, 0.0) * 3.0) - fbm(uv - vec2<f32>(texel.x, 0.0) * 3.0);
    let grad_y = fbm(uv + vec2<f32>(0.0, texel.y) * 3.0) - fbm(uv - vec2<f32>(0.0, texel.y) * 3.0);
    let curl = vec2<f32>(-grad_y, grad_x) * 0.025 * intensity;     // divergence-free
    let warp = haze + curl + vec2<f32>(0.0, sin((uv.x + time) * 6.28318) * 0.0025 * intensity);
    let dispersion = warp * (0.6 + chroma) * 0.5;

    // Beer-Lambert atmospheric absorption: warmer haze tints further-traveled chroma
    let attenR = exp(-0.4 * length(dispersion) * 2.0);
    let attenB = exp(-0.6 * length(dispersion) * 2.0);

    let r = textureSampleLevel(readTexture, u_sampler, uv + warp + dispersion, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + warp, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + warp - dispersion, 0.0).b;
    var color = vec3<f32>(r * attenR, g, b * attenB);

    // Hot-source warm shimmer near mouse + base shimmer
    color += vec3<f32>(0.05, 0.02, 0.01) * shimmer;
    color += vec3<f32>(0.18, 0.08, 0.02) * thermalCol * shimmer * 1.5;

    let warp_mag = clamp(length(warp) * 20.0, 0.0, 1.0);
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.4 + warp_mag * 0.35 + shimmer * 0.5 + thermalCol * 0.2 + luma * 0.1, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(color, alpha));

    // Persist temperature field for future passes (R=temp, G=warpMag)
    textureStore(dataTextureA, coords, vec4<f32>(thermalCol, warp_mag, 0.0, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
