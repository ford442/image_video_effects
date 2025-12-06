// ---------------------------------------------------------------
//  Chromatic Infection – strong colours spread like a living disease
//  Vibrant hues grow organic tendrils that infect neutral regions.
// ---------------------------------------------------------------
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var infectionBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:    texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTexC:     texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=spreadSpeed, y=intensity, z=satThresh, w=tendrilScale
  zoom_config: vec4<f32>,       // x=pulseSpeed, y=depthInfluence, z=hueShift, w=mutationRate
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
//  Organic noise for tendril growth
// ---------------------------------------------------------------
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
    return fract(n * 43758.5453);
}

fn voronoi(uv: vec2<f32>, scale: f32, time: f32) -> f32 {
    let p = uv * scale;
    let i = floor(p);
    let f = fract(p);
    
    var minDist = 1.0;
    for (var y: i32 = -1; y <= 1; y++) {
        for (var x: i32 = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellCenter = hash22(i + neighbor);
            // Animate cell centers for organic movement
            let animated = cellCenter + 0.3 * sin(time * 0.5 + cellCenter * 6.28);
            let diff = neighbor + animated - f;
            let dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    return minDist;
}

fn tendrilNoise(uv: vec2<f32>, time: f32, scale: f32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = scale;
    
    for (var i: i32 = 0; i < 4; i++) {
        value += amplitude * voronoi(uv, frequency, time);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
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
    let spreadSpeed   = u.zoom_params.x * 2.0;
    let intensity     = u.zoom_params.y;
    let satThresh     = u.zoom_params.z * 0.4 + 0.2;
    let tendrilScale  = u.zoom_params.w * 15.0 + 5.0;
    let pulseSpeed    = u.zoom_config.x * 3.0;
    let depthInf      = u.zoom_config.y;
    let hueShift      = u.zoom_config.z;
    let mutationRate  = u.zoom_config.w;

    // -----------------------------------------------------------------
    //  3️⃣  Classify this pixel
    // -----------------------------------------------------------------
    let hsv = rgb2hsv(src);
    let sat = hsv.y;
    let val = hsv.z;
    let isNeutral = (sat < satThresh) || (val < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (sat < 0.5));

    // -----------------------------------------------------------------
    //  4️⃣  Sample nearby pixels to find infection sources
    // -----------------------------------------------------------------
    var infectionColor = vec3<f32>(0.0);
    var infectionStrength = 0.0;
    
    let sampleRadius = 8;
    let sampleCount = 16;
    
    for (var i: i32 = 0; i < sampleCount; i++) {
        let angle = f32(i) / f32(sampleCount) * 6.28318;
        let radius = f32(sampleRadius) * texel.x;
        
        // Organic, irregular sampling pattern
        let noise = hash21(uv * 100.0 + f32(i));
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius * (0.5 + noise);
        
        let sampleUV = uv + offset;
        let sampleCol = textureSampleLevel(videoTex, videoSampler, sampleUV, 0.0).rgb;
        let sampleHSV = rgb2hsv(sampleCol);
        
        // Check if sample is a strong color (infection source)
        let sampleSat = sampleHSV.y;
        let sampleVal = sampleHSV.z;
        let isSaturated = (sampleSat > satThresh) && (sampleVal > 0.2);
        
        if (isSaturated) {
            let dist = length(offset);
            let falloff = 1.0 - smoothstep(0.0, radius, dist);
            infectionStrength += falloff * sampleSat;
            infectionColor += sampleCol * falloff * sampleSat;
        }
    }
    
    // Normalize
    if (infectionStrength > 0.01) {
        infectionColor /= infectionStrength;
        infectionStrength = min(infectionStrength / f32(sampleCount) * 4.0, 1.0);
    }

    // -----------------------------------------------------------------
    //  5️⃣  Tendril growth pattern
    // -----------------------------------------------------------------
    let tendril = tendrilNoise(uv, time * spreadSpeed, tendrilScale);
    
    // Tendrils pulse and breathe
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed + tendril * 10.0);
    
    // Sharpen tendrils into vein-like structures
    let veinPattern = smoothstep(0.3, 0.1, tendril) * smoothstep(0.0, 0.05, tendril);
    
    // Combine with infection strength
    let spreadMask = veinPattern * infectionStrength * pulse;

    // -----------------------------------------------------------------
    //  6️⃣  Depth influence (foreground spreads faster)
    // -----------------------------------------------------------------
    let depthBoost = mix(1.0, 1.5, (1.0 - depth) * depthInf);
    let finalSpread = spreadMask * depthBoost * intensity;

    // -----------------------------------------------------------------
    //  7️⃣  Mutate the infection color
    // -----------------------------------------------------------------
    let infectionHSV = rgb2hsv(infectionColor);
    var mutatedHue = infectionHSV.x;
    
    // Add time-based hue mutation
    mutatedHue = fract(mutatedHue + hueShift + mutationRate * sin(time * 0.5 + tendril * 5.0) * 0.1);
    
    // More saturated, vibrant infection
    let mutatedColor = hsv2rgb(mutatedHue, min(infectionHSV.y * 1.3, 1.0), min(infectionHSV.z * 1.2, 1.0));

    // -----------------------------------------------------------------
    //  8️⃣  Composite: infect neutral areas, boost saturated areas
    // -----------------------------------------------------------------
    var outCol = src;
    
    if (isNeutral && infectionStrength > 0.01) {
        // Neutral pixels get infected
        outCol = mix(src, mutatedColor, finalSpread * 0.8);
        
        // Add glow around infection
        let glow = veinPattern * infectionStrength * 0.3;
        outCol += mutatedColor * glow * pulse;
    } else if (!isNeutral) {
        // Already saturated pixels pulse with life
        let selfPulse = 0.5 + 0.5 * sin(time * pulseSpeed * 0.5 + hsv.x * 10.0);
        outCol = mix(src, mutatedColor, veinPattern * selfPulse * intensity * 0.3);
        
        // Boost saturation slightly
        let boostedHSV = rgb2hsv(outCol);
        outCol = hsv2rgb(boostedHSV.x, min(boostedHSV.y * 1.1, 1.0), boostedHSV.z);
    }

    // -----------------------------------------------------------------
    //  9️⃣  Temporal persistence (infection memory)
    // -----------------------------------------------------------------
    let prev = textureSampleLevel(dataTexC, depthSampler, uv, 0.0).rgb;
    let persist = max(prev * 0.95, outCol * finalSpread);
    textureStore(infectionBuf, gid.xy, vec4<f32>(persist, 1.0));
    
    // Blend persistence trail
    outCol = max(outCol, persist * 0.2);

    // -----------------------------------------------------------------
    //  🔟  Output
    // -----------------------------------------------------------------
    textureStore(outTex, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
