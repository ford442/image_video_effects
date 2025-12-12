// DLA Crystals - Diffusion-Limited Aggregation Crystal Growth
// Random walkers aggregate to form fractal crystal structures

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // frozen crystal map (r=frozen, g=age, b=crystal color, a=branch id)
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // walker positions (packed)
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous state
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=WalkerSpeed, y=AttractStrength, z=Stickiness, w=BranchAngle
  ripples: array<vec4<f32>, 50>,
};

const WALKER_STEPS: i32 = 8;
const NEIGHBOR_CHECK_RADIUS: i32 = 1;

// Pseudo-random number generators
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h1 = hash21(p);
  let h2 = hash21(p + vec2<f32>(1.0, 1.0));
  return vec2<f32>(h1, h2);
}

// Check if any neighbor is frozen (part of crystal)
fn hasNeighborFrozen(uv: vec2<f32>, texelSize: vec2<f32>) -> f32 {
  var maxFrozen = 0.0;
  
  for (var dy = -NEIGHBOR_CHECK_RADIUS; dy <= NEIGHBOR_CHECK_RADIUS; dy = dy + 1) {
    for (var dx = -NEIGHBOR_CHECK_RADIUS; dx <= NEIGHBOR_CHECK_RADIUS; dx = dx + 1) {
      if (dx == 0 && dy == 0) { continue; }
      let neighborUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let neighborState = textureSampleLevel(dataTextureC, non_filtering_sampler, neighborUV, 0.0);
      maxFrozen = max(maxFrozen, neighborState.r);
    }
  }
  
  return maxFrozen;
}

// Get average color of frozen neighbors
fn getFrozenNeighborColor(uv: vec2<f32>, texelSize: vec2<f32>) -> vec3<f32> {
  var colorSum = vec3<f32>(0.0);
  var count = 0.0;
  
  for (var dy = -NEIGHBOR_CHECK_RADIUS; dy <= NEIGHBOR_CHECK_RADIUS; dy = dy + 1) {
    for (var dx = -NEIGHBOR_CHECK_RADIUS; dx <= NEIGHBOR_CHECK_RADIUS; dx = dx + 1) {
      let neighborUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
      let neighborState = textureSampleLevel(dataTextureC, non_filtering_sampler, neighborUV, 0.0);
      if (neighborState.r > 0.5) {
        let neighborSource = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0);
        colorSum = colorSum + neighborSource.rgb;
        count = count + 1.0;
      }
    }
  }
  
  if (count > 0.0) {
    return colorSum / count;
  }
  return vec3<f32>(0.5);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  let frame = u.config.y;
  
  // Parameters
  let walkerSpeed = mix(0.5, 3.0, u.zoom_params.x);
  let attractStrength = mix(0.0, 0.5, u.zoom_params.y);
  let stickiness = mix(0.3, 1.0, u.zoom_params.z);
  let branchAngle = mix(0.1, 1.0, u.zoom_params.w);
  
  // Read current state
  let state = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
  var frozen = state.r;
  var age = state.g;
  var crystalHue = state.b;
  var branchId = state.a;
  
  // Source image data
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let sourceLum = dot(sourceColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Initialize seed crystals at ripple points
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 0.5) {
        let dist = length(uv - ripple.xy);
        if (dist < 0.02 && frozen < 0.5) {
          frozen = 1.0;
          age = time;
          crystalHue = hash21(ripple.xy) * 0.3 + 0.6; // Blue-purple hues
          branchId = f32(i) / 50.0;
        }
      }
    }
  }
  
  // Initialize seed at mouse position
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  let mouseDist = length(uv - mouse);
  if (mouseDist < 0.01 && frozen < 0.5) {
    frozen = 1.0;
    age = time;
    crystalHue = 0.55; // Cyan
    branchId = 0.0;
  }
  
  // If not frozen, simulate walker behavior
  if (frozen < 0.5) {
    // Generate random walk direction based on position and time
    let randSeed = uv * 1000.0 + vec2<f32>(time * 100.0);
    let randDir = hash22(randSeed);
    
    // Bias towards nearby frozen crystals (attraction)
    var attractDir = vec2<f32>(0.0);
    var minFrozenDist = 100.0;
    
    // Search for nearby frozen pixels
    let searchRadius = 5;
    for (var dy = -searchRadius; dy <= searchRadius; dy = dy + 1) {
      for (var dx = -searchRadius; dx <= searchRadius; dx = dx + 1) {
        let searchUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
        let searchState = textureSampleLevel(dataTextureC, non_filtering_sampler, searchUV, 0.0);
        if (searchState.r > 0.5) {
          let dist = length(vec2<f32>(f32(dx), f32(dy)));
          if (dist < minFrozenDist && dist > 0.0) {
            minFrozenDist = dist;
            attractDir = normalize(vec2<f32>(f32(dx), f32(dy)));
          }
        }
      }
    }
    
    // Check if we should freeze (adjacent to frozen crystal)
    let neighborFrozen = hasNeighborFrozen(uv, texelSize);
    
    if (neighborFrozen > 0.5) {
      // Stickiness probability
      let stickChance = hash21(uv * 500.0 + vec2<f32>(time));
      if (stickChance < stickiness) {
        // Freeze this pixel!
        frozen = 1.0;
        age = time;
        
        // Inherit color from neighbor with variation
        let neighborColor = getFrozenNeighborColor(uv, texelSize);
        crystalHue = dot(neighborColor, vec3<f32>(0.333)) + hash21(uv * 123.0) * 0.1;
        
        // Branch angle affects growth direction preference
        let growthAngle = atan2(attractDir.y, attractDir.x);
        branchId = (growthAngle / 6.283 + 0.5) * branchAngle;
      }
    }
  } else {
    // Already frozen - age the crystal
    age = age + 0.001;
  }
  
  // Store crystal state
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(frozen, age, crystalHue, branchId));
  
  // Visualization
  var finalColor = sourceColor.rgb;
  
  if (frozen > 0.5) {
    // Crystal visualization
    let crystalAge = time - age;
    
    // Color based on crystal hue and branch
    let hue = crystalHue + branchId * 0.2;
    
    // HSV to RGB
    let h = hue * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs((h % 2.0) - 1.0));
    let m = 0.2;
    
    var rgb: vec3<f32>;
    if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    
    let crystalColor = rgb + vec3<f32>(m);
    
    // Glow effect based on age
    let glow = exp(-crystalAge * 0.5) * 0.5 + 0.5;
    
    // Edge detection for crystal boundaries
    let edgeStrength = 1.0 - hasNeighborFrozen(uv, texelSize);
    let edgeGlow = vec3<f32>(1.0) * edgeStrength * 0.3;
    
    finalColor = crystalColor * glow + edgeGlow;
    
    // Add sparkle
    let sparkle = pow(hash21(uv * 1000.0 + vec2<f32>(time * 10.0)), 8.0) * 0.5;
    finalColor = finalColor + vec3<f32>(sparkle);
  } else {
    // Non-frozen areas show source with slight darkening
    finalColor = sourceColor.rgb * 0.7;
    
    // Show attraction field as subtle glow
    let searchRadius = 10;
    var closestFrozen = 100.0;
    for (var dy = -searchRadius; dy <= searchRadius; dy = dy + 1) {
      for (var dx = -searchRadius; dx <= searchRadius; dx = dx + 1) {
        let searchUV = uv + vec2<f32>(f32(dx), f32(dy)) * texelSize;
        let searchState = textureSampleLevel(dataTextureC, non_filtering_sampler, searchUV, 0.0);
        if (searchState.r > 0.5) {
          closestFrozen = min(closestFrozen, length(vec2<f32>(f32(dx), f32(dy))));
        }
      }
    }
    
    if (closestFrozen < 10.0) {
      let fieldGlow = (10.0 - closestFrozen) / 10.0 * 0.1;
      finalColor = finalColor + vec3<f32>(0.2, 0.5, 1.0) * fieldGlow;
    }
  }
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
