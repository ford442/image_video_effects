// ═══════════════════════════════════════════════════════════════════
//  Hopf Fibration Fiber Bundle
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-13
//  Ideas: knot-diagram over/under gaps; U(1) fiber-phase beads; base-space S2 inset
//  A packing: ACES display RGBA
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

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(h, h, h) + k) * 6.0 - vec3<f32>(3.0, 3.0, 3.0));
  return v * mix(vec3<f32>(k.x, k.x, k.x), clamp(p - vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(1.0, 1.0, 1.0)), s);
}

fn hash11(n: f32) -> f32 {
  return fract(sin(n * 127.1) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let coord = vec2<i32>(global_id.xy);
  if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let p1 = u.zoom_params.x;
  let p2 = u.zoom_params.y;
  let p3 = u.zoom_params.z;
  let p4 = u.zoom_params.w;

  // Pointer always steers the base sphere; held input increases the orbit.
  let held = u.zoom_config.w > 0.5;
  let pointerGain = select(0.22, 1.0, held);
  var s2phi = uv.x * PI + (mouse.x - 0.5) * PI * pointerGain;
  var s2theta = uv.y * PI + (mouse.y - 0.5) * PI * 0.5 * pointerGain;
  if (u.zoom_config.w > 0.5) {
    s2phi += (mouse.x - 0.5) * PI;
    s2theta += (mouse.y - 0.5) * PI * 0.5;
  }
  let rot4D = time * mix(0.04, 0.55, p1) * (1.0 + bass * 0.25) + p1 * PI;
  let fiberCount = 40;
  let fiberThick = mix(0.0018, 0.0105, p2) * (1.0 + mids * 0.28);
  var accum = vec3<f32>(0.0, 0.0, 0.0);
  var alphaAcc = 0.0;
  var crossingInt = 0.0;
  var maxDepth = 0.0;
  // Idea 1: two-slot compositing — nearest strand vs. everything behind it.
  var frontAcc = vec3<f32>(0.0);
  var restAcc = vec3<f32>(0.0);
  var frontZ = -1.0;
  var frontD = 1.0e3;
  let gapRadius = fiberThick * 2.6;
  // Idea 3: base-space S2 inset placement (lower-left, aspect-corrected).
  let aspect = res.x / max(res.y, 1.0);
  let screenP = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  let insetR = 0.11;
  let insetC = vec2<f32>(-0.5 * aspect + insetR + 0.05, 0.5 - insetR - 0.05);
  let insetQ = (screenP - insetC) / insetR;
  let inInset = dot(insetQ, insetQ) < 1.35;
  var insetCol = vec3<f32>(0.0);
  var insetCov = 0.0;
  let beadSpeed = mix(0.3, 2.2, p4);

  for (var i: i32 = 0; i < fiberCount; i = i + 1) {
    let fi = f32(i);
    let phi = fi * 2.4 + rot4D + s2phi * 0.12;
    let theta = asin(clamp(hash11(fi * 3.7) * 2.0 - 1.0, -0.999, 0.999)) + (s2theta - PI * 0.5) * 0.08;
    let x2 = cos(theta) * cos(phi);
    let y2 = cos(theta) * sin(phi);
    let z2 = sin(theta);
    let fiberPhase = fi * 1.618 + time * mix(0.04, 0.65, p4) + sin(fi + time * 0.3) * mids * 0.08;
    let tSteps = 32;
    var prevProj = vec2<f32>(0.0, 0.0);
    var prevW = 0.0;
    let hue = fract(phi / (2.0 * PI) + theta * 0.3);
    let fiberColor = hsv2rgb(hue, 0.75, 0.9);
    var fiberAcc = vec3<f32>(0.0);
    var fiberMinD = 1.0e3;
    var fiberZ = -1.0;
    let beadPhase = time * beadSpeed + fi * 0.73;

    // Idea 3: plot this fiber's base point on the rotating S2 inset.
    if (inInset) {
      let cy3 = cos(rot4D);
      let sy3 = sin(rot4D);
      let bx = x2 * cy3 + z2 * sy3;
      let bz = -x2 * sy3 + z2 * cy3;
      let dq = insetQ - vec2<f32>(bx, y2);
      let facing = smoothstep(-0.4, 0.4, bz);
      let dot2 = exp(-dot(dq, dq) * 900.0) * (0.3 + 0.7 * facing);
      insetCol += fiberColor * dot2 * 1.6;
      insetCov += dot2;
    }

    for (var t: i32 = 0; t < tSteps; t = t + 1) {
      let tt = f32(t) / f32(tSteps) * PI * 2.0;
      let psi = tt + fiberPhase;
      let z1r = max(sqrt((1.0 + z2) * 0.5), 0.001);
      let z2r = x2 * 0.5 / z1r;
      let z2i = y2 * 0.5 / z1r;
      let cpsi = cos(psi);
      let spsi = sin(psi);
      let w1 = z1r * cpsi;
      let x1 = z2r * cpsi - z2i * spsi;
      let y1 = z2r * spsi + z2i * cpsi;
      let w3 = z1r * spsi;
      let denom = 1.0001 - w1;
      let proj3 = vec3<f32>(x1 / denom, y1 / denom, w3 / denom);
      let cy = cos(rot4D);
      let sy = sin(rot4D);
      let rx = proj3.x * cy + proj3.z * sy;
      let rz = -proj3.x * sy + proj3.z * cy;
      let depth4 = 1.0 / max(2.5 + rz, 0.05);
      let proj2 = vec2<f32>(rx, proj3.y) * depth4 * 0.35 + 0.5;
      let wCoord = w1;

      if (t > 0) {
        let seg = proj2 - prevProj;
        let toPixel = uv - prevProj;
        let segLen2 = dot(seg, seg);
        let tProj = clamp(dot(toPixel, seg) / max(segLen2, 0.00001), 0.0, 1.0);
        let closest = prevProj + seg * tProj;
        let d = length(uv - closest);
        let glow = exp(-d * d / (fiberThick * fiberThick));
        if (glow > 0.001) {
          let depthFade = smoothstep(-1.0, 1.0, wCoord) * 0.5 + 0.5;
          // Idea 2: bead riding the U(1) circle action at its own psi phase.
          let bead = pow(0.5 + 0.5 * cos(tt - beadPhase), 28.0);
          fiberAcc += fiberColor * glow * depthFade;
          fiberAcc += vec3<f32>(1.0, 0.96, 0.88) * glow * bead * depthFade * (0.7 + bass * 1.3);
          if (d < fiberMinD) {
            fiberMinD = d;
            fiberZ = depth4;
          }
          alphaAcc += glow * depthFade;
          maxDepth = max(maxDepth, depthFade * glow);
          let segmentDepthDiff = abs(wCoord - prevW);
          crossingInt += glow * (1.0 - smoothstep(0.0, 0.3, segmentDepthDiff)) * mix(0.25, 1.6, p3);
        }
      }
      prevProj = proj2;
      prevW = wCoord;
    }

    // Idea 1: nearest strand (largest depth4) near this pixel becomes the over-strand.
    if (fiberMinD < gapRadius && fiberZ > frontZ) {
      restAcc += frontAcc;
      frontAcc = fiberAcc;
      frontZ = fiberZ;
      frontD = fiberMinD;
    } else {
      restAcc += fiberAcc;
    }
  }

  // Idea 1: cut a knot-diagram gap in under-strands around the over-strand.
  let gapMask = exp(-frontD * frontD / (gapRadius * gapRadius * 0.55));
  accum = frontAcc + restAcc * (1.0 - gapMask * mix(0.45, 0.9, p3));

  // Idea 3: inset sphere limb + base-point dots.
  if (inInset) {
    let rq = length(insetQ);
    let limb = exp(-(rq - 1.0) * (rq - 1.0) * 700.0) * 0.35;
    let shell = (1.0 - smoothstep(0.96, 1.0, rq)) * 0.05;
    insetCol += vec3<f32>(0.55, 0.6, 0.8) * (limb + shell) * (1.0 + mids * 0.4);
    insetCov += limb + shell;
    accum += insetCol;
    alphaAcc += insetCov * 1.5;
    maxDepth = max(maxDepth, clamp(insetCov, 0.0, 0.6));
  }

  // Treble particle drift + crossing bloom
  let driftCoord = uv + vec2<f32>(time * 0.015, -time * 0.011) * p4;
  let drift = hash11(floor(driftCoord.x * 50.0) + floor(driftCoord.y * 50.0) * 127.0 + time * mix(0.4, 4.0, p4));
  let speck = step(0.97, drift) * treble * 2.0;
  accum += vec3<f32>(1.0, 0.95, 0.85) * speck;
  accum += vec3<f32>(0.5, 0.4, 0.8) * crossingInt * (0.12 + treble * 0.35) * mix(0.3, 1.8, p3);

  // Finite fiber-phase blooms launched by click timestamps.
  let rippleCount = min(u32(u.config.y), 50u);
  var clickBloom = 0.0;
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age < 0.0 || age > 3.0) { continue; }
    let center = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0);
    let d = length(screenP - center);
    let phaseFront = abs(d - age * mix(0.12, 0.42, p4));
    clickBloom += exp(-phaseFront * phaseFront * 620.0) * exp(-age * 0.85);
  }
  accum += hsv2rgb(fract(time * 0.08 + p1), 0.7, 1.0) * clickBloom * (0.8 + p3 * 1.8);
  alphaAcc += clickBloom * 1.4;
  maxDepth = max(maxDepth, clickBloom * 0.75);

  // Alpha: fiber density × crossing_intensity × depth
  let alpha = clamp(alphaAcc * 0.4 * (1.0 + crossingInt) * maxDepth, 0.0, 1.0);
  let currentDisplay = acesToneMap(accum * (0.95 + mids * 0.12));
  let prevDisplay = textureLoad(dataTextureC, coord, 0);
  let display = mix(prevDisplay.rgb * 0.945, currentDisplay, 0.24 + bass * 0.035);
  let displayAlpha = max(alpha, prevDisplay.a * 0.92);
  let out = vec4<f32>(display, displayAlpha);

  // Depth: nearest fiber crossing occludes deeper bundle layers
  textureStore(writeTexture, coord, out);
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(maxDepth, 0.0, 1.0), 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, out);
}
