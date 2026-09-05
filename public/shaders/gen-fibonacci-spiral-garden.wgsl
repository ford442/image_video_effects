// Fibonacci Spiral Garden — audio-reactive phyllotaxis bloom
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
    zoom_params: vec4<f32>, // x=Spiral Scale, y=Growth Cycle, z=Petal Size, w=Bloom
    ripples: array<vec4<f32>, 50>,
};

const GOLDEN_ANGLE: f32 = 2.39996323;

fn palette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(6.28318 * (vec3<f32>(t) + vec3<f32>(0.04, 0.28, 0.58)));
}

fn hash11(x: f32) -> f32 {
    return fract(sin(x * 127.1) * 43758.5453);
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

    let spiralScale = mix(0.5, 1.55, clamp(u.zoom_params.x, 0.0, 1.0));
    let growthSpeed = mix(0.08, 0.7, clamp(u.zoom_params.y, 0.0, 1.0));
    let petalSize = mix(0.008, 0.045, clamp(u.zoom_params.z, 0.0, 1.0));
    let bloomStrength = mix(0.3, 2.4, clamp(u.zoom_params.w, 0.0, 1.0));

    let mouse = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let mouseDelta = p - mouse;
    p += normalize(mouseDelta + vec2<f32>(0.0001)) * exp(-dot(mouseDelta, mouseDelta) * 7.0) * held * 0.15;

    var flower = 0.0;
    var leaf = 0.0;
    var hueSum = 0.0;
    var nearDepth = 0.0;
    for (var i = 0; i < 96; i++) {
        let fi = f32(i);
        let normalizedIndex = (fi + 0.5) / 96.0;
        let unfurl = smoothstep(normalizedIndex - 0.16, normalizedIndex + 0.05,
                                fract(time * growthSpeed * 0.08 + 0.82) + 0.18);
        let radius = sqrt(normalizedIndex) * spiralScale * unfurl;
        let angle = fi * GOLDEN_ANGLE + time * growthSpeed * (0.16 + audio.y * 0.14);
        let node = vec2<f32>(cos(angle), sin(angle)) * radius;
        let q = p - node;
        let localAngle = atan2(q.y, q.x) - angle;
        let lobes = 0.72 + 0.28 * cos(localAngle * 5.0 + time * 0.6 + fi);
        let size = petalSize * (0.72 + 0.55 * hash11(fi)) * (1.0 + audio.x * 0.35);
        let petalDistance = length(q) - size * lobes;
        let petal = exp(-max(petalDistance, 0.0) * 115.0) * smoothstep(size * 1.8, -size * 0.2, petalDistance);
        let halo = exp(-abs(petalDistance) * 38.0) * 0.1;
        flower += petal;
        leaf += halo;
        hueSum += (petal + halo) * normalizedIndex;
        nearDepth = max(nearDepth, petal * (1.0 - normalizedIndex * 0.55));
    }

    var clickBloom = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.2) {
            let center = (ripple.xy * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);
            clickBloom += exp(-abs(distance(p, center) - age * 0.2) * 74.0) * exp(-age * 1.4);
        }
    }

    let hue = hueSum / max(flower + leaf, 0.001) + time * 0.018 + audio.y * 0.14;
    let background = vec3<f32>(0.008, 0.018, 0.012) + palette(length(p) * 0.1) * 0.015;
    var hdrColor = background + palette(hue) * flower * (0.65 + bloomStrength + audio.x * 0.7);
    hdrColor += palette(hue + 0.3) * leaf * bloomStrength * (0.5 + audio.z);
    hdrColor += vec3<f32>(0.45, 0.85 + audio.y * 0.3, 0.3 + audio.z * 0.5) * clickBloom * 0.42;
    let history = textureLoad(dataTextureC, coord, 0);
    hdrColor = clamp(mix(hdrColor, history.rgb, 0.045 + audio.x * 0.06), vec3<f32>(0.0), vec3<f32>(7.0));
    let mapped = acesToneMap(hdrColor * 1.06);
    let alpha = clamp(flower * 0.48 + leaf * 0.15 + clickBloom * 0.12, 0.02, 0.98);
    let depth = clamp(nearDepth * 0.8 + flower * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(hdrColor, alpha));
}
