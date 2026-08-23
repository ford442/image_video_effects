// ----------------------------------------------------------------
// Cybernetic-Mycelium Neural-Web — Batch 63
// Category: generative
// A bio-mechanical mycelial net firing at speed: psychedelic pulse
// spectra, KIFS lattice + hyphal filigree detail, spring-cursor
// attractor, held bloom, capped click mutation bursts.
// Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//           exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//           bounded extraBuffer[133..138] state (the legacy [0..6] writes into
//           the engine-reserved / FFT zone are gone).
// ----------------------------------------------------------------

struct Uniforms {
  config      : vec4<f32>,  // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config : vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
  zoom_params : vec4<f32>,  // x=Growth Rate, y=Pulse Intensity, z=Decay Speed, w=Network Complexity
  ripples     : array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler                : sampler;
@group(0) @binding(1) var readTexture              : texture_2d<f32>;
@group(0) @binding(2) var writeTexture             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u               : Uniforms;
@group(0) @binding(4) var readDepthTexture         : texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler    : sampler;
@group(0) @binding(6) var writeDepthTexture        : texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB             : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC             : texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer : array<f32>;
@group(0) @binding(11) var comparison_sampler      : sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer : array<vec4<f32>>;

const PI : f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

fn hash2(p: vec2<f32>) -> f32 {
  var q = fract(p * vec2<f32>(0.1031, 0.1030));
  q += dot(q, q + 33.33);
  return fract((q.x + q.y) * q.x);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash2(i+vec2<f32>(0.0,0.0)), hash2(i+vec2<f32>(1.0,0.0)), w.x),
    mix(hash2(i+vec2<f32>(0.0,1.0)), hash2(i+vec2<f32>(1.0,1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0; var a = 0.5; var pp = p;
  for(var i = 0; i < 5; i++) {
    v += a * noise2(pp);
    pp = pp * 2.03 + vec2<f32>(1.7, 3.1);
    a *= 0.5;
  }
  return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic mycelial spectrum — neon wheel spun by the audio
fn mycoPalette(t: f32, drive: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.25, 2.0 + drive * 1.3, 4.1 - drive * 0.9);
  return 0.5 + 0.5 * cos(TAU * t + phase);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
  if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

  let coord = vec2<i32>(global_id.xy);
  let uv01 = fragCoord / res;
  let uv = (fragCoord - 0.5 * res) / res.y;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let growthRate = u.zoom_params.x;
  let pulseIntensity = u.zoom_params.y;
  let decaySpeed = u.zoom_params.z;
  let complexity = u.zoom_params.w;

  let rawMouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let heldF = select(0.0, 1.0, held);

  // ── spring cursor — the ONLY persistent state, all in the safe zone ──
  var smoothMouse = rawMouse;
  var cursorSpeed = 0.0;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
    cursorSpeed = length(vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]));
  }
  if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
    if (extraBuffer[SPRING_INIT] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
      let omega = 10.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[SPRING_X] = springPos.x;
    extraBuffer[SPRING_Y] = springPos.y;
    extraBuffer[SPRING_VX] = springVel.x;
    extraBuffer[SPRING_VY] = springVel.y;
    extraBuffer[SPRING_T] = time;
    extraBuffer[SPRING_INIT] = 1.0;
    smoothMouse = springPos;
    cursorSpeed = length(springVel);
  }
  // Whip the cursor and the net mutates — replaces the old click-count state slot
  let whip = clamp(cursorSpeed * 0.6, 0.0, 1.5);

  // ── click mutation bursts (capped, bounded) ─────────────────────────
  var burst = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.4) {
      let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.85);
      burst = max(burst, exp(-front * 30.0) * (1.0 - age / 1.4));
    }
  }
  burst = min(burst, 1.0);
  let mutationSeed = fract(burst * 0.7 + whip * 0.3 + time * 0.05);

  let mousePos = (smoothMouse - 0.5) * vec2<f32>(aspect.x, 1.0) * 2.5;
  let mouseWorld = vec2<f32>(mousePos.x, smoothMouse.y * 2.0);

  // KIFS structural lattice (nutrient hotspots)
  var z = vec3<f32>(uv.x, uv.y, 0.0) * complexity * 3.0;
  var dr = 1.0;
  for(var i = 0; i < 5; i++) {
    z = abs(z);
    if(z.x + z.y < 0.0) { let t = -z.y; z.y = z.x; z.x = t; }
    if(z.x + z.z < 0.0) { let t = -z.z; z.z = z.x; z.x = t; }
    z = z * 2.0 - vec3<f32>(1.0, 1.0, 1.0);
    dr *= 2.0;
  }
  let hotspot = length(z) / abs(dr);

  // Mycelial trail density — fast motion: growth streams several times quicker
  let flow = time * (0.9 + growthRate * 1.8 + bass * 1.4 + heldF * 0.8);
  let trailP = uv * 4.0 + vec2<f32>(flow * 0.35, -flow * 0.2);
  let trailDensity = fbm(trailP) * fbm(trailP * 1.5 + vec2<f32>(flow * 0.8, -flow * 0.6));

  // Hyphal filigree — fine branching striation carved over the trails
  let filigree = 0.5 + 0.5 * sin(trailDensity * 42.0 - flow * 4.0 + hotspot * 60.0);
  let detailedTrails = trailDensity * (0.75 + filigree * 0.5);

  // Mouse attraction — held and burst both deepen the well
  let toMouse = mouseWorld - uv;
  let mouseDist = length(toMouse);
  let mouseAttraction = exp(-mouseDist * mouseDist * 2.0) * (3.0 + burst * 3.0 + heldF * 2.5 + whip * 1.5);

  // Audio-reactive turbulence on trails
  let audioTurbulence = fbm(uv * 8.0 + vec2<f32>(bass * 2.0 + flow * 0.3, mid * 2.0 - flow * 0.25));

  // Data pulses racing the high-density trails — treble sets the fire rate
  let pulsePhase = fract(time * (2.4 + treble * 6.0) * pulseIntensity + detailedTrails * 3.0 + mutationSeed);
  let pulse = exp(-pow(pulsePhase - 0.5, 2.0) * 50.0) * pulseIntensity;

  let audioGrowth = 1.0 + bass * 2.0 + mid * 0.8;
  let totalDensity = detailedTrails * audioGrowth + mouseAttraction + audioTurbulence * 0.3;

  // Decay
  let age2 = fract(hash2(floor(uv * 20.0)) + time * decaySpeed * (1.0 + bass) + mutationSeed);
  let alive = smoothstep(0.0, 0.3, age2) * smoothstep(1.0, 0.7, age2);

  // ── Color: bio-mechanical base under a psychedelic pulse spectrum ────
  let baseHue = fract(detailedTrails * 0.5 + time * (0.12 + treble * 0.6) + mutationSeed);
  let bioCol = mix(
    mycoPalette(baseHue, mid) * 0.32,
    vec3<f32>(0.35, 0.35, 0.38),
    trailDensity * 0.6
  );

  let pulseCol = mycoPalette(baseHue + 0.4 + treble * 0.2, 1.0 + bass) * pulse * 1.4;

  let intersection = smoothstep(0.4, 0.6, trailDensity) * smoothstep(0.6, 0.4, trailDensity);
  let bioLum = mycoPalette(baseHue + 0.65, treble) * intersection * (0.6 + bass * 2.2);

  let mouseGlow = mycoPalette(fract(time * 0.5), bass) * mouseAttraction * 0.5;

  var col = bioCol * alive;
  col += pulseCol;
  col += bioLum;
  col += mouseGlow;
  col += mycoPalette(fract(time * 1.1), 1.0) * burst * 1.2;

  // Organic subsurface scattering approximation
  let sss = fbm(uv * 6.0 + flow * 0.12) * 0.1;
  col += mycoPalette(baseHue + 0.85, mid) * sss * 0.6;

  // Audio bloom
  col += mycoPalette(0.35, bass) * bass * bass * 0.35;
  col += mycoPalette(0.75, mid) * mid * 0.28;

  // Chromatic edge aberration on dense areas
  let ca = totalDensity * 0.02 * (1.0 + treble);
  col.r += noise2(uv + vec2<f32>(ca, 0.0)) * ca;
  col.b += noise2(uv - vec2<f32>(ca, 0.0)) * ca;

  // Depth sample for depth-aware feedback
  let depthSample = textureLoad(readDepthTexture, coord, 0).r;

  // ── temporal feedback — exact load, no filtering ────────────────────
  // A four-neighbor ridge measure reinforces connected hyphae while keeping
  // the history payload display-safe RGBA.
  let prevData = textureLoad(dataTextureC, coord, 0);
  let historyMax = vec2<i32>(i32(u.config.z) - 1, i32(u.config.w) - 1);
  let prevN = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, -1), vec2<i32>(0), historyMax), 0).rgb;
  let prevS = textureLoad(dataTextureC, clamp(coord + vec2<i32>(0, 1), vec2<i32>(0), historyMax), 0).rgb;
  let prevE = textureLoad(dataTextureC, clamp(coord + vec2<i32>(1, 0), vec2<i32>(0), historyMax), 0).rgb;
  let prevW = textureLoad(dataTextureC, clamp(coord + vec2<i32>(-1, 0), vec2<i32>(0), historyMax), 0).rgb;
  let neighborHistory = (prevN + prevS + prevE + prevW) * 0.25;
  let connectivity = clamp(length(prevData.rgb - neighborHistory) * 1.8, 0.0, 1.0);
  let feedbackMix = 0.3 + bass * 0.15;
  col = mix(prevData.rgb * 0.95, col, feedbackMix);
  col += mycoPalette(baseHue + 0.18, mid) * connectivity * (0.08 + treble * 0.12);

  col = acesToneMap(col * (1.05 + mid * 0.25));

  // Semantic alpha: mycelial density + firing energy
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(
    clamp(totalDensity * 0.3, 0.0, 0.7) + luma * 0.45 + pulse * 0.2
      + burst * 0.25 + connectivity * 0.12 + depthSample * 0.1,
    0.0, 1.0);

  let outColor = vec4<f32>(col, alpha);
  textureStore(writeTexture, coord, outColor);
  textureStore(dataTextureA, coord, outColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(hotspot * 0.5 + depthSample * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0));
}
