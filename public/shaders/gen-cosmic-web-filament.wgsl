// ═══════════════════════════════════════════════════════════════
//  Cosmic Web Filament — Batch 63
//  Category: generative
//  Large-scale structure evolving at speed: Zel'dovich streaming,
//  psychedelic stellar-population spectra, ridged filament micro-detail,
//  spring-cursor void well, held collapse, capped click density shocks.
//  Contract: 13 bindings, ACES, semantic alpha, dataTextureA writeback only,
//            exact textureLoad from dataTextureC, plasmaBuffer three-band audio,
//            bounded extraBuffer[133..138] state.
// ═══════════════════════════════════════════════════════════════
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
  zoom_config: vec4<f32>,  // x=Time, yz=MouseUV, w=MouseDown
  zoom_params: vec4<f32>,  // x=Warp Strength, y=Filament Density, z=Evolution Speed, w=Void Pull
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318530718;

const SPRING_X: i32 = 133;
const SPRING_Y: i32 = 134;
const SPRING_VX: i32 = 135;
const SPRING_VY: i32 = 136;
const SPRING_T: i32 = 137;
const SPRING_INIT: i32 = 138;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Psychedelic cosmic spectrum — hue wheel spun by the audio
fn cosmicPalette(t: f32, drive: f32) -> vec3<f32> {
  let phase = vec3<f32>(0.2, 2.2 + drive * 1.2, 4.4 - drive * 0.9);
  return 0.5 + 0.5 * cos(TAU * t + phase);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn hash31(p: vec3<f32>) -> f32 {
  var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn snoise3(p: vec3<f32>) -> f32 {
  let s = vec3<f32>(floor(p.x + p.y + p.z) / 3.0);
  let i = floor(p + s);
  let f = p - i;
  let g = step(f.yzx, f.xyz);
  let l = 1.0 - g;
  let o1 = min(g.xyz, l.zxy);
  let o2 = max(g.xyz, l.zxy);
  let c1 = i + o1;
  let c2 = i + o2;
  let c3 = i + vec3<f32>(1.0);
  let h0 = hash33(i);
  let h1 = hash33(c1);
  let h2 = hash33(c2);
  let h3 = hash33(c3);
  let w0 = f;
  let w1 = f - o1;
  let w2 = f - o2;
  let w3 = f - vec3<f32>(1.0);
  let d0 = dot(w0, w0);
  let d1 = dot(w1, w1);
  let d2 = dot(w2, w2);
  let d3 = dot(w3, w3);
  var w = vec4<f32>(0.0);
  w.x = max(0.5 - d0, 0.0); w.x = w.x * w.x * w.x;
  w.y = max(0.5 - d1, 0.0); w.y = w.y * w.y * w.y;
  w.z = max(0.5 - d2, 0.0); w.z = w.z * w.z * w.z;
  w.w = max(0.5 - d3, 0.0); w.w = w.w * w.w * w.w;
  return dot(w, vec4<f32>(dot(w0, h0 - 0.5), dot(w1, h1 - 0.5), dot(w2, h2 - 0.5), dot(w3, h3 - 0.5))) * 32.0;
}

fn voronoi3D(p: vec3<f32>) -> vec2<f32> {
  let i = floor(p);
  let f = fract(p);
  var res = vec2<f32>(8.0, 8.0);
  for (var k: i32 = -1; k <= 1; k++) {
    for (var j: i32 = -1; j <= 1; j++) {
      for (var i_: i32 = -1; i_ <= 1; i_++) {
        let b = vec3<f32>(f32(i_), f32(j), f32(k));
        let r = b - f + hash33(i + b);
        let d = dot(r, r);
        if (d < res.x) { res.y = res.x; res.x = d; }
        else if (d < res.y) { res.y = d; }
      }
    }
  }
  return sqrt(res);
}

fn fbm(p: vec3<f32>) -> f32 {
  var v = 0.0; var a = 0.5;
  for (var i: i32 = 0; i < 5; i++) {
    v += a * voronoi3D(p * (1.0 + f32(i) * 0.5)).x;
    a *= 0.5;
  }
  return v;
}

fn multifractalNoise(p: vec3<f32>, octaves: i32, H: f32) -> f32 {
  var v = 1.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = voronoi3D(p * f).x;
    v = v * (1.0 + a * n);
    a *= H; f *= 2.1;
  }
  return v - 1.0;
}

fn ridgedVoronoi(p: vec3<f32>, octaves: i32) -> f32 {
  var v = 0.0; var a = 0.5; var f = 1.0;
  for (var i: i32 = 0; i < octaves; i++) {
    let n = 1.0 - voronoi3D(p * f).x;
    v += a * n * n; a *= 0.5; f *= 2.0;
  }
  return v;
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
  let q = vec3<f32>(
    fbm(p + vec3<f32>(0.0, 0.0, t * 0.1)),
    fbm(p + vec3<f32>(5.2, 1.3, t * 0.1)),
    fbm(p + vec3<f32>(1.7, 9.2, t * 0.1))
  );
  return p + q * 0.5;
}

fn sdfSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdfTorus(p: vec3<f32>, t_: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xy) - t_.x, p.z);
  return length(q) - t_.y;
}

fn sdfBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
  let q = abs(p) - b;
  return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn quaternionRotate(p: vec3<f32>, axis: vec3<f32>, angle: f32) -> vec3<f32> {
  let a = normalize(axis);
  let s = sin(angle * 0.5);
  let c = cos(angle * 0.5);
  let q = vec4<f32>(a * s, c);
  let t = 2.0 * cross(q.xyz, p);
  return p + q.w * t + cross(q.xyz, t);
}

fn spiralWarp(p: vec3<f32>, arms: f32, pitch: f32, strength: f32) -> vec3<f32> {
  let r = length(p.xy);
  let angle = atan2(p.y, p.x);
  let twist = r * pitch;
  let armPhase = fract(angle * arms / (2.0 * PI) + twist);
  let warp = sin(armPhase * 2.0 * PI) * strength;
  let c = cos(warp); let s = sin(warp);
  return vec3<f32>(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

fn volumetricGlow(p: vec3<f32>, lightPos: vec3<f32>, density: f32) -> f32 {
  let dist = length(p - lightPos);
  let atten = 1.0 / (1.0 + dist * dist * 2.0);
  return density * atten * 2.0;
}

fn zeldovichDisplacement(q: vec3<f32>, t: f32) -> vec3<f32> {
  let s = t * 0.1;
  let dx = voronoi3D(q + vec3<f32>(0.01, 0.0, 0.0)).x - voronoi3D(q - vec3<f32>(0.01, 0.0, 0.0)).x;
  let dy = voronoi3D(q + vec3<f32>(0.0, 0.01, 0.0)).x - voronoi3D(q - vec3<f32>(0.0, 0.01, 0.0)).x;
  let dz = voronoi3D(q + vec3<f32>(0.0, 0.0, 0.01)).x - voronoi3D(q - vec3<f32>(0.0, 0.0, 0.01)).x;
  return vec3<f32>(dx, dy, dz) * s;
}

fn apollonianEstimate(p: vec3<f32>, scale: f32) -> f32 {
  var z = p; var dr = 1.0; var r = 0.0;
  for (var i: i32 = 0; i < 4; i++) {
    r = length(z);
    if (r > 4.0) { break; }
    let theta = acos(clamp(z.z / max(r, 1e-6), -1.0, 1.0)) * scale;
    let phi = atan2(z.y, z.x) * scale;
    dr = pow(r, scale - 1.0) * scale * dr + 1.0;
    z = pow(r, scale) * vec3<f32>(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + p;
  }
  return 0.5 * log(max(r, 1e-6)) * r / max(dr, 1e-6);
}

fn kleinWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
  let u_ = p.x * 0.5 + t * 0.05;
  let v_ = p.y * 0.5;
  let cu = cos(u_); let su = sin(u_);
  let cv = cos(v_); let sv = sin(v_);
  let a = 0.3;
  return p + vec3<f32>((a + cu) * sv, (a + cu) * cv, -su) * 0.1;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = u.config.zw;
  if (id.x >= u32(res.x) || id.y >= u32(res.y)) { return; }

  let coord = vec2<i32>(id.xy);
  let uv01 = vec2<f32>(id.xy) / res;
  let aspect = vec2<f32>(res.x / max(res.y, 1.0), 1.0);
  var uv = (uv01 - 0.5) * vec2<f32>(res.x / max(res.y, 1.0), -1.0);

  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let rawMouse = u.zoom_config.yz;
  let held = u.zoom_config.w > 0.5;
  let heldF = select(0.0, 1.0, held);

  // ── spring cursor (extraBuffer[133..138] only) ──────────────────────
  var smoothMouse = rawMouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[SPRING_INIT] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[SPRING_X], extraBuffer[SPRING_Y]);
  }
  if (hasSpring && id.x == 0u && id.y == 0u) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[SPRING_VX], extraBuffer[SPRING_VY]);
    if (extraBuffer[SPRING_INIT] <= 0.5) {
      springPos = rawMouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[SPRING_T], 0.001, 0.05);
      let omega = 9.5;
      let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[SPRING_X] = springPos.x;
    extraBuffer[SPRING_Y] = springPos.y;
    extraBuffer[SPRING_VX] = springVel.x;
    extraBuffer[SPRING_VY] = springVel.y;
    extraBuffer[SPRING_T] = time;
    extraBuffer[SPRING_INIT] = 1.0;
    smoothMouse = springPos;
  }

  // ── click density shocks (capped, bounded) ─────────────────────────
  var shock = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 1.5) {
      let front = abs(length((uv01 - rp.xy) * aspect) - age * 0.8);
      shock = max(shock, exp(-front * 26.0) * (1.0 - age / 1.5));
    }
  }
  shock = min(shock, 1.0);

  let zp = u.zoom_params;
  let warpStrength = clamp(zp.x, 0.0, 1.0) * 3.0 + bass * 0.8 + shock * 1.2;
  let densityParam = clamp(zp.y, 0.0, 1.0) * 3.5 + 0.5;
  // Fast motion: cosmic evolution runs an order faster, bass and held on the throttle
  let speed = clamp(zp.z, 0.0, 1.0) * (6.0 + bass * 5.0 + heldF * 3.0) + 0.6;
  let voidPull = clamp(zp.w, 0.0, 1.0);

  // Void well at the smoothed cursor — held collapses the web into it
  let mouseC = (smoothMouse - 0.5) * vec2<f32>(aspect.x, -1.0);
  let dist = length(uv - mouseC);
  let force = smoothstep(0.6, 0.0, dist) * (0.8 + heldF * 1.4 + shock * 0.8) * (0.4 + voidPull);
  uv -= normalize(uv - mouseC + vec2<f32>(1e-4)) * force * 0.8;

  var p = vec3<f32>(uv * 3.0, time * speed * 0.3);
  p += zeldovichDisplacement(p * 0.5, time * speed * 0.1);
  p = spiralWarp(p, 3.0, 0.5, warpStrength * 0.2);
  p = domainWarp(p, time * speed * 0.2);
  p = quaternionRotate(p, vec3<f32>(0.3, 0.7, 0.5), time * speed * 0.15);
  p = kleinWarp(p, time * speed);

  let voidSDF = min(
    min(sdfSphere(p - vec3<f32>(mouseC * 3.0, 0.0), 0.4 + bass * 0.2 + heldF * 0.25),
        sdfTorus(p - vec3<f32>(mouseC * 3.0, 0.0), vec2<f32>(0.5, 0.15))),
    sdfBox(p + vec3<f32>(mouseC * 2.0, 0.0), vec3<f32>(0.3))
  );

  let apollo = apollonianEstimate(p * 0.5, 2.0 + mids);
  let noise3 = snoise3(p * 0.8 + time * speed * 0.1);
  let mf = multifractalNoise(p * 0.4, 4, 0.6);
  p += mf * warpStrength * 0.3;
  let fbmDetail = fbm(p * 0.6);
  let rv = ridgedVoronoi(p * densityParam, 4);
  let v = voronoi3D(p * densityParam);

  let filament = 1.0 / (v.y - v.x + 0.001);
  var filDensity = smoothstep(0.0, 2.0, filament * 0.6) + rv * 0.3 + fbmDetail * 0.15 + noise3 * 0.1;

  // Filament micro-detail — fine caustic striation running along each strand
  let striation = 0.5 + 0.5 * sin((v.y - v.x) * 90.0 - time * (6.0 + treble * 10.0));
  filDensity *= 0.78 + striation * 0.44;

  let structDensity = clamp(filDensity * smoothstep(-0.1, 0.1, -voidSDF) * smoothstep(0.0, 0.5, apollo), 0.0, 1.0);
  let tempGrad = structDensity * (1.0 + bass * 0.5);

  // Stellar population synthesis, graded through the psychedelic wheel
  let age = fract(sin(v.x * 100.0) * 43758.5453);
  let metal = fract(cos(v.y * 100.0) * 43758.5453);
  let popHue = fract(age * 0.4 + metal * 0.3 + time * (0.1 + treble * 0.5) + shock * 0.3);
  let starCol = cosmicPalette(popHue, mids * 1.4);

  let glow = volumetricGlow(vec3<f32>(uv * 3.0, 0.0), vec3<f32>(mouseC * 3.0, 0.0), structDensity);
  let evolution = sin(time * speed * 0.1) * 0.5 + 0.5;

  var col = starCol * structDensity * (0.9 + evolution * 0.5);
  col += cosmicPalette(popHue + 0.35, treble) * tempGrad * 0.55;
  col += cosmicPalette(popHue + 0.6, bass) * glow * (0.35 + voidPull * 0.6);

  // Quasar junctions ignite where Voronoi strands nearly intersect.
  let junction = pow(clamp(1.0 - (v.y - v.x) * (7.0 + densityParam), 0.0, 1.0), 12.0) * structDensity;
  let quasarPulse = 0.45 + 0.55 * sin(time * (3.0 + treble * 8.0) + age * 31.0);
  col += cosmicPalette(popHue + 0.18, 1.0 + mids) * junction * quasarPulse * (0.7 + bass * 1.2);

  // Shock flash + cursor void halo
  col += cosmicPalette(fract(time * 0.9), 1.0) * shock * 1.3;
  let cursorDist = length((uv01 - smoothMouse) * aspect);
  col += cosmicPalette(fract(time * 0.4 + cursorDist), bass) * exp(-cursorDist * 7.0) * (0.12 + heldF * 0.45);

  // ── temporal feedback — exact loads, no filtering ───────────────────
  let prev = textureLoad(dataTextureC, coord, 0);
  col = mix(col, prev.rgb * 0.92, 0.05 + bass * 0.03);

  // Chromatic aberration over the feedback: per-channel integer taps, clamped in-bounds
  let dims = vec2<i32>(i32(res.x) - 1, i32(res.y) - 1);
  let caDir = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(1e-4));
  let caPx = (1.0 + bass * 3.0 + shock * 4.0) * (1.0 + treble);
  let offR = vec2<i32>(round(caDir * caPx));
  let offB = vec2<i32>(round(-caDir * caPx * 0.8));
  let prevR = textureLoad(dataTextureC, clamp(coord + offR, vec2<i32>(0), dims), 0).r;
  let prevB = textureLoad(dataTextureC, clamp(coord + offB, vec2<i32>(0), dims), 0).b;
  col.r = mix(col.r, prevR * 0.9, 0.03 + treble * 0.02);
  col.b = mix(col.b, prevB * 0.9, 0.03 + mids * 0.02);

  col = acesToneMap(col * (1.15 + mids * 0.3));

  // Semantic alpha: filament density is the structure's own opacity
  let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(structDensity * 0.65 + luma * 0.4 + min(glow, 1.5) * 0.2 + shock * 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(col, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(clamp(1.0 - structDensity, 0.0, 1.0), 0.0, 0.0, 0.0));
}
