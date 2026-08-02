// Fireworks Depth Parade — depth-sorted layer launches
// Batch 23: normalized pointer coordinates, discrete click barrages, and
// source/shell-derived depth while preserving the display feedback packing.
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
fn sampleDepth(uv: vec2<f32>) -> f32 {
  return textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv*0.5+0.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}
fn normToCentered(p: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  return (p * res - res * 0.5) / min(res.x, res.y);
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let layerSep = mix(0.15, 0.55, u.zoom_params.x);
  let speed = mix(0.4, 1.3, u.zoom_params.y);
  let depthBoost = mix(0.3, 1.2, u.zoom_params.z);
  let trail = mix(0.88, 0.96, u.zoom_params.w);
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(pixel)/res, 0.0).r;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let imgCol = sampleImg(uv);
  var col = imgCol * (0.5 + depth*0.15);
  var shellDepthSignal = 0.0;

  // Three depth layers: foreground (0.7+), mid (0.35-0.7), background (<0.35)
  let layers = 3;
  for (var layer = 0; layer < layers; layer = layer + 1) {
    let lf = f32(layer);
    let layerDepth = 0.85 - lf * 0.35;
    let layerDelay = lf * layerSep * 1.5;

    for (var s = 0; s < 3; s = s + 1) {
      let si = f32(s); let seed = hash1(lf*17.0+si*41.0+2.0);
      let probe = vec2<f32>((seed-0.5)*1.4, (hash1(si*73.0+lf)-0.5)*0.9);
      let pDepth = sampleDepth(probe);
      let depthMatch = 1.0 - abs(pDepth - layerDepth) / layerSep;
      if (depthMatch < 0.3) { continue; }

      let pCol = sampleImg(probe);
      let cycle = 3.0/speed;
      let birth = floor((time*speed*0.5+seed*2.0+lf*0.8)/cycle)*cycle-seed*2.0-lf*0.8;
      let age = time-birth; if (age < 0.0 || age > 5.5) { continue; }
      let layerAge = max(0.0, age - layerDelay);
      if (layerAge <= 0.0) { continue; }

      let energy = (0.5 + pDepth * depthBoost + bass*0.4) * depthMatch;
      let launchH = 0.5 + pDepth * depthBoost * 0.8;
      let center = probe + vec2<f32>(0.0, launchH);
      let fade = smoothstep(4.5, 0.2, layerAge);

      let launchGlow = exp(-layerAge*7.0) * energy * softGlow(uv, center, 0.04+lf*0.01, 1.2);
      col += pCol * launchGlow;
      shellDepthSignal = max(shellDepthSignal, launchGlow * layerDepth);
      let n = i32(14.0 + energy*22.0 + mids*8.0);
      for (var j = 0; j < n; j = j + 1) {
        let js = hash1(lf*31.0+si*11.0+f32(j)*2.5);
        let ang = f32(j)/f32(n)*TAU + js;
        let spd = (0.25+js*0.35)*energy*(0.7+pDepth*0.5);
        let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*spd, layerAge, 0.7+lf*0.15);
        let sparkGlow = softGlow(uv, sp, 0.005+js*0.003, fade*energy*(0.8+treble*0.4));
        col += pCol * sparkGlow;
        shellDepthSignal = max(shellDepthSignal, sparkGlow * layerDepth);
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mUV = normToCentered(u.zoom_config.yz, res);
    let mDepth = sampleDepth(mUV);
    let mCol = sampleImg(mUV);
    let mAge = fract(time*1.0)*3.0;
    if (mAge > 0.5) {
      let mb = mAge-0.5;
      let energy = (0.6+mDepth*depthBoost+bass*0.5);
      for (var k = 0; k < 30; k = k + 1) {
        let ang = f32(k)/30.0*TAU;
        let sp = sparkPos(mUV+vec2<f32>(0.0,mDepth*0.3), vec2<f32>(cos(ang),sin(ang))*0.45*energy, mb, 0.8);
        let mouseGlow = softGlow(uv, sp, 0.006, smoothstep(2.5,0.1,mb)*energy);
        col += mCol * mouseGlow;
        shellDepthSignal = max(shellDepthSignal, mouseGlow * mDepth);
      }
    }
  }

  // Discrete depth parade: every click launches foreground, midground, then
  // background shells from the ripple position. Source depth weights each
  // layer, while the timestamp makes the barrage one-shot and sortable.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let clickAge = time - rp.z;
    if (clickAge < 0.0 || clickAge > 4.2) { continue; }
    let clickOrigin = normToCentered(rp.xy, res);
    let clickDepth = sampleDepth(clickOrigin);
    let clickColor = sampleImg(clickOrigin);
    for (var dl = 0; dl < 3; dl = dl + 1) {
      let dlf = f32(dl);
      let layerDepth = 0.85 - dlf * 0.35;
      let barrageAge = clickAge - dlf * layerSep * 0.9;
      if (barrageAge < 0.0 || barrageAge > 3.0) { continue; }
      let depthMatch = clamp(1.0 - abs(clickDepth - layerDepth) / max(layerSep, 0.15), 0.2, 1.0);
      let seed = hash1(f32(ri) * 43.0 + dlf * 17.0 + rp.x * 61.0);
      let shellCenter = clickOrigin + vec2<f32>((seed - 0.5) * 0.18, -0.28 - layerDepth * 0.24);
      let shellEnergy = (0.65 + clickDepth * depthBoost + bass * 0.35) * depthMatch;
      let shellFade = smoothstep(2.8, 0.10, barrageAge);
      let sparkCount = 18 + i32(mids * 8.0 + layerDepth * 10.0);
      for (var bj = 0; bj < sparkCount; bj = bj + 1) {
        let jf = f32(bj);
        let jitter = hash1(seed * 89.0 + jf * 7.0);
        let ang = jf / f32(sparkCount) * TAU + jitter * 0.35;
        let velocity = vec2<f32>(cos(ang), sin(ang)) * (0.28 + jitter * 0.28) * shellEnergy;
        let spark = sparkPos(shellCenter, velocity, barrageAge, 0.65 + dlf * 0.12);
        let clickGlow = softGlow(uv, spark, 0.005 + jitter * 0.003,
          shellFade * shellEnergy * (0.75 + treble * 0.35));
        col += clickColor * clickGlow;
        shellDepthSignal = max(shellDepthSignal, clickGlow * layerDepth);
      }
    }
  }
  col = mix(prev*trail, col, 0.32);
  col = acesToneMap(col*1.06);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.5+prev*0.4, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.12, 0.96)));
  let shellLuma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
  let depthOut = clamp(max(depth * 0.85, shellDepthSignal + shellLuma * 0.28), 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
