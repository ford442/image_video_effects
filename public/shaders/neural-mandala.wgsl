// ═══════════════════════════════════════════════════════════════════
//  Neural Mandala — Algorithmist + Interactivist Upgrade
//  Polar kaleidoscope symmetry + Warped FBM distortion + Clifford nodes
//  Quasi-random hue distribution with golden-ratio stepping
//  Interactivist pass 2026-07-22: mouse spring re-centering, click shock
//  rings (ripples[]), per-ring FFT bins, sub-symmetry fold.
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
  zoom_params: vec4<f32>,  // x=RingCount, y=Complexity, z=PulseSpeed, w=Connections
  ripples: array<vec4<f32>, 50>,
};

const PI     = 3.14159265358979323846;
const TAU    = 6.28318530717958647692;
const PHI    = 1.61803398874989484820;
const INV_PI = 0.31830988618379067154;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var a = 0.5; var s = 0.0; var q = p;
  for (var i = 0; i < 5; i = i + 1) {
    s = s + a * valueNoise(q);
    q = q * 2.02; a = a * 0.5;
  }
  return s;
}

fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
  let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)),
                    fbm(p + vec2<f32>(5.2, 1.3)));
  let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2)),
                    fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8)));
  return fbm(p + 4.0 * r);
}

fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
  return vec2<f32>(sin(a * p.y) + c * cos(a * p.x),
                   sin(b * p.x) + d * cos(b * p.y));
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
  let r = length(uv);
  var a = atan2(uv.y, uv.x);
  let seg = TAU / max(segs, 1.0);
  a = abs(((a % seg) + seg) % seg - seg * 0.5);
  return vec2<f32>(cos(a), sin(a)) * r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = u.config.zw;
  if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) { return; }

  let uv = (vec2<f32>(global_id.xy) + 0.5) / res;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // ── Sliders (JSON contract: rings / complexity / pulse / connections) ──
  // x = Ring Count         → number of concentric rings (4–12)
  // y = Node Complexity    → kaleido segment count AND per-ring node count
  //                          (coherent double-duty) + sub-fold mirror mix
  // z = Pulse Speed        → temporal rate of ring/node pulsing (0.2–3.2 Hz)
  // w = Connection Density → inter-ring line alpha/width + Clifford node drift
  let ringCount = 4 + i32(u.zoom_params.x * 8.0);
  let complexity = u.zoom_params.y;
  let pulseSpeed = 0.2 + u.zoom_params.z * 3.0;
  let connectionDensity = u.zoom_params.w;

  let aspect = res.x / res.y;
  let pRaw = (uv - 0.5) * vec2<f32>(aspect, 1.0);

  // ── Mouse spring re-centering (persistent state in extraBuffer[133..136]) ──
  // While the mouse is held, the mandala center is pulled toward the cursor
  // with a damped spring; on release it eases back to the screen center.
  let mouseDown = step(0.5, u.zoom_config.w);
  let mouseCentered = (u.zoom_config.yz - 0.5) * vec2<f32>(aspect, 1.0);
  let springGoal = mouseCentered * 0.55 * mouseDown;
  let springDT = 0.016;
  let springK = 90.0;
  let springDamp = 9.0;
  var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  springVel = springVel + ((springGoal - springPos) * springK - springVel * springDamp) * springDT;
  springPos = springPos + springVel * springDT;
  if (global_id.x == 0u && global_id.y == 0u) {
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
  }
  let p = pRaw - springPos;

  // ── Click shock rings: each recorded click emits an expanding wavefront ──
  // that perturbs ring radii (and adds a brief glow) as it sweeps outward.
  let clickCount = min(u32(u.config.y), 50u);
  var shock = 0.0;
  for (var i = 0u; i < clickCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let clickPos = (ripple.xy - 0.5) * vec2<f32>(aspect, 1.0) - springPos;
      let waveFront = age * 0.45;
      let band = exp(-abs(length(p - clickPos) - waveFront) * 18.0);
      shock = shock + band * exp(-age * 1.4);
    }
  }

  let segs = mix(3.0, 12.0, complexity);
  var fp = kaleido(p, segs);
  // Sub-symmetry fold: a second kaleidoscope pass at half the segment count,
  // mixed in by Complexity for snowflake-like internal mirroring.
  let fpSub = kaleido(fp, max(segs * 0.5, 2.0));
  fp = mix(fp, fpSub, complexity * 0.55);
  let seg = TAU / segs;

  var color = vec3<f32>(0.02, 0.01, 0.04);
  var glow = 0.0;

  for (var ri = 0; ri < ringCount; ri = ri + 1) {
    let r = f32(ri);
    // Per-ring audio: inner rings ride the bass bins, outer rings the treble
    // bins, instead of the whole mandala following the global bands.
    let ringEnergy = plasmaBuffer[u32(ri) % 8u + 1u].x;
    // Domain-warped FBM for organic ring radius distortion
    let warp = warpedFBM(p * 4.0 + r, time * 0.08) * 0.015;
    let radius = 0.05 + r * 0.06 + warp + shock * 0.025;
    let ringPulse = sin(time * pulseSpeed + r * 1.3) * 0.5 + 0.5;
    let ringWidth = 0.003 * (1.0 + ringPulse * (0.3 + ringEnergy));

    let distR = length(fp);
    let ringMask = smoothstep(radius + ringWidth, radius, distR) *
                   smoothstep(radius - ringWidth, radius, distR);

    let nodeCount = 4 + i32(r * complexity * 8.0);
    for (var ni = 0; ni < nodeCount; ni = ni + 1) {
      let nodeAngle = f32(ni) / f32(nodeCount) * seg * 0.5 +
                      time * 0.1 * (0.5 + r * 0.1);
      let nodePos = vec2<f32>(cos(nodeAngle), sin(nodeAngle)) * radius;
      // Clifford attractor perturbation for living node drift
      let perturb = clifford(nodePos * 3.0 + time * 0.05, 1.5, 2.3, 1.1, 1.7) *
                    0.01 * connectionDensity;
      let nodePosPerturbed = nodePos + perturb;
      let nodeDist = length(fp - nodePosPerturbed);
      let nodeSize = 0.008 * (1.0 + ringEnergy * 0.5) * (1.0 + ringPulse);
      let nodeGlow = smoothstep(nodeSize * 2.0, 0.0, nodeDist);

      if (ri < ringCount - 1) {
        let nextRadius = radius + 0.06;
        let nextNodeCount = nodeCount + 2;
        let nextAngle = f32(ni) / f32(nextNodeCount) * seg * 0.5 +
                        time * 0.08 * (0.5 + (r + 1.0) * 0.1);
        let nextPos = vec2<f32>(cos(nextAngle), sin(nextAngle)) * nextRadius;
        let nextPerturb = clifford(nextPos * 3.0 + time * 0.05, 1.5, 2.3, 1.1, 1.7) *
                          0.01 * connectionDensity;
        let nextPosPerturbed = nextPos + nextPerturb;
        let lineDir = nextPosPerturbed - nodePosPerturbed;
        let lineLen = length(lineDir);
        let lineDirNorm = lineDir / max(lineLen, 0.0001);
        let toPixel = fp - nodePosPerturbed;
        let proj = clamp(dot(toPixel, lineDirNorm), 0.0, lineLen);
        let closest = nodePosPerturbed + lineDirNorm * proj;
        let lineDist = length(fp - closest);
        let lineGlow = smoothstep(0.003 * (1.0 + connectionDensity), 0.0, lineDist);
        color = color + vec3<f32>(0.3, 0.6, 1.0) * lineGlow * connectionDensity * (0.3 + mids * 0.7);
        glow = glow + lineGlow * connectionDensity;
      }

      // Golden-ratio hue stepping for quasi-random color distribution
      let hue = fract(r * 0.08 + time * 0.02 + bass * 0.05 + f32(ni) * PHI * INV_PI);
      let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
      let h = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
      let nodeColor = clamp(h - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));

      color = color + nodeColor * nodeGlow * (0.6 + ringEnergy * 0.6 + treble * 0.2);
      glow = glow + nodeGlow;
    }

    color = color + vec3<f32>(0.2, 0.5, 0.9) * ringMask * (0.3 + ringEnergy * 0.3);
    glow = glow + ringMask * 0.3;
  }

  // Visible shock shimmer along the expanding wavefronts
  color = color + vec3<f32>(0.9, 0.95, 1.0) * shock * 0.35;
  glow = glow + shock * 0.4;

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  // Clamp accumulated color pre-tint (luma-echo-warp lesson) before feedback
  let accum = min(color, vec3<f32>(1.2));
  color = mix(accum, prev.rgb * 0.92, 0.05 + bass * 0.01);

  let caStr = 0.003 * (1.0 + bass) + glow * 0.001;
  color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

  let alpha = clamp(glow * 0.6 + 0.15 + bass * 0.05, 0.0, 1.0);
  color = acesToneMap(color * 1.1);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
  textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(glow * 0.3, 0.0, 0.0, 0.0));
}
