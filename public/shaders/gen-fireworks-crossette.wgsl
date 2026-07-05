// Crossette Split — four-arm split burst fireworks
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
const PI: f32 = 3.14159265359;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn hash1(n: f32) -> f32 { return fract(sin(n*127.1)*43758.5453); }
fn softGlow(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = length(uv-c); return (exp(-d*d/(r*r*0.45))+0.3*exp(-d/(r*2.8)))*i;
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
fn armColor(arm: f32, hue: f32) -> vec3<f32> {
  let cols = array<vec3<f32>, 4>(vec3<f32>(1.0,0.2,0.15), vec3<f32>(0.2,0.8,1.0), vec3<f32>(1.0,0.85,0.3), vec3<f32>(0.3,1.0,0.5));
  let i = i32(arm) % 4; return mix(cols[i], cols[(i+1)%4], hue);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
  let power = mix(0.45, 1.5, u.zoom_params.x);
  let splitDly = mix(0.15, 0.7, u.zoom_params.y);
  let armSpread = mix(0.2, 0.55, u.zoom_params.z);
  let hueShift = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.022);

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s); let seed = hash1(si*41.0+5.0);
    let cycle = 2.3*(0.8+seed*0.4);
    let birth = floor((time*0.65+seed*1.8)/cycle)*cycle-seed*1.8;
    let age = time-birth; if (age < 0.0 || age > 7.0) { continue; }
    let bx = (seed-0.5)*1.55; let by = -0.78;
    let bDelay = 1.2+seed*0.4; let bAge = max(0.0, age-bDelay);
    let energy = power*(0.75+bass*0.65);
    if (age < bDelay) {
      let y = mix(by, by+1.2, (age/bDelay)*(age/bDelay));
      col += vec3<f32>(1.0,0.88,0.55)*softGlow(uv, vec2<f32>(bx,y), 0.009, energy*2.0);
    }
    if (bAge > 0.0 && bAge < 6.0) {
      let center = vec2<f32>(bx, by+1.22);
      let fade = smoothstep(5.5, 0.3, bAge);
      col += vec3<f32>(1.0)*exp(-bAge*11.0)*energy*2.0*softGlow(uv, center, 0.065, 1.0);
      // Primary mini burst
      for (var p = 0; p < 16; p = p + 1) {
        let ang = f32(p)/16.0*TAU; let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*0.3*energy, bAge, 0.8);
        col += vec3<f32>(1.0,0.95,0.8)*softGlow(uv, sp, 0.005, fade*energy*exp(-bAge*3.0));
      }
      // Four crossette arms
      let armAge = max(0.0, bAge - splitDly*(0.7+mids*0.3));
      if (armAge > 0.0) {
        for (var a = 0; a < 4; a = a + 1) {
          let af = f32(a);
          let armAng = af*PI*0.5 + seed*0.2;
          let armDir = vec2<f32>(cos(armAng), sin(armAng));
          let armCenter = center + armDir*armSpread*energy*(0.3+armAge*0.7);
          col += armColor(af, hueShift)*exp(-armAge*8.0)*energy*softGlow(uv, armCenter, 0.04, 1.0);
          let n = i32(18.0+power*20.0);
          for (var j = 0; j < n; j = j + 1) {
            let jf = f32(j); let js = hash1(si*53.0+af*17.0+jf*2.3);
            let subAng = armAng + (jf/f32(n)-0.5)*1.2;
            let spd = (0.3+js*0.4)*energy;
            let sp = sparkPos(armCenter, vec2<f32>(cos(subAng),sin(subAng))*spd, armAge, 0.85);
            col += armColor(af, hueShift+js*0.2)*softGlow(uv, sp, 0.005+js*0.003, fade*energy*(0.85+treble*0.4));
          }
        }
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time*0.85)*3.8;
    if (mAge > 0.7) {
      let mb = mAge-0.7; let mc = mouseUV;
      for (var a = 0; a < 4; a = a + 1) {
        let dir = vec2<f32>(cos(f32(a)*PI*0.5), sin(f32(a)*PI*0.5));
        let ac = mc + dir*armSpread*0.5;
        for (var j = 0; j < 20; j = j + 1) {
          let ang = f32(a)*PI*0.5 + (f32(j)/20.0-0.5)*1.0;
          let sp = sparkPos(ac, vec2<f32>(cos(ang),sin(ang))*0.5*power, mb-0.2, 0.8);
          col += armColor(f32(a), hueShift)*softGlow(uv, sp, 0.006, smoothstep(3.0,0.2,mb)*power);
        }
      }
    }
  }
  col = mix(prev*0.925, col, 0.3);
  col = acesToneMap(col*1.1);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.55+prev*0.38, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.13, 0.14, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
