// ═══════════════════════════════════════════════════════════════════
//  mouse-paint-splatter
//  Category: interactive-mouse
//  Features: mouse-driven, temporal, paint-simulation
//  Complexity: High
//  Chunks From: chunk-library.md (hash12)
//  Created: 2026-04-18
//  By: Agent 2C
// ═══════════════════════════════════════════════════════════════════
//  Mouse drags leave colorful paint splatters that spread, mix,
//  and dry over time. Colors are sampled from the input image at
//  the splash origin. Uses dataTextureC for persistent paint state.
//  Alpha channel stores paint wetness (1.0 = wet, 0.0 = dry).
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

// ═══ CHUNK: hash12 (from gen_grid.wgsl) ═══
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  let time = u.config.x;

  let splatterSize = mix(0.03, 0.15, u.zoom_params.x);
  let dryRate = mix(0.3, 0.05, u.zoom_params.y);
  let spreadAmount = mix(0.0, 0.02, u.zoom_params.z);
  let colorIntensity = mix(0.5, 2.0, u.zoom_params.w);

  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w;
  let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
  let mouseVel = length(mousePos - prevMouse);

  // Store current mouse for next frame
  if (global_id.x == 0u && global_id.y == 0u) {
    textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
  }

  // Read previous paint state
  let prevState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  var paintColor = prevState.rgb;
  var wetness = prevState.a;

  // Dry the paint over time
  wetness = wetness * (1.0 - dryRate * 0.016);
  wetness = max(wetness, 0.0);

  // Mouse dragging creates new paint
  if (mouseDown > 0.5 && mousePos.x >= 0.0) {
    let dist = length((uv - mousePos) * vec2<f32>(aspect, 1.0));
    let brushSize = splatterSize * (1.0 + mouseVel * 5.0);
    let splatter = smoothstep(brushSize, 0.0, dist);

    if (splatter > 0.001) {
      // Sample color from input image at mouse position
      let brushColor = textureSampleLevel(readTexture, u_sampler, mousePos, 0.0).rgb * colorIntensity;

      // Mix with existing wet paint
      let mixFactor = splatter * wetness;
      paintColor = mix(brushColor, paintColor, 1.0 - splatter * 0.5);
      wetness = min(wetness + splatter * 0.5, 1.0);
    }
  }

  // Click ripples = explosive paint splatters
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
        let rnd = hash22(vec2<f32>(seed, elapsed));
        let splashColor = textureSampleLevel(readTexture, u_sampler, rPos + rnd * 0.1, 0.0).rgb * colorIntensity;

        // Splat shape variation via noise
        let shapeNoise = hash12(uv * 50.0 + seed);
        let shapedSplash = splash * smoothstep(0.3, 0.7, shapeNoise + 0.3);

        paintColor = mix(paintColor, splashColor, shapedSplash * 0.7);
        wetness = max(wetness, shapedSplash * 0.8 * smoothstep(3.0, 0.0, elapsed));
      }
    }
  }

  // Paint spread: wet paint diffuses slightly to neighbors
  if (wetness > 0.1 && spreadAmount > 0.001) {
    let px = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, px.y), 0.0);
    let s = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, px.y), 0.0);
    let e = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(px.x, 0.0), 0.0);
    let w = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(px.x, 0.0), 0.0);
    let avgColor = (n.rgb + s.rgb + e.rgb + w.rgb) * 0.25;
    let avgWet = (n.a + s.a + e.a + w.a) * 0.25;
    paintColor = mix(paintColor, avgColor, spreadAmount * wetness);
    wetness = mix(wetness, avgWet, spreadAmount * 0.5);
  }

  // Underlying image shows through dry paint
  let baseImage = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let coverage = smoothstep(0.0, 0.3, wetness) * 0.7;
  var finalColor = mix(baseImage, paintColor, coverage);

  // Wet highlight
  let wetHighlight = pow(wetness, 3.0) * 0.3;
  finalColor = finalColor + vec3<f32>(0.1, 0.1, 0.15) * wetHighlight;

  // Store paint state for next frame
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(paintColor, wetness));

  // Alpha = paint wetness
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, wetness));

  // Depth passthrough
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
