# Swarm Brief: fireworks-portrait-burst

**Role:** Algorithmist
**Name:** 4th of July — Portrait Burst
**Category:** image
**Description:** Bright regions of your image become the cores of spectacular firework detonations. Faces, skylines, and luminous highlights erupt in bursts that inherit the source colors. The photo celebrates itself — portraits explode in their own palette. Bass triggers larger cores, treble adds sparkle. Mouse detonates at the cursor.
**Current lines:** 100
**Target lines:** 150–190 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This firework shader's click burst is aimed at the wrong sky - the mouse coordinate math treats normalized [0,1] coords as pixels, so bursts detonate off-screen. Fix the aim, then the depth:
- FIX THE MOUSE COORD BUG (priority 1): `let mUV = (u.zoom_config.yz - res*0.5)/min(res.x,res.y);` - zoom_config.yz is NORMALIZED [0,1], subtracting res*0.5 (hundreds of pixels) puts mUV far off-screen, so the held-click burst never appears at the cursor. Correct: `let mUV = (u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y);`. Verify the burst then centers on the cursor.
- Honest depth: writeDepthTexture currently stores flat 0.0, clobbering chain depth (cosmic-jellyfish bug class) - write a real depth: luminance-derived (`clamp(dot(col, lumWeights) * 0.8 + sparkGlow * 0.2, 0.0, 1.0)`) so bright bursts sit forward.
- Click ripple bursts: loop ripples[] (guard `min(u32(u.config.y), 50u)`) - each live ripple ALSO spawns a one-shot spark burst at its click point (same spark pipeline as the mouse burst, age = time - ripple.z), so individual clicks fire without holding the button. Keep the existing held-mouse auto-repeat.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the spark physics (sparkPos gravity, softGlow falloff, hash1 seeds, 7-probe loop, ACES tonemap) VERBATIM - the pyrotechnics are hand-tuned. dataTextureA/B roles (display state / dimmed echo) must stay raw - never re-tonemap them. The `continue` guards in the probe loop are intentional perf structure - keep them.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "fireworks-portrait-burst",
  "name": "4th of July \u2014 Portrait Burst",
  "url": "shaders/fireworks-portrait-burst.wgsl",
  "description": "Bright regions of your image become the cores of spectacular firework detonations. Faces, skylines, and luminous highlights erupt in bursts that inherit the source colors. The photo celebrates itself \u2014 portraits explode in their own palette. Bass triggers larger cores, treble adds sparkle. Mouse detonates at the cursor.",
  "tags": [
    "fireworks",
    "portrait",
    "bright-region",
    "pyrotechnics",
    "july-4",
    "image-reactive",
    "audio-reactive",
    "4th-of-july"
  ],
  "features": [
    "audio-reactive",
    "temporal",
    "semantic-alpha",
    "depth-aware"
  ],
  "params": [
    {
      "id": "thresh",
      "name": "Brightness",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "size",
      "name": "Burst Size",
      "default": 0.65,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "dissolve",
      "name": "Dissolve",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "warmth",
      "name": "Warmth",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Brightness",
      "default": 0.45,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Burst Size",
      "default": 0.65,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Dissolve",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Warmth",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// Fireworks Portrait Burst — bright regions detonate
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy); let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv = (vec2<f32>(pixel)-res*0.5)/min(res.x,res.y);
  let time = u.config.x;
  let thresh = mix(0.1, 0.75, u.zoom_params.x);
  let burstSize = mix(0.4, 1.5, u.zoom_params.y);
  let dissolve = mix(0.1, 0.7, u.zoom_params.z);
  let warmth = u.zoom_params.w;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  let imgCol = sampleImg(uv);
  let lum = dot(imgCol, vec3<f32>(0.299,0.587,0.114));
  let bright = smoothstep(thresh*0.5, thresh, lum);
  let dissolveAmt = bright * dissolve * (0.3 + bass*0.2);
  var col = imgCol * (0.55 - dissolveAmt*0.4);

  for (var s = 0; s < 7; s = s + 1) {
    let si = f32(s); let seed = hash1(si*29.0+3.0);
    let probe = vec2<f32>((seed-0.5)*1.4, (hash1(si*51.0)-0.5)*1.0);
    let pCol = sampleImg(probe);
    let pLum = dot(pCol, vec3<f32>(0.299,0.587,0.114));
    if (pLum < thresh * 0.6) { continue; }
    let cycle = 2.2/(0.6+mids*0.2);
    let birth = floor((time*0.65+seed*1.4)/cycle)*cycle-seed*1.4;
    let age = time-birth; if (age < 0.0 || age > 5.5) { continue; }
    let energy = burstSize * pLum * (0.65+bass*0.7);
    let bAge = max(0.0, age-0.8);
    if (bAge > 0.0 && bAge < 4.5) {
      let center = probe + vec2<f32>(0.0, 0.3);
      let fade = smoothstep(4.0, 0.2, bAge);
      col += pCol * exp(-bAge*9.0) * energy * 2.0 * softGlow(uv, center, 0.05, 1.0);
      let n = i32(20.0 + energy*35.0);
      for (var j = 0; j < n; j = j + 1) {
        let js = hash1(si*71.0+f32(j)*3.1);
        let ang = f32(j)/f32(n)*TAU + (js-0.5)*0.8;
        let spd = (0.3+js*0.5)*energy;
        let sp = sparkPos(center, vec2<f32>(cos(ang),sin(ang))*spd, bAge, 0.9);
        var sc = mix(pCol, vec3<f32>(1.0,0.7,0.3), warmth*0.4);
        sc = mix(sc, vec3<f32>(1.0,0.95,0.85), smoothstep(0.5,0.0,bAge*0.3));
        col += sc * softGlow(uv, sp, 0.006+js*0.004, fade*energy*(0.85+treble*0.5));
      }
    }
  }
  if (u.zoom_config.w > 0.5) {
    let mUV = (u.zoom_config.yz-res*0.5)/min(res.x,res.y);
    let mCol = sampleImg(mUV);
    let mAge = fract(time*1.1)*3.0;
    if (mAge > 0.5) {
      let mb = mAge-0.5;
      for (var k = 0; k < 35; k = k + 1) {
        let ang = f32(k)/35.0*TAU;
        let sp = sparkPos(mUV, vec2<f32>(cos(ang),sin(ang))*0.55*burstSize, mb, 0.85);
        col += mCol * softGlow(uv, sp, 0.007, smoothstep(2.5,0.1,mb)*burstSize);
      }
    }
  }
  col = mix(prev*0.91, col, 0.33);
  col = acesToneMap(col*1.06);
  textureStore(dataTextureB, pixel, vec4<f32>(col*0.52+prev*0.38, 1.0));
  textureStore(dataTextureA, pixel, vec4<f32>(col, 1.0));
  textureStore(writeTexture, pixel, vec4<f32>(col, clamp(length(col)*1.1+0.14, 0.12, 0.96)));
  textureStore(writeDepthTexture, pixel, vec4<f32>(0.0));
}
```
