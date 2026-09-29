// ═══════════════════════════════════════════════════════════════════
//  Signal Tuner
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: off-station snow (Static Noise mixes treble-flickered snow where the wobble is strongest); RF multipath ghost (delayed-path copy offset right by Frequency, fading with tuning influence); detune beat bands (slow moiré bands where the row wobble nears the virtual raster pitch)
//  A packing: pre-ACES linear display RGB + semantic alpha; C read back as that linear colour for the tuning-zone ghost history
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Frequency, y=Interference, z=DriftSpeed, w=Static
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
// Virtual raster pitch (radians per uv unit) that the row wobble beats against (idea 3).
const RASTER_FREQ: f32 = 48.0;

fn hash(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn beat_pulse(env: f32, time: f32) -> f32 {
  return env * exp(-3.0 * fract(time * 2.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

  // Audio: three bands from plasmaBuffer[0] only (plasmaBuffer[1..] is never written).
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let gid = vec2<i32>(i32(global_id.x), i32(global_id.y));
  let time = u.config.x;

  let freq = mix(5.0, 100.0, u.zoom_params.x);
  let amp = u.zoom_params.y * 0.1;
  let speed = u.zoom_params.z * 5.0;
  let noiseAmt = u.zoom_params.w;

  // Pointer read directly (the old extraBuffer spring/envelope was re-zeroed every frame).
  let mouse = u.zoom_config.yz;

  let aspect = resolution.x / max(resolution.y, 1.0);
  let uv_corrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouse_corrected = vec2<f32>(mouse.x * aspect, mouse.y);

  let dist = distance(uv_corrected, mouse_corrected);
  let mouseInfluence = smoothstep(0.5, 0.0, dist);
  let clickBoost = select(1.0, 1.5, u.zoom_config.w > 0.5);

  // Clicks retune localized expanding bands instead of acting as another held
  // mouse state. Ripple positions are normalized canvas coordinates.
  var rippleTune = 0.0;
  var rippleRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i++) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    let safeAge = max(age, 0.0);
    let live = step(0.0, age) * (1.0 - step(1.6, age));
    let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
    let ring = 1.0 - smoothstep(0.015, 0.05, abs(rd - safeAge * 0.38));
    let wave = ring * exp(-safeAge * 1.7) * live;
    rippleTune += wave * sin(rp.x * 31.0 + rp.y * 17.0);
    rippleRing = max(rippleRing, wave);
  }

  // Tuning influence: how detuned this pixel is (cursor zone or a click ring).
  let influence = max(mouseInfluence, rippleRing);

  let freqRadius = mix(0.3, 1.0, mouseInfluence);
  let pulse = beat_pulse(bass, time);
  let audioAmp = amp * (1.0 + bass * clickBoost + mids * 0.2);
  let freqEff = freq * freqRadius;
  let waveNorm = sin(uv.y * freqEff + time * speed + pulse * 3.14 + rippleTune * 2.0);
  let wave = waveNorm * audioAmp;
  let displacement = vec2<f32>(wave * influence, 0.0);

  // IDEA 3 — detune beat bands. The row wobble (freqEff) beats against a virtual raster pitch;
  // the closer the two, the stronger a slow horizontal moiré envelope that drifts through the
  // detuned zone. Bands both modulate brightness and nudge the rows sideways.
  let beatDelta = freqEff - RASTER_FREQ;
  let beatProximity = 1.0 - smoothstep(0.0, 1.0, abs(beatDelta) / RASTER_FREQ);
  let beatEnv = 0.5 + 0.5 * cos(uv.y * beatDelta * 0.5 - time * speed * 0.35 + rippleTune);
  let beatBand = beatProximity * beatEnv * beatEnv * influence;
  let beatShift = (beatBand - 0.5 * beatProximity * influence) * 0.008 * (1.0 + mids * 0.5);

  // HEAD hashed uv*time (a frozen pattern scaled by time); hash of uv + time flickers properly.
  let noiseHash = hash(uv + vec2<f32>(time * 0.37, time * 1.13));
  let noiseVal = select(0.0, (noiseHash - 0.5) * noiseAmt * influence * (1.0 + treble * 0.4), noiseAmt > 0.01);
  let finalUV = clamp(uv + displacement + vec2<f32>(noiseVal + beatShift, noiseVal), vec2<f32>(0.0), vec2<f32>(1.0));

  let split = audioAmp * influence * 0.5 * (1.0 + treble * 0.25);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(split, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let srcAlpha = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).a;
  var color = vec3<f32>(r, g, b);

  // IDEA 2 — RF multipath ghost. A delayed reflection arrives a little later than the direct
  // path, so a faint second copy sits to the RIGHT of the picture by a distance set by
  // Frequency (higher channel = longer delay), fading in with tuning influence. Not history:
  // it is the same source frame, offset and low-contrast, and it inherits the row wobble.
  let ghostDelay = mix(0.015, 0.075, u.zoom_params.x) * (1.0 + bass * 0.2);
  let ghostUV = clamp(finalUV - vec2<f32>(ghostDelay, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let ghostSrc = textureSampleLevel(readTexture, u_sampler, ghostUV, 0.0).rgb;
  let ghostStrength = influence * (0.22 + audioAmp * 1.5) * smoothstep(0.0, 0.02, finalUV.x - ghostDelay);
  let ghostLuma = dot(ghostSrc, vec3<f32>(0.299, 0.587, 0.114));
  color += mix(vec3<f32>(ghostLuma), ghostSrc, 0.4) * ghostStrength;

  // IDEA 3 (display part) — the beat bands brighten/darken as slow horizontal moiré.
  color *= 1.0 + (beatBand - 0.5 * beatProximity * influence) * 0.35;

  // IDEA 1 — off-station snow. Static Noise mixes real per-pixel snow into the detuned zone,
  // strongest where the row wobble is strongest (|waveNorm|), and treble flickers its density.
  let snowSeed = hash(vec2<f32>(global_id.xy) * 0.173 + vec2<f32>(floor(time * 29.0) * 1.7, floor(time * 31.0) * 0.9));
  let snowGrain = hash(vec2<f32>(global_id.xy) * 0.311 + vec2<f32>(floor(time * 47.0)));
  let snowLevel = 0.15 + snowSeed * 0.85;
  let snowGate = step(0.55 - treble * 0.25, snowGrain);
  let snowMix = clamp(noiseAmt * influence * (0.25 + 0.75 * abs(waveNorm)) * snowGate * 0.9, 0.0, 1.0);
  color = mix(color, vec3<f32>(snowLevel), snowMix);

  // History ghosting only inside the tuning zone. HEAD kept a 0.85 history weight everywhere,
  // which made the whole video lag; away from the cursor the picture is now live.
  let prevColor = textureLoad(dataTextureC, gid, 0);
  let historyWeight = clamp(influence * 0.55 + pulse * 0.15 * influence, 0.0, 0.85);
  color = mix(color, max(prevColor.rgb, vec3<f32>(0.0)), historyWeight);
  color = clamp(color, vec3<f32>(0.0), vec3<f32>(8.0));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r;
  let effectStrength = clamp(mouseInfluence * audioAmp * 10.0, 0.0, 1.0);

  // Semantic alpha: source coverage, thinned by depth, with snow/ghost adding carrier opacity.
  let depthFactor = mix(1.0, 0.85, depth * 0.5);
  let alphaBase = clamp(srcAlpha * depthFactor + snowMix * 0.3 + ghostStrength * 0.2, 0.0, 1.0);
  let alpha = clamp(mix(alphaBase, prevColor.a, historyWeight * 0.5), 0.0, 1.0);

  let depthOut = clamp(depth - effectStrength * 0.025 - rippleRing * 0.02, 0.0, 1.0);

  // A holds pre-ACES linear colour; ACES only on the displayed RGB.
  textureStore(dataTextureA, gid, vec4<f32>(color, alpha));
  textureStore(writeTexture, gid, vec4<f32>(acesToneMap(color), alpha));
  textureStore(writeDepthTexture, gid, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
