// Fireworks Portrait Burst — bright regions detonate
// Upgraded (Batch 18): fixed mouse coordinate bug, honest luminance depth,
// one-shot ripple click bursts. Spark physics preserved verbatim.
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
const lumWeights: vec3<f32> = vec3<f32>(0.299, 0.587, 0.114);

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

// Convert a normalized [0,1] screen point to the shader's centered aspect
// space (same convention as the per-pixel `uv`). zoom_config.yz and
// ripples[].xy are NORMALIZED — multiplying by res turns them into pixels.
fn normToCentered(p: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  return (p * res - res * 0.5) / min(res.x, res.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;

  // --- Sliders (zoom_params) drive real algorithm constants ---
  // thresh:     minimum image luminance that may seed a detonation core.
  // burstSize:  per-burst energy (spark count, speed, radius, brightness).
  // dissolve:   how hard bright regions are dimmed when they detonate.
  // warmth:     spark palette — 0 = inherit source color, 1 = hot ember gold.
  let thresh = mix(0.1, 0.75, u.zoom_params.x);
  let burstSize = mix(0.4, 1.5, u.zoom_params.y);
  let dissolve = mix(0.1, 0.7, u.zoom_params.z);
  let warmth = u.zoom_params.w;
  let ember = vec3<f32>(1.0, 0.7, 0.3);

  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let imgCol = sampleImg(uv);
  let lum = dot(imgCol, lumWeights);
  let bright = smoothstep(thresh*0.5, thresh, lum);
  let dissolveAmt = bright * dissolve * (0.3 + bass*0.2);
  var col = imgCol * (0.55 - dissolveAmt*0.4);
  var sparkGlow = 0.0;

  // --- Auto detonations: 7 probes search for bright cores in the image ---
  for (var s = 0; s < 7; s = s + 1) {
    let si = f32(s); let seed = hash1(si*29.0+3.0);
    let probe = vec2<f32>((seed-0.5)*1.4, (hash1(si*51.0)-0.5)*1.0);
    let pCol = sampleImg(probe);
    let pLum = dot(pCol, lumWeights);
    if (pLum < thresh * 0.6) { continue; }
    let cycle = 2.2/(0.6+mids*0.2);
    let birth = floor((time*0.65+seed*1.4)/cycle)*cycle-seed*1.4;
    let age = time-birth; if (age < 0.0 || age > 5.5) { continue; }
    let energy = burstSize * pLum * (0.65+bass*0.7);
    let bAge = max(0.0, age-0.8);
    if (bAge > 0.0 && bAge < 4.5) {
      let center = probe + vec2<f32>(0.0, 0.3);
      let fade = smoothstep(4.0, 0.2, bAge);
      let coreGlow = softGlow(uv, center, 0.05, 1.0);
      col += pCol * exp(-bAge*9.0) * energy * 2.0 * coreGlow;
      sparkGlow += coreGlow * energy * exp(-bAge*9.0);
      let n = i32(20.0 + energy*35.0);
      for (var j = 0; j < n; j = j + 1) {
        let js = hash1(si*71.0+f32(j)*3.1);
        let ang = f32(j)/f32(n)*TAU + (js-0.5)*0.8;
        let spd = (0.3+js*0.5)*energy;
        let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*spd, bAge, 0.9);
        var sc = mix(pCol, ember, warmth*0.4);
        sc = mix(sc, vec3<f32>(1.0,0.95,0.85), smoothstep(0.5,0.0,bAge*0.3));
        let sg = softGlow(uv, sp, 0.006+js*0.004, fade*energy*(0.85+treble*0.5));
        col += sc * sg;
        sparkGlow += sg * 0.25;
      }
    }
  }

  // --- Held mouse: auto-repeat burst at the cursor ---
  // FIXED: zoom_config.yz is normalized [0,1]; convert to pixels first,
  // otherwise the burst detonates hundreds of pixels off-screen.
  if (u.zoom_config.w > 0.5) {
    let mUV = normToCentered(u.zoom_config.yz, res);
    let mCol = sampleImg(mUV);
    let mAge = fract(time*1.1)*3.0;
    if (mAge > 0.5) {
      let mb = mAge-0.5;
      for (var k = 0; k < 35; k = k + 1) {
        let ang = f32(k)/35.0*TAU;
        let sp = sparkPos(mUV, vec2<f32>(cos(ang),sin(ang))*0.55*burstSize, mb, 0.85);
        let msc = mix(mCol, ember, warmth*0.35);
        let sg = softGlow(uv, sp, 0.007, smoothstep(2.5,0.1,mb)*burstSize);
        col += msc * sg;
        sparkGlow += sg * 0.25;
      }
    }
  }

  // --- Click ripples: every individual click fires a one-shot burst ---
  // ripples[].xy = normalized click position, .z = click time.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let rAge = time - rp.z;
    if (rAge < 0.0 || rAge > 3.0) { continue; }
    let rUV = normToCentered(rp.xy, res);
    let rCol = sampleImg(rUV);
    let rEnergy = burstSize * (0.7 + bass*0.5);
    // Core flash at the click point for the first instant.
    let flash = exp(-rAge*7.0) * rEnergy * 1.5;
    let coreS = softGlow(uv, rUV, 0.04, flash);
    col += rCol * coreS;
    sparkGlow += coreS;
    // One-shot spark burst, same spark pipeline as the held-mouse burst.
    let rb = max(0.0, rAge - 0.15);
    let rFade = smoothstep(2.6, 0.1, rb);
    for (var q = 0; q < 28; q = q + 1) {
      let js = hash1(f32(ri)*97.0 + f32(q)*3.7);
      let ang = f32(q)/28.0*TAU + (js-0.5)*0.7;
      let spd = (0.35+js*0.35) * rEnergy;
      let sp = sparkPos(rUV, vec2<f32>(cos(ang),sin(ang))*spd, rb, 0.85);
      let rsc = mix(rCol, ember, warmth*0.4);
      let sg = softGlow(uv, sp, 0.006+js*0.004, rFade*rEnergy*(0.85+treble*0.5));
      col += rsc * sg;
      sparkGlow += sg * 0.25;
    }
  }

  // --- Temporal echo + tonemap (display state / dimmed echo stay raw) ---
  col = mix(prev*0.91, col, 0.33);
  col = acesToneMap(col*1.06);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.52+prev*0.38, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.12, 0.96)));

  // --- Honest depth: bright bursts sit forward instead of flat 0.0 ---
  let depthOut = clamp(dot(col, lumWeights) * 0.8 + sparkGlow * 0.2, 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut));
}
