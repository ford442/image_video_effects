// ═══════════════════════════════════════════════════════════════════
//  RGB Glitch Trail — Alpha Translucency Upgrade
//  Category: retro-glitch
//  Features: mouse-driven, chromatic, trail, audio-reactive, upgraded-rgba
//  Complexity: Medium-High
//  Created: 2026-05-10
//  Upgraded: 2026-05-17
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ── Domain-Warped FBM ────────────────────────────────────────
fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)), fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)), fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}

// ── Turbulent Displacement Field ─────────────────────────────
fn turbulentFBM(p: vec2<f32>, t: f32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 4; i = i + 1) {
        let n = valueNoise(p * freq + t * 0.1);
        sum = sum + amp * abs(n * 2.0 - 1.0);
        freq = freq * 2.3;
        amp = amp * 0.5;
    }
    return sum;
}

// ── Spectral Tint ────────────────────────────────────────────
fn wavelengthToRGB(w: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(vec3<f32>(w, w + 2.09, w + 4.18));
}

// ── Physical Decay Equation ──────────────────────────────────
fn temporalDecay(intensity: f32, decayRate: f32, time: f32) -> f32 {
  return intensity * pow(decayRate, 1.0 + fract(time * 0.1) * 0.1);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  var uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Audio reactivity
  let bass = plasmaBuffer[0].x;

  // Parameters
  let decayRate = 0.9 + u.zoom_params.x * 0.09;
  let radius = 0.05 + u.zoom_params.y * 0.2;
  let shiftStrength = u.zoom_params.z * 0.05 * (1.0 + bass * 2.0);
  let chaos = clamp(u.zoom_params.w * (1.0 + bass * 0.5), 0.0, 1.0);

  // Mouse
  var mouse = u.zoom_config.yz;
  let dist = distance(uv, mouse);

  // Persistence (Glitch Intensity)
  var intensity = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  // Decay with physical falloff
  intensity = temporalDecay(intensity, decayRate, time);

  // Add from mouse
  if (dist < radius) {
     let val = smoothstep(radius, radius * 0.2, dist);
     intensity = min(1.0, intensity + val);
  }

  // Organic displacement via domain-warped FBM
  let warp = warpedFBM(uv * 4.0, time * 0.2);
  let warpAngle = warp * 6.2831 + time * 0.3;
  let warpDir = vec2<f32>(cos(warpAngle), sin(warpAngle));

  // Turbulent layer for high-frequency detail
  let turb = turbulentFBM(uv * 8.0, time * 0.4);

  // Single smooth displacement field
  let shift = intensity * shiftStrength;
  let smoothOffset = warpDir * shift * (1.0 + chaos * 0.5) + warpDir * turb * shift * 0.3;

  // Displacement magnitude for alpha encoding
  let displacementMagnitude = length(smoothOffset) / max(shiftStrength, 0.001);

  // Alpha = glitch intensity * temporal persistence
  let alpha = clamp(displacementMagnitude * intensity * 2.0, 0.0, 1.0);

  // Single UV sample — no per-channel splitting
  let displacedUV = clamp(uv + smoothOffset, vec2<f32>(0.0), vec2<f32>(1.0));
  let baseColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;

  // Spectral tint via mix, NOT per-channel sampling
  let spectralTint = wavelengthToRGB(time * 0.5 + chaos * 3.14 + warp * 2.0);
  let tintStrength = chaos * intensity;
  let color = mix(baseColor, baseColor * spectralTint, alpha * tintStrength);

  // Write state as trail with alpha-translucency
  let trailHue = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(0.0, 1.0, 1.0), chaos);
  let trail_color = vec4<f32>(trailHue * intensity, intensity);
  textureStore(dataTextureA, global_id.xy, trail_color);

  // Streak corruption with unified displacement field
  var finalColor = color;
  if (chaos > 0.0 && intensity > 0.5) {
     let seed = uv.y * 100.0 + time;
     let noise = fract(sin(seed) * 43758.5453);
     if (noise > 0.9) {
        let streakOffset = smoothOffset + vec2<f32>(noise * 0.05, 0.0);
        let streakUV = clamp(uv + streakOffset, vec2<f32>(0.0), vec2<f32>(1.0));
        let streakColor = textureSampleLevel(readTexture, u_sampler, streakUV, 0.0).rgb;
        finalColor = mix(finalColor, streakColor, alpha * chaos);
     }
  }

  // Depth pass-through
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
}
