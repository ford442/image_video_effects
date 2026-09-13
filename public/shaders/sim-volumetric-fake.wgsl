// ═══════════════════════════════════════════════════════════════════
//  Sim: Volumetric Fake (Fast God Rays)
//  Category: lighting-effects
//  Features: simulation, fake-volumetrics, radial-blur, god-rays, upgraded-rgba, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-09-11
//  Ideas: depth occlusion vs the light; discrete dust motes on radial taps
//  A packing: ACES display RGBA
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    let lightIntensity = mix(0.5, 2.0, u.zoom_params.x);
    let dustDensity = mix(0.0, 1.0, u.zoom_params.y);
    let scattering = mix(0.3, 1.5, u.zoom_params.z);
    let noiseSpeed = mix(0.1, 1.0, u.zoom_params.w);

    let lightPos = vec2<f32>(
        0.5 + cos(time * 0.2) * 0.3,
        0.2 + sin(time * 0.15) * 0.1
    );

    let toLight = lightPos - uv;
    let distToLight = max(length(toLight), 0.001);
    let dirToLight = toLight / distToLight;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let lightDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(lightPos, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

    var volumetric = vec3<f32>(0.0);
    var motes = 0.0;
    let samples = i32(16.0 + dustDensity * 16.0);
    var occlusion = 0.0;

    for (var i = 0; i < 32; i++) {
        if (i >= samples) { break; }
        let t = f32(i) / f32(max(samples, 1));
        let samplePos = uv + dirToLight * t * distToLight;
        if (samplePos.x < 0.0 || samplePos.x > 1.0 || samplePos.y < 0.0 || samplePos.y > 1.0) {
            continue;
        }
        let sampleColor = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, samplePos, 0.0).r;
        let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
        // Idea 1: occluder closer to camera than the light blocks the shaft
        let blocked = step(lightDepth + 0.02, sampleDepth);
        occlusion += luma * (1.0 - t) * (1.0 - blocked);
        let attenuation = (1.0 - t) * (1.0 - t) * (1.0 - blocked);
        volumetric += vec3<f32>(1.0) * attenuation;
        // Idea 2: discrete motes on taps
        let mote = step(0.92, hash12(floor(samplePos * 80.0) + vec2<f32>(time * noiseSpeed, f32(i))));
        motes += mote * attenuation * dustDensity;
    }

    volumetric /= f32(max(samples, 1));
    occlusion = clamp(occlusion / f32(max(samples, 1)), 0.0, 1.0);
    motes /= f32(max(samples, 1));

    let dustNoise = noise(uv * 20.0 + time * noiseSpeed) * noise(uv * 15.0 - time * noiseSpeed * 0.5);
    let dust = pow(dustNoise, 3.0) * dustDensity;

    let density = 0.3 * scattering * (1.0 + bass * 0.3);
    var lightRays = volumetric * (1.0 - occlusion) * density * lightIntensity;
    lightRays += vec3<f32>(dust * lightIntensity * 0.5);
    lightRays += vec3<f32>(1.0, 0.97, 0.88) * motes * lightIntensity * 2.2;
    let sunColor = vec3<f32>(1.0, 0.95, 0.8);
    lightRays *= sunColor;

    var color = src.rgb + lightRays;
    let lightDir = normalize(vec2<f32>(0.5) - lightPos);
    let viewDir = normalize(uv - lightPos);
    let alignment = max(0.0, dot(viewDir, lightDir));
    color += sunColor * alignment * alignment * lightIntensity * 0.1;
    let falloff = 1.0 / (1.0 + distToLight * distToLight * 2.0);
    color = mix(src.rgb, color, falloff);

    let alpha = clamp(0.55 + length(lightRays) * 0.8 + treble * 0.1, 0.0, 1.0) * src.a;
    let display = vec4<f32>(aces(color), alpha);
    textureStore(writeTexture, gid.xy, display);
    textureStore(dataTextureA, gid.xy, display);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
