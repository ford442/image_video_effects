// Patriotic July 4th Pyro — red white blue image fireworks
// Slider map (saved-preset contract — ids/defaults unchanged):
//   x Patriot Mix  : image-hue vs red/white/blue palette blend (0.3..1.0)
//   y Burst Power  : shell energy, spark count, velocity, finale radius (0.35..1.6)
//   z Stripe Wave  : waving flag-stripe tint amplitude + scroll speed (0..1)
//   w Sparkle      : star-field density + crackle finale brightness (0.2..1.0)
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
const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv-c); return (exp(-d*d/(r*r*0.5))+0.3*exp(-d/(r*3.0)))*i;
}
fn sampleImg(uv: vec2<f32>) -> vec3<f32> {
  return textureSampleLevel(readTexture, u_sampler, clamp(uv*0.5+0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
fn patriotColor(t: f32, mix_: f32, imgCol: vec3<f32>) -> vec3<f32> {
  let red = vec3<f32>(1.0, 0.15, 0.1);
  let white = vec3<f32>(0.95, 0.97, 1.0);
  let blue = vec3<f32>(0.15, 0.35, 1.0);
  let band = fract(t * 3.0);
  var p = red;
  if (band < 0.33) { p = mix(red, white, band/0.33); }
  else if (band < 0.66) { p = mix(white, blue, (band-0.33)/0.33); }
  else { p = mix(blue, red, (band-0.66)/0.34); }
  return mix(imgCol, p, mix_);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let patriot = mix(0.3, 1.0, u.zoom_params.x);
  let power = mix(0.35, 1.6, u.zoom_params.y);
  let wave = mix(0.0, 1.0, u.zoom_params.z);
  let sparkle = mix(0.2, 1.0, u.zoom_params.w);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let imgCol = sampleImg(uv);
  let lum = dot(imgCol, vec3<f32>(0.299,0.587,0.114));
  // Waving flag stripes: mids rocks the stripe phase, wave slider sets scroll speed
  let stripe = sin(uv.y*12.0 + time*wave*2.0 + mids*0.3*sin(uv.x*7.0 + time*1.7))*0.5+0.5;
  var col = imgCol * (0.5 + lum*0.2);
  col = mix(col, patriotColor(stripe, patriot, imgCol), wave*0.15*lum*(0.7+mids*0.3));

  for (var s = 0; s < 8; s = s + 1) {
    let si = f32(s); let seed = hash1(si*33.0+7.0);
    let probe = vec2<f32>((seed-0.5)*1.5, (hash1(si*59.0)-0.5)*1.1);
    let pCol = sampleImg(probe);
    let pLum = dot(pCol, vec3<f32>(0.299,0.587,0.114));
    let cycle = 1.8;
    let birth = floor((time*(0.75+bass*0.15)+seed*1.2)/cycle)*cycle-seed*1.2;
    let age = time-birth; if (age < 0.0 || age > 5.0) { continue; }
    let energy = power * (0.5+pLum*0.8+bass*0.5);
    let bAge = max(0.0, age-0.7);
    if (bAge > 0.0) {
      let center = probe + vec2<f32>(0.0, 0.35);
      let fade = smoothstep(4.5, 0.2, bAge);
      col += patriotColor(seed, patriot, pCol) * exp(-bAge*8.0) * energy * softGlow(uv, center, 0.055, 1.5);
      let n = i32(22.0 + power*30.0);
      for (var j = 0; j < n; j = j + 1) {
        let js = hash1(si*47.0+f32(j)*2.9);
        let ang = f32(j)/f32(n)*TAU + js;
        let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*(0.3+js*0.45)*energy, bAge, 0.85);
        col += patriotColor(js+time*0.05, patriot, pCol) * softGlow(uv, sp, 0.006, fade*energy*(0.8+treble*0.5));
      }
    }
  }
  // Twinkling star field: patriotic pin-stars hiding in the dark sky regions
  let starCell = floor(uv * 24.0);
  let starH = hash1(dot(starCell, vec2<f32>(17.3, 41.7)));
  if (starH > 1.0 - sparkle * 0.05) {
    let starPos = (starCell + vec2<f32>(hash1(starH*91.0), hash1(starH*57.0))) / 24.0;
    let twinkle = 0.5 + 0.5 * sin(time * (2.0 + starH * 6.0) + starH * 40.0);
    col += patriotColor(starH, patriot, imgCol) * softGlow(uv, starPos, 0.004, twinkle * sparkle * (1.0 - lum) * 0.7);
  }
  // Bass mortar flash: each boom lifts a warm launch glow off the bottom edge
  let mortarIdx = floor(time * (0.75 + bass * 0.15) / 1.8);
  let mortarPhase = fract(time * (0.75 + bass * 0.15) / 1.8);
  let mortarPos = vec2<f32>((hash1(mortarIdx * 3.7) - 0.5) * 1.2, -0.55);
  let mortarGlow = exp(-mortarPhase * 6.0) * bass * softGlow(uv, mortarPos, 0.16, 1.0);
  col += patriotColor(hash1(mortarIdx * 3.7), patriot, imgCol) * mortarGlow * power;

  let spk = step(0.985-sparkle*0.04, hash1(dot(uv,vec2<f32>(127.0,311.0))+time*15.0));
  col += patriotColor(time*0.1, patriot, vec3<f32>(1.0)) * spk * sparkle * treble * 0.8;
  // Crackle afterglow: slow-decay ember grid riding the treble finale
  let crackleSeed = floor(time * 8.0);
  let crackle = step(0.99-sparkle*0.03, hash1(dot(uv,vec2<f32>(311.0,127.0)) + crackleSeed*0.37));
  col += patriotColor(crackleSeed*0.37, patriot, vec3<f32>(1.0)) * crackle * exp(-fract(time*8.0)*5.0) * sparkle * treble * 0.5;
  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);
    let mAge = fract(time*1.3)*2.8;
    if (mAge > 0.4) {
      for (var k = 0; k < 40; k = k + 1) {
        let ang = f32(k)/40.0*TAU;
        let sp = sparkPos(mUV, vec2<f32>(cos(ang),sin(ang))*0.5*power, mAge-0.4, 0.8);
        col += patriotColor(f32(k)*0.1, patriot, sampleImg(mUV)) * softGlow(uv, sp, 0.006, smoothstep(2.5,0.1,mAge)*power);
      }
    }
  }
  // Grand finale: every live click ripple launches a one-shot patriotic shell
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rip = u.ripples[ri];
    let rAge = time - rip.z;
    if (rAge < 0.0 || rAge > 4.2) { continue; }
    // rip.xy is NORMALIZED [0,1] — same unit fix as the mouse barrage
    let rUV = (rip.xy * res - res * 0.5) / min(res.x, res.y);
    let rCol = sampleImg(rUV);
    let rSeed = f32(ri % 3u) * 0.11; // cycles red -> white -> blue by click index
    let rise = min(rAge, 0.6);
    let rCenter = rUV + vec2<f32>(0.0, rise * 0.45);
    if (rAge < 0.6) {
      // ascending shell: bright comet head + short fading tail
      col += patriotColor(rSeed, patriot, rCol) * softGlow(uv, rCenter, 0.02, 1.4 * power);
      col += patriotColor(rSeed, patriot, rCol) * softGlow(uv, rCenter - vec2<f32>(0.0, 0.05), 0.03, 0.5 * power);
    } else {
      let fAge = rAge - 0.6; // burst at age 0.6
      let rFade = smoothstep(3.6, 0.15, fAge);
      col += patriotColor(rSeed, patriot, rCol) * exp(-fAge * 9.0) * power * softGlow(uv, rCenter, 0.06, 1.6);
      let fn_ = i32(26.0 + power * 26.0);
      for (var q = 0; q < fn_; q = q + 1) {
        let qs = hash1(f32(ri) * 13.7 + f32(q) * 3.1);
        let qAng = f32(q) / f32(fn_) * TAU + qs;
        let qSp = sparkPos(rCenter, vec2<f32>(cos(qAng), sin(qAng)) * (0.35 + qs * 0.4) * power, fAge, 0.8);
        col += patriotColor(rSeed + qs * 0.05, patriot, rCol) * softGlow(uv, qSp, 0.006, rFade * power * (0.8 + treble * 0.5));
      }
    }
  }
  col = mix(prev*0.92, col, 0.33);
  col = acesToneMap(col*1.1);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.5+prev*0.4, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.12, 0.97)));
  // Honest depth: shells and stripes sit forward, dark sky recedes
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(dot(col, vec3<f32>(0.299,0.587,0.114)) * 0.9 + stripe * 0.15, 0.0, 1.0)));
}
