// ═══════════════════════════════════════════════════════════════════
//  Mouse Pixel Sort
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba, multi-layer-sort, fbm-patterns, noise-warping
//  Complexity: High
//  Chunks From: mouse-pixel-sort
//  Upgraded: 2026-06-28
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn get_luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn hash12(p: vec2<f32>) -> f32 {
    let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
    return fract(h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let h = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453;
    return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var total = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        total = total + amplitude * noise2(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.1;
    }
    return total;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0) + time * 0.1, 5);
    let n2 = fbm(p + vec2<f32>(-eps, 0.0) + time * 0.1, 5);
    let n3 = fbm(p + vec2<f32>(0.0, eps) + time * 0.1, 5);
    let n4 = fbm(p + vec2<f32>(0.0, -eps) + time * 0.1, 5);
    let dx = (n1 - n2) / (2.0 * eps);
    let dy = (n3 - n4) / (2.0 * eps);
    return vec2<f32>(dy, -dx);
}

fn voronoiF2F1(p: vec2<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var minDist1 = 100.0;
    var minDist2 = 100.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash22(n + g);
            let r = g + o - f;
            let d = dot(r, r);
            if (d < minDist1) {
                minDist2 = minDist1;
                minDist1 = d;
            } else if (d < minDist2) {
                minDist2 = d;
            }
        }
    }
    return vec2<f32>(sqrt(minDist1), sqrt(minDist2));
}

fn strangeAttractor(uv: vec2<f32>, time: f32, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    // De Jong strange attractor
    var p = uv * 3.0;
    p.x = sin(a * p.y) - cos(b * p.x) + time * 0.1;
    p.y = sin(c * p.x) - cos(d * p.y) + time * 0.08;
    return p * 0.3;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let isMouseDown = u.zoom_config.w;
    let aspect = resolution.x / resolution.y;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;
    let time = u.config.x;

    let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let sortThreshold = zp.x;
    let sortLength = zp.y * (0.2 + bass * 0.06);
    let direction = zp.z;
    let mode = zp.w;

    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let influence = smoothstep(0.35, 0.0, dist);
    var localThreshold = mix(sortThreshold, sortThreshold * 0.35, influence * (0.55 + isMouseDown * 0.45));

    // Multi-layer FBM noise for organic sorting threshold
    let noiseThreshold = fbm(uv * 6.0 + time * 0.15 + bass * 2.0, 6) * 0.3;
    let voro = voronoiF2F1(uv * 10.0 + time * 0.1);
    let cellPattern = (voro.y - voro.x) * 0.2;
    localThreshold = clamp(localThreshold + noiseThreshold * 0.15 + cellPattern * 0.1, 0.0, 1.0);

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(base.rgb);

    // Multi-layer sorting offsets
    var offset1 = 0.0;
    var offset2 = 0.0;
    if (luma > localThreshold) {
        offset1 = (luma - localThreshold) * sortLength;
        offset2 = (luma - localThreshold) * sortLength * 0.5 * (1.0 + fbm(uv * 8.0 + time * 0.2, 4));
    }
    if (mode > 0.5 && luma < (1.0 - localThreshold)) {
        offset1 = ((1.0 - localThreshold) - luma) * sortLength;
        offset2 = ((1.0 - localThreshold) - luma) * sortLength * 0.5 * (1.0 + fbm(uv * 8.0 + time * 0.2, 4));
    }

    // Curl-noise-driven sorting direction
    let curl = curlNoise(uv * 4.0, time * 0.3);
    let attractor = strangeAttractor(uv, time, 1.4, -2.3, 2.4, -2.1);
    let combinedWarp = curl * 0.02 + attractor * 0.01 * influence;

    // Audio-reactive jitter with FBM
    let audioJitter = vec2<f32>(
        sin(uv.y * 40.0 + time * (3.0 + treble * 8.0) + fbm(uv * 5.0, 4) * TAU),
        cos(uv.x * 36.0 + time * (2.5 + mids * 5.0) + fbm(uv * 7.0 + vec2<f32>(10.0), 4) * TAU)
    ) * 0.003 * influence;

    // Layer 1: Primary sort direction
    var sourceUV1 = uv + audioJitter + combinedWarp * influence;
    if (direction > 0.5) {
        sourceUV1.x -= offset1;
    } else {
        sourceUV1.y -= offset1;
    }
    sourceUV1 = clamp(sourceUV1, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    // Layer 2: Secondary offset with perpendicular direction
    var sourceUV2 = uv + audioJitter * 0.5;
    if (direction > 0.5) {
        sourceUV2.y -= offset2 * 0.5;
    } else {
        sourceUV2.x -= offset2 * 0.5;
    }
    sourceUV2 = clamp(sourceUV2, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let sorted1 = textureSampleLevel(readTexture, u_sampler, sourceUV1, 0.0);
    let sorted2 = textureSampleLevel(readTexture, u_sampler, sourceUV2, 0.0);

    // Blend multi-layer sorts
    let layerBlend = fbm(uv * 3.0 + time * 0.1, 5) * 0.5 + 0.5;
    let sorted = mix(sorted1, sorted2, layerBlend * influence * 0.5);

    // Trail tint with bass/mids/treble spectrum
    let trailTint1 = mix(
        vec3<f32>(0.1, 0.95, 1.0),
        vec3<f32>(1.0, 0.5 + treble * 0.2, 0.18),
        select(0.0, 1.0, mode > 0.5)
    );
    let trailTint2 = mix(
        vec3<f32>(0.95, 0.2, 1.0),
        vec3<f32>(0.18, 1.0, 0.5 + bass * 0.3),
        select(0.0, 1.0, mode > 0.5)
    );
    let trailTint = mix(trailTint1, trailTint2, mids);

    let streak = smoothstep(localThreshold, 1.0, luma);

    // Particle sparkle trails from treble
    let sparkleNoise = hash12(vec2<f32>(global_id.xy) + vec2<f32>(time * 15.0, time * 11.0));
    let sparkle = smoothstep(0.97, 1.0, sparkleNoise) * treble * influence * 2.0;

    var finalColor = sorted.rgb + trailTint * streak * influence * (0.15 + bass * 0.12) + vec3<f32>(sparkle);

    // FBM-based color grading
    let colorGrade = fbm(uv * 2.0 + time * 0.05, 4);
    finalColor = finalColor * (0.85 + colorGrade * 0.3);

    let totalOffset = offset1 + offset2 * 0.3;
    let alpha = clamp(sorted.a * 0.4 + totalOffset * 5.0 + influence * 0.12 + bass * 0.05 + sparkle * 0.5, 0.08, 1.0);
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sourceUV1, 0.0).r + totalOffset * 0.25, 0.0, 1.0);

    // Premultiplied alpha
    let premultColor = finalColor * alpha;
    let finalPixel = vec4<f32>(premultColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(totalOffset, influence, streak, alpha));
}
