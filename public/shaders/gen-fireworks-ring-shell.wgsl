// Ring Shell — circular halo/donut burst fireworks
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
fn hash2(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx)*0.1031); p3 += dot(p3,p3.yzx+33.33);
  return fract((p3.x+p3.y)*p3.z);
}
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv-c); return (exp(-d*d/(r*r*0.45))+0.3*exp(-d/(r*2.5)))*i;
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
fn ringColor(t: f32, cycle: f32) -> vec3<f32> {
  let h = fract(t + cycle);
  let r = abs(h*6.0-3.0)-1.0; let g = abs(h*6.0-2.0)-1.0; let b = abs(h*6.0-4.0)-1.0;
  return clamp(vec3<f32>(r,g,b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
  let ringR = mix(0.2, 0.55, u.zoom_params.x);
  let thick = mix(0.02, 0.12, u.zoom_params.y);
  let count = mix(0.4, 1.2, u.zoom_params.z);
  let colorC = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.025);
  col += vec3<f32>(0.8)*step(0.993, hash2(floor(uv*130.0)))*0.5;

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s); let seed = hash1(si*31.0+2.0);
    let cycle = 2.0*(0.85+seed*0.35);
    let birth = floor((time*(0.7+bass*0.15)+seed*1.5)/cycle)*cycle-seed*1.5;
    let age = time-birth; if (age < 0.0 || age > 6.5) { continue; }
    let bx = (seed-0.5)*1.6; let by = -0.78;
    let bDelay = 1.1+seed*0.5; let bAge = max(0.0, age-bDelay);
    let energy = (0.7+bass*0.6)*(1.0+count*0.3);
    if (age < bDelay) {
      let y = mix(by, by+1.2, (age/bDelay)*(age/bDelay));
      col += vec3<f32>(1.0,0.9,0.6)*softGlow(uv, vec2<f32>(bx,y), 0.009, energy*2.0);
    }
    if (bAge > 0.0 && bAge < 5.5) {
      let center = vec2<f32>(bx, by+1.25);
      let fade = smoothstep(5.0, 0.3, bAge);
      col += vec3<f32>(1.0)*exp(-bAge*12.0)*energy*softGlow(uv, center, 0.06, 1.5);
      let n = i32(40.0+count*50.0);
      let expand = ringR*energy*(0.5+bAge*0.5);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let jf = f32(j); let js = hash1(si*67.0+jf*3.1);
        let ang = jf/f32(n)*TAU + (js-0.5)*thick*3.0;
        let radial = vec2<f32>(cos(ang), sin(ang));
        let ringPos = center + radial*expand;
        let vel = radial*(0.15+js*0.1) + vec2<f32>(0.0, -0.05);
        let sp = sparkPos(ringPos, vel, bAge*0.3, 0.7+bAge*0.2);
        let onRing = softGlow(uv, sp, 0.005+js*0.003, fade*energy*1.4);
        let inner = softGlow(uv, center+radial*expand*0.7, 0.003, treble*fade*0.6);
        col += ringColor(js, colorC+time*0.02) * (onRing+inner);
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time*0.9)*3.5;
    if (mAge > 0.8) {
      let mb = mAge-0.8; let mc = mouseUV;
      let n = i32(50.0);
      for (var k = 0; k < n; k = k + 1) {
        let ang = f32(k)/f32(n)*TAU; let r = ringR*(0.4+mb*0.6);
        let rp = mc + vec2<f32>(cos(ang),sin(ang))*r;
        col += ringColor(hash1(f32(k)), colorC)*softGlow(uv, sparkPos(rp, vec2<f32>(0.0,-0.1), mb, 0.5), 0.006, smoothstep(3.5,0.2,mb));
      }
    }
  }
  col = mix(prev*0.92, col, 0.32);
  col = acesToneMap(col*1.08);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.55+prev*0.35, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.14, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
