// ═══════════════════════════════════════════════════════════════════
//  Hybrid Magnetic Field + Audio Reactive
//  Category: generative
//  Features: hybrid, vector-field, particle-trails, magnetic-distortion, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10
//  Ideas: opposite-polarity second pole; exact-C LIC along fieldDir
//  A packing: display RGB in A; ACES on writeTexture
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
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn magneticField(pos: vec2<f32>, dipolePos: vec2<f32>, strength: f32) -> vec2<f32> {
    let r = pos - dipolePos;
    let dist = length(r);
    let dist3 = dist * dist * dist + 0.001;
    let radial = r / max(dist, 0.001);
    let field = radial * strength / dist3;
    return vec2<f32>(-field.y, field.x);
}

fn historyCoord(uv: vec2<f32>, dimsI: vec2<i32>) -> vec2<i32> {
    return clamp(vec2<i32>(uv * vec2<f32>(dimsI)), vec2<i32>(0), dimsI - vec2<i32>(1));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let dimsI = vec2<i32>(resolution);

    let audioBass = plasmaBuffer[0].x;
    let audioMids = plasmaBuffer[0].y;
    let audioTreble = plasmaBuffer[0].z;
    let audioPulse = 1.0 + audioBass * 0.5;

    let fieldStrength = mix(0.5, 3.0, u.zoom_params.x) * audioPulse;
    let lineDensity = mix(5.0, 30.0, u.zoom_params.y) * (1.0 + audioMids * 0.3);
    let trailPersistence = u.zoom_params.z * 0.95;
    let noiseInfluence = u.zoom_params.w * 2.0 * (1.0 + audioTreble * 0.4);

    var mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    mouse.x *= aspect;
    var p = uv;
    p.x *= aspect;

    let source1 = vec2<f32>(mouse.x, mouse.y);
    let source2 = vec2<f32>(0.5 * aspect + sin(time * 0.5) * 0.2, 0.5 + cos(time * 0.3) * 0.2);

    var field = vec2<f32>(0.0);
    field += magneticField(p, source1, fieldStrength);
    field += magneticField(p, source2, -fieldStrength * 0.5);

    let noiseField = vec2<f32>(
        fbm2(uv * 5.0 + time * 0.1, 4),
        fbm2(uv * 5.0 + vec2<f32>(5.2, 1.3), 4)
    ) * noiseInfluence;
    field += noiseField;

    let fieldMag = length(field);
    let fieldDir = field / (fieldMag + 0.001);

    let fieldAngle = atan2(fieldDir.y, fieldDir.x);
    let linePattern = sin(fieldAngle * lineDensity + fieldMag * 10.0);
    let isFieldLine = smoothstep(0.8, 1.0, linePattern);

    let flowUV = clamp(uv + fieldDir * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let lic1UV = clamp(uv + fieldDir * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let lic2UV = clamp(uv - fieldDir * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    let prevFrame = (
        textureLoad(dataTextureC, historyCoord(flowUV, dimsI), 0).rgb
        + textureLoad(dataTextureC, historyCoord(lic1UV, dimsI), 0).rgb
        + textureLoad(dataTextureC, historyCoord(lic2UV, dimsI), 0).rgb
    ) / 3.0;

    let fieldColor = palette(fieldAngle * 0.5 + time * 0.1,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.8, 0.9, 0.3)
    );
    let audioTint = vec3<f32>(audioBass * 0.3, audioMids * 0.15, audioTreble * 0.1);

    var color = prevFrame * trailPersistence;
    color += (fieldColor + audioTint) * isFieldLine * (0.5 + fieldMag * 0.3);

    let dist1 = length(p - source1);
    let dist2 = length(p - source2);
    let glowAmt = exp(-dist1 * 3.0) + exp(-dist2 * 3.0) * 0.5;
    color += vec3<f32>(1.0, 0.8, 0.3) * glowAmt * 0.5 * audioPulse;
    color += vec3<f32>(0.35, 0.55, 1.0) * exp(-dist2 * 3.0) * 0.25;

    let vortex = sin(atan2(p.y - source1.y, p.x - source1.x) * 10.0 + dist1 * 20.0);
    color += vec3<f32>(0.3, 0.6, 1.0) * vortex * exp(-dist1 * 2.0) * 0.3 * (1.0 + audioBass * 0.3);

    let isBeat = step(0.7, audioBass);
    color += vec3<f32>(0.1, 0.08, 0.05) * isBeat * glowAmt;

    let alpha = mix(0.4, 1.0, isFieldLine + glowAmt * 0.5);

    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(acesToneMap(color), alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(fieldMag * 0.5, 0.0, 0.0, 0.0));
}
