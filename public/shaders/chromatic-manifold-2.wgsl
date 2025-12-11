// ────────────────────────────────────────────────────────────────────────────────
//  Chromatic Manifold 2 - Enhanced Color-as-Dimension Topology
//  4-D space (x, y, depth, hue) with Möbius-like hue folding,
//  depth curvature tensor, and growing feedback folds over time.
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
  config:      vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_params: vec4<f32>,       // x=foldStrength, y=pivotHue, z=satScale, w=depthInfluence
  zoom_config: vec4<f32>,       // x=noiseAmount, y=feedbackPersist, z=rippleAmp, w=curvePower
  ripples:     array<vec4<f32>, 50>,
};

// ───────────────────────────────────────────────────────────────────────────────
//  RGB ↔ HSV conversion
// ───────────────────────────────────────────────────────────────────────────────
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    let p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    let q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
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

// ───────────────────────────────────────────────────────────────────────────────
//  Möbius-like hue fold around a pivot
// ───────────────────────────────────────────────────────────────────────────────
fn foldHue(h: f32, pivot: f32, strength: f32) -> f32 {
    let delta = h - pivot;
    // Non-linear fold creates Möbius-like twist
    let folded = pivot + sign(delta) * pow(abs(delta), strength);
    return fract(folded);
}

// ───────────────────────────────────────────────────────────────────────────────
//  Wrap-around modulo for hue gradients
// ───────────────────────────────────────────────────────────────────────────────
fn wrapMod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// ───────────────────────────────────────────────────────────────────────────────
//  2-D hash for noise
// ───────────────────────────────────────────────────────────────────────────────
fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
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

    let uv = vec2<f32>(gid.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // ──────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ──────────────────────────────────────────────────────────────────────────
    let foldStrength = u.zoom_params.x * 2.0 + 0.5;         // 0.5 - 2.5
    let pivotHue = u.zoom_params.y;                          // 0 - 1
    let satScale = u.zoom_params.z * 0.5 + 0.75;            // 0.75 - 1.25
    let depthInfluence = u.zoom_params.w;                    // 0 - 1
    let noiseAmount = u.zoom_config.x * 0.003;               // noise displacement
    let feedbackPersist = u.zoom_config.y * 0.1 + 0.9;      // 0.9 - 1.0
    let rippleAmp = u.zoom_config.z * 0.015;                 // ripple amplitude
    let curvePower = u.zoom_config.w * 2.0 + 1.0;           // 1 - 3

    // ──────────────────────────────────────────────────────────────────────────
    //  1. Read source color & depth
    // ──────────────────────────────────────────────────────────────────────────
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depthVal = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // ──────────────────────────────────────────────────────────────────────────
    //  2. Compute local hue gradient (with wrap-around handling)
    // ──────────────────────────────────────────────────────────────────────────
    let h = rgb2hsv(srcColor).x;
    let hR = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hL = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(texel.x, 0.0), 0.0).rgb).x;
    let hU = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv + vec2<f32>(0.0, texel.y), 0.0).rgb).x;
    let hD = rgb2hsv(textureSampleLevel(videoTex, videoSampler, uv - vec2<f32>(0.0, texel.y), 0.0).rgb).x;

    // Wrap-around gradient (handle hue discontinuity at 0/1)
    let gradX = wrapMod(hR - hL + 1.5, 1.0) - 0.5;
    let gradY = wrapMod(hU - hD + 1.5, 1.0) - 0.5;
    let hueGrad = vec2<f32>(gradX, gradY);

    // ──────────────────────────────────────────────────────────────────────────
    //  3. Depth curvature tensor
    // ──────────────────────────────────────────────────────────────────────────
    let curvature = pow(depthVal, curvePower) * depthInfluence;

    // ──────────────────────────────────────────────────────────────────────────
    //  4. Calculate fold displacement
    // ──────────────────────────────────────────────────────────────────────────
    let dispBase = hueGrad * foldStrength * 0.05 * (1.0 + curvature);

    // Add temporal noise
    let noise = hash2(uv * 100.0 + time);
    let noiseDisp = vec2<f32>(
        sin(time + noise * 6.28318),
        cos(time + noise * 6.28318)
    ) * noiseAmount;

    var totalDisp = dispBase + noiseDisp;

    // ──────────────────────────────────────────────────────────────────────────
    //  5. Mouse-driven ripples
    // ──────────────────────────────────────────────────────────────────────────
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let r = u.ripples[i];
        let t = time - r.z;
        if (t > 0.0 && t < 3.0) {
            let dir = uv - r.xy;
            let d = length(dir);
            if (d > 0.0001) {
                let rippleDepth = textureSampleLevel(depthTex, depthSampler, r.xy, 0.0).r;
                let depthFactor = 1.0 - rippleDepth;
                let speed = mix(1.0, 2.0, depthFactor);
                let amp = rippleAmp * mix(0.5, 1.5, depthFactor);
                let wave = sin(d * 30.0 - t * speed);
                let falloff = 1.0 / (d * 20.0 + 1.0);
                let atten = 1.0 - smoothstep(0.0, 3.0, t);
                totalDisp = totalDisp + normalize(dir) * wave * amp * falloff * atten;
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  6. Sample displaced UV for color
    // ──────────────────────────────────────────────────────────────────────────
    let displacedUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
    let displacedColor = textureSampleLevel(videoTex, videoSampler, displacedUV, 0.0).rgb;

    // ──────────────────────────────────────────────────────────────────────────
    //  7. Fold the hue (Möbius-like effect)
    // ──────────────────────────────────────────────────────────────────────────
    var hsv = rgb2hsv(displacedColor);
    hsv.x = foldHue(hsv.x, pivotHue, foldStrength);
    hsv.y = clamp(hsv.y * satScale, 0.0, 1.0);
    let foldedColor = hsv2rgb(hsv.x, hsv.y, hsv.z);

    // ──────────────────────────────────────────────────────────────────────────
    //  8. Feedback: blend with previous frame (folds grow over time)
    // ──────────────────────────────────────────────────────────────────────────
    let prev = textureSampleLevel(feedbackTex, videoSampler, uv, 0.0).rgb;
    let finalColor = mix(foldedColor, prev, feedbackPersist);

    // ──────────────────────────────────────────────────────────────────────────
    //  9. Write outputs
    // ──────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(feedbackOut, gid.xy, vec4<f32>(finalColor, 1.0));
}
