// ---------------------------------------------------------------
//  Radiating Displacement – waves emanate from strong colours only
//  Neutrals (browns, greys, blacks) are left untouched & sharp.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var persistBuf: texture_storage_2d<rgba32float, write>; // optional persistence
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=speed, y=displaceStrength, z=satThresh, w=radius
  zoom_config: vec4<f32>,       // x=pulseSpeed, y=depthInfluence, z=unused, w=unused
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Colour classification
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// ---------------------------------------------------------------
//  Wave generator – returns a vec2 displacement
// ---------------------------------------------------------------
fn waveDisplacement(uv: vec2<f32>, centre: vec2<f32>, time: f32,
                    speed: f32, strength: f32, radius: f32) -> vec2<f32> {
    let dist = length(uv - centre);
    // outward travelling wave
    let wave = sin((dist - time * speed) * 20.0) * 0.5 + 0.5;
    let mask = smoothstep(radius, 0.0, dist) * smoothstep(0.2, 0.8, wave);
    let dir = normalize(uv - centre);
    return dir * mask * strength * 0.02;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv  = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // -----------------------------------------------------------------
    //  1️⃣  Read source
    // -----------------------------------------------------------------
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // -----------------------------------------------------------------
    //  2️⃣  Uniforms
    // -----------------------------------------------------------------
    let speed      = u.zoom_params.x * 0.5;
    let strength   = u.zoom_params.y;
    let satThresh  = u.zoom_params.z * 0.4 + 0.2;
    let radius     = u.zoom_params.w * 0.15;
    let pulseSpd   = u.zoom_config.x * 2.0;
    let depthInf   = u.zoom_config.y;

    // -----------------------------------------------------------------
    //  3️⃣  Classify colour (strong vs neutral)
    // -----------------------------------------------------------------
    let hsv = rgb2hsv(src);
    let sat = hsv.y;
    let val = hsv.z;
    let isNeutral = (sat < satThresh) || (val < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (sat < 0.5));

    // -----------------------------------------------------------------
    //  4️⃣  Build displacement vector
    // -----------------------------------------------------------------
    var displacement = vec2<f32>(0.0);

    // --- a) Radiate from strong‑colour regions ---
    if (!isNeutral) {
        // Use the pixel itself as a wave centre
        displacement += waveDisplacement(uv, uv, time, speed, strength, radius);
    }

    // --- b) Mouse‑driven ripples (like the original) ---
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let d = length(uv - ripple.xy);
            if (d > 0.0001) {
                let rippleDepth = textureSampleLevel(depthTex, depthSampler, ripple.xy, 0.0).r;
                let depthFactor = 1.0 - rippleDepth;
                let rippleSpeed = mix(1.0, 2.0, depthFactor);
                let rippleAmp   = mix(0.005, 0.015, depthFactor);
                let wave = sin(d * 25.0 - age * rippleSpeed);
                let falloff = 1.0 / (d * 20.0 + 1.0);
                let atten = 1.0 - smoothstep(0.0, 3.0, age);
                displacement += (uv - ripple.xy) / d * wave * rippleAmp * falloff * atten;
            }
        }
    }

    // --- c) Depth‑aware ambient drift (subtle background motion) ---
    let bgFactor = 1.0 - smoothstep(0.0, 0.1, depth);
    if (bgFactor > 0.0) {
        let ambient = vec2<f32>(
            sin(uv.y * 15.0 + time * 1.2),
            cos(uv.x * 15.0 + time)
        ) * 0.004 * bgFactor;
        displacement += ambient;
    }

    // -----------------------------------------------------------------
    //  5️⃣  Apply displacement (only where colour is strong)
    // -----------------------------------------------------------------
    var finalUV = uv;
    if (!isNeutral) {
        finalUV += displacement;
    }

    // -----------------------------------------------------------------
    //  6️⃣  Sample & output (image stays sharp – no blur/haze overlay)
    // -----------------------------------------------------------------
    let outCol = textureSampleLevel(videoTex, videoSampler, finalUV, 0.0).rgb;
    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));

    // Depth is also displaced for consistency
    let outD = textureSampleLevel(depthTex, depthSampler, uv + displacement, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(outD, 0.0, 0.0, 0.0));
}
