// Voronoi Dynamics - Interactive Bubble Physics
// Dynamic Voronoi cells with physics-based centroid movement

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // centroid positions
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // velocities
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // read previous
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=CentroidCount, y=Repulsion, z=Attraction, w=EdgeWidth
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_CENTROIDS: i32 = 32;

// Hash functions
fn hash21(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
  p3 = p3 + dot(p3, vec3<f32>(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
  return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// Get centroid position from seed (stored in extraBuffer or generated)
fn getCentroid(index: i32, time: f32) -> vec2<f32> {
  // Generate stable pseudo-random position
  let seed = vec2<f32>(f32(index) * 127.1, f32(index) * 311.7);
  var pos = hash22(seed);
  
  // Add gentle animation
  let phase = f32(index) * 0.7;
  pos = pos + vec2<f32>(
    sin(time * 0.3 + phase) * 0.05,
    cos(time * 0.4 + phase * 1.3) * 0.05
  );
  
  return pos;
}

// Find nearest centroid and distance
fn findNearestCentroid(uv: vec2<f32>, time: f32, centroidCount: i32, mouse: vec2<f32>) -> vec3<f32> {
  var nearestDist = 1e10;
  var secondDist = 1e10;
  var nearestIdx = 0;
  
  // Check regular centroids
  for (var i = 0; i < centroidCount; i = i + 1) {
    if (i >= MAX_CENTROIDS) { break; }
    let centroid = getCentroid(i, time);
    let dist = length(uv - centroid);
    
    if (dist < nearestDist) {
      secondDist = nearestDist;
      nearestDist = dist;
      nearestIdx = i;
    } else if (dist < secondDist) {
      secondDist = dist;
    }
  }
  
  // Mouse as dynamic centroid
  let mouseDist = length(uv - mouse);
  if (mouseDist < nearestDist) {
    secondDist = nearestDist;
    nearestDist = mouseDist;
    nearestIdx = -1; // Special index for mouse
  } else if (mouseDist < secondDist) {
    secondDist = mouseDist;
  }
  
  // Check ripple positions as temporary centroids
  for (var r = 0; r < 50; r = r + 1) {
    let ripple = u.ripples[r];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let dist = length(uv - ripple.xy);
        if (dist < nearestDist) {
          secondDist = nearestDist;
          nearestDist = dist;
          nearestIdx = 100 + r; // Ripple indices
        } else if (dist < secondDist) {
          secondDist = dist;
        }
      }
    }
  }
  
  return vec3<f32>(nearestDist, secondDist, f32(nearestIdx));
}

// HSV to RGB
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
  let c = v * s;
  let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
  let m = v - c;
  
  var rgb: vec3<f32>;
  let hi = i32(floor(h * 6.0)) % 6;
  if (hi == 0) { rgb = vec3<f32>(c, x, 0.0); }
  else if (hi == 1) { rgb = vec3<f32>(x, c, 0.0); }
  else if (hi == 2) { rgb = vec3<f32>(0.0, c, x); }
  else if (hi == 3) { rgb = vec3<f32>(0.0, x, c); }
  else if (hi == 4) { rgb = vec3<f32>(x, 0.0, c); }
  else { rgb = vec3<f32>(c, 0.0, x); }
  
  return rgb + vec3<f32>(m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  let coord = gid.xy;
  if (coord.x >= size.x || coord.y >= size.y) { return; }
  
  let uv = vec2<f32>(f32(coord.x), f32(coord.y)) / vec2<f32>(f32(size.x), f32(size.y));
  let texelSize = 1.0 / vec2<f32>(f32(size.x), f32(size.y));
  let time = u.config.x;
  
  // Parameters
  let centroidCount = i32(mix(4.0, f32(MAX_CENTROIDS), u.zoom_params.x));
  let repulsion = mix(0.0, 0.1, u.zoom_params.y);
  let attraction = mix(0.0, 0.05, u.zoom_params.z);
  let edgeWidth = mix(0.001, 0.02, u.zoom_params.w);
  
  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  
  // Find nearest centroid
  let nearest = findNearestCentroid(uv, time, centroidCount, mouse);
  let nearestDist = nearest.x;
  let secondDist = nearest.y;
  let nearestIdx = i32(nearest.z);
  
  // Get source color at this position
  let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  
  // Get color from nearest centroid position
  var centroidPos: vec2<f32>;
  if (nearestIdx == -1) {
    centroidPos = mouse;
  } else if (nearestIdx >= 100) {
    let rippleIdx = nearestIdx - 100;
    centroidPos = u.ripples[rippleIdx].xy;
  } else {
    centroidPos = getCentroid(nearestIdx, time);
  }
  
  let centroidColor = textureSampleLevel(readTexture, u_sampler, centroidPos, 0.0);
  
  // Edge detection - difference between nearest and second nearest
  let edgeDist = secondDist - nearestDist;
  let edge = smoothstep(0.0, edgeWidth, edgeDist);
  
  // Cell shading
  var cellColor = centroidColor.rgb;
  
  // Add subtle gradient within cell
  let gradient = 1.0 - nearestDist * 2.0;
  cellColor = cellColor * (0.8 + gradient * 0.2);
  
  // Iridescent edge coloring
  let edgeHue = fract(f32(nearestIdx) * 0.1 + time * 0.1);
  let edgeColor = hsv2rgb(edgeHue, 0.7, 1.0);
  
  // Bubble-like specular highlight
  let bubbleHighlight = pow(1.0 - nearestDist * 3.0, 8.0);
  let highlightPos = centroidPos + vec2<f32>(-0.02, -0.02);
  let highlightDist = length(uv - highlightPos);
  let highlight = exp(-highlightDist * 50.0) * 0.5;
  
  // Mouse interaction - cells near mouse expand
  let toMouse = length(uv - mouse);
  let mouseInfluence = 1.0 - smoothstep(0.0, 0.2, toMouse);
  
  // Ripple influence - waves through cells
  var rippleWave = 0.0;
  for (var i = 0; i < 50; i = i + 1) {
    let ripple = u.ripples[i];
    if (ripple.z > 0.0) {
      let rippleAge = time - ripple.z;
      if (rippleAge > 0.0 && rippleAge < 2.0) {
        let dist = length(uv - ripple.xy);
        let wave = sin(dist * 30.0 - rippleAge * 10.0);
        let fade = 1.0 - rippleAge / 2.0;
        rippleWave = rippleWave + wave * fade * 0.02 / (dist + 0.1);
      }
    }
  }
  
  // Compose final color
  var finalColor = cellColor;
  
  // Blend with edge
  finalColor = mix(edgeColor * 0.3, finalColor, edge);
  
  // Add highlight
  finalColor = finalColor + vec3<f32>(highlight + bubbleHighlight * 0.2);
  
  // Ripple displacement
  let displacedUV = uv + vec2<f32>(rippleWave);
  let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
  finalColor = mix(finalColor, displacedColor, abs(rippleWave) * 5.0);
  
  // Depth influence - foreground cells are sharper
  let depthSharpness = 0.5 + depth * 0.5;
  finalColor = mix(sourceColor.rgb, finalColor, depthSharpness);
  
  // Store cell info for potential physics
  textureStore(dataTextureA, vec2<i32>(coord), vec4<f32>(centroidPos, nearestDist, f32(nearestIdx)));
  
  // Clamp
  finalColor = clamp(finalColor, vec3<f32>(0.0), vec3<f32>(1.0));
  
  textureStore(writeTexture, vec2<i32>(coord), vec4<f32>(finalColor, 1.0));
  textureStore(writeDepthTexture, vec2<i32>(coord), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
