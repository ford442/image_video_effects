// ═══════════════════════════════════════════════════════════════════
//  Prism Displacement — Anamorphic Spectral Lens Dispersion
//  Category: distortion
//  Features: mouse-driven, audio-reactive, chromatic-aberration,
//            temporal-lens-rotation, chromatic-angular-dispersion,
//            depth-magnification, spectral-wavelength-sampling,
//            lens-distortion, fresnel-rim, semantic-alpha, ACES
//  Ideas:    1. white-balanced spectrum — 7 taps over 400–700 nm, each channel normalised
//               by its summed weight, so white stays white (HEAD summed to a red cast)
//            2. Cauchy fan — the tap offset follows n(λ) ∝ 1/λ², so blue bends hardest and
//               the fan's anamorphic axis turns with Rotation Speed
//            3. Fresnel lens rim — grazing reflection at the lens edge (replaces cosine palette)
//  Complexity: High
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
  zoom_params: vec4<f32>,  // x=ZoomAmount, y=ChromaticAmount, z=RotationSpeed, w=DepthWeight
  ripples: array<vec4<f32>, 50>,
};

fn lensDistort(uv: vec2<f32>, center: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
  let d = uv - center;
  let r2 = dot(d, d);
  let factor = 1.0 + k1 * r2 + k2 * r2 * r2;
  return center + d * factor;
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
  if (lambda < 440.0) {
    return vec3<f32>(-(lambda - 440.0) / 60.0, 0.0, 1.0);
  } else if (lambda < 490.0) {
    return vec3<f32>(0.0, (lambda - 440.0) / 50.0, 1.0);
  } else if (lambda < 510.0) {
    return vec3<f32>(0.0, 1.0, -(lambda - 510.0) / 20.0);
  } else if (lambda < 580.0) {
    return vec3<f32>((lambda - 510.0) / 70.0, 1.0, 0.0);
  } else if (lambda < 645.0) {
    return vec3<f32>(1.0, -(lambda - 645.0) / 65.0, 0.0);
  } else {
    return vec3<f32>(1.0, 0.0, 0.0);
  }
}

fn sampleSpectral(uv: vec2<f32>, dir: vec2<f32>, dispersion: f32) -> vec3<f32> {
  var acc = vec3<f32>(0.0);
  var wsum = vec3<f32>(0.0);
  for (var i = 0; i < 7; i = i + 1) {
    let t = f32(i) / 6.0;
    // Idea 1: 400–700 nm and per-channel normalisation. A flat white input
    // comes out white, where the old 380–780 nm sum came out (0.72, 0.31, 0.29).
    let lambda = 400.0 + t * 300.0;
    // Idea 2: Cauchy fan. n(λ) − n(550) ∝ 550²/λ² − 1, so violet swings about
    // three times further than deep red, as through real glass. The sign keeps
    // HEAD's orientation (blue toward −dir); the scale matches its blue extreme.
    let cauchy = 302500.0 / (lambda * lambda) - 1.0;
    let shift = -dir * cauchy * 155.0 * dispersion;
    let sample = textureSampleLevel(readTexture, u_sampler, clamp(uv + shift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    // Trim the violet red lobe so red swings opposite blue (a rainbow fan).
    var w = wavelengthToRGB(lambda);
    if (lambda < 440.0) { w.r *= 0.3; }
    acc += sample * w;
    wsum += w;
  }
  return acc / max(wsum, vec3<f32>(1e-3));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Raw pointer: the old extraBuffer[133..138] spring raced (pixel (0,0) wrote
  // while every other pixel read) and the buffer is re-uploaded each frame.
  let mouse = rawMouse;

  // Exact parameter contracts
  let nParams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
  let zoomAmount = nParams.x;
  let chromaticAmount = nParams.y;
  let rotationSpeed = nParams.z;
  let depthWeight = nParams.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var p = (uv - mouse) * vec2<f32>(aspect, 1.0);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleWarp = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleWarp += rDir * wave * 0.04;
    }
  }
  p += rippleWarp;

  let len = length(p);

  // HEAD rotated each pixel by −(angle + t), which maps every pixel at a given
  // radius to the same point and collapses the image into concentric rings.
  // Now the lens sways by a bounded angle that fades out with radius.
  let lensFalloff = 1.0 - smoothstep(0.0, 0.6, len);
  let rotAngle = (sin(time * rotationSpeed * 0.5) * 0.35 + held * 0.3) * lensFalloff;
  let cosR = cos(rotAngle);
  let sinR = sin(rotAngle);
  var rotated = vec2<f32>(cosR * p.x + sinR * p.y, -sinR * p.x + cosR * p.y);
  rotated.x /= aspect;
  var rotatedUV = rotated + mouse;

  let z = len * zoomAmount * (1.0 + depth * depthWeight * 0.5) * (1.0 + bass * 0.25);
  let zoomedUV = mouse + (rotatedUV - mouse) * max(1.0 - z, 0.05);

  let k1 = (zoomAmount - 0.5) * 0.3;
  let k2 = -zoomAmount * 0.1;
  let lensedUV = lensDistort(zoomedUV, mouse, k1, k2);

  // Anamorphic stretch of the dispersion fan along an axis that turns with
  // Rotation Speed (chromatic rotation).
  var dispDir = normalize(p + vec2<f32>(1e-4));
  let fanAngle = time * rotationSpeed * 0.5;
  let anaAxis = vec2<f32>(cos(fanAngle), sin(fanAngle));
  dispDir = dispDir + anaAxis * dot(dispDir, anaAxis) * chromaticAmount * 3.0;
  dispDir.x /= aspect;

  let dispersion = chromaticAmount * 0.00008 * (1.0 + treble * 0.4);
  var color = sampleSpectral(lensedUV, dispDir, dispersion);

  let baseColor = textureSampleLevel(readTexture, u_sampler, clamp(lensedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Idea 3: Fresnel lens rim. The lens is a glass dome whose radius follows
  // Zoom Amount. Toward its edge the view becomes grazing, so Schlick
  // reflectance climbs and the rim mirrors the scene outside the lens.
  let lensR = 0.25 + zoomAmount * 0.25;
  let rr = len / lensR;
  let inLens = 1.0 - smoothstep(0.96, 1.04, rr);
  let cosV = sqrt(max(1.0 - rr * rr, 0.0));
  let rimF = (0.04 + 0.96 * pow(1.0 - cosV, 5.0)) * inLens;
  // Mirror across the rim: a point at radius r samples the scene at 2R − r.
  let outsideUV = clamp(mouse + (uv - mouse) * ((2.0 - rr) / max(rr, 0.05)),
                        vec2<f32>(0.0), vec2<f32>(1.0));
  let rimRefl = textureSampleLevel(readTexture, u_sampler, outsideUV, 0.0).rgb;
  let edgeGlow = rimF * smoothstep(0.2, 0.5, zoomAmount);
  color = mix(color, rimRefl * (1.1 + bass * 0.3) + vec3<f32>(0.04, 0.05, 0.07), edgeGlow * (0.4 + chromaticAmount * 0.5));

  // Exact dataTextureC persistence, blended in display space (C holds ACES output).
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  let finalRGB = mix(aces(color), prevC, 0.08);
  let finalAlpha = clamp(mix(baseColor.a, 1.0, edgeGlow * 0.5 + len * 0.1) + held * 0.1, 0.15, 1.0);
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
