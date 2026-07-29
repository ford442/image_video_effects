// ═══════════════════════════════════════════════════════════════════
//  Cursor Aura
//  Category: interactive-mouse
//  Features: mouse-driven, glow, audio-reactive, upgraded-rgba
//  Complexity: Low
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
//  Optimized: 2026-07-30 — mislabeled sliders rewired honestly:
//    z 'Edge Softness' now widens the aura edge feather (was hidden mix),
//    w 'Color Hue' now hue-rotates the glow color (was hidden pulse speed,
//    default 0.5 lands exactly on the original blue). Added click aura
//    rings, directional spectral edge shimmer, smoothed bass envelope.
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
  zoom_params: vec4<f32>,  // x=AuraSize, y=GlowIntensity, z=EdgeSoftness, w=ColorHue
  ripples: array<vec4<f32>, 50>,
};

// Cosine-palette hue remap (IQ): hue = 0.5 reproduces the original blue
// (0.0, 0.5, 1.0) exactly; sweeping 0..1 rotates through the spectrum.
fn auraGlowColor(hue: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.2831853 * (hue + vec3<f32>(0.0, 0.25, 0.5)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
  let texel = vec2<i32>(global_id.xy);
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
  let time = u.config.x;

  // ── Audio reactivity ──────────────────────────────────────────────
  let bass   = plasmaBuffer[0].x;
  let mids   = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Per-bin mids: one FFT mid bin per 4-tap direction so the edge
  // shimmer becomes directional (L/R bins drive horizontal edges,
  // T/B bins drive vertical edges).
  let midL = plasmaBuffer[2].y;
  let midR = plasmaBuffer[3].y;
  let midT = plasmaBuffer[4].y;
  let midB = plasmaBuffer[5].y;

  // Smoothed bass envelope — persistent shader state is restricted to
  // extraBuffer[133..255] (engine FFT bins occupy [5..132]).
  let prevEnv = extraBuffer[133];
  let bassEnv = mix(prevEnv, bass, 0.2);
  extraBuffer[133] = bassEnv;

  // ── Slider params (rewired to honest, shader-specific constants) ──
  //  x 'Aura Size'      → aura radius, swollen by the bass envelope
  //  y 'Glow Intensity' → glow strength, lifted by mids
  //  z 'Edge Softness'  → aura edge feather width (was a hidden mix slider)
  //  w 'Color Hue'      → hue of the glow color (was a hidden speed slider)
  let radius     = clamp(u.zoom_params.x * (1.0 + bassEnv * 0.2), 0.0, 1.0) * 0.5;
  let intensity  = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
  let feather    = mix(0.01, 0.20, u.zoom_params.z);
  let glowColor  = auraGlowColor(u.zoom_params.w);

  // The old mislabeled behaviors move to fixed sensible constants:
  let mixVal     = 0.5;                        // was z: effect/base blend
  let pulseSpeed = 2.5 * (1.0 + treble * 0.1); // was w: ~2.5 at default 0.5

  let mousePos  = u.zoom_config.yz;
  let downBoost = 1.0 + u.zoom_config.w * 0.75; // mouseDown flares the aura

  // Aspect ratio correction with guard
  let aspect = resolution.x / max(resolution.y, 0.001);
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mousePos.x * aspect, mousePos.y);

  let dist = distance(uvCorrected, mouseCorrected);

  // Pulsing radius with audio reactivity (sinusoid preserved verbatim)
  let currentRadius = max(radius + sin(time * pulseSpeed) * 0.02 * (1.0 + bass), 0.001);

  // Aura Mask — 'Edge Softness' now honestly widens the feather band
  let mask = 1.0 - smoothstep(currentRadius, currentRadius + feather, dist);

  // Base Color
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  // Effect Color (Edge Detection / High Pass) — 4-tap kernel verbatim
  let offset = 1.0 / max(resolution.x, 0.001);
  let left   = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(-offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right  = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>( offset, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let top    = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, -offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0,  offset), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  let edges = abs(left - right) + abs(top - bottom);

  // Directional spectral edge shimmer: each axis rides its own mid bins.
  let hEdge = abs(left - right) * (1.0 + 0.5 * (midL + midR));
  let vEdge = abs(top - bottom) * (1.0 + 0.5 * (midT + midB));
  let spectralEdges = hEdge + vEdge;
  let spectralTint = vec3<f32>(
    0.5 * (midL + midT),
    0.5 * (midR + midB),
    0.5 * (midL + midB)
  );

  let glowStrength = intensity * (1.0 + bassEnv * 0.5) * downBoost;
  let effectColor = mix(edges, spectralEdges, 0.6) * 2.0
                  + vec4<f32>(glowColor * glowStrength, glowStrength)
                  + vec4<f32>(spectralTint * intensity * 0.25, 0.0);

  // Combine — fixed 50/50 blend (the old hidden z behavior, now constant)
  let inside = mix(baseColor, effectColor, mixVal);

  // Treble shimmer: fine spectral sparkle across the aura interior
  let shimmerPhase = dot(uvCorrected, vec2<f32>(37.0, 53.0)) + time * (3.0 + treble * 4.0);
  let auraFill = glowColor * mask * intensity * 0.15 * (0.5 + 0.5 * sin(shimmerPhase) * treble);

  // Glowing ring at the edge — hue-tinted, white core retained
  let ring = smoothstep(currentRadius - 0.01, currentRadius, dist) * smoothstep(currentRadius + 0.01, currentRadius, dist);
  let ringStrength = ring * intensity * 2.0 * (1.0 + bassEnv) * downBoost;
  let ringColor = vec4<f32>(mix(vec3<f32>(1.0), glowColor, 0.6) * ringStrength, ringStrength);

  // Click aura rings: each live ripple spawns an expanding secondary aura
  // ring at its click point, decaying over ~1.5 s.
  let rippleCount = min(u32(u.config.y), 50u);
  var clickRings = vec3<f32>(0.0);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age > 0.0 && age < 1.5) {
      let clickPos  = vec2<f32>(ripple.x * aspect, ripple.y);
      let clickDist = distance(uvCorrected, clickPos);
      let ringRadius = age * 0.35;             // expansion speed
      let ringDecay  = 1.0 - age / 1.5;        // ~1.5 s lifetime
      let bandWidth  = 0.015 + age * 0.03;     // band widens as it expands
      let band = 1.0 - smoothstep(0.0, bandWidth, abs(clickDist - ringRadius));
      clickRings = clickRings + glowColor * band * ringDecay * ringDecay;
    }
  }

  // Ring alpha can exceed 1.0 pre-clamp — the final clamp handles it.
  let preFinal = mix(baseColor, inside, mask) + ringColor
               + vec4<f32>(auraFill + clickRings * intensity * 2.0, 0.0);
  let finalAlpha = clamp(preFinal.a, 0.0, 1.0);
  let finalColor = vec4<f32>(preFinal.rgb, finalAlpha);

  // Depth read and mandatory writes
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  textureStore(writeTexture, texel, finalColor);
  textureStore(dataTextureA, global_id.xy, finalColor);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
