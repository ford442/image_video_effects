// ═══════════════════════════════════════════════════════════════════
//  Vortex Cathedral — God Rays & Volumetric Beams Enhanced
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, volumetric-god-rays,
//            starburst-diffraction, chromatic-aberration, light-attenuation
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-06-06, 2026-06-28, 2026-09-27
//  Ideas: arch-gated crepuscular shafts; stained-glass sector tint; counter-rotating second vault
//  A packing: ACES display RGBA (HEAD stored arches/rings/centerLight but read C back as colour)
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

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

// Stained-glass jewel table: one flat colour per pane (hand-picked, not a cosine palette).
fn stainedGlass(idx: f32) -> vec3<f32> {
  let h = fract(sin(idx * 127.1 + 311.7) * 43758.5453);
  let s = floor(h * 5.0);
  var c = vec3<f32>(0.85, 0.12, 0.22);          // ruby
  if (s >= 4.0) { c = vec3<f32>(0.55, 0.22, 0.95); }      // violet
  else if (s >= 3.0) { c = vec3<f32>(0.15, 0.75, 0.42); } // emerald
  else if (s >= 2.0) { c = vec3<f32>(0.2, 0.36, 1.0); }   // sapphire
  else if (s >= 1.0) { c = vec3<f32>(1.0, 0.7, 0.2); }    // amber
  return c;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ Volumetric God Rays (ray march toward light source) ═══
// vault = (archCount, spinRate, twist, aspect). Returns (tint-weighted rgb, scalar intensity).
fn godRays(uv: vec2<f32>, lightPos: vec2<f32>, density: f32, time: f32,
           vault: vec4<f32>, mouse: vec2<f32>) -> vec4<f32> {
  let toLight = lightPos - uv;
  let rayLen = length(toLight);
  let rayDir = toLight / max(rayLen, 1e-5);
  let steps = 20.0;
  var rayIntensity = 0.0;
  var tintAcc = vec3<f32>(0.0);

  for (var i = 0.0; i < steps; i = i + 1.0) {
    let t = i / steps;
    let samplePos = uv + rayDir * rayLen * t;
    // Density modulation: more dust in center
    let distFromCenter = length(samplePos - vec2<f32>(0.5));
    let dustDensity = exp(-distFromCenter * 3.0) * density;
    // Noise for volumetric variation
    let noise = fract(sin(dot(samplePos * 8.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let attenuation = 1.0 - t * t; // Stronger near light source

    // IDEA 1: arch-gated crepuscular shafts - same spinA formula in the sample's polar coords
    var q = samplePos * 2.0 - 1.0;
    q.x = q.x * vault.w;
    q = q - mouse * 0.2;
    let qr = max(length(q), 1e-5);
    let x = (atan2(q.y, q.x) + time * vault.y - qr * vault.z) * vault.x;
    let pier = smoothstep(0.75, 1.0, abs(sin(x)));
    let gate = (1.0 - 0.85 * pier) * 1.3; // light falls between the piers

    let w = dustDensity * attenuation * (0.5 + noise * 0.5) * gate;
    // IDEA 2: stained-glass tint - one jewel colour per gap pane, fading out at the sanctum
    let glassMix = smoothstep(0.05, 0.35, qr) * 0.6;
    let glass = mix(vec3<f32>(1.0), stainedGlass(floor(x / PI + 0.5)) * 1.8, glassMix);
    rayIntensity = rayIntensity + w;
    tintAcc = tintAcc + w * glass;
  }
  return vec4<f32>(tintAcc / steps, rayIntensity / steps);
}

// ═══ Light Attenuation ═══
fn lightAttenuation(d: f32, k: f32, q: f32) -> f32 {
  return 1.0 / (1.0 + k * d + q * d * d);
}

// ═══ Starburst Diffraction Spikes (6-pointed) ═══
fn starburstSpikes(uv: vec2<f32>, center: vec2<f32>, intensity: f32, time: f32) -> f32 {
  let d = uv - center;
  let r = length(d);
  let angle = atan2(d.y, d.x);
  var spikes = 0.0;
  // 6-pointed starburst
  for (var i = 0; i < 6; i = i + 1) {
    let spikeAngle = f32(i) * PI / 3.0 + time * 0.1;
    let angleDiff = angle - spikeAngle;
    let spike = pow(max(0.0, cos(angleDiff * 3.0)), 8.0) * exp(-r * 6.0);
    spikes = spikes + spike;
  }
  return spikes * intensity;
}

// ═══ Chromatic Aberration at Edges ═══
fn chromaticAberration(uv: vec2<f32>, center: vec2<f32>, strength: f32) -> vec3<f32> {
  let d = uv - center;
  let radialDist = length(d);
  let offset = radialDist * strength;
  let rUV = uv + d * offset * 1.2;
  let gUV = uv + d * offset * 0.6;
  let bUV = uv + d * offset * 2.0;
  return vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
    textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g,
    textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b
  );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  // Stateless bass (extraBuffer[0] is the raw uploaded bass; no shader-side state, no extraBuffer writes)
  let smoothBass = max(bass, 0.0);
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let archCount = mix(4.0, 22.0, u.zoom_params.x);
  let spin = mix(0.1, 3.0, u.zoom_params.y);
  let haze = mix(0.0, 1.0, u.zoom_params.z);
  let sanctum = mix(0.1, 1.5, u.zoom_params.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p - mouse * 0.2;

  let r = max(length(p), 1e-5);
  let a = atan2(p.y, p.x);
  let spinRate = spin * (1.0 + smoothBass * 0.7);
  let twist = 1.8 + mids;
  let vault = vec4<f32>(archCount, spinRate, twist, aspect);
  let spinA = a + time * spinRate - r * twist;
  let sector = sin(spinA * archCount);
  let arches = smoothstep(0.75, 1.0, abs(sector));

  let rings = 0.5 + 0.5 * sin(r * 26.0 - time * (2.0 + treble * 5.0));
  let columns = arches * (0.4 + rings * 0.6);
  let centerLight = exp(-r * r * (12.0 / sanctum));
  let fog = exp(-r * 2.5) * haze;

  // Chromatic cathedral separation: R arches, G columns, B fog
  let chromaR = arches * (1.0 + treble * 0.15);
  let chromaG = columns * (1.0 + mids * 0.1);
  let chromaB = fog * (1.0 + smoothBass * 0.1);

  var color = vec3<f32>(0.02, 0.01, 0.03);
  // IDEA 2: each pier is one stained-glass pane (tint fades toward the sanctum)
  let pierGlass = stainedGlass(floor(spinA * archCount / PI));
  let glassFade = smoothstep(0.05, 0.35, r);
  color = color + mix(vec3<f32>(0.42, 0.15, 0.65), pierGlass * 0.75, 0.4 * glassFade) * chromaR;
  color = color + mix(vec3<f32>(0.75, 0.55, 0.85), pierGlass, 0.3 * glassFade) * chromaG;
  color = color + vec3<f32>(0.15, 0.3, 0.55) * chromaB;
  color = color + vec3<f32>(0.9, 0.7, 1.0) * centerLight * (0.5 + smoothBass);

  // IDEA 3: counter-rotating second vault ring at r ~ 0.6 (half arch density, opposite spin/twist)
  let spinB = a - time * spinRate * 0.7 + r * (1.2 + mids * 0.5);
  let xB = spinB * archCount * 0.5;
  let dB = (r - 0.6) / 0.13;
  let vaultB = smoothstep(0.8, 1.0, abs(sin(xB))) * exp(-dB * dB);
  color = color + stainedGlass(floor(xB / PI)) * 0.55 * vaultB * (0.5 + rings * 0.5);

  // ═══ VOLUMETRIC GOD RAYS ═══
  // Light source at center (sanctum), ray marching toward it
  let lightPos = vec2<f32>(0.5) + mouse * 0.1; // Mouse shifts light center slightly
  let rayDensity = 0.8 + haze * 0.5 + smoothBass * 0.3;
  let rays1 = godRays(uv, lightPos, rayDensity, time, vault, mouse);
  let godRayIntensity = rays1.w;
  // Warm golden god rays (cathedral sunlight), stained by the panes they cross
  let rayColor = vec3<f32>(1.0, 0.85, 0.6) * rays1.rgb * (0.5 + smoothBass * 0.5) * sanctum;
  color = color + rayColor;

  // Secondary volumetric beams from arches (cooler blue-white)
  let archLightPos = vec2<f32>(0.5 + sin(time * 0.3) * 0.3, 0.5 + cos(time * 0.2) * 0.2);
  let rays2 = godRays(uv, archLightPos, rayDensity * 0.5, time, vault, mouse);
  let archRayColor = vec3<f32>(0.7, 0.8, 1.0) * rays2.rgb * 0.3 * haze;
  color = color + archRayColor;

  // Light attenuation: falloff from center
  let atten = lightAttenuation(r, 1.0, 2.0);
  color = color * (0.6 + atten * 0.4);

  // Temporal persistence: previous light bleeds for ghost cathedral
  let prev = textureLoad(dataTextureC, coord, 0);
  let prevLight = prev.rgb;
  color = mix(color, prevLight * 0.92, 0.04 + mids * 0.015);

  // ═══ ENHANCED SANCTUM GLOW ═══
  // Multi-layered glow at the center with audio reactivity
  let sanctumGlow = centerLight * (1.0 + smoothBass * 1.2) * sanctum;
  let glowColor1 = vec3<f32>(1.0, 0.9, 0.7) * sanctumGlow * 0.4; // Warm core
  let glowColor2 = vec3<f32>(0.8, 0.6, 1.0) * sanctumGlow * 0.2 * mids; // Purple halo
  color = color + glowColor1 + glowColor2;

  // ═══ STARBURST DIFFRACTION SPIKES ═══
  // 6-pointed starburst from the bright sanctum center
  let starburst = starburstSpikes(uv, lightPos, centerLight * 0.8 * (1.0 + treble), time);
  let starburstColor = vec3<f32>(1.0, 0.95, 0.85) * starburst * (0.5 + smoothBass * 0.5);
  color = color + starburstColor;

  // ═══ CHROMATIC ABERRATION AT EDGES ═══
  let edgeDist = length(p);
  let chromaticStrength = smoothstep(0.3, 1.0, edgeDist) * 0.03 * (1.0 + treble * 0.2);
  if (chromaticStrength > 0.001) {
    let chromaticColor = chromaticAberration(uv, lightPos, chromaticStrength);
    color = mix(color, chromaticColor, smoothstep(0.3, 0.8, edgeDist) * 0.3);
  }

  let presence = sat(columns * 0.85 + vaultB * 0.4 + centerLight * 0.9 + fog * 0.3);
  let depth = sat(0.92 - centerLight * 0.7 - columns * 0.25 + haze * 0.1);

  // Bloom-weighted alpha: light intensity drives compositing
  let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = sat(0.1 + presence * 0.9 + luma * 0.2 + godRayIntensity * 0.15);

  color = acesToneMap(color * 1.1);

  // Premultiplied alpha writeback
  textureStore(writeTexture, coord, vec4<f32>(color * alpha, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha)); // A = ACES display RGBA (non-premultiplied)
}
