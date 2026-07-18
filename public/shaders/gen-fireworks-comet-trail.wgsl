// ═══ gen-fireworks-comet-trail ═══════════════════════════════════════
//  Category: generative
//  Features: audio-reactive, mouse-driven, fireworks, temporal,
//            aces-tone-map, ign-dither, semantic-alpha, premultiplied-alpha
//  Complexity: Medium

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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;
const GRAVITY: f32 = 0.85;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
  return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx)*0.1031); p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y)*p3.z);
}
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv-c);
  return (exp(-d*d/(r*r*0.45))+0.3*exp(-d/(r*2.8)))*i;
}
fn hexBokeh(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = uv - c;
  let q = vec2<f32>(d.x*1.2 + d.y*0.6, d.y);
  return softGlow(uv, c, r, i)*(0.7 + 0.3*smoothstep(r*0.5, r*1.5, length(q)));
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
fn starField(uv: vec2<f32>) -> vec3<f32> {
  return vec3<f32>(0.8, 0.9, 1.0)*step(0.992, hash2(floor(uv*160.0)))*0.35;
}
fn cometColor(t: f32, shift: f32) -> vec3<f32> {
  let h = fract(t+shift);
  return clamp(vec3<f32>(abs(h*6.0-3.0)-1.0, abs(h*6.0-2.0)-1.0, abs(h*6.0-4.0)-1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let sampleUV = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let speed = mix(0.4, 1.4, u.zoom_params.x);
  let trailLen = mix(0.3, 0.95, u.zoom_params.y);
  let colorShift = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let headBright = mix(0.5, 1.8, u.zoom_params.z) * (1.0 + bass * 0.4);
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.022);
  col += starField(uv);
  col += camera * 0.04;

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si*43.0+5.0);
    let cycle = 2.0*(0.8+seed*0.4);
    let birth = floor((time*(0.55+bass*0.35)+seed*1.6)/cycle)*cycle-seed*1.6;
    let age = time-birth;
    if (age < 0.0 || age > 5.5) { continue; }
    let bx = (seed-0.5)*1.6;
    let energy = speed*(0.7+bass*0.6)*headBright;
    if (energy < 0.01) { continue; }
    let angle = seed*TAU*0.3 + 0.2;
    let vel = vec2<f32>(sin(angle)*0.15, 1.0)*energy;
    let headPos = sparkPos(vec2<f32>(bx, -0.75), vel, age, 0.12);
    let fade = smoothstep(5.0, 0.2, age);

    col += vec3<f32>(1.0,0.95,0.85)*hexBokeh(uv, headPos, 0.012+energy*0.006, fade*energy*2.5);
    col += cometColor(seed, colorShift)*hexBokeh(uv, headPos, 0.008, fade*energy*1.2);

    let trailSteps = i32(8.0 + trailLen*14.0);
    for (var t = 0; t < trailSteps; t = t + 1) {
      let tf = f32(t)/f32(trailSteps);
      let trailAge = max(0.0, age - tf*1.5);
      let tPos = sparkPos(vec2<f32>(bx, -0.75), vel, trailAge, 0.12);
      let tFade = fade*(1.0-tf)*(0.6+hash1(si+f32(t))*0.4);
      col += cometColor(seed+tf*0.3, colorShift) * hexBokeh(uv, tPos, 0.005+tf*0.004, tFade*energy*1.4);
    }

    if (age > 0.5 && age < 4.0) {
      let n = i32(8.0 + treble*18.0);
      for (var j = 0; j < n; j = j + 1) {
        let js = hash1(si*61.0+f32(j)*4.1);
        let peelAge = max(0.0, age - 0.5 - js*0.8);
        let peelAng = js*TAU;
        let peelPos = headPos + vec2<f32>(cos(peelAng), sin(peelAng))*peelAge*0.2 - vec2<f32>(0.0, peelAge*peelAge*0.3);
        col += cometColor(js, colorShift)*hexBokeh(uv, peelPos, 0.004, fade*treble*0.9);
      }
    }

    if (age > 1.8 && age < 3.5) {
      let bAge = age-1.8;
      for (var b = 0; b < 14; b = b + 1) {
        let ang = f32(b)/14.0*TAU;
        let bp = headPos + vec2<f32>(cos(ang), sin(ang))*bAge*0.35*energy;
        col += cometColor(seed+f32(b)*0.05, colorShift)*hexBokeh(uv, bp, 0.005, exp(-bAge*2.0)*energy);
      }
    }
  }

  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
    let mAge = fract(time*1.2)*3.0;
    let mVel = vec2<f32>(0.0, 1.0)*speed*headBright;
    let head = mUV + mVel*mAge;
    col += vec3<f32>(1.0)*hexBokeh(uv, head, 0.015, (1.0-mAge*0.4)*headBright);
    for (var t = 0; t < 10; t = t + 1) {
      let tf = f32(t)*0.12;
      col += cometColor(tf, colorShift)*hexBokeh(uv, head-mVel*tf, 0.006, (1.0-tf*3.0)*headBright);
    }
  }

  col = mix(prev*mix(0.88, 0.95, trailLen), col, 0.32);
  col = acesToneMap(col*1.08);
  col += vec3<f32>(ign(vec2<f32>(pixel))) / 255.0;
  let alpha = clamp(length(col)*1.2+0.1, 0.12, 0.96);
  let persistent = col*0.55 + prev*0.38;
  textureStore(dataTextureB, pixel, vec4<f32>(persistent, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col*alpha, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}