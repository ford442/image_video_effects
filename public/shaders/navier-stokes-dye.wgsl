// Navier-Stokes Dye Injection - simplified compute skeleton
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // velocity
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // dye
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=unused, y=unused, z=unused, w=unused
  ripples: array<vec4<f32>, 50>,
};

const DT: f32 = 0.016;
@compute @workgroup_size(8, 8, 1)
fn advect_velocity(@builtin(global_invocation_id) gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let vel = textureLoad(dataTextureC, coord, 0).rg;
  let pos = vec2<f32>(f32(coord.x), f32(coord.y));
  let sourcePos = pos - vel * DT;
  let dim = textureDimensions(dataTextureC);
  let res = textureSampleLevel(dataTextureC, u_sampler, sourcePos / vec2<f32>(f32(dim.x), f32(dim.y)), 0.0).rg;
  textureStore(dataTextureA, coord, vec4<f32>(res, 0.0, 0.0));
}

fn inject_dye_impl(gid: vec3<u32>) {
  let coord = vec2<i32>(i32(gid.x), i32(gid.y));
  let src = textureLoad(readTexture, coord, 0);
  let time = u.config.x;
  let dim = textureDimensions(dataTextureA);
  let uv = vec2<f32>(f32(gid.x), f32(gid.y)) / vec2<f32>(f32(dim.x), f32(dim.y));
  
  // Inject dye and energy at ripple locations
  var added_energy = vec2<f32>(0.0);
  for (var i = 0; i < 50; i++) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let ripple_age = time - ripple.z;
      if (ripple_age > 0.0 && ripple_age < 2.0) {
        let dist_to_ripple = distance(uv, ripple.xy);
        if (dist_to_ripple < 0.05) {
          let dir = normalize(uv - ripple.xy);
          added_energy += dir * 20.0 * (1.0 - ripple_age / 2.0);
        }
      }
    }
  }
  
  // Mouse as continuous inflow source
  let mouse_pos = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let dist_to_mouse = distance(uv, mouse_pos);
  if (dist_to_mouse < 0.03) {
    let dir = normalize(uv - mouse_pos);
    added_energy += dir * 10.0;
  }
  
  // Apply added energy to velocity
  var vel = textureLoad(dataTextureC, coord, 0).rg;
  vel += added_energy;
  textureStore(dataTextureA, coord, vec4<f32>(vel, 0.0, 0.0));
  
  // Simple dye injection: shift saturation by velocity curl approximate
  let velL = textureLoad(dataTextureC, coord + vec2<i32>(-1,0), 0).rg;
  let velR = textureLoad(dataTextureC, coord + vec2<i32>(1,0), 0).rg;
  let velT = textureLoad(dataTextureC, coord + vec2<i32>(0,-1), 0).rg;
  let velB = textureLoad(dataTextureC, coord + vec2<i32>(0,1), 0).rg;
  let curl = (velR.y - velL.y) - (velB.x - velT.x);
  let hsv_saturation = min(length(vec3<f32>(curl)) * 10.0, 1.0);
  let shifted_color = vec3<f32>(src.rgb * (1.0 + hsv_saturation));
  let cur = textureLoad(dataTextureC, coord, 0);
  textureStore(dataTextureB, coord, vec4<f32>(mix(cur.rgb, shifted_color, 0.1), 1.0));
  textureStore(writeTexture, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(shifted_color, 1.0));
}

// Main entrypoint runs the dye injection pass
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  inject_dye_impl(gid);
}
