// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Ring Slicer
// Param1: Ring Density (Frequency)
// Param2: Rotation Speed
// Param3: Chaos / Offset
// Param4: Center Influence (0 = always centered on screen, 1 = centered on mouse)

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;
  let time = u.config.x;

  let density = u.zoom_params.x * 20.0 + 2.0;
  let speed = (u.zoom_params.y - 0.5) * 4.0;
  let chaos = u.zoom_params.z;
  let mouseInfluence = u.zoom_params.w;

  // Determine center of rotation
  var center = vec2<f32>(0.5, 0.5);
  // Correct aspect ratio for distance calcs
  let aspect = resolution.x / resolution.y;

  if (mouseInfluence > 0.1 && mousePos.x >= 0.0) {
      center = mix(center, mousePos, mouseInfluence);
  }

  var dVec = uv - center;
  dVec.x *= aspect;

  let r = length(dVec);
  let a = atan2(dVec.y, dVec.x);

  // Calculate ring index
  let ringIndex = floor(r * density);

  // Determine rotation for this ring
  // Alternating direction
  let direction = select(-1.0, 1.0, (ringIndex % 2.0) == 0.0);

  // Random speed multiplier per ring if chaos is high
  let randFactor = hash12(vec2<f32>(ringIndex, 1.0));
  let chaosSpeed = mix(1.0, 0.5 + randFactor * 2.0, chaos);

  let angleOffset = time * speed * direction * chaosSpeed;

  // Add some discrete stepping/locking if desired? No, smooth is better.

  let newAngle = a + angleOffset;

  // Convert back to UV
  // x = r * cos(a), y = r * sin(a)
  // Remember we corrected x for aspect earlier, need to un-correct?
  // Original logic: dVec.x = (uv.x - center.x) * aspect;
  // newX = r * cos(newA); newY = r * sin(newA);
  // targetX = newX / aspect + center.x;

  let newX = r * cos(newAngle);
  let newY = r * sin(newAngle);

  let warpedUV = vec2<f32>(newX / aspect, newY) + center;

  // Bounds check (repeat or clamp? Repeat looks cooler for rotation)
  // But standard clamp avoids artifacts.
  // Let's mirror or wrap.
  let finalUV = fract(warpedUV);

  var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  // Highlight ring edges slightly
  let ringPos = fract(r * density);
  let edgeWidth = 0.05 * chaos; // Glow edges with chaos
  if (edgeWidth > 0.0 && (ringPos < edgeWidth || ringPos > 1.0 - edgeWidth)) {
     color += vec4<f32>(0.1, 0.2, 0.3, 0.0) * chaos * 5.0;
  }

  textureStore(writeTexture, global_id.xy, color);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
