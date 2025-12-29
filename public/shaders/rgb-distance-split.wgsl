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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=SplitStrength, y=AngleOffset, z=BlurAmount, w=Deadzone
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;

  let mousePos = u.zoom_config.yz;

  let strength = u.zoom_params.x * 0.1; // Scale down for usable range
  let angleOffset = u.zoom_params.y * 6.28;
  let blur = u.zoom_params.z;
  let deadzone = u.zoom_params.w;

  // Calculate vector from mouse to current pixel
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Direction
  var dir = vec2<f32>(0.0, 0.0);
  if (dist > 0.001) {
      dir = normalize(dVec);
  }

  // Calculate separation amount based on distance (linear or exponential?)
  // Deadzone: no effect inside
  let effectFactor = smoothstep(deadzone, 1.0, dist);

  let separation = dir * strength * effectFactor;

  // Rotate separation vector by angleOffset
  let c = cos(angleOffset);
  let s = sin(angleOffset);
  let rotSeparation = vec2<f32>(
      separation.x * c - separation.y * s,
      separation.x * s + separation.y * c
  );

  // Sample
  // R pushed out, B pushed in (or reverse), G stays?
  // Or R rotates one way, B other way

  let rUV = clamp(uv + rotSeparation, vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = uv;
  let bUV = clamp(uv - rotSeparation, vec2<f32>(0.0), vec2<f32>(1.0));

  // Simple Blur/Ghosting if blur > 0
  // Very expensive to do real blur, so just do 3-tap or small offset

  var r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  var g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
  var b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

  if (blur > 0.0) {
      let bOffset = rotSeparation * blur * 0.5;
      r = (r + textureSampleLevel(readTexture, u_sampler, rUV + bOffset, 0.0).r) * 0.5;
      g = (g + textureSampleLevel(readTexture, u_sampler, gUV + bOffset, 0.0).g) * 0.5;
      b = (b + textureSampleLevel(readTexture, u_sampler, bUV + bOffset, 0.0).b) * 0.5;
  }

  let finalColor = vec4<f32>(r, g, b, 1.0);

  textureStore(writeTexture, global_id.xy, finalColor);
}
