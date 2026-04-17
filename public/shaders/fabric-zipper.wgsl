// ═══════════════════════════════════════════════════════════════
//  Fabric Zipper - Image Effect with Textile and Metal Materials
//  Category: interactive-mouse
//  Features: Woven fabric, metal zipper teeth, seam opacity
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Material Properties
const FABRIC_ALPHA: f32 = 0.82;           // Woven fabric base transparency
const SEAM_ALPHA: f32 = 0.95;             // Seams are more opaque
const METAL_ALPHA: f32 = 0.98;            // Metal teeth are nearly opaque
const FABRIC_DENSITY: f32 = 2.5;          // Thread density

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Calculate fabric alpha with weave pattern
fn calculateFabricAlpha(uv: vec2<f32>, isSeam: bool, isTeeth: bool) -> f32 {
    if (isTeeth) {
        return METAL_ALPHA;
    }
    
    if (isSeam) {
        // Seams have tighter weave = more opaque
        return SEAM_ALPHA;
    }
    
    // Fabric weave creates varying opacity
    let weavePattern = sin(uv.x * mix(50.0, 400.0, u.zoom_params.z)) * sin(uv.y * mix(50.0, 400.0, u.zoom_params.z)) * 0.5 + 0.5;
    let weaveAlpha = mix(FABRIC_ALPHA * 0.9, FABRIC_ALPHA, weavePattern);
    
    // Thread density affects opacity
    let densityAlpha = exp(-FABRIC_DENSITY * 0.2);
    let finalAlpha = mix(weaveAlpha, weaveAlpha * 0.9, densityAlpha * 0.3);
    
    return clamp(finalAlpha, 0.65, 0.92);
}

// Fabric SSS for textile areas
fn fabricSSS(baseColor: vec3<f32>, noiseVal: f32) -> vec3<f32> {
    // Fabric has soft diffusion from thread gaps
    let threadTint = vec3<f32>(0.95, 0.95, 0.98);
    let scattered = mix(baseColor, baseColor * threadTint, noiseVal * 0.15);
    return scattered;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
    return;
  }
  let coord = vec2<i32>(global_id.xy);
  var uv = vec2<f32>(coord) / vec2<f32>(dims);

  // Parameters
  let teeth_size = mix(20.0, 100.0, u.zoom_params.x);
  let opening_width = mix(0.1, 1.0, u.zoom_params.y);

  // Mouse
  var mouse = u.zoom_config.yz;
  let aspect = u.config.z / u.config.w;

  // Zipper Logic
  let dx = (uv.x - mouse.x) * aspect;
  let dy = uv.y - mouse.y;

  var width = 0.0;
  if (dy < 0.0) {
      width = -dy * opening_width;
  }

  // Zipper Teeth
  let teeth_pattern = step(0.5, fract(uv.y * teeth_size));

  let tooth_amp = mix(0.0, 0.1, u.zoom_params.w);
  let jagged_width = width + tooth_amp * sin(uv.y * teeth_size * 6.28);

  // Mask
  let edge_dist = abs(dx) - jagged_width;
  let mask = 1.0 - smoothstep(0.0, 0.01, edge_dist);

  // Zipper Slider (The Metal Piece)
  let slider_dist = distance(vec2<f32>((uv.x - mouse.x) * aspect, uv.y), vec2<f32>(0.0, mouse.y));
  let slider_mask = 1.0 - smoothstep(0.03, 0.035, slider_dist);

  // Fabric Texture with noise
  let noise_val = noise(uv * 50.0);
  var fabric_col = vec3<f32>(0.1, 0.1, 0.15) + vec3<f32>(noise_val * 0.05);
  
  // Apply fabric SSS
  fabric_col = fabricSSS(fabric_col, noise_val);
  
  // Add a seam line
  let seam = 1.0 - smoothstep(0.0, 0.005, abs(dx));
  let isSeam = seam * step(0.0, dy) > 0.5;
  let fabric_final = mix(fabric_col, vec3<f32>(0.05), seam * step(0.0, dy));

  // Image Texture
  let img_col = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

  // Metal Color
  let metal_col = vec3<f32>(0.7, 0.7, 0.8) + vec3<f32>(noise_val * 0.1);

  // Teeth Color (Gold/Silver)
  let teeth_region = smoothstep(0.0, 0.02, abs(edge_dist));
  let tooth_col = vec3<f32>(0.6, 0.5, 0.2);

  // Final Mix
  var final_col = mix(fabric_final, img_col, mask);

  // Draw Teeth (The edge)
  let border = smoothstep(0.01, 0.0, abs(edge_dist));
  let tooth_vis = step(0.4, fract(uv.y * teeth_size));
  let isTeeth = abs(edge_dist) < 0.015 && tooth_vis > 0.5;

  if (isTeeth) {
      final_col = tooth_col;
  }

  // Draw Slider
  let isSlider = slider_mask > 0.5;
  final_col = mix(final_col, metal_col, slider_mask);

  // Calculate material alpha
  let materialAlpha = calculateFabricAlpha(uv, isSeam, isTeeth || isSlider);
  
  // Blend alpha: fabric allows some image through, metal is opaque
  let finalAlpha = mix(materialAlpha, 1.0, mask * 0.7);

  textureStore(writeTexture, coord, vec4<f32>(final_col, finalAlpha));

  // Pass through depth
  let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
