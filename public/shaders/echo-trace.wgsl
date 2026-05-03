// ═══════════════════════════════════════════════════════════════════
//  Structure Tensor Echo Field
//  Category: artistic
//  Features: mouse-driven, temporal-persistence, audio-reactive,
//            structure-tensor, flow-advection, multi-octave-echo,
//            velocity-sensing, feedback-displacement, curl-noise
//  Complexity: High
//  Upgraded by: Interactivist Agent
//  Date: 2026-05-03
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 32>,
};

fn hash12(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn curlNoise(uv: vec2<f32>, eps: f32) -> vec2<f32> {
    let n = valueNoise2D(uv);
    let nx = valueNoise2D(uv + vec2<f32>(eps, 0.0));
    let ny = valueNoise2D(uv + vec2<f32>(0.0, eps));
    return vec2<f32>((ny - n) / eps, -(nx - n) / eps);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0; var a = 0.5;
    var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pos = p;
    for(var i: i32 = 0; i < octaves; i = i + 1) {
        v = v + a * valueNoise2D(pos);
        pos = rot * pos * 2.0 + 100.0;
        a = a * 0.5;
    }
    return v;
}

fn hueShift(color: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cos_angle = cos(shift);
    return vec3<f32>(color * cos_angle + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cos_angle));
}

fn structureTensor(uv: vec2<f32>, tex: texture_2d<f32>, samp: sampler, px: vec2<f32>) -> mat2x2<f32> {
    let l = textureSampleLevel(tex, samp, uv + vec2<f32>(-px.x, 0.0), 0.0).rgb;
    let r = textureSampleLevel(tex, samp, uv + vec2<f32>( px.x, 0.0), 0.0).rgb;
    let t = textureSampleLevel(tex, samp, uv + vec2<f32>(0.0, -px.y), 0.0).rgb;
    let b = textureSampleLevel(tex, samp, uv + vec2<f32>(0.0,  px.y), 0.0).rgb;
    let dx = vec3<f32>(r - l) * 0.5;
    let dy = vec3<f32>(b - t) * 0.5;
    let gx = dot(dx, vec3<f32>(0.299, 0.587, 0.114));
    let gy = dot(dy, vec3<f32>(0.299, 0.587, 0.114));
    return mat2x2<f32>(gx * gx, gx * gy, gx * gy, gy * gy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }
    let uv = vec2<f32>(coords) / vec2<f32>(dimensions);
    let px = 1.0 / vec2<f32>(dimensions);
    let time = u.config.x;

    let decayBase = u.zoom_params.x * 0.5 + 0.4;
    let brushBase = u.zoom_params.y * 0.3;
    let shiftBase = u.zoom_params.z * 0.3;
    let flowStrength = u.zoom_params.w;

    let audioBass = plasmaBuffer[0].x;
    let audioMids = plasmaBuffer[0].y;
    let audioTreble = plasmaBuffer[0].z;
    let audioHueShift = audioMids * 0.4 + audioTreble * 0.2;
    let audioReactivity = 1.0 + audioBass * 2.0;

    let mousePos = u.zoom_config.yz;
    let aspect = u.config.z / u.config.w;
    let mouseVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);

    var mouseVel = vec2<f32>(0.0);
    let rippleCount = u32(u.config.y);
    if (rippleCount > 1u && rippleCount <= 32u) {
        let latest = u.ripples[rippleCount - 1u];
        let prev = u.ripples[rippleCount - 2u];
        let dt = max(time - prev.z, 0.016);
        mouseVel = (latest.xy - prev.xy) / dt;
    }
    let mouseSpeed = length(mouseVel);
    let brushSize = brushBase * (1.0 + mouseSpeed * 2.0);

    let st = structureTensor(uv, readTexture, u_sampler, px);
    let trace = st[0][0] + st[1][1];
    let eigenDir = vec2<f32>(st[0][0] - st[1][1] + 0.001, 2.0 * st[0][1]);
    let anisoDir = select(vec2<f32>(0.0), normalize(eigenDir), trace > 0.001);

    let flow = curlNoise(uv * 3.0 + time * 0.1, 0.01) * flowStrength * 0.02;
    let advectUV = uv + flow + anisoDir * trace * 0.008 * (1.0 + audioMids);

    let history = textureLoad(dataTextureC, coords, 0);

    let echo1 = textureSampleLevel(dataTextureC, filteringSampler, advectUV, 0.0);
    let echo2UV = advectUV + flow * 0.7 + vec2<f32>(sin(time * 0.3), cos(time * 0.2)) * 0.005 * audioReactivity;
    let echo2 = textureSampleLevel(dataTextureC, filteringSampler, echo2UV, 0.0);
    let echo3UV = advectUV - flow * 0.5 + vec2<f32>(cos(time * 0.4), sin(time * 0.5)) * 0.008;
    let echo3 = textureSampleLevel(dataTextureC, filteringSampler, echo3UV, 0.0);

    let currentVideo = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let videoLuma = dot(currentVideo.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let decay1 = decayBase;
    let decay2 = decayBase * 0.92;
    let decay3 = decayBase * 0.82;

    var acc = history.rgb * decay3;
    acc = mix(acc, echo1.rgb, (1.0 - decay1) * 0.45);
    acc = mix(acc, echo2.rgb, (1.0 - decay2) * 0.30);
    acc = mix(acc, echo3.rgb, (1.0 - decay3) * 0.20);

    let warpHue = shiftBase + audioHueShift + mouseSpeed * 0.1 + fbm(uv * 2.0 + time * 0.05, 3) * 0.05;
    acc = hueShift(acc, warpHue);

    let dist = length(mouseVec);
    let brushMask = smoothstep(brushSize, brushSize * 0.25, dist);
    acc = mix(acc, currentVideo.rgb, brushMask * (0.25 + audioBass * 0.35));

    let lumGrad = vec2<f32>(
        dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)) - videoLuma,
        dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114)) - videoLuma
    );
    let feedbackDisp = lumGrad * videoLuma * 0.04 * (1.0 + audioTreble);
    let dispUV = uv + feedbackDisp;
    let dispSample = textureSampleLevel(dataTextureC, filteringSampler, dispUV, 0.0);
    acc = mix(acc, dispSample.rgb, 0.15 + audioMids * 0.05);

    let outColor = vec4<f32>(acc, 1.0);

    textureStore(writeTexture, coords, outColor);
    textureStore(dataTextureA, coords, outColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(0.0));
}
