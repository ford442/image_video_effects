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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;

  // Mouse position (will be injected into zoom_config.yz)
  let mousePos = u.zoom_config.yz;

  // Params
  let strength = u.zoom_params.x; // Charge Strength
  let radius = u.zoom_params.y;   // Radius
  let density = u.zoom_params.z;  // Field Density (lines)
  let mode = u.zoom_params.w;     // Mode (<0.5 attract, >0.5 repel)

  // Calculate distance to mouse
  let aspect = resolution.x / resolution.y;
  let diff = uv - mousePos;
  // Correct distance for aspect ratio so the field is circular
  let dist_vec = vec2<f32>(diff.x * aspect, diff.y);
  let dist = length(dist_vec);

  var offset = vec2<f32>(0.0);

  if (dist < radius) {
      let angle = atan2(diff.y, diff.x);

      // Magnetic field lines effect
      let field = sin(angle * 20.0 + dist * (density * 100.0) - time * 2.0);

      let falloff = smoothstep(radius, 0.0, dist);
      let effect = falloff * strength * 0.2;

      // Direction
      let dir = normalize(diff);

      // Wiggle based on field lines
      let wiggle = dir * field * 0.02 * strength;

      if (mode > 0.5) { // Repel / Bulge
          offset = dir * effect + wiggle;
      } else { // Attract / Pinch
          offset = -dir * effect + wiggle;
      }
  }

  let finalUV = uv - offset;

  // Bounds check (optional, but sampler usually clamps/repeats)
  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
  textureStore(writeTexture, global_id.xy, color);

  // Passthrough depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
