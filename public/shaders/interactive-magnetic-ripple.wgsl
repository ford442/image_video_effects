// ═══════════════════════════════════════════════════════════════════
//  Interactive Magnetic Ripple — Batch 58E
//  Keeps Worley field lines, curl, spring envelopes, exact C state.
//  Caps click loop at live ripple count, adds held field punch,
//  oil-slick domain-wall runners. A remains [env, mouseXY, intensity].
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

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
             u2.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var f = 1.0;
  for (var i: i32 = 0; i < oct; i = i + 1) {
    s += a * valueNoise(p * f);
    f *= 2.0;
    a *= 0.5;
  }
  return s;
}

fn curlNoise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let e = 0.008;
  let n0 = fbm(p + vec2<f32>(0.0,  e) + t * 0.12, 3);
  let n1 = fbm(p + vec2<f32>(0.0, -e) + t * 0.12, 3);
  let n2 = fbm(p + vec2<f32>( e, 0.0) + t * 0.12, 3);
  let n3 = fbm(p + vec2<f32>(-e, 0.0) + t * 0.12, 3);
  return vec2<f32>(n0 - n1, n3 - n2) / (2.0 * e);
}

fn worley(p: vec2<f32>, t: f32) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var f1 = 8.0;
  var f2 = 8.0;
  for (var gy: i32 = -1; gy <= 1; gy = gy + 1) {
    for (var gx: i32 = -1; gx <= 1; gx = gx + 1) {
      let g = vec2<f32>(f32(gx), f32(gy));
      let h = hash21(i + g);
      let pt = g + vec2<f32>(0.5 + 0.4 * sin(t * 0.7 + h * TAU),
                             0.5 + 0.4 * cos(t * 0.6 + h * TAU * 1.7)) - f;
      let d = dot(pt, pt);
      if (d < f1) { f2 = f1; f1 = d; }
      else if (d < f2) { f2 = d; }
    }
  }
  return vec2<f32>(sqrt(f1), sqrt(f2));
}

fn rot2(angle: f32) -> mat2x2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return mat2x2<f32>(c, -s, s, c);
}

fn springEnvelope(x: f32, zeta: f32, omega: f32) -> f32 {
  let z = clamp(zeta, 0.05, 0.95);
  let wd = omega * sqrt(max(1.0 - z * z, 0.01));
  let ring = cos(wd * x) + (z * omega / wd) * sin(wd * x);
  return exp(-z * omega * x) * ring;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
  return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn bass_env(prev: f32, bass: f32) -> f32 {
  let k = select(0.15, 0.8, bass > prev);
  return mix(prev, bass, k);
}

fn sparkle(uv: vec2<f32>, t: f32, treble: f32) -> f32 {
  return pow(hash21(uv * 300.0 + t * 15.0), 18.0) * treble * 2.5;
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
  return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

fn colorCycle(t: f32) -> vec3<f32> {
  return vec3<f32>(0.5 + 0.5 * cos(t + vec3<f32>(0.0, 2.094, 4.189)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let aspect = res.x / max(res.y, 1.0);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let held = f32(mouseDown);

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let env = bass_env(prev.r, bass);
  let k = 0.12 + env * 0.08;
  let mSmooth = mix(prev.gb, mouse, vec2<f32>(k));
  let mVel = mSmooth - prev.gb;

  let pFreq = u.zoom_params.x;
  let pLineMix = clamp(u.zoom_params.y, 0.0, 1.0);
  let pSpring = clamp(u.zoom_params.z, 0.0, 1.0);
  let pSparkle = clamp(u.zoom_params.w, 0.0, 1.0);

  let bassPulse = 1.0 + env * 0.5;
  let freq = pFreq * 40.0 * (0.8 + env * 0.4);
  let dampZeta = 0.12 + pSpring * 0.78;
  let springOmega = 2.5 + freq * 0.35;
  let decay = 0.5 + pSpring * 3.0;
  let fieldStrength = 0.55 * bassPulse * (1.0 + held * 0.45);
  let chromaticSplit = 0.04;
  let sparkGain = 0.3 + pSparkle * 1.6;
  let pulseStrength = fieldStrength * (1.0 + env * 0.7);
  let clickBurst = select(0.0, 1.0, mouseDown) * (1.0 + env);

  var totalDisp = vec2<f32>(0.0);
  var rippleIntensity = 0.0;
  var crestMask = 0.0;
  let spark = sparkle(uv01, time, treble) * sparkGain;
  rippleIntensity += spark;

  if (mouse.x >= 0.0) {
    let dMouse = mSmooth - uv01;
    let dAspect = vec2<f32>(dMouse.x * aspect, dMouse.y);
    let dist = length(dAspect);
    let dir = select(vec2<f32>(0.0), dMouse / dist, dist > 0.001);
    let w = worley(uv01 * 5.0 + vec2<f32>(time * 0.05, -time * 0.04), time);
    let ridge = w.y - w.x;
    let bendAng = (ridge - 0.35) * PI * pLineMix;
    let sampAspect = mix(dAspect, rot2(bendAng) * dAspect, pLineMix);
    let sampDist = max(length(sampAspect), 0.0001);
    let curl = curlNoise(uv01 * 3.0 + time * 0.3, time) * 0.25;
    let phase = sampDist * freq - time * 4.0;
    let fbmWarp = fbm(vec2<f32>(sampDist * 4.0, time * 0.4), 3) * 2.5;
    let ripple = cos(phase + fbmWarp) * 0.55 + sin(phase * 1.618) * 0.45;
    let rippleAtten = springEnvelope(sampDist, dampZeta, springOmega);
    totalDisp += dir * ripple * rippleAtten * 0.06;
    rippleIntensity += abs(ripple * rippleAtten);
    crestMask += smoothstep(0.72, 0.98, ripple * rippleAtten) * exp(-dist * 2.0);
    let velBoost = 1.0 + length(mVel) * 5.0;
    let magFalloff = fbm(vec2<f32>(dist * 6.0, time * 0.2), 3) * 0.3 + 0.7;
    let magPull = dir * pulseStrength * velBoost * magFalloff / (dist * dist + 0.04) * 0.06;
    totalDisp += magPull + curl * 0.04;
    rippleIntensity += length(magPull) * 10.0;
    let lineFreq = 12.0 + mids * 8.0;
    let angTerm = atan2(sampAspect.y, sampAspect.x) * lineFreq;
    let fieldLine = sin(angTerm + fbm(uv01 * 5.0, 3) * 3.0 + ridge * 4.0 * pLineMix);
    let fieldLineMask = smoothstep(0.3, 0.0, abs(fieldLine)) * exp(-dist * 3.0);
    totalDisp += dir * fieldLineMask * pulseStrength * 0.02;
    rippleIntensity += fieldLineMask * pulseStrength + spark * fieldLineMask * 5.0;
    crestMask += fieldLineMask * smoothstep(0.6, 1.0, ridge) * 0.5;
  }

  totalDisp += normalize(uv01 - mSmooth + vec2<f32>(0.0001)) * clickBurst * 0.03 * sin(length(uv01 - mSmooth) * 40.0 - time * 10.0);

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    if (rp.z <= 0.0) { continue; }
    let rAge = time - rp.z;
    let rDiff = vec2<f32>((rp.x - uv01.x) * aspect, rp.y - uv01.y);
    let rDist = length(rDiff);
    let rDir = select(vec2<f32>(0.0), vec2<f32>(rDiff.x / aspect, rDiff.y) / rDist, rDist > 0.001);
    let rEnv = springEnvelope(rAge * 0.6, dampZeta, 4.0 + freq * 0.1) * exp(-rDist * decay);
    let rRipple = cos(rDist * freq * 0.6 - rAge * 5.0) * rEnv;
    totalDisp += rDir * rRipple * 0.035;
    rippleIntensity += abs(rRipple) * 0.5;
    crestMask += smoothstep(0.75, 1.0, rRipple) * 0.6;
  }

  let warp = fbm(uv01 * 4.0 + time * 0.2, 3) * 0.015;
  totalDisp = totalDisp * (1.0 + warp) * (0.6 + depth * 0.8);
  let abNoise = fbm(uv01 * 6.0 + vec2<f32>(time * 0.1, 0.0), 3) * 0.015;
  let abScale = 1.0 + chromaticSplit + abNoise;
  let rUV = clamp(uv01 - totalDisp * abScale, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv01 - totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv01 - totalDisp * (2.0 - abScale), vec2<f32>(0.0), vec2<f32>(1.0));
  var color = vec3<f32>(
    textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r,
    textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g,
    textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b
  );

  let glow = smoothstep(0.2, 0.8, rippleIntensity) * bassPulse;
  let cycleGlow = colorCycle(time * 0.5 + mids * TAU + rippleIntensity * 3.0);
  color += mix(vec3<f32>(0.3 + mids * 0.3, 0.5 + treble * 0.3, 0.8), cycleGlow, mids * 0.5) * glow * 0.4;
  color += vec3<f32>(spark * (0.6 + treble * 0.4));
  let crest = clamp(crestMask, 0.0, 1.5);
  let crestSparkle = sparkle(uv01 * 1.7 + vec2<f32>(13.1, 7.3), time * 1.3, treble) * crest * sparkGain;
  color += vec3<f32>(crestSparkle * 0.85, crestSparkle * 0.95, crestSparkle * 1.2) * 0.7;
  let slick = hsv2rgb(vec3<f32>(fract(0.58 + crest * 0.2 + mids * 0.15 + time * 0.08), 0.72, 1.0));
  color = mix(color, color * slick * 1.18, 0.12 + crest * 0.18 + held * 0.08);
  color += slick * crest * 0.12;

  let trailDecay = 0.94 + env * 0.04;
  color = mix(prev.rgb * trailDecay, color, 0.18 + rippleIntensity * 0.15);
  color = acesToneMap(color * (0.95 + mids * 0.15));
  let fog = 1.0 - exp(-depth * fieldStrength * 2.0);
  color = mix(color, vec3<f32>(luma(color) * (1.0 - fog * 0.3)), fog * 0.25);
  let alpha = clamp(luma(color) * 1.4 + rippleIntensity * 0.35 + crest * 0.1, 0.15, 0.95) * (0.6 + depth * 0.4);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(env, mSmooth.x, mSmooth.y, rippleIntensity));
}
