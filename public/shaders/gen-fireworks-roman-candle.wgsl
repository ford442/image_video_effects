// Roman Candle — vertical star barrage from launch tubes
// Batch 23: normalized mouse launches, discrete click candles, treble detail,
// and luminance-derived depth without changing the display feedback packing.
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
  let d = length(uv-c); return (exp(-d*d/(r*r*0.5))+0.35*exp(-d/(r*3.0)))*i;
}
fn starCol(i: f32) -> vec3<f32> {
  let cols = array<vec3<f32>, 5>(
    vec3<f32>(1.0,0.2,0.15), vec3<f32>(0.2,0.75,1.0), vec3<f32>(1.0,0.85,0.3),
    vec3<f32>(0.3,1.0,0.5), vec3<f32>(1.0,0.5,0.9));
  return cols[i32(i*4.99) % 5];
}
// Mouse and ripple positions arrive as normalized canvas UVs. Convert them to
// this shader's centered, min-resolution coordinate space before launching.
fn normToCentered(p: vec2<f32>, res: vec2<f32>) -> vec2<f32> {
  return (p * res - res * 0.5) / min(res.x, res.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let mouseUV = normToCentered(u.zoom_config.yz, res);
  let fireRate = mix(0.3, 1.2, u.zoom_params.x);
  let starSize = mix(0.004, 0.014, u.zoom_params.y);
  let tubeSpread = mix(0.3, 1.0, u.zoom_params.z);
  let trailLen = mix(0.88, 0.96, u.zoom_params.w);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let trebleDetail = clamp(treble, 0.0, 1.5);
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.022);

  let numTubes = 6;
  for (var t = 0; t < numTubes; t = t + 1) {
    let tf = f32(t); let seed = hash1(tf*19.0+1.0);
    let tubeX = (seed-0.5)*1.8*tubeSpread;
    let tubeY = -0.82;
    let shotInterval = 0.35/fireRate;
    let numShots = i32(8.0+fireRate*10.0);
    for (var shot = 0; shot < numShots; shot = shot + 1) {
      let sf = f32(shot);
      let shotTime = sf*shotInterval + seed*0.5;
      let cycle = f32(numShots)*shotInterval + 1.5;
      let birth = floor(time/cycle)*cycle + shotTime;
      let age = time - birth;
      if (age < 0.0 || age > 3.5) { continue; }
      let energy = (0.7+bass*0.5)*(1.0+seed*0.2);
      let starY = tubeY + age*1.8*energy;
      let starPos = vec2<f32>(tubeX + sin(age*(3.0+mids*1.5)+seed*10.0)*0.02*(1.0+mids), starY);
      let fade = smoothstep(3.0, 0.1, age);
      let sz = starSize*(1.0+bass*0.2);
      col += starCol(seed+sf*0.1)*softGlow(uv, starPos, sz, fade*energy*2.0);
      // Comet trail
      let trailSamples = 4 + i32(trebleDetail * 3.0);
      for (var tr = 1; tr <= trailSamples; tr = tr + 1) {
        let trf = f32(tr)*0.08;
        let trailPos = vec2<f32>(starPos.x, starY - trf*0.15);
        col += starCol(seed)*softGlow(uv, trailPos, sz*0.6, fade*energy*(1.0-trf*0.8)*0.7);
      }
      // Mini burst at apex
      if (age > 1.2 && age < 2.5) {
        let bAge = age-1.2;
        let burstY = tubeY + 1.2*energy;
        let burstC = vec2<f32>(tubeX, burstY);
        let burstSparks = 10 + i32(trebleDetail * 8.0);
        for (var sp = 0; sp < burstSparks; sp = sp + 1) {
          let ang = f32(sp)/f32(burstSparks)*TAU;
          let bp = burstC + vec2<f32>(cos(ang), sin(ang))*bAge*0.25*energy;
          col += starCol(seed)*softGlow(uv, bp, sz*0.8, fade*exp(-bAge*2.0)*energy*0.8);
        }
      }
    }
    // Tube glow at base
    col += vec3<f32>(0.8,0.4,0.1)*softGlow(uv, vec2<f32>(tubeX, tubeY), 0.012, 0.4+treble*0.3);
  }
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time*1.5);
    let shots = i32(5.0+fireRate*5.0);
    for (var s = 0; s < shots; s = s + 1) {
      let sa = f32(s)*0.15;
      if (mAge < sa || mAge > sa+0.4) { continue; }
      let localAge = mAge-sa;
      let sp = mouseUV + vec2<f32>(0.0, localAge*1.5);
      col += starCol(f32(s)*0.2)*softGlow(uv, sp, starSize*1.5, (1.0-localAge*2.5)*(0.8+bass));
    }
  }

  // Every click is a discrete personal Roman candle. Ripple timestamps make
  // the launch one-shot, unlike the held-fire cadence above.
  let rippleCount = min(u32(u.config.y), 50u);
  for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
    let rp = u.ripples[ri];
    let clickAge = time - rp.z;
    if (clickAge < 0.0 || clickAge > 2.8) { continue; }
    let origin = normToCentered(rp.xy, res);
    let clickSeed = hash1(f32(ri) * 23.0 + rp.x * 71.0 + rp.y * 37.0);
    let clickShots = 4 + i32(fireRate * 3.0 + trebleDetail * 2.0);
    for (var cs = 0; cs < clickShots; cs = cs + 1) {
      let localAge = clickAge - f32(cs) * 0.10;
      if (localAge < 0.0 || localAge > 1.7) { continue; }
      let jitter = hash1(clickSeed * 91.0 + f32(cs) * 17.0) - 0.5;
      let energy = 0.85 + bass * 0.45 + trebleDetail * 0.12;
      let launch = origin + vec2<f32>(jitter * 0.08, localAge * 0.75 * energy);
      let clickFade = smoothstep(1.7, 0.05, localAge);
      let clickColor = starCol(clickSeed + f32(cs) * 0.17);
      col += clickColor * softGlow(uv, launch, starSize * 1.2, clickFade * energy * 1.4);
      let glitterCount = 3 + i32(trebleDetail * 4.0);
      for (var gs = 0; gs < glitterCount; gs = gs + 1) {
        let ga = hash1(f32(gs) * 31.0 + clickSeed) * TAU;
        let gp = launch + vec2<f32>(cos(ga), sin(ga)) * localAge * 0.035;
        col += clickColor * softGlow(uv, gp, starSize * 0.45,
          clickFade * (0.2 + trebleDetail * 0.25));
      }
    }
  }
  col = mix(prev*trailLen, col, 0.35);
  let dust = step(0.987-treble*0.03, hash1(dot(uv, vec2<f32>(127.1,311.7))+time*8.0));
  col += vec3<f32>(0.7,0.85,1.0)*dust*treble*0.5;
  col = acesToneMap(col*1.08);
  let alpha = clamp(length(col)*1.1+0.14, 0.14, 0.96);
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  let depthOut = clamp(dot(col, vec3<f32>(0.299, 0.587, 0.114)) * 0.95, 0.0, 1.0);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
