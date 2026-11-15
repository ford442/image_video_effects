// ═══════════════════════════════════════════════════════════════════
//  Kimi Liquid Glass — refractive thickness field with caustic optics.
//  Category: liquid-effects
//  Upgraded: 2026-09-21, 2026-11-15
//  Ideas: total internal reflection on steep flanks; rising seed bubbles; Cauchy dispersion (§12.2F); ripple-driven signed-focus caustic (native)
//  A packing: raw — R=height, G=velocity, B=thickness, A=coverage.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;
// Cauchy B coefficient = dispersion amplitude x DISP_K (µm²-scale, ~100x real crown glass on purpose: a photo needs a
// visible fringe). 130 reproduces the old fixed +-delta fringe magnitude (~0.0011 uv mean at the saved defaults); the
// shipped 200 is ~1.5x that so the non-linear fringe actually reads (flagged in NOTES as a default-look change).
const DISP_K: f32 = 200.0;
const CONVERGE_EXTRA: f32 = 0.6; // extra caustic-line weight on converging curvature (HEAD |lap| treated both signs alike)
const FOCUS_GAIN: f32 = 0.28;   // transmitted-photo gain where the surface focuses light
const DIVERGE_SHADE: f32 = 0.28; // transmitted-photo loss where it dishes (the dim twin of a caustic)

fn clampPixel(p: vec2<i32>, dims: vec2<i32>) -> vec2<i32> { return clamp(p, vec2<i32>(0), dims - vec2<i32>(1)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
// Saturating, zero-slope-free response: 0 at 0 (no gain from numerical-noise curvature), 1 at 1, broad in between.
fn focusResp(x: f32) -> f32 { return x * 1.3 / (x + 0.3); }
fn schlick(cosTheta: f32, f0: f32) -> f32 { return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let pixel = vec2<i32>(gid.xy); let dims = vec2<i32>(resolution);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution; let time = u.config.x;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  // Saved slots: intensity, speed, scale, detail.
  let intensity = u.zoom_params.x; let speed = mix(0.25, 1.55, u.zoom_params.y);
  let scale = mix(3.0, 13.0, u.zoom_params.z); let detail = u.zoom_params.w;

  let c = textureLoad(dataTextureC, pixel, 0);
  let l = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-1, 0), dims), 0);
  let r = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(1, 0), dims), 0);
  let d = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -1), dims), 0);
  let t = textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, 1), dims), 0);
  let initialized = c.a > 0.00001;
  let cells = floor(uv * scale * vec2<f32>(aspectVec.x, 1.0));
  let seedHeight = 0.14 + hash21(cells) * 0.035;
  var height = select(seedHeight, c.r, initialized); var velocity = select(0.0, c.g, initialized);
  var thickness = select(0.22, c.b, initialized);
  let hL = select(seedHeight, l.r, initialized); let hR = select(seedHeight, r.r, initialized);
  let hD = select(seedHeight, d.r, initialized); let hU = select(seedHeight, t.r, initialized);
  let laplacian = hL + hR + hD + hU - 4.0 * height;
  // Wide-stencil signed curvature for Idea 4. The hashed seed cells are a persistent step pattern (velocity is
  // restored toward seedHeight), so the 1-px laplacian is dominated by thin tile-edge lines; a stencil of ~res/96 px
  // averages most of those away while the broad ripple curvature survives. Normalised to a 192-px render's px^2 so the
  // gain does not depend on resolution.
  let rW = max(1, i32(round(resolution.y / 96.0)));
  let wL = select(seedHeight, textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(-rW, 0), dims), 0).r, initialized);
  let wR = select(seedHeight, textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(rW, 0), dims), 0).r, initialized);
  let wD = select(seedHeight, textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, -rW), dims), 0).r, initialized);
  let wU = select(seedHeight, textureLoad(dataTextureC, clampPixel(pixel + vec2<i32>(0, rW), dims), 0).r, initialized);
  let lapWide = (wL + wR + wD + wU - 4.0 * height) * (resolution.y * resolution.y) / (36864.0 * f32(rW * rW));

  let p = (uv - 0.5) * aspectVec;
  let modal = sin(p.x * scale + time * speed * (0.42 + bass * 0.22))
    * cos(p.y * scale * 1.17 - time * speed * (0.36 + mids * 0.18));
  let mouseDelta = (uv - u.zoom_config.yz) * aspectVec; let mouseDist = length(mouseDelta);
  let held = select(0.16, 1.0, u.zoom_config.w > 0.5);
  let lensPush = exp(-mouseDist * mouseDist * mix(80.0, 26.0, intensity)) * held;
  var impulse = lensPush * (0.012 + intensity * 0.045);
  var clickEnergy = 0.0; var driven = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i += 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age >= 0.0 && age < 2.7) {
      let dist = length((uv - ripple.xy) * aspectVec);
      // ── Rescue 1: was pow(negative, 2.0) inside the ring (undefined / NaN on some GPUs) ──
      let ringArg = (dist - age * (0.16 + speed * 0.06)) * (36.0 + detail * 18.0);
      let ring = exp(-ringArg * ringArg) * exp(-age * 1.05);
      impulse += ring * sin(age * 8.0) * (0.018 + intensity * 0.06); clickEnergy += ring;
      let wakeArg = ringArg * 0.3; driven += exp(-wakeArg * wakeArg) * exp(-age * 0.7); // broad band around the ring: where the surface is actually being driven
    }
  }
  velocity = clamp(velocity * mix(0.94, 0.982, detail) + laplacian * mix(0.12, 0.055, detail)
    + (seedHeight - height) * 0.014 + modal * intensity * 0.0018 + impulse, -0.75, 0.75);
  height = clamp(height + velocity * mix(0.085, 0.045, detail), 0.015, 0.95);
  thickness = clamp(mix(thickness, height * (0.8 + detail * 0.55) + abs(laplacian) * 2.5, 0.055) + lensPush * 0.012, 0.01, 1.0);
  let coverage = clamp(max(c.a * 0.997, smoothstep(0.015, 0.13, thickness)), 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(height, velocity, thickness, coverage));

  let gradient = vec2<f32>(hL - hR, hD - hU) * (5.0 + intensity * 15.0 + detail * 5.0);
  let normal = normalize(vec3<f32>(gradient, 0.26));
  let ior = mix(1.31, 1.58, detail); let eta = 1.0 / ior;
  let incident = vec3<f32>(0.0, 0.0, -1.0);
  let refracted = refract(incident, normal, eta);
  let offScale = thickness * (0.025 + intensity * 0.075) / aspectVec;
  let offset = (refracted.xy + normal.xy * 0.35) * offScale;
  // ── Idea 3: Cauchy dispersion (§12.2F) ────────────────────────────
  // n(lambda) = ior + B*(1/lambda^2 - 1/lambda_g^2) at 650/550/450 nm, so green keeps the file's own ior. Red and
  // blue deflect by their own Snell angle: first-order, the deflection changes by d(1/n) = -dn/ior^2 along
  // normal.xy, scaled by the same thickness x intensity factor as the refraction itself. The old fixed
  // +-delta*normal split was symmetric and ignored how much glass the ray crossed; now blue bends further than red
  // is spared (non-linear in 1/lambda^2) and the fringe grows with thickness x slope. B rides the file's existing
  // dispersion amplitude (detail + treble), linearly, with no clamp so the treble response keeps its range.
  let dispAmp = 0.001 + detail * 0.006 + treble * 0.0025;
  let dnCauchy = dispAmp * DISP_K
    * (vec3<f32>(1.0 / 0.4225, 1.0 / 0.3025, 1.0 / 0.2025) - vec3<f32>(1.0 / 0.3025));
  let dDeflect = -dnCauchy / (ior * ior);
  let offsetR = offset + normal.xy * dDeflect.x * offScale;
  let offsetB = offset + normal.xy * dDeflect.z * offScale;
  let centerUV = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
  let sourceR = textureSampleLevel(readTexture, u_sampler, clamp(uv + offsetR, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let sourceG = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);
  let sourceB = textureSampleLevel(readTexture, u_sampler, clamp(uv + offsetB, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0);
  let source = vec4<f32>(sourceR.r, sourceG.g, sourceB.b, max(sourceR.a, max(sourceG.a, sourceB.a)));
  let f0 = pow((ior - 1.0) / (ior + 1.0), 2.0); let fresnel = schlick(max(normal.z, 0.0), f0);
  // ── Idea 4: signed-focus caustic (native, energy accounting) ──────
  // The old caustic used |laplacian|, so diverging curvature glowed as brightly as converging. A surface
  // focuses light where the height field has a crest (lapWide < 0) and starves it where it dishes (lapWide > 0):
  // converging curvature adds a brighter caustic line on top of HEAD's term, and the transmitted photo gains
  // light on the focus side and loses it on the diverging side (a saturating response keeps the broad, soft shape of a real
  // focus/defocus pair) — every real caustic line has a dark neighbour. HEAD's |laplacian| term is kept as is. Gated by `driven` (a broad
  // band around each live click ring) because at the saved defaults the only curvature is the static seed-cell grid.
  let lapGain = 22.0 + detail * 38.0;
  let driveMask = clamp(driven * 1.5, 0.0, 1.0);
  let converge = clamp(max(-lapWide, 0.0) * lapGain, 0.0, 1.0) * driveMask;
  let diverge = clamp(max(lapWide, 0.0) * lapGain, 0.0, 1.0) * driveMask;
  let curvature = clamp(abs(laplacian) * lapGain, 0.0, 1.0) + converge * CONVERGE_EXTRA;
  let caustic = pow(clamp(curvature + clickEnergy * 0.36, 0.0, 1.0), 2.2);
  let focusGain = 1.0 + FOCUS_GAIN * focusResp(converge) - DIVERGE_SHADE * focusResp(diverge);
  let interference = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.88, 1.0, 1.14) * (thickness * 2.2 + time * 0.012) + vec3<f32>(0.0, 0.21, 0.43)));
  let absorption = exp(-thickness * vec3<f32>(0.22, 0.09, 0.035) * (0.6 + intensity));
  var color = source.rgb * absorption * focusGain + vec3<f32>(0.36, 0.66, 1.0) * fresnel * (0.18 + mids * 0.14)
    + interference * caustic * (0.12 + detail * 0.3 + treble * 0.12) + vec3<f32>(1.0, 0.82, 0.48) * lensPush * bass * 0.08;

  // ── Idea 1: total internal reflection ─────────────────────────────
  // Light leaving glass for air cannot escape past the critical angle
  // asin(1/ior). On a steep enough flank the photo is simply not
  // transmitted; what you see is the inside of the glass reflected back —
  // the silvery flash along every real glass or water edge. Soft mask on
  // the Snell discriminant, using the same ior the refraction already uses.
  let cosI = clamp(normal.z, 0.0, 1.0);
  let kTir = 1.0 - ior * ior * (1.0 - cosI * cosI);
  let tir = 1.0 - smoothstep(-0.08, 0.05, kTir);
  let insideUV = clamp(uv - offset * 2.0, vec2<f32>(0.001), vec2<f32>(0.999));
  let insideRefl = textureSampleLevel(readTexture, u_sampler, insideUV, 0.0).rgb;
  color = mix(color, insideRefl * absorption * 1.2 + vec3<f32>(0.10, 0.13, 0.17), tir * 0.8);

  // ── Idea 2: seed bubbles ──────────────────────────────────────────
  // Glassmakers call trapped air bubbles "seeds". They rise slowly and only
  // exist where the glass is thick enough to hold them. Each is a small
  // diverging lens: a dark rim (TIR again, at the bubble wall) around a
  // bright specular dot offset toward the light.
  let bp = uv * aspectVec * (scale * 2.3) + vec2<f32>(0.0, time * speed * 0.18);
  let bCell = floor(bp);
  let bLocal = fract(bp) - 0.5;
  let bSeed = hash21(bCell + vec2<f32>(17.3, 4.1));
  let bCenter = (vec2<f32>(hash21(bCell + vec2<f32>(3.1, 8.2)), hash21(bCell + vec2<f32>(9.7, 1.3))) - 0.5) * 0.6;
  let bRadius = mix(0.06, 0.2, hash21(bCell + vec2<f32>(5.5, 6.6)));
  let bDist = length(bLocal - bCenter);
  let bubblePresent = step(0.62 - detail * 0.3, bSeed) * smoothstep(0.1, 0.3, thickness);
  let bubbleRim = smoothstep(bRadius, bRadius * 0.72, bDist) * smoothstep(bRadius * 0.35, bRadius * 0.72, bDist);
  let bubbleGlint = smoothstep(bRadius * 0.28, 0.0, length(bLocal - bCenter + vec2<f32>(0.35, 0.35) * bRadius));
  color = color * (1.0 - bubbleRim * 0.6 * bubblePresent) + vec3<f32>(1.0, 0.98, 0.94) * bubbleGlint * bubblePresent * 0.7;

  let alpha = clamp(source.a + (1.0 - source.a) * coverage * (0.16 + thickness * 0.6) + fresnel * 0.08 + tir * 0.06, 0.0, 1.0);
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(color), alpha));
  let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeDepthTexture, pixel, vec4<f32>(max(sourceDepth * 0.91, thickness * 0.24 + caustic * 0.03), 0.0, 0.0, 0.0));
}
