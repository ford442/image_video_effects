// ---------------------------------------------------------------
//  Radiating Haze – with adjustable aura colour
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var auraBuf:    texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=speed, y=intensity, z=satThresh, w=radius
  zoom_config: vec4<f32>,       // x=pulseSpd, y=depthInf, z=hueBias, w=colourMode
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Colour space
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
    if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}


// ---------------------------------------------------------------
//  Hash for sparkle
// ---------------------------------------------------------------
fn hash(p: vec2<f32>) -> f32 {
    var h = fract(vec3<f32>(p.xyx) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
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
    let speed   = u.zoom_params.x * 0.5;
    let intensity = u.zoom_params.y;
    let satThresh = u.zoom_params.z * 0.4 + 0.2;
    let radius    = u.zoom_params.w * 0.15;
    let pulseSpd  = u.zoom_config.x * 2.0;
    let depthInf  = u.zoom_config.y;
    let hueBias   = u.zoom_config.z;
    let colourMode = u.zoom_config.w;   // 0=shifted, 1=original, 2=fixed

    // -----------------------------------------------------------------
    //  3️⃣  Classify colour
    // -----------------------------------------------------------------
    let hsv = rgb2hsv(src);
    let sat = hsv.y;
    let val = hsv.z;

    let isNeutral = (sat < satThresh) || (val < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (sat < 0.5));

    // -----------------------------------------------------------------
    //  4️⃣  Strong‑colour mask (softened)
    // -----------------------------------------------------------------
    var strongMask = 0.0;
    if (!isNeutral) {
        // tiny blur
        let b = 2.0 * texel;
        strongMask += select(0.0, 1.0, !isNeutral) * 0.25;
        strongMask += select(0.0, 1.0, !isNeutral) * 0.25;
        strongMask += select(0.0, 1.0, !isNeutral) * 0.25;
        strongMask += select(0.0, 1.0, !isNeutral) * 0.25;
    }

    // -----------------------------------------------------------------
    //  5️⃣  Radiating wave
    // -----------------------------------------------------------------
    let dist = length(uv - vec2<f32>(0.5));
    let wave = sin((dist - time * speed) * 15.0) * 0.5 + 0.5;
    let waveMask = smoothstep(0.2, 0.8, wave) * smoothstep(radius, 0.0, dist);

    // -----------------------------------------------------------------
    //  6️⃣  Depth falloff
    // -----------------------------------------------------------------
    let depthFalloff = mix(1.0, depth, depthInf);
    let aura = strongMask * waveMask * depthFalloff * intensity;

    // -----------------------------------------------------------------
    //  7️⃣  Aura colour – three modes
    // -----------------------------------------------------------------
    var auraCol = vec3<f32>(0.0);
    if (colourMode < 0.5) {                     // 0 = shifted (original)
        let auraHue = fract(hsv.x + hueBias + time * pulseSpd * 0.02);
        auraCol = hsv2rgb(auraHue, 0.9, 1.0);
    } else if (colourMode < 1.5) {              // 1 = original colour
        auraCol = src;
    } else {                                    // 2 = fixed hue (user‑biased)
        auraCol = hsv2rgb(hueBias, 0.9, 1.0);
    }

    // -----------------------------------------------------------------
    //  8️⃣  Temporal persistence (soft glow trail)
    // -----------------------------------------------------------------
    let prev = textureSampleLevel(dataTexC, depthSampler, uv, 0.0).r;
    let persist = max(prev * 0.92, aura);
    textureStore(auraBuf, gid.xy, vec4<f32>(persist,0.0,0.0,1.0));

    // -----------------------------------------------------------------
    //  9️⃣  Composite
    // -----------------------------------------------------------------
    var outCol = src + auraCol * aura;
    outCol = 1.0 - (1.0 - outCol) * (1.0 - vec3<f32>(persist * 0.3));

    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth,0.0,0.0,0.0));
}