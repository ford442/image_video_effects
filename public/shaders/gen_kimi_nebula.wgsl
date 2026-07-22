// ═══════════════════════════════════════════════════════════════════
//  Kimi Nebula
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-06
//  Rewired:  2026-07-22 (slider params now drive real nebula constants)
// ═══════════════════════════════════════════════════════════════════
//
//  Slider contract (saved-preset safe — ids/defaults unchanged):
//    param1 Intensity -> gas density gain      (u.zoom_params.x)
//    param2 Speed     -> animation time scale  (u.zoom_params.y)
//    param3 Scale     -> noise spatial scale   (u.zoom_params.z)
//    param4 Detail    -> star density cutoff   (u.zoom_params.w)
//
//  Audio wiring:
//    bass   -> chromatic aberration offset (as before)
//    mids   -> drift speed of the mid-scale fbm density layer
//    treble -> drift speed of the fine-scale fbm density layer

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
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
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Kimi Nebula - Cosmic Cloud Swirls
// Ethereal gas clouds with twinkling stars and mouse-driven stellar winds

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 57.0 + i.z * 113.0;
    var res = mix(mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
                      mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), f.x), f.y),
                 mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
                     mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), f.x), f.y), f.z);
    return res;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amplitude * noise3(p * freq);
        amplitude *= 0.5;
        freq *= 2.0;
    }
    return value;
}

// Real nebula control constants derived from the four slider params.
// These replace the old generic applyGenerativePrimaryControls boilerplate.
struct NebulaControls {
    gasGain: f32,        // param1 Intensity: multiplies raw gas density
    timeScale: f32,      // param2 Speed: multiplier on global animation time
    spatialScale: f32,   // param3 Scale: base frequency of the fbm field
    starCutoff: f32,     // param4 Detail: hash threshold for star spawning
};

fn nebulaControls() -> NebulaControls {
    var ctl: NebulaControls;
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.0, 1.0);
    let detail = clamp(u.zoom_params.w, 0.0, 1.0);
    // Defaults (0.5) reproduce the legacy hard-coded constants.
    ctl.gasGain = mix(0.4, 2.0, intensity);
    ctl.timeScale = mix(0.0, 0.2, speed);
    ctl.spatialScale = mix(0.5, 2.5, scale);
    ctl.starCutoff = mix(0.99, 0.999, detail);
    return ctl;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);

    // Slider-derived nebula constants (see NebulaControls above)
    let ctl = nebulaControls();
    let time = u.config.x * ctl.timeScale;

    // Audio bands: bass drives chromatic offset, mids/treble drive layer drift
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Create swirling nebula effect
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;

    // Mouse creates stellar wind
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    let dist = length(p - mousePos);
    let windStrength = smoothstep(0.8, 0.0, dist) * (0.5 + mouseDown * 0.5);

    // Animated 3D noise for gas clouds (spatial scale is slider-driven)
    var noisePos = vec3<f32>(p * ctl.spatialScale, time * 0.2);

    // Add swirling motion from mouse
    let angle = windStrength * 2.0;
    let rot = vec2<f32>(
        noisePos.x * cos(angle) - noisePos.y * sin(angle),
        noisePos.x * sin(angle) + noisePos.y * cos(angle)
    );
    noisePos.x = mix(noisePos.x, rot.x, windStrength);
    noisePos.y = mix(noisePos.y, rot.y, windStrength);

    // Extra domain warp: one additional fbm3 lookup pushes the sampling
    // position around for more turbulent, billowing gas structures.
    let warp = fbm3(noisePos * 0.8 + vec3<f32>(31.4, -17.2, time * 0.15), 3);
    let warpVec = vec3<f32>(warp - 0.5, 0.5 - warp, (warp - 0.5) * 0.5);
    noisePos = noisePos + warpVec * 0.7;

    // Multi-octave nebula density. Each stratum gets its own audio-driven
    // drift: mids push the mid-scale layer, treble pushes the fine layer,
    // so the cloud strata visibly disaggregate with the music.
    let midsDrift = vec3<f32>(0.0, time * mids * 0.6, time * mids * 0.3);
    let trebleDrift = vec3<f32>(time * treble * 0.9, 0.0, time * treble * 0.5);

    let density1 = fbm3(noisePos, 4);
    let density2 = fbm3(noisePos * 2.0 + vec3<f32>(100.0) + midsDrift, 3);
    let density3 = fbm3(noisePos * 4.0 + vec3<f32>(200.0) + trebleDrift, 2);

    // Intensity slider = gas density gain, applied before palette mapping
    let nebulaDensity = (density1 * 0.5 + density2 * 0.3 + density3 * 0.2) * ctl.gasGain;

    // Color palette - deep purples, blues, and pink accents
    let color1 = vec3<f32>(0.1, 0.05, 0.2);  // Deep purple
    let color2 = vec3<f32>(0.2, 0.1, 0.4);   // Purple
    let color3 = vec3<f32>(0.4, 0.2, 0.6);   // Magenta
    let color4 = vec3<f32>(0.8, 0.6, 0.9);   // Pink highlight
    let color5 = vec3<f32>(0.1, 0.3, 0.5);   // Blue

    var color = color1;
    color = mix(color, color2, smoothstep(0.2, 0.4, nebulaDensity));
    color = mix(color, color3, smoothstep(0.4, 0.6, nebulaDensity));
    color = mix(color, color4, smoothstep(0.7, 0.9, nebulaDensity + windStrength * 0.3));
    color = mix(color, color5, smoothstep(0.5, 0.8, density3 * ctl.gasGain));

    // Add stars — Detail slider sets the hash cutoff: higher Detail means
    // a higher threshold, i.e. fewer but crisper star points.
    let starNoise = hash3(vec3<f32>(floor(p * 100.0), time * 0.01));
    let star = select(0.0, 1.0, starNoise > ctl.starCutoff && nebulaDensity < 0.6);

    // Twinkling stars near mouse
    let starTwinkle = sin(time * 5.0 + starNoise * 10.0) * 0.5 + 0.5;
    color += vec3<f32>(star) * (0.5 + starTwinkle * 0.5) * (1.0 + windStrength);

    // Soft halo around each star, tinted by the local gas color so the
    // starfield feels embedded in the nebula rather than pasted on top.
    let haloNoise = hash3(vec3<f32>(floor(p * 100.0) + vec2<f32>(1.0, 0.0), time * 0.01));
    let halo = select(0.0, 1.0, haloNoise > ctl.starCutoff) * 0.15;
    color += color4 * halo * (0.5 + starTwinkle * 0.5);

    // Bright core near mouse
    color += vec3<f32>(0.6, 0.8, 1.0) * windStrength * 0.5;

    // Gentle bass-reactive shimmer: low-end pulses make the gas breathe
    // without disturbing the mids/treble layer separation above.
    color *= 1.0 + bass * 0.12 * smoothstep(0.3, 0.8, nebulaDensity);

    // Gamma correction and intensity
    color = pow(color, vec3<f32>(0.8)) * 1.2;

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Opacity control
    let opacity = 0.85;

    // ═══ BLEND WITH INPUT ═══
    let finalColor = mix(inputColor.rgb, color, opacity);
    let finalAlpha = max(inputColor.a, opacity);

    // Store for feedback — bass still drives the chromatic offset
    let caStr = 0.003 * (1.0 + bass) + inputDepth * 0.001;
    let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
    let acesColor = acesToneMap(chromaticColor * 1.1);

    textureStore(writeTexture, px, vec4<f32>(acesColor, finalAlpha));
    textureStore(dataTextureA, px, vec4<f32>(acesColor, nebulaDensity));
    textureStore(writeDepthTexture, px, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
