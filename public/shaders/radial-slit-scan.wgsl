// ═══════════════════════════════════════════════════════════════════
//  Radial Slit Scan — Visualist Enhanced Edition
//  Category: interactive-mouse
//  Features: mouse-driven, feedback, audio-reactive, upgraded-rgba,
//            cosine-palette, volumetric-glow, aces-tone-map, oklab-mixing
//  Complexity: Medium
//  Upgraded: 2026-06-28
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

// ── Color Science ─────────────────────────────────────────────────

// Inigo Quilez cosine palette
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
  return a + b * cos(6.28318 * (c * t + d));
}

// OkLab color space for smooth mixing (prevents muddy mid-tones)
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(2.2));
}

fn linearToSrgb(c: vec3<f32>) -> vec3<f32> {
  return pow(c, vec3<f32>(1.0 / 2.2));
}

fn linearToOkLab(c: vec3<f32>) -> vec3<f32> {
  let lms = mat3x3<f32>(
    0.8189330101, 0.3618667424, -0.1288597137,
    0.0329845436, 0.9293118715, 0.0361456387,
    0.0482003018, 0.2643662691, 0.6338517070
  ) * c;
  let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0 / 3.0));
  return mat3x3<f32>(
    0.2104542553, 0.7936177850, -0.0040720468,
    1.9779984951, -2.4285922050, 0.4505937099,
    0.0259040371, 0.7827717662, -0.8086757660
  ) * lms_;
}

fn okLabToLinear(c: vec3<f32>) -> vec3<f32> {
  let lms_ = mat3x3<f32>(
    1.0, 0.3963377774, 0.2158037573,
    1.0, -0.1055613458, -0.0638541728,
    1.0, -0.0894841775, -1.2914855480
  ) * c;
  let lms = lms_ * lms_ * lms_;
  return mat3x3<f32>(
    4.0767416621, -3.3077115913, 0.2309699292,
    -1.2684380046, 2.6097574011, -0.3413193965,
    -0.0041960863, -0.7034186147, 1.7076147010
  ) * lms;
}

fn okLabMix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
  let la = linearToOkLab(srgbToLinear(a));
  let lb = linearToOkLab(srgbToLinear(b));
  return linearToSrgb(okLabToLinear(mix(la, lb, t)));
}

// ACES filmic tone mapping
fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return (x * (a * x + b)) / (x * (c * x + d) + e);
}

// Hue-preserving clamp before ACES
fn huePreserveClamp(c: vec3<f32>) -> vec3<f32> {
  let maxc = max(max(c.r, c.g), c.b);
  if (maxc > 1.0) {
    return c / maxc;
  }
  return c;
}

// IGN blue-noise dither (kills 8-bit banding)
fn ignDither(p: vec2<f32>, t: f32) -> f32 {
  let fp = fract(p + t * 0.07);
  return fract(52.9829189 * fract(0.06711056 * fp.x + 0.00583715 * fp.y));
}

// ── Atmosphere ────────────────────────────────────────────────────

// Volumetric glow / fog
fn volumetricGlow(dist: f32, scanDist: f32, width: f32, density: f32) -> f32 {
  let fogDist = abs(dist - scanDist);
  return exp(-density * fogDist * 8.0) * smoothstep(width * 4.0, 0.0, fogDist);
}

// Helper for chromatic spread based on distance from scan ring
fn spectralSpread(dist: f32, scanDist: f32, width: f32) -> f32 {
    let edgeProximity = 1.0 - smoothstep(0.0, width * 2.0, abs(dist - scanDist));
    return edgeProximity;
}

// ── Main ──────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let scan_speed = u.zoom_params.x;
    let scan_width = u.zoom_params.y;
    let decay = u.zoom_params.z;
    let softness = u.zoom_params.w;

    // Calculate aspect ratio corrected distance from mouse
    let aspect = resolution.x / resolution.y;

    // Handle mouse not present (negative values)
    var center = mouse;
    if (center.x < 0.0) {
        center = vec2<f32>(0.5, 0.5);
    }

    let dist_vec = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Scan radius moves over time — audio modulates speed
    let loop_speed = mix(0.1, 2.0, scan_speed) * (1.0 + bass * 0.3);
    let radius = fract(time * loop_speed);

    // Scale radius to cover screen
    let max_dist = 1.5 * aspect;
    let current_scan_dist = radius * max_dist;

    let delta = abs(dist - current_scan_dist);
    let width = scan_width * 0.5;

    let current_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    // dataTextureC contains the previous frame (feedback)
    var history_color = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);

    // Determine if we are updating this pixel
    let half_width = width * 0.5;
    let soft_edge = softness * half_width;

    var update_factor = 0.0;

    if (delta < half_width) {
        if (softness > 0.001) {
            update_factor = smoothstep(half_width, half_width - soft_edge, delta);
        } else {
            update_factor = 1.0;
        }
    }

    var final_color = mix(history_color, current_color, update_factor);

    // Apply decay (slowly fade to current time everywhere)
    if (decay > 0.0) {
        final_color = mix(final_color, current_color, decay * 0.05);
    }

    // ═══════════════════════════════════════════════════════════════
    //  VISUALIST ENHANCEMENTS
    // ═══════════════════════════════════════════════════════════════

    // Cosine palette for scan ring color cycling — driven by time + mids
    let paletteSpeed = time * 0.15 + mids * 2.0;
    let paletteT = fract(radius + paletteSpeed);
    let scanColor = palette(paletteT,
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(1.0, 1.0, 1.0),
      vec3<f32>(0.00, 0.33, 0.67)
    );
    // Audio-reactive palette shift
    let scanColorAudio = palette(paletteT + bass * 0.5,
      vec3<f32>(0.5, 0.5, 0.5),
      vec3<f32>(0.5 + treble * 0.3, 0.5, 0.5 + bass * 0.3),
      vec3<f32>(1.0 + mids * 0.5, 1.0, 0.8),
      vec3<f32>(0.00, 0.33, 0.67)
    );

    // Volumetric glow around the scan ring
    let glowIntensity = volumetricGlow(dist, current_scan_dist, width, 1.5 + bass * 2.0);
    let glowColor = okLabMix(scanColor, scanColorAudio, bass);

    // Add scan ring glow to final color
    var rgb = final_color.rgb;
    rgb = rgb + glowColor * glowIntensity * (0.4 + bass * 0.6) * update_factor;

    // Chromatic aberration on the scan edge
    let chromaOffset = spectralSpread(dist, current_scan_dist, width);
    let chromaR = textureSampleLevel(readTexture, u_sampler, uv + chromaOffset * vec2<f32>(1.0, 0.0) * 0.008, 0.0).r;
    let chromaB = textureSampleLevel(readTexture, u_sampler, uv - chromaOffset * vec2<f32>(1.0, 0.0) * 0.012, 0.0).b;
    rgb = vec3<f32>(
      mix(rgb.r, chromaR, glowIntensity * 0.3),
      rgb.g,
      mix(rgb.b, chromaB, glowIntensity * 0.3)
    );

    // Split-tone: shadows cool, highlights warm
    let luma = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let shadowColor = vec3<f32>(0.15, 0.25, 0.45); // cool blue shadows
    let highlightColor = vec3<f32>(0.95, 0.75, 0.45); // warm gold highlights
    rgb = okLabMix(rgb, shadowColor, (1.0 - luma) * 0.25);
    rgb = okLabMix(rgb, highlightColor, smoothstep(0.5, 1.0, luma) * 0.2);

    // HDR workflow: let values exceed 1.0 before tone mapping
    rgb = rgb * (1.0 + treble * 0.5);

    // Hue-preserving clamp before ACES
    rgb = huePreserveClamp(rgb);

    // ACES filmic tone mapping
    rgb = aces(rgb);

    // IGN blue-noise dither before textureStore
    let dither = ignDither(vec2<f32>(global_id.xy), time) * 0.0039; // 1/256
    rgb = rgb + vec3<f32>(dither);

    // Bloom-based alpha
    let bloomAlpha = pow(max(0.0, luma - 0.6), 2.0) * 3.0;
    let alpha = clamp(final_color.a + glowIntensity * 0.3 + bloomAlpha * 0.2, 0.0, 1.0);

    // Premultiplied alpha writeback
    let outColor = vec4<f32>(rgb * alpha, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);

    // Write to history for next frame
    textureStore(dataTextureA, global_id.xy, outColor);

    // Pass depth through
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
