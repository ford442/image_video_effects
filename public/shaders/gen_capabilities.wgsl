@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Hash function for glitch effect
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn segment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return smoothstep(0.005, 0.0, length(pa - ba * h));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let px = vec2<i32>(global_id.xy);

  // Read history for trails
  let history = textureLoad(dataTextureC, px, 0);

  // Aspect corrected coordinates for drawing shapes
  let aspect = resolution.x / resolution.y;
  var p = uv * 2.0 - 1.0;
  p.x *= aspect;

  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
  mouse.x *= aspect;

  var color = vec3<f32>(0.0);

  // 1. Grid Background
  let gridSize = 4.0;
  let grid = abs(fract(p * gridSize - 0.5) - 0.5);
  let gridLine = 1.0 - smoothstep(0.0, 0.02, min(grid.x, grid.y));
  color += vec3<f32>(0.0, 0.1, 0.1) * gridLine;

  // 2. Mouse Cursor & Interaction
  let d = length(p - mouse);
  let cursor = 1.0 - smoothstep(0.0, 0.05, d);

  // Color change on click
  let isClick = u.zoom_config.w > 0.5;
  let cursorColor = select(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), isClick);

  color += cursorColor * cursor;

  // Crosshairs around mouse
  let crosshair = max(
      segment(p, mouse - vec2<f32>(0.2, 0.0), mouse + vec2<f32>(0.2, 0.0)),
      segment(p, mouse - vec2<f32>(0.0, 0.2), mouse + vec2<f32>(0.0, 0.2))
  );
  color += vec3<f32>(0.0, 1.0, 0.0) * crosshair * 0.5;

  // 3. Data Readout Visualization (Fake FFT/Data bars at bottom)
  if (uv.y < 0.1) {
      let barId = floor(uv.x * 20.0);
      let h = hash12(vec2<f32>(barId, floor(time * 5.0)));
      if (uv.y < h * 0.08) {
          color += vec3<f32>(0.0, 0.8, 0.2);
      }
  }

  // 4. Time Scanline
  let scanY = fract(time * 0.2) * 2.0 - 1.0;
  let scanLine = 1.0 - smoothstep(0.0, 0.01, abs(p.y - scanY));
  color += vec3<f32>(0.5, 0.5, 1.0) * scanLine * 0.3;

  // 5. Glitch Effect on History
  // Shift history slightly based on Y position (glitchy shear)
  let glitchOffset = vec2<i32>(i32(sin(uv.y * 50.0 + time * 10.0) * 2.0 * u.zoom_config.w), 0);
  let historyGlitch = textureLoad(dataTextureC, px + glitchOffset, 0);

  // Blend with history (Trail effect)
  // Decay history
  var finalColor = max(color, historyGlitch.rgb * 0.92);

  // Add a bit of noise
  finalColor += (hash12(uv + time) - 0.5) * 0.05;

  let output = vec4<f32>(finalColor, 1.0);

  // Write to Output and History
  textureStore(writeTexture, global_id.xy, output);
  textureStore(dataTextureA, global_id.xy, output);
}
