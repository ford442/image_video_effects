// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Simple pseudo-random function
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Params
  let density = u.zoom_params.x;
  let revealSize = u.zoom_params.y;
  let trailFade = u.zoom_params.z;
  let rainSpeed = u.zoom_params.w;

  // --- TRAIL MASK LOGIC (History Buffer) ---

  // Read previous mask state (R channel of dataTextureC)
  // Coordinates for textureSampleLevel must be normalized UV
  // Coordinates for textureStore must be integer coords

  // Note: dataTextureC matches canvas resolution
  let prevVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

  // Mouse interaction
  let mouse = u.zoom_config.yz;
  let aspect = resolution.x / resolution.y;
  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let mouseCorrected = vec2<f32>(mouse.x * aspect, mouse.y);
  let dist = distance(uvCorrected, mouseCorrected);

  // Brush logic: if mouse is close, set mask to 1.0
  let brushRadius = revealSize * 0.3 + 0.05;
  let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);

  // Fade logic: slowly decrease mask value over time
  // trailFade param: 0.0 = fast fade (0.8 multiplier), 1.0 = slow fade (0.99 multiplier)
  let fadeFactor = 0.8 + trailFade * 0.19;
  let newVal = max(prevVal * fadeFactor, brush);

  // Write new mask to history (dataTextureA)
  textureStore(dataTextureA, global_id.xy, vec4<f32>(newVal, 0.0, 0.0, 1.0));


  // --- DIGITAL RAIN GENERATION ---

  // Create grid for characters/rain drops
  let gridSize = vec2<f32>(20.0, 20.0 * aspect) * (1.0 + density * 2.0);
  let cellUV = fract(uv * gridSize);
  let cellID = floor(uv * gridSize);

  // Random speed per column
  let colSpeed = hash22(vec2<f32>(cellID.x, 0.0)).y * (rainSpeed * 5.0 + 1.0);

  // Animate vertical movement
  let verticalPos = cellID.y + time * colSpeed;
  let charID = floor(verticalPos);

  // Brightness based on position in the drop
  let dropVal = fract(verticalPos);
  let charBright = smoothstep(0.0, 0.2, dropVal) * smoothstep(1.0, 0.8, dropVal);

  // Random flicker
  let flicker = step(0.1, hash22(vec2<f32>(cellID.x, charID)).x);

  let rainColor = vec3<f32>(0.0, 1.0, 0.2) * charBright * flicker;

  // Some random "glitch" blocks
  if (hash22(vec2<f32>(cellID.x, charID)).y > 0.98 - density * 0.1) {
    rainColor = vec3<f32>(0.8, 1.0, 0.8);
  }


  // --- COMPOSITION ---

  // Sample the underlying image/video
  let imageColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Mix based on the reveal mask (newVal)
  // If mask is 1.0 (revealed), show image. If 0.0, show rain.

  let finalColor = mix(rainColor, imageColor, clamp(newVal, 0.0, 1.0));

  textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
