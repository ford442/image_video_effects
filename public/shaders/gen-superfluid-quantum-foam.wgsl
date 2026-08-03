// ═══════════════════════════════════════════════════════════════════
//  Superfluid Quantum-Foam
//  Category: generative
//  Features: mouse-driven, audio-reactive, raymarched, temporal, chromatic, depth-aware
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 33)
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
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash13(p3: vec3<f32>) -> f32 {
  var p = fract(p3 * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
  var p = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
  let e = vec3<f32>(0.01, 0.0, 0.0);
  let n1 = hash33(p + e);
  let n2 = hash33(p - e);
  let n3 = hash33(p + e.zxy);
  let n4 = hash33(p - e.zxy);
  let n5 = hash33(p + e.yzx);
  let n6 = hash33(p - e.yzx);
  return vec3<f32>(n4.z - n3.z - n6.y + n5.y, n6.x - n5.x - n2.z + n1.z, n3.y - n4.y - n1.y + n2.y) * 12.5;
}

fn map(p: vec3<f32>) -> vec2<f32> {
  let t = u.config.x * (0.15 + u.zoom_params.w * 0.35);
  let bass = plasmaBuffer[0].x;
  let env = 1.0 + bass * 2.0;
  var pos = p + curlNoise(p * 0.5 + t * 0.1) * 0.3 * env;
  
  let mouse = select(clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)), vec2<f32>(extraBuffer[133], extraBuffer[134]), extraBuffer[137] > 0.5);
  let m = vec3<f32>((mouse.x * 2.0 - 1.0) * 10.0, (mouse.y * 2.0 - 1.0) * 5.0, 0.0);
  let dm = length(p - m);
  let vr = u.zoom_params.y;
  if (dm < vr) {
    pos += (m - p) / max(dm, 0.001) * (vr - dm) * 0.5;
    let s = sin(dm);
    let c = cos(dm);
    let xz = pos.xz * mat2x2<f32>(c, -s, s, c);
    pos.x = xz.x;
    pos.z = xz.y;
  }
  
  let sp = 3.0 / env;
  var cell = floor(pos / sp);
  pos = pos - sp * round(pos / sp);
  let boil = hash13(cell) * sin(t * 3.0 + bass * 10.0) * u.zoom_params.x;
  let r = (0.6 + hash13(cell + 1.0) * 0.6) * env + boil;
  return vec2<f32>(length(pos) - r, hash13(cell));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
  let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
  return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x + e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let coords = vec2<i32>(global_id.xy);
  let dims = textureDimensions(writeTexture);
  if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }
  
  let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
  let t = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let env = 1.0 + bass * 2.0;
  
  let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
  if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
  let springDt = select(0.016, clamp(t - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
  let springOmega = 8.0;
  mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
  mouse += mouseVelocity * springDt;
  if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
    extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
    extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
    extraBuffer[137] = 1.0; extraBuffer[138] = t;
  }

  let cameraDrift = (mouse - vec2<f32>(0.5)) * vec2<f32>(0.35, 0.2);
  let ro = vec3<f32>(0.0, 0.0, -8.0);
  let rd = normalize(vec3<f32>(uv + cameraDrift, 1.0));
  var dist = 0.0;
  var glow = 0.0;
  
  for (var i = 0; i < 72; i++) {
    let p = ro + rd * dist;
    let res = map(p);
    if (res.x < 0.5) { glow += (0.5 - res.x) * 0.08 * u.zoom_params.z; }
    if (res.x < 0.001 || dist > 30.0) { break; }
    dist += max(res.x * 0.55, 0.002);
  }
  
  var col = vec3<f32>(0.02, 0.0, 0.05);
  var alpha = 0.0;
  
  if (dist < 30.0) {
    let p = ro + rd * dist;
    let n = calcNormal(p);
    let v = -rd;
    let ndotv = clamp(dot(n, v), 0.0, 1.0);

    // ═══ Chromatic dispersion: per-channel iridescence offsets ═══
    let ndotvR = clamp(ndotv + bass * 0.05, 0.0, 1.0);
    let ndotvG = clamp(ndotv + mids * 0.05, 0.0, 1.0);
    let ndotvB = clamp(ndotv + treble * 0.05, 0.0, 1.0);

    let irid = vec3<f32>(
      0.5 + 0.5 * cos(6.28318 * (ndotvR + 0.0)),
      0.5 + 0.5 * cos(6.28318 * (ndotvG + 0.33)),
      0.5 + 0.5 * cos(6.28318 * (ndotvB + 0.67))
    );

    let dif = clamp(dot(n, normalize(vec3<f32>(0.8, 0.7, -0.6))), 0.0, 1.0);
    col = mix(vec3<f32>(0.1, 0.1, 0.2), irid, 0.6) * dif;
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * dist * dist));
    alpha = clamp(1.0 - exp(-0.05 * dist), 0.0, 1.0) * (0.4 + 0.6 * dif);
  }
  
  var clickCavitation = 0.0;
  let aspect = f32(dims.x) / f32(dims.y);
  let uv01 = (vec2<f32>(coords) + vec2<f32>(0.5)) / vec2<f32>(dims);
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = t - ripple.z;
    if (age >= 0.0 && age < 1.8) {
      let delta = (uv01 - ripple.xy) * vec2<f32>(aspect, 1.0);
      let radius = length(delta);
      let shell = exp(-abs(radius - age * 0.24) * 70.0) * exp(-age * 1.4);
      clickCavitation = max(clickCavitation, shell);
    }
  }

  let flash = vec3<f32>(0.8, 0.1, 1.0) * glow * env;
  col += flash;
  col += vec3<f32>(0.25, 0.75, 1.4) * clickCavitation * (0.7 + treble * 0.4);
  alpha = max(alpha, glow * 0.5 + clickCavitation * 0.45);
  
  let lum = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  col = max(col, vec3<f32>(0.0));
  col = max(col, lum * vec3<f32>(0.3, 0.2, 0.4));

  // ═══ Temporal feedback ═══
  let prev = textureLoad(dataTextureC, coords, 0);
  col = mix(col, prev.rgb * 0.9, clamp(0.03 + bass * 0.01, 0.0, 0.08));
  col = acesToneMap(col * (1.0 + mids * 0.12));
  alpha = clamp(alpha, 0.0, 0.96);
  let hit = dist < 30.0;
  let depth = select(0.0, clamp(1.0 - dist / 30.0, 0.0, 1.0), hit);
  
  textureStore(writeTexture, coords, vec4<f32>(col * alpha, alpha));
  textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coords, vec4<f32>(col * alpha, alpha));
}
