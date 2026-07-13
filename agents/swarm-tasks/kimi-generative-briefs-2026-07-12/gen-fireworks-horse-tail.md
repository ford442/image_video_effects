# Swarm Brief: gen-fireworks-horse-tail

**Role:** Optimizer
**Name:** 4th of July — Horse Tail Brocade
**Category:** generative
**Description:** Classic horse tail and brocade shells rain long, straight golden streamers from a single burst point. Each spark traces a tight gravity arc with minimal spread, creating luminous waterfalls of light. Bass lengthens the tails, treble adds silver micro-dust along the streams. Mouse launches a personal brocade cascade.
**Current lines:** 104
**Target lines:** 154–194 (expand by +50 to +90)

## Role Instructions

You are the Optimizer. Focus on performance, elegance, and pipeline integration:
- Standardize code structure: named constants, helper functions, logical sections.
- Add early-exit opportunities and minimize texture samples.
- Ensure all 13 bindings are used correctly and writeDepthTexture / dataTextureA are written.
- Use hex-bokeh sampling, anti-moiré LOD bias, or shared-memory tiling hints where appropriate.
- Keep the fireworks family visually consistent while giving each shell its own distinct signature.


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
{
  "name": "4th of July \u2014 Horse Tail Brocade",
  "category": "generative",
  "tags": [
    "fireworks",
    "horse-tail",
    "brocade",
    "streamers",
    "pyrotechnics",
    "july-4",
    "audio-reactive",
    "generative",
    "4th-of-july"
  ],
  "description": "Classic horse tail and brocade shells rain long, straight golden streamers from a single burst point. Each spark traces a tight gravity arc with minimal spread, creating luminous waterfalls of light. Bass lengthens the tails, treble adds silver micro-dust along the streams. Mouse launches a personal brocade cascade.",
  "workgroup_size": [
    16,
    16,
    1
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Tail Length",
      "default": 0.7,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Stream Width",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Gold Intensity",
      "default": 0.65,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Fall Speed",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "id": "gen-fireworks-horse-tail",
  "url": "shaders/gen-fireworks-horse-tail.wgsl",
  "features": []
}
```

## Current WGSL Code

```wgsl
// Horse Tail Brocade — long straight golden streamers
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
  let d = length(uv-c); return (exp(-d*d/(r*r*0.5))+0.35*exp(-d/(r*4.0)))*i;
}
fn tailPos(o: vec2<f32>, dir: vec2<f32>, age: f32, fall: f32, spread: f32, seed: f32) -> vec2<f32> {
  let drift = vec2<f32>((seed-0.5)*spread*0.08, 0.0);
  return o + dir*age*0.15 + drift + vec2<f32>(0.0, -fall*age*age*0.45);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let tailLen = mix(0.4, 1.0, u.zoom_params.x);
  let spread = mix(0.02, 0.15, u.zoom_params.y);
  let gold = mix(0.4, 1.0, u.zoom_params.z);
  let fall = mix(0.25, 0.85, u.zoom_params.w);
  let bass = plasmaBuffer[0].x; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  var col = vec3<f32>(0.008, 0.006, 0.02);

  for (var s: i32 = 0; s < 6; s = s + 1) {
    let si = f32(s); let seed = hash1(si*37.0+2.0);
    let cycle = 2.8*(0.85+seed*0.35);
    let birth = floor((time*0.55+seed*2.0)/cycle)*cycle-seed*2.0;
    let age = time-birth; if (age < 0.0 || age > 8.0) { continue; }
    let bx = (seed-0.5)*1.5; let by = -0.76;
    let bDelay = 1.3+seed*0.5; let bAge = max(0.0, age-bDelay);
    let energy = (0.65+bass*0.5)*tailLen;
    if (age < bDelay) {
      let y = mix(by, by+1.25, (age/bDelay)*(age/bDelay));
      col += vec3<f32>(1.0,0.85,0.4)*softGlow(uv, vec2<f32>(bx,y), 0.009, energy*2.0);
    }
    if (bAge > 0.0 && bAge < 7.5) {
      let center = vec2<f32>(bx, by+1.28);
      let fade = smoothstep(7.0, 0.5, bAge);
      col += vec3<f32>(1.0,0.9,0.5)*exp(-bAge*6.0)*energy*softGlow(uv, center, 0.07, 1.5);
      let n = i32(35.0 + energy*45.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let js = hash1(si*79.0+f32(j)*3.3);
        let js2 = hash1(si*23.0+f32(j)*5.7);
        let dir = vec2<f32>((js-0.5)*spread, 0.6+js2*0.4);
        let streamLen = 6 + i32(tailLen*8.0);
        for (var t = 0; t < streamLen; t = t + 1) {
          let tf = f32(t)/f32(streamLen);
          let tAge = max(0.0, bAge - tf*1.2);
          let sp = tailPos(center, dir, tAge, fall, spread, js);
          let tFade = fade*(1.0-tf*0.6)*(0.5+js2*0.5);
          let gc = mix(vec3<f32>(1.0,0.82,0.3), vec3<f32>(0.9,0.92,1.0), (1.0-gold)*js);
          col += gc * softGlow(uv, sp, 0.004+js*0.002, tFade*energy*1.3);
        }
        if (treble > 0.3) {
          let sp = tailPos(center, dir, bAge, fall, spread, js);
          col += vec3<f32>(0.85,0.9,1.0)*softGlow(uv, sp, 0.002, treble*fade*0.5);
        }
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
    let mAge = fract(time*0.7)*4.5;
    if (mAge > 0.8) {
      let mb = mAge-0.8;
      for (var k = 0; k < 30; k = k + 1) {
        let ks = hash1(f32(k)*2.1);
        let dir = vec2<f32>((ks-0.5)*spread*2.0, 0.7);
        let sp = tailPos(mUV, dir, mb, fall, spread, ks);
        col += mix(vec3<f32>(1.0,0.8,0.3), vec3<f32>(1.0), gold)*softGlow(uv, sp, 0.005, smoothstep(3.5,0.3,mb));
      }
    }
  }
  col = mix(prev*mix(0.9, 0.97, tailLen), col, 0.28);
  col = acesToneMap(col*1.1);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.65+prev*0.28, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.12, 0.14, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}

```
