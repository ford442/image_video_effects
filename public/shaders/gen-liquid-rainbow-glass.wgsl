// ═══════════════════════════════════════════════════════════════════
//  Liquid Rainbow Glass
//  Category: generative
//  Features: liquid, refraction, chromatic, mouse-stir, audio-reactive, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
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

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530;

// ---- NOISE ----
fn hash1(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash2(p: vec2<f32>) -> vec2<f32> {
  return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}

fn noise2d(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

// Value noise with smoother interpolation
fn smoothNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(
    mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), s.x),
    mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), s.x),
    s.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val: f32 = 0.0;
  var amp: f32 = 0.5;
  var freq: f32 = 1.0;
  for (var i: i32 = 0; i < 8; i = i + 1) {
    if (i >= octaves) { break; }
    val += amp * smoothNoise(p * freq);
    freq *= 2.1;
    amp *= 0.5;
  }
  return val;
}

fn fbm3(p: vec2<f32>, octaves: i32) -> vec3<f32> {
  return vec3<f32>(
    fbm(p + vec2<f32>(0.0, 0.0), octaves),
    fbm(p + vec2<f32>(5.2, 1.3), octaves),
    fbm(p + vec2<f32>(1.7, 9.2), octaves)
  );
}

// ---- COLOR FUNCTIONS ----

// Ultra bright rainbow
fn liquidRainbow(t: f32) -> vec3<f32> {
  let p = abs(fract(t + vec3<f32>(0.0, 0.333, 0.667)) * 6.0 - vec3<f32>(3.0));
  return pow(clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.55)) * 2.2;
}

// Glass refraction color shift
fn chromaticDispersion(uv: vec2<f32>, amount: f32, time: f32) -> vec3<f32> {
  let rOffset = vec2<f32>(amount, 0.0);
  let gOffset = vec2<f32>(0.0, 0.0);
  let bOffset = vec2<f32>(-amount, 0.0);
  
  let r = fbm(uv * 3.0 + rOffset + time * 0.1, 5);
  let g = fbm(uv * 3.0 + gOffset + time * 0.1, 5);
  let b = fbm(uv * 3.0 + bOffset + time * 0.1, 5);
  
  return vec3<f32>(r, g, b) * liquidRainbow(r * 2.0 + time * 0.05);
}

// Liquid layer - flowing, blending, refracting
fn liquidLayer(uv: vec2<f32>, time: f32, layerIdx: f32, scale: f32, speed: f32) -> vec4<f32> {
  let t = time * speed;
  let idx = layerIdx;
  
  // Offset each layer differently
  let p = uv * (1.5 + idx * 0.8) * scale + vec2<f32>(idx * 10.0, idx * 7.0);
  
  // Flow field - advected noise creating swirling motion
  let flow1 = fbm(p + vec2<f32>(t * 0.3, t * 0.2), 4);
  let flow2 = fbm(p * 1.5 - vec2<f32>(t * 0.15, t * 0.25) + flow1 * 0.5, 4);
  let flow3 = fbm(p * 2.0 + vec2<f32>(t * 0.1, -t * 0.18) + flow2 * 0.3, 3);
  
  // Combine flows into organic shapes
  let shape1 = smoothstep(0.35, 0.65, flow1);
  let shape2 = smoothstep(0.3, 0.7, flow2) * 0.7;
  let shape3 = smoothstep(0.4, 0.6, flow3) * 0.5;
  
  // Color for this layer
  let hue = flow1 * 2.0 + flow2 * 1.5 + idx * 0.33 + time * 0.05;
  let color = liquidRainbow(hue);
  
  // Layer alpha based on shapes
  let alpha = shape1 * 0.7 + shape2 * 0.5 + shape3 * 0.3;
  
  return vec4<f32>(color, clamp(alpha, 0.0, 1.0));
}

// Thick glass refraction effect
fn glassRefraction(uv: vec2<f32>, time: f32, intensity: f32, scale: f32) -> vec2<f32> {
  let refractStrength = 0.15 * intensity;
  let n1 = fbm(uv * 4.0 * scale + time * 0.2, 4);
  let n2 = fbm(uv * 6.0 * scale - time * 0.15 + 100.0, 4);
  return vec2<f32>(n1 - 0.5, n2 - 0.5) * refractStrength;
}

// Oil-in-water interference pattern
fn oilFilm(uv: vec2<f32>, time: f32, scale: f32) -> vec3<f32> {
  let p = uv * 5.0 * scale;
  
  // Thin film interference simulation
  let d1 = fbm(p + time * 0.1, 4);
  let d2 = fbm(p * 1.3 - time * 0.08 + vec2<f32>(50.0, 30.0), 4);
  let film = (d1 + d2) * 0.5;
  
  // Convert film thickness to color (interference)
  let interference = film * TAU * 4.0;
  let r = cos(interference) * 0.5 + 0.5;
  let g = cos(interference + 2.094) * 0.5 + 0.5;
  let b = cos(interference + 4.189) * 0.5 + 0.5;
  
  return vec3<f32>(r, g, b) * 2.5;
}

// Vortex stir effect from mouse
fn vortexStir(uv: vec2<f32>, mousePos: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
  let d = uv - mousePos;
  let r = length(d);
  let angle = atan2(d.y, d.x);
  
  // Swirl strength falls off with distance
  let swirl = strength / (r * 5.0 + 0.1);
  let swirlX = -d.y * swirl;
  let swirlY = d.x * swirl;
  
  return vec2<f32>(swirlX, swirlY) * exp(-r * r * 8.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = vec2<f32>(u.config.z, u.config.w);
  let aspect = res.x / res.y;

  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) {
    return;
  }

  let fragCoord = vec2<f32>(pixel);
  let uv = fragCoord / res;
  let centered = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);

  let time = u.config.x;
  let mouseNorm = u.zoom_config.yz / res;
  let mouseCentered = (mouseNorm - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let mouseDown = u.zoom_config.w;

  let intensity = u.zoom_params.x;
  let speed = u.zoom_params.y;
  let scale = u.zoom_params.z;
  let colorShift = u.zoom_params.w;

  // ═══ Audio reactivity (plasmaBuffer) ═══
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let audioSpeed = speed * (0.85 + bass * 0.6);
  let audioIntensity = intensity * (0.9 + treble * 0.5);
  let audioColor = colorShift + mids * 0.22;

  let t = time * audioSpeed;

  // ---- BASE: Deep glass background ----
  let bgGrad = mix(
    vec3<f32>(0.05, 0.1, 0.25),
    vec3<f32>(0.15, 0.05, 0.2),
    length(centered) * 0.5 + 0.5
  );
  var color = bgGrad;

  // ---- LAYER 1: Background liquid flow ----
  let uv1 = centered + t * 0.05;
  let layer1 = liquidLayer(uv1, t, 0.0, scale * 2.0, 0.3);
  color = mix(color, layer1.rgb, layer1.a * 0.4 * audioIntensity);

  // ---- LAYER 2: Oil film interference (thin) ----
  let oil = oilFilm(centered * 1.5, t, scale);
  let oilMask = fbm(centered * 3.0 + t * 0.1, 4);
  color += oil * oilMask * 0.3 * audioIntensity;

  // ---- LAYER 3: Main flowing liquid (thick) ----
  // Apply mouse stir if active
  var uv3 = centered * 0.8;
  if (mouseDown > 0.5) {
    let stir = vortexStir(centered, mouseCentered, t, 0.3 * intensity);
    uv3 += stir;
  }
  let layer3 = liquidLayer(uv3, t, 1.0, scale * 1.5, 0.5);
  color = mix(color, layer3.rgb, layer3.a * 0.6);

  // ---- LAYER 4: Glass refraction layer ----
  let refraction = glassRefraction(centered, t, intensity, scale);
  let uv4 = (centered + refraction) * 1.2;
  let layer4 = liquidLayer(uv4, t, 2.0, scale * 2.5, 0.4);
  color = mix(color, layer4.rgb, layer4.a * 0.5);

  // ---- LAYER 5: Chromatic dispersion bubbles ----
  // Bubbles of color with different refraction per channel
  let bubbleNoise = fbm3(centered * 4.0 * scale + t * 0.15, 5);
  let bubbleField = smoothstep(0.3, 0.8, bubbleNoise.x);
  
  // Chromatic aberration within bubbles
  let caStrength = 0.04 * intensity;
  let rCh = liquidRainbow(bubbleNoise.x * 3.0 + colorShift + caStrength * 3.0);
  let gCh = liquidRainbow(bubbleNoise.y * 3.0 + colorShift);
  let bCh = liquidRainbow(bubbleNoise.z * 3.0 + colorShift - caStrength * 3.0);
  let chromatic = vec3<f32>(rCh.r, gCh.g, bCh.b);
  color = mix(color, chromatic, bubbleField * 0.35);

  // ---- LAYER 6: Edge refraction highlights ----
  let edgeDist = length(centered);
  let edgeGlow = pow(edgeDist, 4.0) * intensity;
  let edgeColor = liquidRainbow(t * 0.1 + colorShift + edgeDist * 2.0);
  color += edgeColor * edgeGlow * 0.4;

  // ---- LAYER 7: Flowing ribbons ----
  let ribbonP = centered * 3.0 * scale;
  let ribbonNoise = fbm(ribbonP + vec2<f32>(t * 0.3, -t * 0.2), 5);
  let ribbon2 = fbm(ribbonP * 0.7 + vec2<f32>(-t * 0.15, t * 0.25), 4);
  let ribbon = smoothstep(0.4, 0.6, ribbonNoise) * smoothstep(0.5, 0.3, ribbon2);
  let ribbonColor = liquidRainbow(ribbonNoise * 4.0 + t * 0.1 + audioColor);
  color += ribbonColor * ribbon * 0.5 * intensity;

  // ---- LAYER 8: Bright caustic highlights ----
  let causticP = centered * 8.0 * scale + t * 0.3;
  let caustic = pow(fbm(causticP, 4), 6.0) * 3.0;
  let caustic2 = pow(fbm(causticP * 0.7 + vec2<f32>(100.0, 50.0), 3), 8.0) * 4.0;
  let causticColor = liquidRainbow(caustic * 2.0 + t * 0.08 + colorShift);
  color += causticColor * (caustic + caustic2 * 0.5) * intensity * 0.6;

  // ---- LAYER 9: Swirling vortex from mouse ----
  if (mouseDown > 0.5) {
    let md = length(centered - mouseCentered);
    let vortex = exp(-md * md * 6.0) * (0.8 + 0.2 * sin(t * 4.0));
    let vortexColor = liquidRainbow(md * 5.0 - t * 0.5 + colorShift);
    color += vortexColor * vortex * intensity * 0.8;
    
    // Spiral arms from mouse
    let vAngle = atan2((centered - mouseCentered).y, (centered - mouseCentered).x);
    let spiral = sin(vAngle * 4.0 + md * 15.0 - t * 3.0);
    color += liquidRainbow(spiral + colorShift) * exp(-md * md * 4.0) * pow(abs(spiral), 0.5) * intensity * 0.4;
  }

  // ---- POST PROCESSING ----
  // Glass-like brightness curve
  color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.85));
  
  // Bloom on bright areas
  let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let bloom = pow(max(luminance - 0.7, 0.0), 2.0) * intensity * 0.8;
  color += liquidRainbow(t * 0.05 + colorShift) * bloom;
  
  // Final saturation push
  let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  color = mix(vec3<f32>(lum), color, 1.4 + intensity * 0.3);
  
  // Tone map preserving neon
  color = color / (1.0 + color * 0.1);

  // Semantic alpha - stronger where the bright liquid effect is active
  let effectStrength = clamp(luminance * 0.6 + bubbleField * 0.4, 0.3, 0.95);
  textureStore(writeTexture, pixel, vec4<f32>(color, effectStrength));
}
