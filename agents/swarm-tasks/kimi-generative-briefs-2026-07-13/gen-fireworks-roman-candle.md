# Swarm Brief: gen-fireworks-roman-candle

**Role:** Optimizer
**Name:** 4th of July — Roman Candle
**Category:** generative
**Description:** Classic roman candles firing rapid star bursts from fixed launch tubes along the horizon. Each tube shoots a sequence of colored stars straight upward with comet trails. Bass makes bigger stars, treble increases fire rate. The quintessential backyard July 4th barrage. Mouse aims a personal roman candle at the cursor.
**Current lines:** 111
**Target lines:** 151–201 (expand by +40 to +90)

## Role Instructions

You are the Optimizer. Focus on performance, elegance, and pipeline integration:
- Add early-exit/background fallbacks, LOD scaling, and minimize texture samples.
- Use the 7-tap hex bokeh kernel where blur/glow is needed.
- Name constants, deduplicate code into helpers, and keep branchless hot paths.
- Preserve the original "soul" and theme of the shader.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.

## JSON Parameters / Controls

```json
[]
```

## Current WGSL Code

```wgsl
// Roman Candle — vertical star barrage from launch tubes
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let mouseUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
  let fireRate = mix(0.3, 1.2, u.zoom_params.x);
  let starSize = mix(0.004, 0.014, u.zoom_params.y);
  let tubeSpread = mix(0.3, 1.0, u.zoom_params.z);
  let trailLen = mix(0.88, 0.96, u.zoom_params.w);
  let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
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
      let starPos = vec2<f32>(tubeX + sin(age*3.0+seed*10.0)*0.02, starY);
      let fade = smoothstep(3.0, 0.1, age);
      let sz = starSize*(1.0+bass*0.2);
      col += starCol(seed+sf*0.1)*softGlow(uv, starPos, sz, fade*energy*2.0);
      // Comet trail
      for (var tr = 1; tr < 5; tr = tr + 1) {
        let trf = f32(tr)*0.08;
        let trailPos = vec2<f32>(starPos.x, starY - trf*0.15);
        col += starCol(seed)*softGlow(uv, trailPos, sz*0.6, fade*energy*(1.0-trf*0.8)*0.7);
      }
      // Mini burst at apex
      if (age > 1.2 && age < 2.5) {
        let bAge = age-1.2;
        let burstY = tubeY + 1.2*energy;
        let burstC = vec2<f32>(tubeX, burstY);
        for (var sp = 0; sp < 10; sp = sp + 1) {
          let ang = f32(sp)/10.0*TAU;
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
  col = mix(prev*trailLen, col, 0.35);
  let dust = step(0.987-treble*0.03, hash1(dot(uv, vec2<f32>(127.1,311.7))+time*8.0));
  col += vec3<f32>(0.7,0.85,1.0)*dust*treble*0.5;
  col = acesToneMap(col*1.08);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.5+prev*0.4, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.14, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}

```
