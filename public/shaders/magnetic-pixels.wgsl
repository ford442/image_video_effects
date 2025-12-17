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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Magnetic Pixels
// Param1: Force Strength
// Param2: Effect Radius
// Param3: Hardness (Edge sharpness)
// Param4: Chaos

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  // Defaults
  let strength = max(u.zoom_params.x * 0.5, 0.0);
  let radius = max(u.zoom_params.y * 0.5, 0.01);
  let hardness = u.zoom_params.z * 10.0 + 1.0;
  let chaos = u.zoom_params.w;

  var distortion = vec2<f32>(0.0);

  // u.zoom_config.yz are 0-1 if mouse is active, but might be -1 or similar if not?
  // Usually the renderer passes 0.5, 0.5 or last position.
  // We can check if mousePos is within 0..1 to be safe, but usually it's fine.

  if (mousePos.x >= 0.0 && mousePos.y >= 0.0 && strength > 0.0) {
      let aspect = resolution.x / resolution.y;
      let dVec = uv - mousePos;
      // Correct for aspect ratio in distance calculation so the circle is circular
      let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

      if (dist < radius) {
          // Normalized distance 0..1 (0 at center, 1 at edge)
          let t = dist / radius;

          // Repulsion force profile
          // We want max force at center (t=0), 0 at edge (t=1).
          // pow(1.0 - t, hardness) gives a curve that is 1 at center and 0 at edge.
          // hardness > 1 makes it fall off faster (sharper center).
          let force = pow(1.0 - t, hardness);

          // Direction away from mouse
          let dir = normalize(dVec);

          // Add chaos/noise to the force direction or magnitude
          var noise = 0.0;
          if (chaos > 0.0) {
             noise = (hash12(uv * 100.0 + u.config.x) - 0.5) * chaos * 0.1;
          }

          distortion = dir * force * strength + noise;
      }
  }

  // To push pixels AWAY from mouse, we sample CLOSER to mouse.
  // P_new = P_old - distortion.
  // If P_old is to the right of mouse (dir = +x), we sample from left (closer to mouse).
  let sampleUV = clamp(uv - distortion, vec2<f32>(0.0), vec2<f32>(1.0));

  var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

  textureStore(writeTexture, global_id.xy, color);
}
