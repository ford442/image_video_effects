// Strobe Blink Shell — rhythmic multi-flash bursts (upgraded)
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
  config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const GRAVITY: f32 = 0.85;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
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
  let id = floor(uv*160.0);
  return vec3<f32>(0.8, 0.9, 1.0)*step(0.992, hash2(id))*0.35;
}
fn strobePulse(age: f32, rate: f32, bass: f32) -> f32 {
  let freq = 4.0 + rate * 12.0 + bass * 4.0;
  let wave = sin(age * freq * TAU) * 0.5 + 0.5;
  return pow(wave, 3.0);
}
fn flashColor(t: f32, colorAmt: f32, white: f32) -> vec3<f32> {
  let h = fract(t);
  let rgb = clamp(vec3<f32>(abs(h*6.0-3.0)-1.0, abs(h*6.0-2.0)-1.0, abs(h*6.0-4.0)-1.0), vec3<f32>(0.0), vec3<f32>(1.0));
  return mix(vec3<f32>(1.0,0.97,0.92), rgb, colorAmt) * white;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let sampleUV = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let flashRate = mix(0.2, 1.0, u.zoom_params.x);
  let pulsePow = mix(0.45, 1.6, u.zoom_params.y);
  let afterglow = mix(0.85, 0.96, u.zoom_params.z);
  let colorFlash = u.zoom_params.w;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.022);
  col += starField(uv);
  col += camera * 0.04;

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si*47.0+7.0);
    let cycle = 2.4*(0.8+seed*0.4);
    let birth = floor((time*0.65+seed*1.7)/cycle)*cycle-seed*1.7;
    let age = time-birth;
    if (age < 0.0 || age > 6.5) { continue; }
    let bx = (seed-0.5)*1.55;
    let by = -0.78;
    let bDelay = 1.15+seed*0.5;
    let bAge = max(0.0, age-bDelay);
    let energy = pulsePow*(0.7+bass*0.65);
    if (energy < 0.01) { continue; }

    if (age < bDelay) {
      let y = mix(by, by+1.2, (age/bDelay)*(age/bDelay));
      col += vec3<f32>(1.0,0.88,0.55)*softGlow(uv, vec2<f32>(bx,y), 0.009, energy*2.0);
    }
    if (bAge > 0.0 && bAge < 6.0) {
      let center = vec2<f32>(bx, by+1.22);
      let fade = smoothstep(5.5, 0.3, bAge);
      let pulse = strobePulse(bAge, flashRate, bass);
      let flash = pulse * energy * (1.0 + treble * 0.5);
      col += flashColor(seed, colorFlash, flash) * hexBokeh(uv, center, 0.05 + pulse * 0.04, 2.0);

      let n = i32(22.0 + energy * 28.0 + mids * 10.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si*83.0+jf*3.7);
        let ang = jf/f32(n)*TAU + (js-0.5)*0.5;
        let spd = (0.35+js*0.45)*energy;
        let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*spd, bAge, GRAVITY);
        let sparkFlash = mix(0.3, 1.0, pulse);
        col += flashColor(js+time*0.05, colorFlash, sparkFlash) * hexBokeh(uv, sp, 0.005+js*0.003, fade*energy);
      }

      if (bAge > 1.5) {
        let glowAge = bAge - 1.5;
        let glowFade = smoothstep(4.0, 0.0, glowAge) * afterglow;
        let embers = i32(8.0 + afterglow * 10.0);
        for (var e = 0; e < embers; e = e + 1) {
          let es = hash1(si*29.0+f32(e)*5.1);
          let epos = sparkPos(center, vec2<f32>((es-0.5)*0.4, -0.2-es*0.2), glowAge, 0.6);
          col += flashColor(es, colorFlash*0.7, glowFade) * softGlow(uv, epos, 0.004, glowFade*energy*0.6);
        }
      }
    }
  }

  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz-vec2<f32>(0.5))*res/min(res.x,res.y);
    let mAge = fract(time*1.1)*3.5;
    if (mAge > 0.5) {
      let mb = mAge-0.5;
      let pulse = strobePulse(mb, flashRate, bass);
      col += flashColor(time*0.1, colorFlash, pulse*pulsePow) * hexBokeh(uv, mUV, 0.06+pulse*0.05, 2.0);
      for (var k = 0; k < 25; k = k + 1) {
        let ang = f32(k)/25.0*TAU;
        let sp = sparkPos(mUV, vec2<f32>(cos(ang),sin(ang))*0.4*pulsePow, mb, GRAVITY);
        col += flashColor(f32(k)*0.1, colorFlash, pulse) * hexBokeh(uv, sp, 0.005, pulsePow);
      }
    }
  }

  col = mix(prev*afterglow, col, 0.32);
  col = acesToneMap(col*1.1);
  let alpha = clamp(length(col)*1.2+0.1, 0.12, 0.97);
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  let depthOut = clamp(dot(col, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
