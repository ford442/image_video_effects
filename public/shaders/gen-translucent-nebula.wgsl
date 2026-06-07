// ═══════════════════════════════════════════════════════════════════
//  Translucent Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Description: Volumetric gas clouds with density-based alpha
//    translucency. FBM and Worley noise create nebula structure.
//    Dense cores are opaque while edges fade to transparent.
//    Star sparkle reacts to treble; nebula pulses with bass.
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

// ═══ CHUNK: hash functions ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
  var p3 = fract(p * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: value noise 3D ═══
fn vnoise3(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 0.0)), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), u.x),
      u.y
    ),
    mix(
      mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
      mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.0, 1.0)), u.x),
      u.y
    ),
    u.z
  );
}

// ═══ CHUNK: fbm 3D ═══
fn fbm3(p: vec3<f32>) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0u; i < 5u; i = i + 1u) {
    val = val + amp * vnoise3(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return val;
}

// ═══ CHUNK: Worley noise (cellular) ═══
fn worley3(p: vec3<f32>) -> f32 {
  let n = floor(p);
  var dist1 = 1.0;
  for (var ix = -1; ix <= 1; ix = ix + 1) {
    for (var iy = -1; iy <= 1; iy = iy + 1) {
      for (var iz = -1; iz <= 1; iz = iz + 1) {
        let neighbor = n + vec3<f32>(f32(ix), f32(iy), f32(iz));
        let point = neighbor + hash13(neighbor + vec3<f32>(127.1, 311.7, 74.7));
        let d = length(p - point);
        dist1 = min(dist1, d);
      }
    }
  }
  return dist1;
}

// ═══ CHUNK: nebula density function ═══
fn nebulaDensity(p: vec3<f32>, t: f32, pulse: f32) -> f32 {
  // Large-scale FBM structure
  let large = fbm3(p * 0.8 + vec3<f32>(t * 0.02, t * 0.01, 0.0));
  // Medium detail
  let medium = fbm3(p * 2.0 + vec3<f32>(t * 0.03, -t * 0.02, 1.5));
  // Cellular/Worley for gas pockets
  let cells = worley3(p * 1.5 + vec3<f32>(t * 0.01, t * 0.015, 2.3));
  // Combine: large structure + medium detail * cell boundaries
  var density = large * 0.5 + medium * 0.3 + (1.0 - cells) * 0.4;
  // Audio pulse expands the nebula
  density = density * (0.8 + pulse * 0.4);
  // Sharpen into cloud-like blobs
  density = smoothstep(0.35, 0.7, density);
  return density;
}

// ═══ CHUNK: nebula color palette ═══
fn nebulaColor(density: f32, depth: f32, hueShift: f32) -> vec3<f32> {
  // Core colors
  let coreColor = vec3<f32>(0.9, 0.3, 0.5);   // magenta-pink core
  let midColor = vec3<f32>(0.3, 0.4, 0.9);    // blue midtones
  let edgeColor = vec3<f32>(0.1, 0.8, 0.7);   // teal edges
  let darkColor = vec3<f32>(0.02, 0.03, 0.08);

  // Hue rotation
  let hue = fract(density * 0.3 + depth * 0.1 + hueShift);
  let h6 = hue * 6.0;
  let c = 1.0;
  let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
  var hueCol: vec3<f32>;
  if (h6 < 1.0) { hueCol = vec3<f32>(c, x, 0.0); }
  else if (h6 < 2.0) { hueCol = vec3<f32>(x, c, 0.0); }
  else if (h6 < 3.0) { hueCol = vec3<f32>(0.0, c, x); }
  else if (h6 < 4.0) { hueCol = vec3<f32>(0.0, x, c); }
  else if (h6 < 5.0) { hueCol = vec3<f32>(x, 0.0, c); }
  else { hueCol = vec3<f32>(c, 0.0, x); }

  var col = mix(darkColor, edgeColor, density * 0.5);
  col = mix(col, midColor, smoothstep(0.3, 0.6, density));
  col = mix(col, coreColor, smoothstep(0.6, 0.9, density));
  col = mix(col, hueCol * 0.7, density * 0.4);
  return col;
}

// ═══ CHUNK: star field ═══
fn starField(uv: vec2<f32>, seed: f32, treble: f32) -> vec3<f32> {
  var stars = vec3<f32>(0.0);
  let layers = 3;
  for (var l = 0; l < layers; l = l + 1) {
    let scale = 150.0 + f32(l) * 200.0;
    let starUV = uv * scale + vec2<f32>(seed * f32(l + 1), seed * f32(l + 3));
    let h = hash12(floor(starUV));
    let fracUV = fract(starUV) - 0.5;
    let d = length(fracUV);
    let brightness = step(0.995 - f32(l) * 0.002, h);
    let twinkle = 0.5 + 0.5 * sin(time * (1.0 + h * 3.0) + f32(l));
    let star = brightness * smoothstep(0.5, 0.0, d) * twinkle;
    let starCol = mix(vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(1.0, 0.9, 0.7), h);
    stars = stars + starCol * star * (0.3 + treble * 0.7);
  }
  return stars;
}

// ═══ CHUNK: bass envelope smoothing ═══
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

var<private> time: f32;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = u.config.zw;
  if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

  let uv = vec2<f32>(gid.xy) / res;
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  time = u.config.x;

  // Audio input
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let rms = plasmaBuffer[0].w;

  // Parameters
  let densityParam = mix(0.4, 1.2, u.zoom_params.x);
  let cloudScale = mix(0.5, 2.0, u.zoom_params.y);
  let colorShift = u.zoom_params.z;
  let starDensity = mix(0.3, 1.5, u.zoom_params.w);

  // Mouse: position controls nebula center drift
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let centerOffset = (mousePos - 0.5) * 0.5;

  // Smooth bass for pulsing
  var prevBass = extraBuffer[1];
  let smoothBass = bass_env(prevBass, bass, 0.1, 0.03);
  extraBuffer[1] = smoothBass;

  // Temporal feedback
  let prevState = textureLoad(dataTextureC, coord, 0);

  // ═══ DENSITY RAY-MARCHING APPROXIMATION ═══
  // Sample multiple layers along Z to approximate volumetric density
  var accumDensity = 0.0;
  var accumColor = vec3<f32>(0.0);
  let layers = 8;
  let zStep = 1.0 / f32(layers);

  for (var z = 0; z < layers; z = z + 1) {
    let zDepth = f32(z) * zStep;
    let p = vec3<f32>(
      (uv.x - 0.5) * cloudScale + centerOffset.x + time * 0.01,
      (uv.y - 0.5) * cloudScale + centerOffset.y + time * 0.005,
      zDepth * 2.0
    );

    let d = nebulaDensity(p, time, smoothBass) * densityParam;
    let layerAlpha = d * zStep * 2.5;
    let layerCol = nebulaColor(d, zDepth, colorShift);

    // Front-to-back compositing
    accumColor = accumColor + layerCol * layerAlpha * (1.0 - accumDensity);
    accumDensity = accumDensity + layerAlpha * (1.0 - accumDensity);

    if (accumDensity >= 0.99) { break; }
  }

  accumDensity = clamp(accumDensity, 0.0, 1.0);

  // ═══ MOUSE GAS CONCENTRATIONS (via ripples) ═══
  var gasBoost = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var r = 0u; r < rippleCount; r = r + 1u) {
    let ripple = u.ripples[r];
    let rAge = time - ripple.z;
    if (rAge < 0.0 || rAge > 4.0) { continue; }
    let rDist = length(uv - ripple.xy);
    let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-rAge * 0.8);
    gasBoost = gasBoost + rInfluence;
  }

  // Add gas concentration from mouse clicks
  let gasColor = vec3<f32>(0.6, 0.2, 0.8) * gasBoost;
  accumColor = accumColor + gasColor * (1.0 - accumDensity);
  accumDensity = clamp(accumDensity + gasBoost * 0.3, 0.0, 1.0);

  // ═══ STAR FIELD ═══
  let stars = starField(uv, 42.0, treble) * starDensity;
  let starVisibility = 1.0 - accumDensity * 0.85;
  accumColor = accumColor + stars * starVisibility;

  // ═══ AUDIO-REACTIVE SPARKLE ═══
  let sparkleNoise = hash12(uv * 1000.0 + time * 10.0);
  let sparkleThreshold = 0.997 - treble * 0.003;
  let sparkle = step(sparkleThreshold, sparkleNoise);
  let sparkleColor = vec3<f32>(1.0, 0.95, 0.9) * sparkle * treble * 2.0;
  accumColor = accumColor + sparkleColor * (1.0 - accumDensity * 0.5);

  // Temporal smoothing for nebula motion
  let persistence = 0.12;
  let prevColor = prevState.rgb;
  var finalColor = mix(accumColor, prevColor, persistence);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.5));

  // Soft tone mapping
  finalColor = finalColor / (1.0 + finalColor * 0.3);
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));

  // Alpha encodes gas density: dense cores opaque, edges transparent
  // Also modulated by audio for breathing effect
  let breath = 1.0 + smoothBass * 0.15 + rms * 0.1;
  let finalAlpha = clamp(accumDensity * breath * 0.9 + prevState.a * 0.05, 0.0, 1.0);

  // Depth for chromatic + pass-through
  let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Store state for temporal feedback
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, finalAlpha));

  finalColor = acesToneMap(finalColor * 1.1);

  // Chromatic aberration
  let caStr = 0.003 * (1.0 + bass) + depthVal * 0.001;
  finalColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
