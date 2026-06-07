// ═══════════════════════════════════════════════════════════════════
//  Kaleido Scope v2
//  Category: geometric
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Chunks From: kaleido-scope
//  Upgraded: 2026-05-30
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
    return fract(vec2<f32>(n) * vec2<f32>(43758.5453, 22578.1459));
}

fn lensDistort(p: vec2<f32>, strength: f32) -> vec2<f32> {
    let r2 = dot(p, p);
    return p * (1.0 + strength * r2 + strength * r2 * r2 * 0.5);
}

fn poincareMap(p: vec2<f32>, segments: f32, rot: f32) -> vec3<f32> {
    let r = length(p);
    let theta = atan2(p.y, p.x) + rot;
    let hypR = r / (1.0 - min(r * 0.94, 0.99) + 0.001);
    let sector = abs(fract(theta / 6.28318 * segments) - 0.5) * 2.0;
    let edgeDist = min(sector, 1.0 - sector);
    let mirrorAngle = sector * 3.14159265;
    return vec3<f32>(mirrorAngle, hypR, edgeDist);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let morphSpeed = max(u.zoom_params.y, 0.01);
    let zoom = max(u.zoom_params.z, 0.15);
    let ringOffset = u.zoom_params.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let warpStrength = length(mouse - 0.5) * 0.2;
    let warpDir = normalize((mouse - 0.5) + vec2<f32>(0.001, 0.001));
    let center = vec2<f32>(0.5, 0.5) + (mouse - 0.5) * 0.12 + warpDir * warpStrength * 0.06;

    var p = (uv - center) * vec2<f32>(aspect, 1.0);
    p = lensDistort(p, warpStrength * 0.3);

    let r = length(p);
    let morph = sin(time * morphSpeed * (1.0 + bass * 0.6)) * 0.5 + 0.5;
    let tessA = mix(4.0, 7.0, u.zoom_params.x);
    let tessB = mix(6.0, 11.0, u.zoom_params.x);
    let segments = mix(tessA, tessB, morph);
    let rotation = time * morphSpeed * 0.25 * (1.0 + treble * 0.4);

    let pm = poincareMap(p / zoom, segments, rotation);
    let mirrorAngle = pm.x;
    let hypR = pm.y;
    let edgeDist = pm.z;
    let sector = fract(mirrorAngle / 3.14159265);

    let mirrored = vec2<f32>(cos(mirrorAngle), sin(mirrorAngle)) * hypR;
    let sampleUV = clamp(center + vec2<f32>(mirrored.x / aspect, mirrored.y), vec2<f32>(0.001), vec2<f32>(0.999));

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r, 0.0, 1.0);
    let sep = (0.004 + depth * 0.014) * (1.0 + mids * 0.5);
    let caR = clamp(center + vec2<f32>((mirrored.x + sep) / aspect, mirrored.y + sep * 0.3), vec2<f32>(0.001), vec2<f32>(0.999));
    let caB = clamp(center + vec2<f32>((mirrored.x - sep) / aspect, mirrored.y - sep * 0.3), vec2<f32>(0.001), vec2<f32>(0.999));

    let baseR = textureSampleLevel(readTexture, u_sampler, caR, 0.0).r;
    let baseG = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let baseB = textureSampleLevel(readTexture, u_sampler, caB, 0.0).b;
    var baseColor = vec3<f32>(baseR, baseG, baseB);

    let boundary = smoothstep(0.05 / segments, 0.0, edgeDist);
    let hue = fract(sector * 1.618 + morph * 0.3 + depth * 0.2 + time * 0.05);
    let irid = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * hue + 0.0),
        0.5 + 0.5 * cos(6.28318 * hue + 2.094),
        0.5 + 0.5 * cos(6.28318 * hue + 4.188)
    );
    let metal = mix(irid * 0.6, vec3<f32>(1.0, 0.92, 0.78), 0.4) * boundary * (0.4 + treble * 0.35);

    let ringPos = abs(hypR - (0.22 + ringOffset * 0.38 + bass * 0.1));
    let vertex = smoothstep(0.1, 0.0, ringPos) * boundary;
    let spec = vec3<f32>(1.0, 0.95, 0.85) * vertex * (0.6 + mids * 0.6);

    let caStrength = smoothstep(0.035, 0.0, edgeDist) * (0.12 + depth * 0.18);
    baseColor = mix(baseColor, baseColor * vec3<f32>(1.12, 0.96, 0.88), caStrength);

    let finalColor = acesToneMap(baseColor * (0.7 + sector * 0.14) + metal + spec);
    let alpha = clamp(boundary * 0.5 + depth * 0.25 + vertex * 0.18 + bass * 0.06, 0.1, 0.92);
    let outDepth = clamp(depth + boundary * 0.06 + vertex * 0.04, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(boundary, hypR, sector, alpha));
}
