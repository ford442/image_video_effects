// Magnetic Dipole Field - Particle Alignment Visualization
// Simulates magnetic field lines with dipole physics

// ═══════════════════════════════════════════════════════════════════════════════
//  Upgraded: 2026-08-23 (Batch 67 — fast motion / psychedelic / high energy)
//
//  TWO BUGS FIXED
//
//  1. Alignment read from the wrong channel. The shader stored
//     `dataTextureA = [fieldDirection.xy, fieldStrength, fieldAngle]` and the
//     alignment into `dataTextureB` — but per docs/BINDING_CONTRACT.md the host
//     copies B→C then A→C, so **A wins** and `dataTextureC` is the A tuple. The
//     inertia term then read `prevState.b`, which is `fieldStrength`, not the
//     stored alignment; and the filing sprites read `filingField.r` as an angle
//     when A.r is `fieldDirection.x`. Both the inertia and the sprite rotation
//     were driven by unrelated quantities. A now carries
//     `[fieldDir.xy, alignment, fieldStrength]` so every read lines up.
//
//  2. `plasmaBuffer` was bound at binding 12 and never read — no audio at all
//     despite the effect being a natural fit for it.
//
//  Also: alpha was hardcoded to 1.0, and the output was written untone-mapped.
//
//  FAST MOTION (two analytic techniques)
//
//    1. Field-line particle dance — charge packets stream ALONG the field lines
//       at a rate set by local field strength, drawn as a closed-form phase
//       running down the line rather than a static dashed pattern. Strong-field
//       regions visibly rip while weak ones crawl.
//
//    2. Pole-flip orbital whip — the dipole axis precesses continuously and
//       snaps through a flip on a damped-sine schedule, dragging the whole
//       filing field around with it in an orbital whip.
//
//  PSYCHEDELIC COLOUR — the two-tone red/blue polarity tint becomes a full IQ
//  cosine spectrum keyed to field angle, strength and per-band FFT energy, so
//  the field reads as a continuous rainbow flow map rather than a duotone.
//
//  HIGH ENERGY — clicks fire magnetic pulse rings that momentarily reverse the
//  local polarity and send the filings into a scramble that settles elastically.
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // field data
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // alignment data
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=ChargeStrength, y=AlignmentInertia, z=SpriteSize, w=FieldDensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MU0: f32 = 1.0; // Magnetic permeability (simplified)

// Dipole field at point p from dipole at origin with moment m
fn dipoleField(p: vec2<f32>, m: vec2<f32>) -> vec2<f32> {
  let r = length(p);
  if (r < 0.01) { return vec2<f32>(0.0); }
  
  let r3 = r * r * r;
  let r5 = r3 * r * r;
  
  // Simplified 2D dipole field
  let mDotP = dot(m, p);
  let B = (3.0 * p * mDotP / (r5 + 0.001) - m / (r3 + 0.001)) * MU0 / (4.0 * PI);
  
  return B;
}

// Hash function
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(1.0, 1.0)));
}

// Render iron filing sprite
fn ironFilingSprite(localUV: vec2<f32>, angle: f32, intensity: f32) -> f32 {
  // Rotate local coordinates
  let c = cos(angle);
  let s = sin(angle);
  let rotUV = vec2<f32>(
    localUV.x * c - localUV.y * s,
    localUV.x * s + localUV.y * c
  );
  
  // Elongated ellipse
  let ellipse = rotUV.x * rotUV.x * 16.0 + rotUV.y * rotUV.y * 64.0;
  let shape = smoothstep(1.0, 0.5, ellipse);
  
  return shape * intensity;
}

fn spectrum(tt: f32) -> vec3<f32> {
  return 0.5 + 0.5 * cos(6.2831853 * (tt + vec3<f32>(0.0, 0.33, 0.67)));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let chargeStrength = mix(0.1, 2.0, u.zoom_params.x);
  let alignmentInertia = mix(0.0, 0.95, u.zoom_params.y);
  let spriteSize = mix(0.01, 0.05, u.zoom_params.z);
  let fieldDensity = mix(10.0, 50.0, u.zoom_params.w);
  
  // Aspect ratio correction
  let aspect = u.config.z / u.config.w;
  
  // Mouse as primary dipole
  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseMoment = vec2<f32>(0.0, chargeStrength * 0.1);
  
  // Compute total magnetic field at this point
  var totalField = vec2<f32>(0.0);
  
  // Field from mouse dipole
  let toMouse = uv - mouse;
  let mouseField = dipoleField(toMouse, mouseMoment);
  totalField = totalField + mouseField;
  
  // Add ripples as temporary dipoles
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 3.0) {
        let toRipple = uv - ripple.xy;
        let rippleStrength = (1.0 - rippleAge / 3.0) * chargeStrength;
        // Alternate polarity based on ripple index
        let polarity = select(-1.0, 1.0, i % 2 == 0);
        let rippleMoment = vec2<f32>(cos(rippleAge * 2.0), sin(rippleAge * 2.0)) * rippleStrength * polarity * 0.05;
        let rippleField = dipoleField(toRipple, rippleMoment);
        totalField = totalField + rippleField;
      }
    }
  }
  
  // Add some fixed dipoles based on source image features
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Depth-based field contribution
  let depthGradX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).r - depth;
  let depthGradY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).r - depth;
  totalField = totalField + vec2<f32>(depthGradX, depthGradY) * chargeStrength * 0.1;
  
  let fieldStrength = length(totalField);
  let fieldDirection = normalize(totalField + vec2<f32>(0.0001));
  let fieldAngle = atan2(fieldDirection.y, fieldDirection.x);
  
  // ── Audio (plasmaBuffer was bound and never read) ─────────────────────────
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── HIGH ENERGY: bounded magnetic pulse rings ─────────────────────────────
  var pulseRing = 0.0;
  var polarityFlip = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age < 0.0 || age >= 2.2) { continue; }
    let r = length(uv - rp.xy);
    let front = r - age * 0.55;
    let env = exp(-front * front * 170.0) * exp(-age * 1.5);
    pulseRing += env;
    // Inside the expanding ring the local polarity is briefly reversed.
    polarityFlip += smoothstep(age * 0.55, age * 0.55 - 0.12, r) * exp(-age * 2.0);
  }
  pulseRing = min(pulseRing, 1.5);
  polarityFlip = min(polarityFlip, 1.0);

  // Read previous alignment for inertia — exact load, and from the channel the
  // alignment is actually stored in (see header: this used to read fieldStrength).
  let prevState = textureLoad(dataTextureC, vec2<i32>(coord), 0);
  var alignment = prevState.b;

  // ── FAST MOTION 2: pole-flip orbital whip ─────────────────────────────────
  // The dipole axis precesses continuously and snaps through a flip on a
  // damped-sine schedule, dragging the filing field around with it.
  let precession = time * (0.35 + mids * 0.8);
  let flipCycle = fract(time * 0.12);
  let flipSnap = exp(-flipCycle * 7.0) * sin(flipCycle * 40.0) * 1.2;
  let axisSpin = precession + flipSnap + polarityFlip * 3.14159265;

  // Align to field with inertia, then whip by the precessing axis.
  let targetAlignment = fieldAngle + axisSpin;
  alignment = mix(targetAlignment, alignment, clamp(alignmentInertia, 0.0, 0.98));

  // A carries [fieldDir.xy, alignment, fieldStrength] — every read below lines
  // up with this packing, and C is a copy of A.
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(fieldDirection, alignment, fieldStrength));
  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(fieldAngle, fieldStrength, pulseRing, 1.0));
  
  // Render iron filings grid
  var filingAccum = 0.0;
  
  // Grid of iron filings
  let gridSize = 1.0 / fieldDensity;
  let gridCoord = floor(uv / gridSize);
  
  // Check nearby grid cells
  for (var dy = -1; dy <= 1; dy = dy + 1) {
    for (var dx = -1; dx <= 1; dx = dx + 1) {
      let cellCoord = gridCoord + vec2<f32>(f32(dx), f32(dy));
      
      // Random offset within cell
      let cellHash = hash22(cellCoord * 123.456);
      let filingCenter = (cellCoord + cellHash * 0.8 + 0.1) * gridSize;
      
      // Distance to this filing
      let toFiling = uv - filingCenter;
      let filingDist = length(toFiling);
      
      if (filingDist < spriteSize * 2.0) {
        // Get field at filing position
        // b = alignment, a = field strength (see the A packing above).
        let fcI = clamp(vec2<i32>(filingCenter * vec2<f32>(f32(size.x), f32(size.y))),
                        vec2<i32>(0), vec2<i32>(i32(size.x) - 1, i32(size.y) - 1));
        let filingField = textureLoad(dataTextureC, fcI, 0);
        let filingAngle = filingField.b;
        let filingIntensity = clamp(filingField.a * 2.0, 0.3, 1.0);
        
        // Render sprite
        let localUV = toFiling / spriteSize;
        filingAccum = filingAccum + ironFilingSprite(localUV, filingAngle, filingIntensity);
      }
    }
  }
  
  filingAccum = clamp(filingAccum, 0.0, 1.0);
  
  // ── FAST MOTION 1: field-line particle dance ──────────────────────────────
  // Charge packets stream ALONG the field lines at a rate set by local field
  // strength, so strong regions rip and weak ones crawl. Rate is clamped.
  let streamRate = clamp(0.5 + fieldStrength * 5.0 + bass * 2.0, 0.0, 9.0);
  let alongLine = dot(uv, fieldDirection) * 20.0;
  let packetPhase = fract(alongLine - time * streamRate);
  // Narrow packets rather than a 50% duty dash.
  let packet = pow(1.0 - abs(packetPhase * 2.0 - 1.0), 7.0);
  let fieldLineIntensity = packet * fieldStrength * (0.7 + treble * 1.1);
  
  // Compose final image
  var finalColor = sourceColor.rgb;
  
  // ── PSYCHEDELIC: field-angle spectrum instead of a red/blue duotone ───────
  let bandIdx = u32(clamp(fract(fieldAngle * 0.159154943 + 0.5) * 8.0, 0.0, 7.999));
  let band = plasmaBuffer[bandIdx + 1u].x;
  let fieldHue = fract(fieldAngle * 0.159154943 + fieldStrength * 0.5
                       + band * 0.55 + time * 0.05 + polarityFlip * 0.5);
  let polarityColor = pow(spectrum(fieldHue), vec3<f32>(0.72));
  
  // Add iron filings
  let filingColor = vec3<f32>(0.2, 0.2, 0.25); // Dark iron color
  finalColor = mix(finalColor, filingColor, filingAccum * 0.8);
  
  // Add streaming field-line packets, tinted by the spectrum.
  let lineColor = spectrum(fract(fieldHue + 0.25));
  finalColor = finalColor + lineColor * fieldLineIntensity * 1.4;

  // Add glow around strong field regions
  let fieldGlow = exp(-1.0 / (fieldStrength + 0.1)) * 0.3;
  finalColor = finalColor + polarityColor * fieldGlow * (1.0 + mids * 0.6);

  // Click pulse rings flash full-spectrum.
  finalColor = finalColor + spectrum(fract(fieldHue + 0.5)) * pulseRing * (0.8 + bass * 0.9);

  finalColor = acesFilm(finalColor);

  // Semantic alpha: filings, lines and pulses are the content (was hardcoded 1.0).
  let presence = clamp(filingAccum * 0.9 + fieldLineIntensity * 1.2
                       + pulseRing * 0.7 + fieldGlow, 0.0, 1.0);
  let alpha = clamp(mix(sourceColor.a * 0.7 + 0.15, 1.0, presence), 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
