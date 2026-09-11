// ═══════════════════════════════════════════════════════════════════
//  mouse-paint-splatter
//  Category: interactive-mouse
//  Features: mouse-driven, temporal, paint-simulation, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: cast-off satellites; dry craquelure
//  A packing: paint.rgb + wetness.a; (0,0) mouse stash kept
// ═══════════════════════════════════════════════════════════════════

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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn loadC(p: vec2<i32>, res: vec2<f32>) -> vec4<f32> {
  let hi = vec2<i32>(res) - vec2<i32>(1);
  return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let splatterSize = mix(0.03, 0.15, u.zoom_params.x);
  let dryRate = mix(0.3, 0.05, u.zoom_params.y);
  let spreadAmount = mix(0.0, 0.02, u.zoom_params.z);
  let colorIntensity = mix(0.5, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseDelta = mousePos - prevMouse;
  let mouseVel = length(mouseDelta);

  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  let prevState = loadC(coord, resolution);
  var paintColor = prevState.rgb;
  var wetness = prevState.a;

  wetness = wetness * (1.0 - dryRate * 0.016);
  wetness = max(wetness, 0.0);

  if (mouseDown > 0.5 && mousePos.x >= 0.0) {
    let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let brushSize = splatterSize * (1.0 + mouseVel * 5.0);
    let splatter = smoothstep(brushSize, 0.0, dist);

    if (splatter > 0.001) {
      let brushColor = textureSampleLevel(readTexture, u_sampler, mousePos, 0.0).rgb * colorIntensity;
      paintColor = mix(brushColor, paintColor, 1.0 - splatter * 0.5);
      wetness = min(wetness + splatter * 0.5, 1.0);
    }

    // Idea 1 — cast-off satellites along the stroke tangent
    let tanDir = normalize(vec2<f32>(-mouseDelta.y, mouseDelta.x) + vec2<f32>(0.0001));
    let satOff = tanDir * (0.04 + mouseVel * 0.12) * (0.7 + bass * 0.3);
    let satCenter = mousePos + satOff;
    let satDist = length((uv - satCenter) * vec2<f32>(aspect, 1.0));
    let sat = smoothstep(splatterSize * 0.45, 0.0, satDist) * step(0.018, mouseVel) * mouseDown;
    let satSeed = hash12(uv * 90.0 + mousePos * 40.0);
    let satMask = sat * step(0.55, satSeed);
    if (satMask > 0.001) {
      let satCol = textureSampleLevel(readTexture, u_sampler, clamp(satCenter, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * colorIntensity;
      paintColor = mix(paintColor, satCol, satMask * 0.65);
      wetness = max(wetness, satMask * 0.7);
    }
  }

  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let elapsed = time - ripple.z;
    if (elapsed > 0.0 && elapsed < 3.0) {
      let rPos = ripple.xy;
      let rDist = length((uv - rPos) * vec2<f32>(aspect, 1.0));
      let splashRadius = splatterSize * 3.0 * (1.0 + elapsed * 0.5);
      let splash = smoothstep(splashRadius, 0.0, rDist) * exp(-elapsed * 0.8);

      if (splash > 0.001) {
        let seed = rPos * 100.0 + f32(i) * 7.7;
        let rnd = hash22(vec2<f32>(seed.x, elapsed));
        let splashColor = textureSampleLevel(readTexture, u_sampler, rPos + rnd * 0.1, 0.0).rgb * colorIntensity;
        let shapeNoise = hash12(uv * 50.0 + seed);
        let shapedSplash = splash * smoothstep(0.3, 0.7, shapeNoise + 0.3);
        paintColor = mix(paintColor, splashColor, shapedSplash * 0.7);
        wetness = max(wetness, shapedSplash * 0.8 * smoothstep(3.0, 0.0, elapsed));
      }
    }
  }

  if (wetness > 0.1 && spreadAmount > 0.001) {
    let n = loadC(coord + vec2<i32>(0, 1), resolution);
    let s = loadC(coord + vec2<i32>(0, -1), resolution);
    let e = loadC(coord + vec2<i32>(1, 0), resolution);
    let w = loadC(coord + vec2<i32>(-1, 0), resolution);
    let avgColor = (n.rgb + s.rgb + e.rgb + w.rgb) * 0.25;
    let avgWet = (n.a + s.a + e.a + w.a) * 0.25;
    paintColor = mix(paintColor, avgColor, spreadAmount * wetness);
    wetness = mix(wetness, avgWet, spreadAmount * 0.5);
  }

  let baseImage = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let coverage = smoothstep(0.0, 0.3, wetness) * 0.7;
  var finalColor = mix(baseImage.rgb, paintColor, coverage);

  let wetHighlight = pow(wetness, 3.0) * 0.3;
  finalColor = finalColor + vec3<f32>(0.1, 0.1, 0.15) * wetHighlight;

  // Idea 2 — dry craquelure as wetness falls
  let crack = abs(sin(uv.x * 70.0 + hash12(uv * 9.0) * 6.0)) * abs(sin(uv.y * 55.0));
  let dryCrack = (1.0 - smoothstep(0.08, 0.35, wetness)) * smoothstep(0.02, 0.2, coverage) * step(0.78, crack);
  finalColor *= 1.0 - dryCrack * (0.22 + treble * 0.12);

  if (!(global_id.x == 0u && global_id.y == 0u)) {
    textureStore(dataTextureA, coord, vec4<f32>(paintColor, wetness));
  }

  finalColor = acesToneMap(finalColor * (1.0 + mids * 0.06));
  let outA = clamp(wetness + dryCrack * 0.15 + baseImage.a * 0.1, 0.0, 1.0);
  textureStore(writeTexture, coord, vec4<f32>(finalColor, outA));
  let d = textureLoad(readDepthTexture, coord, 0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(d, 0.0, 0.0, 0.0));
}
