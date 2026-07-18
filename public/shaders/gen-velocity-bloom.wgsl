// ═══ Velocity Bloom ═══════════════════════════════════════════════
//  Category: generative
//  Features: temporal, velocity-based, multi-octave bloom, anamorphic-streak,
//            audio-reactive, bass-envelope, color-temperature, treble-sparkle,
//            aces-tone-map, ign-dither, semantic-alpha
//  Chunks From: agents/WGSL_BUILTINS_GENERATIVE.md
//  Complexity: Medium

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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn velocityAt(uv: vec2<f32>, px: vec2<f32>, pixel: vec2<i32>) -> f32 {
    let cur = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    let diff = length(cur - prev);
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0).rgb;
    return diff + (length(right - left) + length(up - down)) * 0.5;
}

fn starBloom(uv: vec2<f32>, radius: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    var w = 0.0;
    for (var o: i32 = 0; o < 4; o++) {
        let fo = f32(o);
        let r = radius * (1.0 + fo * 0.5);
        let wt = 1.0 / (1.0 + fo * 0.5);
        for (var i: i32 = 0; i < 8; i++) {
            let a = f32(i) * TAU / 8.0;
            acc += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(cos(a), sin(a)) * r, 0.0).rgb * wt;
        }
        w += wt * 8.0;
    }
    return acc / w;
}

fn streakBloom(uv: vec2<f32>, radius: f32, velocity: f32) -> vec3<f32> {
    var acc = vec3<f32>(0.0);
    let stretch = 1.0 + velocity * 2.0;
    for (var i: i32 = 0; i < 16; i++) {
        let t = (f32(i) / 15.0 - 0.5) * 2.0;
        acc += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(t * radius * stretch, 0.0), 0.0).rgb;
    }
    return acc / 16.0;
}

fn velocityColor(velocity: f32, mids: f32) -> vec3<f32> {
    let warm = mix(vec3<f32>(1.0, 0.96, 0.88), vec3<f32>(1.0, 0.72, 0.42), mids * 0.6);
    let v = clamp(velocity, 0.0, 1.0);
    var c: vec3<f32>;
    if (v < 0.3) {
        c = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.8, 0.9, 1.0), v / 0.3);
    } else if (v < 0.6) {
        c = mix(vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(0.4, 0.7, 1.0), (v - 0.3) / 0.3);
    } else {
        c = mix(vec3<f32>(0.4, 0.7, 1.0), vec3<f32>(0.9, 0.4, 0.8), (v - 0.6) / 0.4);
    }
    return mix(c, warm, mids * 0.35 * v);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let px = 1.0 / res;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let prevEnv = extraBuffer[0];
    let bEnv = bass_env(prevEnv, bass, 0.2, 0.05);
    if (global_id.x == 0u && global_id.y == 0u) { extraBuffer[0] = bEnv; }

    let threshold = mix(0.0, 0.25, u.zoom_params.x);
    let bloomIntensity = mix(0.3, 2.2, u.zoom_params.y) * (1.0 + bEnv * 0.5 + bass * 0.25);
    let bloomRadius = mix(0.008, 0.045, u.zoom_params.z) * (1.0 + bEnv * 0.55);
    let decay = mix(0.75, 0.98, u.zoom_params.w);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let velocity = velocityAt(uv, px, pixel);
    let velocityMask = smoothstep(threshold, threshold + 0.18, velocity);

    var bloom = starBloom(uv, bloomRadius);
    let streak = streakBloom(uv, bloomRadius * 1.8, velocity);
    bloom = mix(bloom, streak, velocityMask * 0.5);

    let tint = velocityColor(velocity, mids);
    bloom = bloom * tint;

    let edge = smoothstep(0.35, 0.85, velocity) * treble;
    let sparkle = step(1.0 - edge * 0.22, ign(uv * 700.0 + time * 12.0)) * edge;
    bloom += vec3<f32>(sparkle);

    let prevBloom = textureLoad(dataTextureC, pixel, 0).rgb;
    let accumulatedBloom = max(bloom * bloomIntensity, prevBloom * decay * 0.92);

    let screenBlend = 1.0 - (1.0 - baseColor) * (1.0 - accumulatedBloom);
    let addBlend = baseColor + accumulatedBloom * velocityMask;
    var color = mix(screenBlend, addBlend, velocityMask * 0.5);
    color = color * (1.0 + velocity * bEnv * 0.25);

    color = acesToneMap(color * (0.95 + mids * 0.15));
    let dither = (ign(vec2<f32>(pixel) + time * 80.0) - 0.5) / 255.0;
    color = color + vec3<f32>(dither);

    let alpha = clamp(luma(accumulatedBloom) * 1.2 + velocityMask * 0.25, 0.2, 0.95);
    textureStore(dataTextureA, pixel, vec4<f32>(accumulatedBloom, alpha));
    textureStore(writeTexture, pixel, vec4<f32>(color * alpha, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}