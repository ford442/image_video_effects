# Swarm Brief: gen-fireworks-fan-shell

**Role:** Optimizer
**Name:** 4th of July — Fan Shell
**Category:** generative
**Description:** Wide fan shells that burst into a sweeping hemisphere of colored sparks, like a peacock tail opening in the sky. Sparks spread in a broad arc with strong horizontal bias before falling. Mids widen the fan angle, bass deepens the colors. Mouse opens a personal fan at the cursor.
**Current lines:** 102
**Target lines:** 152–192 (expand by +50 to +90)

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
  "name": "4th of July \u2014 Fan Shell",
  "category": "generative",
  "tags": [
    "fireworks",
    "fan",
    "spread",
    "hemisphere",
    "pyrotechnics",
    "july-4",
    "audio-reactive",
    "generative",
    "4th-of-july"
  ],
  "description": "Wide fan shells that burst into a sweeping hemisphere of colored sparks, like a peacock tail opening in the sky. Sparks spread in a broad arc with strong horizontal bias before falling. Mids widen the fan angle, bass deepens the colors. Mouse opens a personal fan at the cursor.",
  "workgroup_size": [
    16,
    16,
    1
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Fan Angle",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Shell Power",
      "default": 0.65,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Spark Density",
      "default": 0.55,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Hue Cycle",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
  ],
  "supportsDepth": true,
  "supportsDof": false,
  "updated": true,
  "id": "gen-fireworks-fan-shell",
  "url": "shaders/gen-fireworks-fan-shell.wgsl",
  "features": []
}
```

## Current WGSL Code

```wgsl
// Fan Shell Spread — wide hemisphere fan burst
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let fanAngle = mix(0.4, 1.6, u.zoom_params.x);
  let power = mix(0.45, 1.5, u.zoom_params.y);
  let density = mix(0.35, 1.1, u.zoom_params.z);
  let hueCycle = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  var col = vec3<f32>(0.01, 0.008, 0.022);

  for (var s: i32 = 0; s < 7; s = s + 1) {
    let si = f32(s); let seed = hash1(si*31.0+3.0);
    let cycle = 2.1*(0.85+seed*0.35);
    let birth = floor((time*0.7+seed*1.5)/cycle)*cycle-seed*1.5;
    let age = time-birth; if (age < 0.0 || age > 6.0) { continue; }
    let bx = (seed-0.5)*1.55; let by = -0.78;
    let bDelay = 1.1+seed*0.45; let bAge = max(0.0, age-bDelay);
    let energy = power*(0.7+bass*0.6);
    if (age < bDelay) {
      let y = mix(by, by+1.2, (age/bDelay)*(age/bDelay));
      col += vec3<f32>(1.0,0.88,0.55)*softGlow(uv, vec2<f32>(bx,y), 0.009, energy*2.0);
    }
    if (bAge > 0.0 && bAge < 5.5) {
      let center = vec2<f32>(bx, by+1.22);
      let fade = smoothstep(5.0, 0.3, bAge);
      let halfFan = fanAngle*(0.5+mids*0.3);
      col += vec3<f32>(1.0)*exp(-bAge*10.0)*energy*softGlow(uv, center, 0.065, 1.5);

      let n = i32(30.0 + density*50.0);
      for (var j: i32 = 0; j < n; j = j + 1) {
        let jf = f32(j); let js = hash1(si*67.0+jf*3.1);
        // Fan: spread horizontally in arc above center
        let fanT = jf/f32(n) - 0.5;
        let ang = fanT * halfFan * PI + (js-0.5)*0.15;
        let spd = (0.4+js*0.35)*energy;
        let vel = vec2<f32>(sin(ang)*spd, cos(ang)*spd*0.7 + 0.15);
        let sp = sparkPos(center, vel, bAge, 0.85);
        let h = fract(js + hueCycle + time*0.02);
        let fc = vec3<f32>(abs(h*6.0-3.0)-1.0, abs(h*6.0-2.0)-1.0, abs(h*6.0-4.0)-1.0);
        col += clamp(fc, vec3<f32>(0.0), vec3<f32>(1.0)) * softGlow(uv, sp, 0.005+js*0.004, fade*energy*(0.85+treble*0.4));
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
    let mAge = fract(time*1.0)*3.2;
    if (mAge > 0.6) {
      let mb = mAge-0.6; let halfF = fanAngle*0.6;
      for (var k = 0; k < 35; k = k + 1) {
        let fanT = f32(k)/35.0 - 0.5;
        let ang = fanT * halfF * PI;
        let vel = vec2<f32>(sin(ang), cos(ang)*0.6+0.2)*power*0.5;
        let sp = sparkPos(mUV, vel, mb, 0.8);
        let h = fract(f32(k)*0.1+hueCycle);
        col += vec3<f32>(abs(h*6.0-3.0)-1.0, abs(h*6.0-2.0)-1.0, abs(h*6.0-4.0)-1.0) * softGlow(uv, sp, 0.006, smoothstep(2.5,0.1,mb)*power);
      }
    }
  }
  col = mix(prev*0.92, col, 0.32);
  col = acesToneMap(col*1.1);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.55+prev*0.38, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.13, 0.14, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}

```
