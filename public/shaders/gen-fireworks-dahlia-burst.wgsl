// ═══════════════════════════════════════════════════════════════════
//  Dahlia Burst
//  Category: generative
//  Features: flat petal-disk shells, layered petal rows, audio-reactive,
//            mouse dahlia burst, hex-bokeh, temporal feedback, aces-tone-map
//  Complexity: Medium-High
//  Created: 2026-07-12
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
  let d = length(uv - c);
  return (exp(-d*d/(r*r*0.45)) + 0.3*exp(-d/(r*2.8)))*i;
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
fn palette(t: f32) -> vec3<f32> {
  let h = fract(t);
  return clamp(vec3<f32>(abs(h*6.0-3.0)-1.0, abs(h*6.0-2.0)-1.0, abs(h*6.0-4.0)-1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Dahlia petal color: warm core → magenta/coral petals → gold tips
fn dahliaColor(petalT: f32, row: f32, seed: f32) -> vec3<f32> {
  let core = vec3<f32>(1.0, 0.95, 0.88);
  let inner = vec3<f32>(1.0, 0.35, 0.45);
  let outer = vec3<f32>(0.95, 0.55, 0.15);
  let tip = vec3<f32>(1.0, 0.82, 0.35);
  let hue = fract(seed * 1.7 + row * 0.15);
  let mid = mix(inner, outer, hue);
  let edge = mix(mid, tip, petalT);
  return mix(core, edge, smoothstep(0.0, 1.0, petalT));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

  let uv = (vec2<f32>(pixel) - res*0.5) / min(res.x, res.y);
  let sampleUV = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz - res*0.5) / min(res.x, res.y);

  let petalCount = mix(12.0, 36.0, u.zoom_params.x);
  let diskSize = mix(0.25, 0.75, u.zoom_params.y);
  let petalRows = mix(1.0, 4.0, u.zoom_params.z);
  let hueCycle = u.zoom_params.w;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.024);
  col += starField(uv);
  col += camera * 0.04;

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si * 37.0 + 11.0);
    let cycle = 2.2 * (0.85 + seed * 0.35);
    let birth = floor((time * 0.68 + seed * 1.4) / cycle) * cycle - seed * 1.4;
    let age = time - birth;
    if (age < 0.0 || age > 6.5) { continue; }

    let bx = (seed - 0.5) * 1.5;
    let by = -0.78;
    let bDelay = 1.1 + seed * 0.4;
    let bAge = max(0.0, age - bDelay);
    let energy = diskSize * (0.75 + bass * 0.55);
    if (energy < 0.01) { continue; }

    if (age < bDelay) {
      let y = mix(by, by + 1.15, (age / bDelay) * (age / bDelay));
      col += vec3<f32>(1.0, 0.88, 0.55) * softGlow(uv, vec2<f32>(bx, y), 0.009, energy * 2.0);
    }

    if (bAge > 0.0 && bAge < 5.8) {
      let center = vec2<f32>(bx, by + 1.2);
      let fade = smoothstep(5.2, 0.25, bAge);
      let rows = i32(petalRows + mids * 1.5);
      let petals = i32(petalCount + treble * 8.0);

      col += vec3<f32>(1.0) * exp(-bAge * 9.0) * energy * hexBokeh(uv, center, 0.06, 1.4);

      for (var row = 0; row < rows; row = row + 1) {
        let rf = f32(row);
        let rowDelay = rf * 0.08 * (1.0 + mids * 0.2);
        let rowAge = max(0.0, bAge - rowDelay);
        if (rowAge <= 0.0) { continue; }
        let rowRadius = energy * (0.15 + rf * 0.12) * rowAge;
        let rowFade = fade * exp(-rowAge * (1.2 + rf * 0.3));

        for (var p = 0; p < petals; p = p + 1) {
          let pf = f32(p);
          let ps = hash1(si * 71.0 + rf * 19.0 + pf * 2.9);
          let ang = pf / f32(petals) * TAU + seed * 0.3 + rf * 0.15;
          let petalWidth = 0.25 + ps * 0.2;
          let dir = vec2<f32>(cos(ang), sin(ang));
          let perp = vec2<f32>(-dir.y, dir.x);

          // Flat disk petal: elongate along radial direction
          let along = rowRadius * (0.6 + ps * 0.4);
          let across = petalWidth * 0.04 * energy;
          let petalCenter = center + dir * along * 0.5;
          let tipPos = center + dir * along + perp * across * (ps - 0.5);
          let fallPos = sparkPos(tipPos, dir * 0.08 + vec2<f32>(0.0, -0.05), rowAge * 0.5, GRAVITY * 0.3);

          let petalT = along / max(energy * 0.7, 0.01);
          let pc = dahliaColor(petalT, rf, seed + ps + hueCycle);
          let glowR = 0.004 + ps * 0.003 + rf * 0.001;
          col += pc * hexBokeh(uv, fallPos, glowR, rowFade * energy * (0.8 + treble * 0.3));
          col += pc * 0.4 * hexBokeh(uv, petalCenter, glowR * 1.5, rowFade * energy * 0.5);
        }
      }
    }
  }

  // Mouse dahlia — flat disk burst at cursor
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time * 0.9) * 3.5;
    if (mAge > 0.5) {
      let mb = mAge - 0.5;
      let mFade = smoothstep(2.8, 0.1, mb);
      let mPetals = i32(petalCount * 0.8);
      for (var p = 0; p < mPetals; p = p + 1) {
        let ang = f32(p) / f32(mPetals) * TAU;
        let dir = vec2<f32>(cos(ang), sin(ang));
        let tip = mouseUV + dir * diskSize * mb * 0.35;
        let fall = sparkPos(tip, dir * 0.06, mb * 0.4, GRAVITY * 0.25);
        let pc = dahliaColor(mb * 0.5, 0.0, hueCycle + f32(p) * 0.05);
        col += pc * hexBokeh(uv, fall, 0.005, mFade * diskSize);
      }
    }
  }

  col = mix(prev * 0.91, col, 0.33);
  col = acesToneMap(col * 1.12);
  col += vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0);

  let alpha = clamp(length(col) * 1.2 + 0.1, 0.12, 0.97);
  let persistent = col * 0.55 + prev * 0.38;
  textureStore(dataTextureB, pixel, vec4<f32>(persistent * alpha, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(col * alpha, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
