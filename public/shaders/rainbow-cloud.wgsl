// ────────────────────────────────────────────────────────────────────────────────
//  Rainbow Cloud - Psychedelic Sky Shader
//  Turns any image/video into swirling, rainbow-coloured clouds with fbm density,
//  HDR bursts, negative color voids, and curl-field feedback trails.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ────────────────────────────────────────────────────────────────────────────────

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=densityPower, y=saturation, z=octaves, w=depthInf
  zoom_params: vec4<f32>,       // x=cloudScale, y=twistSpeed, z=feedbackStep, w=persistence
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  2-D hash (returns a pseudo-random float in [0,1])
// ───────────────────────────────────────────────────────────────────────────────
fn hash(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2-D value noise (smoothstep interpolation)
// ───────────────────────────────────────────────────────────────────────────────
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    // Four corners
    let a = hash(i + vec2<f32>(0.0, 0.0));
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));
    // Smooth interpolation
    let uv = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, uv.x), mix(c, d, uv.x), uv.y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Fractal Brownian Motion
// ───────────────────────────────────────────────────────────────────────────────
fn fbm(p: vec2<f32>, octaves: i32, persistence: f32) -> f32 {
    var sum: f32 = 0.0;
    var amp: f32 = 1.0;
    var freq: f32 = 1.0;
    var totalAmp: f32 = 0.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * noise(p * freq);
        totalAmp = totalAmp + amp;
        freq = freq * 2.0;
        amp = amp * persistence;
    }
    return sum / totalAmp;
}

// ───────────────────────────────────────────────────────────────────────────────
//  HSV → RGB (both in [0,1])
// ───────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    let p = abs(fract(vec3<f32>(hsv.x, hsv.x, hsv.x) + K.xyz) * 6.0 - K.www);
    return hsv.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Compute luminance gradient for curl field
// ───────────────────────────────────────────────────────────────────────────────
fn computeCurl(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let Lu = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    let Ld = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let Ll = textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let Lr = textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let grad = vec2<f32>(Lr - Ll, Ld - Lu);
    return vec2<f32>(-grad.y, grad.x);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ───────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ──────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ──────────────────────────────────────────────────────────────────────────
    let cloudScale = u.zoom_params.x * 4.0 + 1.0;           // 1 - 5
    let twistSpeed = u.zoom_params.y * 0.5;                  // 0 - 0.5
    let feedbackStep = u.zoom_params.z * 0.03;               // 0 - 0.03
    let persistence = u.zoom_params.w * 0.4 + 0.3;          // 0.3 - 0.7
    let densityPower = u.zoom_config.x * 1.5 + 1.0;         // 1 - 2.5
    let saturation = u.zoom_config.y * 0.3 + 0.7;           // 0.7 - 1.0
    let octaves = i32(u.zoom_config.z * 4.0 + 3.0);         // 3 - 7
    let depthInf = u.zoom_config.w;                          // 0 - 1

    // Sample inputs
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0);
    let lum = max(max(src.r, src.g), src.b);

    // ──────────────────────────────────────────────────────────────────────────
    //  Build cloud density using fbm
    // ──────────────────────────────────────────────────────────────────────────
    let cloudPos = uv * cloudScale + vec2<f32>(time * 0.1, time * 0.07);
    var density = fbm(cloudPos, octaves, persistence);
    
    // Sharpen clouds with power function
    density = pow(density, densityPower);
    
    // Depth influence - farther = more cloud
    density = density * (1.0 + (1.0 - depth) * depthInf * 0.5);

    // ──────────────────────────────────────────────────────────────────────────
    //  Map density → rainbow hue
    // ──────────────────────────────────────────────────────────────────────────
    let hueBase = fract(density + time * twistSpeed);
    let sat = saturation;
    let val = mix(0.2, 1.2, density); // allow values >1 for HDR bursts

    let cloudRGB = hsv2rgb(vec3<f32>(hueBase, sat, val));

    // ──────────────────────────────────────────────────────────────────────────
    //  Energy injection for very bright source pixels
    // ──────────────────────────────────────────────────────────────────────────
    var extra = vec3<f32>(0.0);
    if (lum > 1.0) {
        let curl = computeCurl(uv, texel);
        let burstHue = fract(atan2(curl.y, curl.x) / (2.0 * 3.14159265));
        extra = hsv2rgb(vec3<f32>(burstHue, 1.0, (lum - 1.0) * 2.0)) * 0.4;
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  Colour-debt (negative channels) for very dark regions
    // ──────────────────────────────────────────────────────────────────────────
    var finalRGB = cloudRGB + extra;
    if (lum < 0.2) {
        finalRGB = -finalRGB; // creates ghost-like voids
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  Feedback warp – drag previous colour along a curl-field
    // ──────────────────────────────────────────────────────────────────────────
    let curl = computeCurl(uv, texel);
    let warpedUV = clamp(uv + curl * feedbackStep, vec2<f32>(0.0), vec2<f32>(1.0));
    let prevCol = textureSampleLevel(feedbackTex, videoSampler, warpedUV, 0.0).rgb;

    // ──────────────────────────────────────────────────────────────────────────
    //  Temporal blend (persistence creates silky trails)
    // ──────────────────────────────────────────────────────────────────────────
    let temporalBlend = 0.7 + persistence * 0.25; // Use persistence param (0.7 - 0.95)
    let outCol = prevCol * temporalBlend + finalRGB * (1.0 - temporalBlend);

    // ──────────────────────────────────────────────────────────────────────────
    //  Output
    // ──────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(feedbackOut, gid.xy, vec4<f32>(outCol, 1.0));
}
