// ═══ Waveform Glitch (Oscilloscope Edition) ════════════════════════
//  Category: advanced-hybrid
//  Features: glitch, waveform, retro, rgb-tear, scanline, depth-jitter,
//            oscilloscope-style rendering, lissajous patterns, signal aliasing,
//            beat frequency effects, vector display
//  Upgraded: 2026-08-21 (Batch 42 - Oscilloscope / Lissajous)
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

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }

fn lissajous(uv: vec2<f32>, t: f32, freqX: f32, freqY: f32, phase: f32, thickness: f32) -> f32 {
    let centered = uv * 2.0 - 1.0;
    // Parameter t from 0 to 2PI to draw the curve
    var minDist = 1.0;
    let steps = 64.0;
    for (var i = 0.0; i < steps; i += 1.0) {
        let pt = i * TAU / steps;
        let lx = sin(freqX * pt + t);
        let ly = sin(freqY * pt + t + phase);
        let dist = length(centered - vec2<f32>(lx, ly) * 0.8);
        if (dist < minDist) { minDist = dist; }
    }
    return smoothstep(thickness, thickness * 0.2, minDist);
}

fn signalAliasing(uv: vec2<f32>, sampleRate: f32) -> vec2<f32> {
    return floor(uv * sampleRate) / sampleRate;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ── Main ──────────────────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.zw);
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let waveIntensity = u.zoom_params.x * (1.0 + bass * 0.8);
  let vhsIntensity = u.zoom_params.y * (1.0 + mids * 0.5);
  let aliasingFactor = mix(200.0, 20.0, u.zoom_params.z); 
  let scopeIntensity = u.zoom_params.w;

  // Signal Aliasing
  let aliasedUV = signalAliasing(uv, aliasingFactor + treble * 50.0);
  
  // Waveform distortion (Beat frequency effects)
  let beatFreq = time * (1.0 + bass * 2.0);
  let waveX = sin(aliasedUV.y * 50.0 + beatFreq) * 0.05 * waveIntensity;
  let waveY = cos(aliasedUV.x * 40.0 - beatFreq * 0.8) * 0.03 * waveIntensity;
  
  let displacedUV = clamp(aliasedUV + vec2<f32>(waveX, waveY), vec2<f32>(0.0), vec2<f32>(1.0));

  // RGB Tear & Aberration
  let r = textureSampleLevel(readTexture, u_sampler, displacedUV + vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, displacedUV - vec2<f32>(0.01 * vhsIntensity, 0.0), 0.0).b;
  var col = vec3<f32>(r, g, b);

  // Vector Display / Oscilloscope Simulation
  let lissX = 3.0 + floor(mids * 2.0);
  let lissY = 2.0 + floor(bass * 2.0);
  let lissPhase = PI * 0.25 * treble;
  let lissPattern = lissajous(uv, time * 2.0, lissX, lissY, lissPhase, 0.02 + bass * 0.02);
  
  // Vector glow (greenish oscilloscope tint)
  let scopeColor = vec3<f32>(0.2, 1.0, 0.4) * lissPattern * scopeIntensity * 2.0;
  col += scopeColor;
  
  // Blanking intervals and scanlines
  let scanline = sin(uv.y * res.y * PI) * 0.2 + 0.8;
  let blanking = step(0.05, fract(time * 5.0 + uv.y * 2.0));
  
  col = col * scanline * mix(1.0, blanking, vhsIntensity * 0.5);

  let prev = textureLoad(dataTextureA, pixel, 0);
  let decay = 0.85;
  let trail = mix(prev.rgb * decay, col, 0.3 + bass * 0.2);
  textureStore(dataTextureA, pixel, vec4<f32>(trail, prev.a));

  col = mix(col, trail, 0.6); // Phosphor persistence
  col = acesToneMap(col);

  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let alpha = clamp(length(col) * 1.5, 0.0, 1.0);

  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
