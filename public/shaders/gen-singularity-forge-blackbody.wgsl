// ═══════════════════════════════════════════════════════════════════
//  Singularity Forge Blackbody
//  Category: advanced-hybrid
//  Features: generative, raymarched, blackbody-radiation, HDR
//  Complexity: Very High
//  Chunks From: gen-singularity-forge.wgsl, spec-blackbody-thermal.wgsl
//  Created: 2026-04-18
//  By: Agent CB-23 — Generative Abstract Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Raymarched black hole with accretion disk where thermal energy is
//  rendered via physically-accurate blackbody radiation. Disk
//  temperatures range from cool red dwarfs to blazing blue giants.
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

// ═══ CHUNK: rotate2D (from gen-singularity-forge.wgsl) ═══
fn rotate2D(angle: f32) -> mat2x2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
  var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
  q += dot(q, q.yxz + 33.33);
  return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)), dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
        mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)), dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
    mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)), dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
        mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)), dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
  var f = 0.0;
  var bp = p;
  var amp = 0.5;
  for(var i=0; i<4; i++) {
    f += amp * noise(bp);
    bp *= 2.0;
    amp *= 0.5;
  }
  return f;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
  let q = vec2<f32>(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

// ═══ CHUNK: blackbodyColor (from spec-blackbody-thermal.wgsl) ═══
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
  let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
  var r: f32;
  var g: f32;
  var b: f32;
  if (t <= 6.5) {
    r = 1.0;
    g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
    b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
  } else {
    r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
    g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
    b = 1.0;
  }
  let radiance = pow(t / 6.5, 4.0);
  return vec3<f32>(r, g, b) * radiance;
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Map disk distance to blackbody temperature
fn diskTemperature(diskDist: f32, diskDensity: f32, jetIntensity: f32) -> f32 {
  // Inner disk = hotter, outer = cooler
  let innerTemp = 12000.0;
  let outerTemp = 2000.0;
  let normalizedDist = clamp((diskDist - 1.0) / (3.0 * diskDensity), 0.0, 1.0);
  var temp = mix(innerTemp, outerTemp, normalizedDist);
  // Jet regions get extra heat
  temp += jetIntensity * 2000.0 * exp(-abs(diskDist - 2.0));
  return temp;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let res = vec2<f32>(u.config.z, u.config.w);
  if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }
  let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
  let uv = (fragCoord * 2.0 - res) / res.y;
  let screenUV = fragCoord / res;

  let diskDensity = u.zoom_params.x;
  let jetIntensity = u.zoom_params.y;
  let gravityWarp = u.zoom_params.z;
  let timeDilation = u.zoom_params.w;
  let spaghettification = u.config.y;

  let time = u.config.x * timeDilation * 0.5;
  let audioOverall = u.config.y;
  let audioReactivity = 1.0 + audioOverall * 0.5;

  var ro = vec3<f32>(0.0, 1.5, -4.0);
  var rd = normalize(vec3<f32>(uv, 1.0));

  let camRotX = rotate2D(0.3);
  let camRotY = rotate2D(time * 0.1 * audioReactivity);
  let temp_ro_yz = camRotX * ro.yz;
  ro.y = temp_ro_yz.x;
  ro.z = temp_ro_yz.y;
  let temp_rd_yz = camRotX * rd.yz;
  rd.y = temp_rd_yz.x;
  rd.z = temp_rd_yz.y;
  let temp_ro_xz = camRotY * ro.xz;
  ro.x = temp_ro_xz.x;
  ro.z = temp_ro_xz.y;
  let temp_rd_xz = camRotY * rd.xz;
  rd.x = temp_rd_xz.x;
  rd.z = temp_rd_xz.y;

  let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
  let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
  let mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, 0.0);
  let mouseDist = distance(ro, mousePos);
  if (mouseDist > 0.1) {
    let mouseGravityStrength = 0.5;
    rd = normalize(rd + (mousePos - ro) * (mouseGravityStrength / pow(mouseDist, 2.0)));
  }

  var col = vec3<f32>(0.0);
  var t = 0.0;
  var glow = vec3<f32>(0.0);

  for(var i=0; i<100; i++) {
    var p = ro + rd * t;
    let distToOrigin = length(p);
    if (distToOrigin > 0.01) {
      p += normalize(p) * (gravityWarp * 0.5 / distToOrigin);
    }

    let dBlackHole = length(p) - 0.8;
    var pDisk = p;
    pDisk.y *= 5.0;
    var dDisk = sdTorus(pDisk, vec2<f32>(2.0, 0.4 * diskDensity));
    let n = fbm(pDisk * 2.0 + vec3<f32>(time * 2.0 * audioReactivity, spaghettification * 5.0, time * 2.0 * audioReactivity));
    dDisk += n * 0.5;

    var pJet = p;
    let dJet = length(pJet.xz) - 0.1 / (abs(pJet.y) + 0.1);

    let d = min(dBlackHole, dDisk);

    if (d < 0.01) {
      if (d == dBlackHole) {
        col = vec3<f32>(0.0);
      } else if (d == dDisk) {
        let diskDist = length(pDisk.xz);
        let temp = diskTemperature(diskDist, diskDensity, jetIntensity);
        let thermal = blackbodyColor(temp);
        // Heat increases toward inner disk
        let heat = clamp(1.0 - (diskDist - 1.0) * 0.3, 0.0, 1.0);
        col = thermal * heat * 2.0;
      }
      break;
    }

    // Photon sphere bloom - white-hot
    glow += vec3<f32>(1.0, 0.9, 1.0) * 0.02 / (abs(dBlackHole) + 0.05);
    // Jets - blue-white
    let jetTemp = 15000.0;
    let jetColor = blackbodyColor(jetTemp);
    glow += jetColor * (0.01 * jetIntensity * (1.0 + sin(spaghettification))) / (abs(dJet) + 0.05);
    // Disk ambient - warm
    let ambTemp = 4000.0;
    let ambColor = blackbodyColor(ambTemp);
    glow += ambColor * 0.005 / (abs(dDisk) + 0.1);

    t += d * 0.5;
    if (distToOrigin < 0.8) {
      col = vec3<f32>(0.0);
      break;
    }
    if(t > 20.0) { break; }
  }

  col += glow;
  col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

  // Tone map the HDR blackbody output
  col = toneMapACES(col * 1.5);

  let maxChannel = max(col.r, max(col.g, col.b));
  let exposure = max(0.0, maxChannel - 1.0);

  textureStore(dataTextureA, vec2<i32>(id.xy), vec4<f32>(col, exposure));
  textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, exposure + 0.1));

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, screenUV, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
