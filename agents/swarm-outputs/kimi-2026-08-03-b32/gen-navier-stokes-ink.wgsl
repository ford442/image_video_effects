// ═══════════════════════════════════════════════════════════════════
//  Navier-Stokes Ink - 2D fluid sim + extruded 3D ink geometry
//  Category: generative
//  Features: upgraded-rgba, aces-tone-map, depth-aware, audio-reactive, temporal, mouse-driven, pressure-stub, hue-preserve-clamp, ign-dither, sdf-vortex-tubes, tessellated-corona, orbit-camera, ripple-deform, fft-reactive
//  Complexity: High
//  Created: 2026-05-30
//  Upgraded: 2026-06-07
//  b32 Interactivist: 2026-08-03 — SDF vortex tubes advected by the sim,
//    tessellated ink-drop coronas, mouse orbit camera, ripple deformation
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ═══ CHUNK: hue-preserve-clamp (from AGENTS.md) ═══
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
  let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
  return c * min(1.0, maxLum / max(l, 1e-4));
}

// ═══ CHUNK: ign-dither (from AGENTS.md) ═══
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn rotY(a: f32) -> mat3x3<f32> {
  let s = sin(a); let c = cos(a);
  return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotX(a: f32) -> mat3x3<f32> {
  let s = sin(a); let c = cos(a);
  return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
  let pa = p - a; let ba = b - a;
  let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  // bounds guard — mandatory (b32 fix: was missing)
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let time = u.config.x;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let coord = vec2<i32>(global_id.xy);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouseUV = u.zoom_config.yz; // already normalized 0-1, y=0 top — used as-is
  let mouseDown = step(0.5, u.zoom_config.w);

  let injectionRate = mix(0.3, 1.2, u.zoom_params.x) * (1.0 + bass * 0.5);
  let viscosity = mix(0.92, 0.65, u.zoom_params.y);
  let dispersion = u.zoom_params.z;
  let vorticityScale = u.zoom_params.w;

  // Real FFT bins (read-only, length-guarded) + smoothed-bass persistent state
  var fftLow = 0.0;
  var fftHigh = 0.0;
  var bassS = bass;
  let ebLen = arrayLength(&extraBuffer);
  if (ebLen > 132u) {
    fftLow = extraBuffer[8u];
    fftHigh = extraBuffer[64u];
  }
  if (ebLen > 133u) {
    bassS = extraBuffer[133u];
    if (global_id.x == 0u && global_id.y == 0u) {
      extraBuffer[133u] = mix(bassS, bass, 0.12);
    }
  }

  let texel = 1.0 / resolution;
  let dt = 0.7;

  let c = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  let vel = c.rg;

  let backUV = uv - vel * texel * dt;
  let advected = textureSampleLevel(dataTextureC, non_filtering_sampler, backUV, 0.0);
  var newVel = advected.rg;
  var newInk = advected.b;

  let mouseForce = (mouseUV - uv) * mouseDown * 4.0;
  newVel = newVel + mouseForce * dt;

  let vn = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0);
  let vs = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0);
  let ve = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0);
  let vw = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0);

  let avgVel = (vn.rg + vs.rg + ve.rg + vw.rg) * 0.25;
  newVel = mix(newVel, avgVel, 1.0 - viscosity);

  let div = (ve.r - vw.r + vn.g - vs.g) * 0.5;
  newVel.x = newVel.x - div * 0.5;
  newVel.y = newVel.y - div * 0.5;

  let source = exp(-length(uv - mouseUV) * length(uv - mouseUV) * 600.0) * mouseDown * injectionRate;
  newInk = newInk + source * dt;
  newInk = newInk * (0.992 - dispersion * 0.02);

  let curl = (ve.g - vw.g) - (vn.r - vs.r);
  let vorticity = abs(curl) * vorticityScale;

  // ═══ b32: guarded click ripples → per-pixel deformation wave ═══
  var rippleWave = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
    for (var r: u32 = 0u; r < rippleCount; r = r + 1u) {
    let rp = u.ripples[r];
    let age = time - rp.z;
    if (age > 0.0 && age < 4.0) {
      let rd2 = length(uv - rp.xy);
      rippleWave += exp(-rd2 * 9.0) * sin(rd2 * 40.0 - age * 8.0) * exp(-age * 1.5);
      }
    }
  rippleWave = clamp(rippleWave, -0.8, 1.5);

  // ═══ b32: 3D extrusion — SDF vortex tubes + tessellated ink-drop corona ═══
  let aspect = resolution.x / resolution.y;
  // Mouse orbit camera (zoom_config.yz used directly, no flip)
  let camRot = rotY((u.zoom_config.y - 0.5) * PI * 1.5) * rotX((u.zoom_config.z - 0.5) * PI * 0.7);
  let ndc = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let ro = camRot * vec3<f32>(0.0, 0.0, 2.4);
  let rd = camRot * normalize(vec3<f32>(ndc, -1.6));

  // 4 vortex tubes whose anchors ride the simulated velocity field
  var tubeA: array<vec3<f32>, 4>;
  var tubeB: array<vec3<f32>, 4>;
  var tubeR: array<f32, 4>;
  let twist = mids * 2.0 + time * 0.3;
  for (var i: u32 = 0u; i < 4u; i = i + 1u) {
    let fi = f32(i);
    let anchorUV = vec2<f32>(
      fract(0.23 + fi * 0.31 + time * 0.013 * (1.0 + fi * 0.2)),
      fract(0.61 + fi * 0.17 + time * 0.009)
    );
    let adv = textureSampleLevel(dataTextureC, non_filtering_sampler, anchorUV, 0.0);
    let anchor = vec3<f32>((anchorUV - 0.5) * vec2<f32>(aspect, 1.0) * 1.6, (fi - 1.5) * 0.35);
    let va = atan2(adv.g, adv.r) + twist + fi * 1.7;
    let tubeDir = normalize(vec3<f32>(cos(va), sin(va), 0.3 + 0.3 * sin(time * 0.5 + fi)));
    let halfLen = (0.35 + vorticityScale * 0.3 + bassS * 0.15) * (1.0 + adv.b * 0.5);
    tubeA[i] = anchor - tubeDir * halfLen;
    tubeB[i] = anchor + tubeDir * halfLen;
    tubeR[i] = max((0.03 + bassS * 0.04 + fftLow * 0.02) * (1.0 + rippleWave * 0.8), 0.006);
  }

  // Tessellated ink-drop corona at the emitter (mouse-driven)
  let emitPos = vec3<f32>((mouseUV - 0.5) * vec2<f32>(aspect, 1.0) * 1.6, 0.15 * sin(time * 0.8));
  let coronaBase = 0.14 + injectionRate * 0.06 + bassS * 0.05 + fftHigh * 0.03;
  let facets = 6.0 + floor(treble * 6.0);

  var tRay = 0.0;
  var hitTube = false;
  var glowAcc = 0.0;
  let glowK = mix(24.0, 10.0, dispersion);
  for (var s: i32 = 0; s < 26; s = s + 1) {
    let pos = ro + rd * tRay;
    var dScene = 1e5;
    for (var i: u32 = 0u; i < 4u; i = i + 1u) {
      dScene = min(dScene, sdCapsule(pos, tubeA[i], tubeB[i], tubeR[i]));
    }
    // corona: sphere with quantized angular facets (tessellated look)
    let q = pos - emitPos;
    let qa = atan2(q.y, q.x);
    let qb = atan2(q.z, length(q.xy));
    let facet = abs(fract(qa * facets / TAU) - 0.5) + abs(fract(qb * facets / TAU) - 0.5);
    let coronaR = coronaBase * (1.0 + (0.3 + (1.0 - viscosity) * 0.5) * facet * 0.4 + rippleWave * 0.5);
    dScene = min(dScene, length(q) - coronaR);
    glowAcc += exp(-max(dScene, 0.0) * glowK) * 0.03;
    if (dScene < 0.004) { hitTube = true; break; }
    tRay += max(dScene * 0.8, 0.01);
    if (tRay > 5.0) { break; }
  }

  let inkColor = vec3<f32>(0.05, 0.08, 0.2);
  let deepInk = vec3<f32>(0.02, 0.03, 0.12);
  let eddyColor = vec3<f32>(0.3, 0.5, 1.0);

  var col = mix(deepInk, inkColor, newInk * 3.0);
  col = col + eddyColor * vorticity * newInk * 2.0;
  col = col + vec3<f32>(0.6, 0.7, 1.0) * vorticity * vorticity * 0.3;

  let shear = length(newVel) * 2.0;
  let chromaR = newInk * (1.0 + shear * 0.5);
  let chromaB = newInk * (1.0 - shear * 0.3);
  col = col + vec3<f32>(chromaR * 0.15, 0.0, chromaB * 0.2) * shear;

  // ═══ b32: 3D geometry shading — filament glow + solid tube/corona hits ═══
  var depth3d = 0.0;
  var alpha3d = glowAcc * (0.4 + treble * 0.3);
  col = col + eddyColor * glowAcc * (0.6 + vorticity * 2.0 + mids * 0.4);
  if (hitTube) {
    let shade = 0.4 + 0.6 * exp(-tRay * 0.6);
    let tubeCol = mix(eddyColor, vec3<f32>(0.85, 0.92, 1.0), clamp(glowAcc, 0.0, 1.0));
    col = col + tubeCol * shade * (0.35 + vorticity * 2.0 + newInk);
    depth3d = 1.0 - tRay / 5.0;
    alpha3d = alpha3d + 0.55;
  }

  var outCol = acesToneMapping(huePreserveClamp(col * 1.5, 2.0));
  outCol += (ign(vec2<f32>(coord)) - 0.5) / 255.0;

  let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depth = mix(0.3, 1.0, inputDepth);

  let alpha = clamp(newInk * depth * 1.5 + vorticity * depth * 0.3 + alpha3d, 0.0, 0.95);

  let finalColor = mix(inputColor.rgb, outCol, alpha);
  let finalAlpha = max(inputColor.a, alpha);

  // ═══ CHUNK: pressure-stub — divergence-derived pressure estimate for dataB ═══
  // One Jacobi-style pressure estimate: p ≈ -div * 0.25 (stub for multi-pass pressure solve)
  let pressureEst = -div * 0.25;
  let pressureGrad = vec2<f32>(
    (ve.r - vw.r) * 0.5 - pressureEst,
    (vn.g - vs.g) * 0.5 - pressureEst
  );

  // Real depth: 2D ink column vs 3D tube/corona surface, whichever is nearer
  let outDepth = clamp(max(newInk * depth, depth3d * 0.9), 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(newVel.x, newVel.y, newInk, alpha));
  // Store pressure estimate and velocity magnitude for downstream passes
  textureStore(dataTextureB, coord, vec4<f32>(pressureEst, pressureGrad.x, pressureGrad.y, length(newVel)));
}
