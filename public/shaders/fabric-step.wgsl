// ═══════════════════════════════════════════════════════════════
//  Fabric of Reality - Mass-Spring Cloth Simulation with Textile Alpha
//  Category: artistic
//  Features: Woven textile, thread density, strain-based translucency
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Stiffness, y=TearThreshold, z=Gravity, w=Damping
  ripples: array<vec4<f32>, 50>,
};

// Textile Material Properties
const THREAD_DENSITY: f32 = 3.0;          // Threads per unit area
const FABRIC_BASE_ALPHA: f32 = 0.78;      // Woven fabric is somewhat transparent
const STRAINED_ALPHA: f32 = 0.55;         // Stretched fabric is more translucent
const TORN_ALPHA: f32 = 0.25;             // Torn areas are very transparent

const REST_LENGTH: f32 = 1.0;
const CONSTRAINT_ITERATIONS: i32 = 4;

// Noise function for organic motion
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn noise2D(p: vec2<f32>) -> f32 {
  var i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, time: f32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var freq = 1.0;
  var pos = p;
  for (var i = 0; i < 4; i = i + 1) {
    value = value + amplitude * noise2D(pos * freq + vec2<f32>(time * 0.1, time * 0.15));
    freq = freq * 2.0;
    amplitude = amplitude * 0.5;
  }
  return value;
}

// Calculate fabric density based on strain
fn calculateFabricDensity(strain: f32, isTorn: bool) -> f32 {
    if (isTorn) {
        return 0.15;
    }
    
    // Higher strain = stretched threads = lower density
    let stretchedDensity = mix(THREAD_DENSITY, THREAD_DENSITY * 0.6, strain);
    return stretchedDensity;
}

// Fabric subsurface scattering (threads scatter light)
fn fabricSSS(strain: f32, baseColor: vec3<f32>) -> vec3<f32> {
    // Thread scattering creates soft diffusion
    let threadScatter = strain * 0.3;
    
    // Fabric often has slight color variation from thread gaps
    let gapTint = vec3<f32>(0.9, 0.9, 0.95);
    
    return mix(baseColor, baseColor * gapTint, threadScatter);
}

// Calculate alpha for textile based on strain and damage
fn calculateFabricAlpha(strain: f32, isTorn: bool, threadDensity: f32) -> f32 {
    var alpha = FABRIC_BASE_ALPHA;
    
    if (isTorn) {
        // Torn fabric is very transparent
        alpha = TORN_ALPHA;
    } else if (strain > 0.5) {
        // High strain = stretched = more see-through
        let stretchFactor = smoothstep(0.5, 1.0, strain);
        alpha = mix(FABRIC_BASE_ALPHA, STRAINED_ALPHA, stretchFactor);
    }
    
    // Thread density affects opacity (Beer-Lambert)
    let densityAlpha = exp(-threadDensity * 0.3);
    alpha = mix(alpha, alpha * 0.85, densityAlpha * 0.3);
    
    return clamp(alpha, 0.2, 0.88);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  var uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let dt = 0.016;
  
  // Parameters from zoom_params
  let stiffness = mix(0.1, 0.99, u.zoom_params.x);
  let tearThreshold = mix(1.5, 4.0, u.zoom_params.y);
  let gravity = mix(0.0, 0.02, u.zoom_params.z);
  let damping = mix(0.95, 0.999, u.zoom_params.w);
  
  // Read previous state from dataTextureC
  let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  
  var pos = prevState.xy;
  var prevPos = prevState.zw;
  
  if (length(pos) < 0.001 && length(prevPos) < 0.001) {
    pos = uv;
    prevPos = uv;
  }
  
  var vel = (pos - prevPos) * damping;
  vel.y = vel.y + gravity * dt;
  
  // Mouse interaction
  var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let toMouse = pos - mouse;
  let mouseDist = length(toMouse);
  let mouseInfluenceRadius = 0.15;
  
  if (mouseDist < mouseInfluenceRadius && mouseDist > 0.001) {
    var force = (1.0 - mouseDist / mouseInfluenceRadius) * 0.02;
    vel = vel + normalize(toMouse) * force;
  }
  
  // Apply ripple forces
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let toRipple = pos - ripple.xy;
        let dist = length(toRipple);
        if (dist < 0.2 && dist > 0.001) {
          var force = (1.0 - dist / 0.2) * (1.0 - rippleAge / 2.0) * 0.03;
          vel = vel + normalize(toRipple) * force;
        }
      }
    }
  }
  
  // Wind force
  let windX = fbm(pos * 4.0 + vec2<f32>(time * 0.5, 0.0), time) - 0.5;
  let windY = fbm(pos * 4.0 + vec2<f32>(0.0, time * 0.5), time) - 0.5;
  vel = vel + vec2<f32>(windX, windY) * 0.001;
  
  // Update position
  let newPrevPos = pos;
  pos = pos + vel;
  
  // Constraint solving
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let restLen = texelSize.x * REST_LENGTH;
  
  let leftUV = uv + vec2<f32>(-texelSize.x, 0.0);
  let rightUV = uv + vec2<f32>(texelSize.x, 0.0);
  let upUV = uv + vec2<f32>(0.0, -texelSize.y);
  let downUV = uv + vec2<f32>(0.0, texelSize.y);
  
  let leftState = textureSampleLevel(dataTextureC, non_filtering_sampler, leftUV, 0.0);
  let rightState = textureSampleLevel(dataTextureC, non_filtering_sampler, rightUV, 0.0);
  let upState = textureSampleLevel(dataTextureC, non_filtering_sampler, upUV, 0.0);
  let downState = textureSampleLevel(dataTextureC, non_filtering_sampler, downUV, 0.0);
  
  var leftPos = leftState.xy;
  var rightPos = rightState.xy;
  var upPos = upState.xy;
  var downPos = downState.xy;
  
  if (length(leftPos) < 0.001) { leftPos = leftUV; }
  if (length(rightPos) < 0.001) { rightPos = rightUV; }
  if (length(upPos) < 0.001) { upPos = upUV; }
  if (length(downPos) < 0.001) { downPos = downUV; }
  
  var isTorn = false;
  
  for (var iter = 0; iter < CONSTRAINT_ITERATIONS; iter = iter + 1) {
    if (coord.x > 0u) {
      let delta = pos - leftPos;
      let dist = length(delta);
      if (dist > restLen && dist < tearThreshold * restLen) {
        let correction = (dist - restLen) / dist * 0.5 * stiffness;
        pos = pos - delta * correction;
      } else if (dist >= tearThreshold * restLen) {
        isTorn = true;
      }
    }
    
    if (coord.x < size.x - 1u) {
      let delta = pos - rightPos;
      let dist = length(delta);
      if (dist > restLen && dist < tearThreshold * restLen) {
        let correction = (dist - restLen) / dist * 0.5 * stiffness;
        pos = pos - delta * correction;
      } else if (dist >= tearThreshold * restLen) {
        isTorn = true;
      }
    }
    
    if (coord.y > 0u) {
      var delta = pos - upPos;
      var dist = length(delta);
      if (dist > restLen && dist < tearThreshold * restLen) {
        var correction = (dist - restLen) / dist * 0.5 * stiffness;
        pos = pos - delta * correction;
      } else if (dist >= tearThreshold * restLen) {
        isTorn = true;
      }
    }
    
    if (coord.y < size.y - 1u) {
      var delta = pos - downPos;
      var dist = length(delta);
      if (dist > restLen && dist < tearThreshold * restLen) {
        var correction = (dist - restLen) / dist * 0.5 * stiffness;
        pos = pos - delta * correction;
      } else if (dist >= tearThreshold * restLen) {
        isTorn = true;
      }
    }
  }
  
  // Pin top edge
  if (coord.y == 0u) {
    pos = uv;
  }
  
  pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));
  
  // Store state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(pos, newPrevPos));
  
  // Calculate strain for visualization and alpha
  var totalStrain = 0.0;
  if (coord.x > 0u) {
    var d = length(pos - leftPos);
    totalStrain = totalStrain + abs(d - restLen) / restLen;
  }
  if (coord.y > 0u) {
    var d = length(pos - upPos);
    totalStrain = totalStrain + abs(d - restLen) / restLen;
  }
  totalStrain = clamp(totalStrain * 2.0, 0.0, 1.0);
  
  textureStore(dataTextureB, vec2<i32>(coord), vec4<f32>(totalStrain, vel, 1.0));
  
  // Sample source texture at deformed position
  let sourceColor = textureSampleLevel(readTexture, u_sampler, pos, 0.0);
  
  // Apply fabric SSS
  let fabricColor = fabricSSS(totalStrain, sourceColor.rgb);
  
  // Strain color visualization
  let strainColor = mix(
    vec3<f32>(0.2, 0.4, 0.8),
    vec3<f32>(1.0, 0.3, 0.1),
    totalStrain
  );
  
  let finalColor = mix(fabricColor, strainColor, totalStrain * 0.3);
  
  // Calculate textile alpha
  let threadDensity = calculateFabricDensity(totalStrain, isTorn);
  let fabricAlpha = calculateFabricAlpha(totalStrain, isTorn, threadDensity);
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, fabricAlpha));
  
  // Write depth
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, pos, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
