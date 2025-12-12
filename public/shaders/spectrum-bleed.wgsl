// ---------------------------------------------------------------
//  Spectrum Bleed – vibrant colors bleed outward like ink diffusion
//  Adjustable diffusion speed, hue drift, and saturation boost.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var bleedBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  bleed_params: vec4<f32>,      // x=diffusion, y=hueDrift, z=satBoost, w=unused
  bleed_config: vec4<f32>,      // reserved for future use
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Colour utilities
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ---------------------------------------------------------------
//  Simple Gaussian blur kernel (2x2) for diffusion
// ---------------------------------------------------------------
fn sampleBlur(uv: vec2<f32>, tex: texture_2d<f32>, sampler_: sampler) -> vec3<f32> {
    let texel = 1.0 / u.config.zw;
    var sum = vec3<f32>(0.0);
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb * 0.25;
    return sum;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // 1️⃣ Read source colour and depth
    let src = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // 2️⃣ Uniforms
    let diffusion = u.bleed_params.x;   // speed of colour spread
    let hueDrift  = u.bleed_params.y;   // how fast hue rotates
    let satBoost  = u.bleed_params.z;   // extra saturation for bleed

    // 3️⃣ Compute blurred colour (diffusion)
    var blurred = src;
    // Apply multiple blur passes based on diffusion amount
    let passes = u32(diffusion * 4.0 + 1.0);
    for (var i: u32 = 0u; i < passes; i = i + 1u) {
        blurred = sampleBlur(uv, videoTex, videoSampler);
    }

    // 4️⃣ Hue drift over time
    let hsv = rgb2hsv(blurred);
    let newHue = fract(hsv.x + hueDrift * time * 0.05);
    let drifted = hsv2rgb(newHue, hsv.y, hsv.z);

    // 5️⃣ Boost saturation for vivid bleed effect
    let finalCol = hsv2rgb(newHue, min(hsv.y + satBoost, 1.0), hsv.z);

    // 6️⃣ Blend original with bleed based on diffusion strength
    let blendFactor = diffusion * 0.6;
    var outCol = mix(src, finalCol, blendFactor);

    // 7️⃣ Temporal persistence (memory of previous frame)
    let prev = textureSampleLevel(dataTexC, depthSampler, uv, 0.0).rgb;
    let persist = max(prev * 0.93, outCol);
    textureStore(bleedBuf, gid.xy, vec4<f32>(persist, 1.0));
    outCol = max(outCol, persist * 0.2);

    // 8️⃣ Output colour and depth
    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
