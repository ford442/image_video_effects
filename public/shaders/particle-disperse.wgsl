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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let aspect = resolution.x / resolution.y;
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Params
  let windForce = mix(0.01, 0.1, u.zoom_params.x);
  let returnSpeed = mix(0.01, 0.2, u.zoom_params.y);
  let damping = mix(0.8, 0.99, u.zoom_params.z);
  let radius = mix(0.1, 0.5, u.zoom_params.w);

  let mouse = u.zoom_config.yz;

  // Read state: RG = Offset (displacement from original UV), BA = Velocity
  let state = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
  var offset = state.xy;
  var vel = state.zw;

  // Calculate current apparent position
  let currentPos = uv + offset;

  // Mouse interaction
  // We repel from mouse position
  let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let pos_aspect = vec2<f32>(currentPos.x * aspect, currentPos.y);

  var dist = distance(pos_aspect, mouse_aspect);

  // Avoid division by zero and extreme forces
  if (dist < 0.001) { dist = 0.001; }

  var force = vec2<f32>(0.0);
  if (dist < radius) {
      let dir = normalize(pos_aspect - mouse_aspect);
      // Correct direction back to UV space (undo aspect for X)
      let dirUV = vec2<f32>(dir.x * aspect, dir.y); // Wait, no. Aspect ratio is applied to coordinates for distance. Direction vector components need care.
      // Easiest: calculate direction in aspect space, then un-aspect.
      let push = (1.0 - dist / radius) * windForce;
      force = vec2<f32>(dir.x, dir.y) * push; // Keep aspect ratio in force?
      // If we push in aspect space, we need to convert that force back to UV space displacement.
      // dx_uv = dx_aspect / aspect
      force.x = force.x / aspect;
  }

  // Add randomness/turbulence
  // ... maybe later

  // Update Velocity
  // 1. Add mouse force
  vel = vel + force;

  // 2. Spring force (return to offset 0)
  // Force = -k * x
  let spring = -offset * returnSpeed;
  vel = vel + spring;

  // 3. Damping
  vel = vel * damping;

  // Update Offset
  offset = offset + vel;

  // Clamp offset to avoid sampling way outside (optional, but good)
  // offset = clamp(offset, vec2<f32>(-1.0), vec2<f32>(1.0));

  // Write state
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(offset, vel));

  // Sample Image
  // We sample at uv (original position) - offset? No, we are at pixel (x,y).
  // This pixel (x,y) REPRESENTS a particle that belongs at (x,y).
  // It is currently displaced by 'offset'.
  // So we should Draw the particle at (uv + offset).
  // But this is a compute shader that writes to (x,y).
  // This is an Eulerian vs Lagrangian problem.
  //
  // Approach A (Scatter): We write to a different pixel. (Can't easily do parallel w/o atomic).
  // Approach B (Gather): We are pixel (x,y). We want to find which particle LANDS here. Hard.
  // Approach C (Distortion Map): We treat this as a texture lookup displacement.
  // If we want the image to look like it's blown away, we want to see the color of the pixel that was blown *to here*.
  // Or rather, if I am pixel P, and I am "blown away", I move to P'.
  // We are rendering P. We want to know what is at P.
  // If the "wind" blows RIGHT, then at P, we see what was to the LEFT.
  // So we sample at (uv - offset).

  // Let's interpret 'offset' as "how far pixels have moved FROM here".
  // If offset is positive (moved right), then at (uv + offset) we should see this pixel's color.
  // But we can only write to (uv).

  // Let's reverse the model:
  // 'offset' at (x,y) tells us where to look for the color.
  // "Inverse semi-lagrangian".
  // If mouse is at M, it PUSHES.
  // If I am at P, and mouse is to my left, the wind blows right.
  // Material from the left comes to me.
  // So I should look at (uv - offset).
  // And the offset should grow in the direction of the wind.

  // Wait, if mouse is at M, and I am at P (to the right of M). Wind blows Right.
  // I should receive content from M.
  // So I look "upstream" (towards M).
  // So offset should point *away* from wind?
  // Let's stick to standard displacement:
  // displacement = vector from original position.
  // We sample at uv - displacement.

  let sampleUV = uv - offset;

  // Boundary check
  var color = vec4<f32>(0.0);
  if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
      color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  } else {
      // Out of bounds: Transparent or Edge?
      color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  }

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
