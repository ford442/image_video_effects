// Kamuro Gold — dense slow-falling gold/silver glitter
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
  let d = length(uv - c);
  return (exp(-d*d/(r*r*0.55)) + 0.35*exp(-d/(r*4.0)))*i;
}
fn sparkPos(o: vec2<f32>, v: vec2<f32>, age: f32, g: f32) -> vec2<f32> {
  return o + v*age - vec2<f32>(0.0, g)*age*age*0.5;
}
fn kamuroPos(o: vec2<f32>, v: vec2<f32>, age: f32, fall: f32, hang: f32) -> vec2<f32> {
  let hover = exp(-age*0.4)*hang*0.15;
  let drag = exp(-age*0.05);
  return o + vec2<f32>(v.x*drag + age*0.012, v.y*drag - fall*age*age*0.35 + hover);
}
fn goldCol(gold: f32, seed: f32) -> vec3<f32> {
  let goldC = vec3<f32>(1.0, 0.82, 0.3);
  let silver = vec3<f32>(0.85, 0.9, 1.0);
  let warm = vec3<f32>(1.0, 0.6, 0.15);
  return mix(mix(goldC, silver, seed), warm, (1.0 - gold)*0.3);
}
fn starField(uv: vec2<f32>) -> vec3<f32> {
  let id = floor(uv*160.0);
  let h = hash2(id);
  return vec3<f32>(0.8, 0.9, 1.0)*step(0.992, h)*0.35;
}
fn hexBokeh(uv: vec2<f32>, c: vec2<f32>, r: f32, i: f32) -> f32 {
  let d = uv - c;
  let q = vec2<f32>(d.x*1.2 + d.y*0.6, d.y);
  return softGlow(uv, c, r, i)*(0.7 + 0.3*smoothstep(r*0.5, r*1.5, length(q)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  // ---- screen setup ----
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel) - res*0.5) / min(res.x, res.y);
  let sampleUV = (vec2<f32>(pixel) + 0.5) / res;
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz - res*0.5) / min(res.x, res.y);

  // ---- parameters & audio ----
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let density = mix(0.3, 1.0, u.zoom_params.x);
  let fallSpd = mix(0.15, 0.7, u.zoom_params.y);
  let goldMix = u.zoom_params.z;
  let hang = mix(0.3, 1.2, u.zoom_params.w);

  // ---- previous frame inputs (single sample each) ----
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let camera = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  // ---- night sky base ----
  var col = vec3<f32>(0.008, 0.006, 0.02);
  col += starField(uv);
  col += camera * 0.04;
  col += vec3<f32>(0.75, 0.82, 1.0)*step(0.994, hash2(floor(uv*140.0)))*0.45;

  // ---- kamuro gold cloud bursts ----
  for (var s: i32 = 0; s < 5; s = s + 1) {
    let si = f32(s);
    let seed = hash1(si*37.0 + 3.0);
    let cycle = 3.2 * (0.9 + seed * 0.3);
    let birth = floor((time * 0.5 + seed * 2.5) / cycle) * cycle - seed * 2.5;
    let age = time - birth;
    if (age < 0.0 || age > 10.0) { continue; }

    let bx = (seed - 0.5) * 1.5;
    let by = -0.75;
    let bDelay = 1.4 + seed * 0.5;
    let bAge = max(0.0, age - bDelay);
    let energy = (0.6 + bass * 0.5) * density;
    if (energy < 0.01) { continue; }

    // ascending rocket trail
    if (age < bDelay) {
      let y = mix(by, by + 1.3, (age / bDelay) * (age / bDelay));
      col += vec3<f32>(1.0, 0.85, 0.4) * softGlow(uv, vec2<f32>(bx, y), 0.01, energy * 2.2);
    }

    // dense glitter cloud
    if (bAge > 0.0 && bAge < 9.0) {
      let center = vec2<f32>(bx, by + 1.3);
      let fade = smoothstep(8.5, 1.0, bAge);

      // core glow
      col += vec3<f32>(1.0, 0.9, 0.5) * exp(-bAge * 7.0) * energy * 2.5 * hexBokeh(uv, center, 0.08, 1.0);

      let n = i32(50.0 + density*80.0 + bass*20.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let jf = f32(j);
        let js = hash1(si*89.0 + jf*2.7);
        let js2 = hash1(si*23.0 + jf*5.3);
        let ang = js * TAU;
        let spd = (0.2 + js2*0.35) * energy;
        let vel = vec2<f32>(cos(ang)*spd*0.5, js2*spd*0.8 + 0.1);
        let sp = kamuroPos(center, vel, bAge, fallSpd, hang);
        let sz = 0.003 + js*0.003;

        // main glitter spark
        let g = softGlow(uv, sp, sz, fade*energy*(0.7 + js2*0.5));
        col += goldCol(goldMix, js) * g * (0.8 + treble*0.5);

        // micro glitter trail
        if (treble > 0.25) {
          let trail = kamuroPos(center, vel, max(0.0, bAge - 0.15), fallSpd, hang);
          col += vec3<f32>(0.9, 0.95, 1.0) * softGlow(uv, trail, sz*0.7, treble*fade*0.4);
        }
      }
    }
  }

  // ---- mouse-triggered kamuro shower ----
  if (u.zoom_config.w > 0.5) {
    let mAge = fract(time * 0.6) * 5.0;
    if (mAge > 0.8) {
      let mb = mAge - 0.8;
      let mFade = smoothstep(4.5, 0.5, mb);
      let n = i32(60.0 * density);
      for (var k: i32 = 0; k < n; k = k + 1) {
        let ks = hash1(f32(k)*1.9);
        let ang = ks * TAU;
        let vel = vec2<f32>(cos(ang), 0.3 + ks*0.4) * 0.3;
        let sp = kamuroPos(mouseUV, vel, mb, fallSpd, hang);
        col += goldCol(goldMix, ks) * softGlow(uv, sp, 0.004, mFade);
      }
    }
  }

  // ---- temporal blend & tone map ----
  let trailDecay = mix(0.9, 0.97, hang);
  col = mix(prev * trailDecay, col, 0.25);
  col = acesToneMap(col * 1.12);

  let alpha = clamp(length(col) * 1.2 + 0.1, 0.12, 0.97);
  let persistent = col * 0.7 + prev * 0.25;
  textureStore(dataTextureB, pixel, vec4<f32>(persistent, alpha));
  textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
