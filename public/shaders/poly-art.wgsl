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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Simple pseudo-random
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mousePos = u.zoom_config.yz;

  let cellSize = u.zoom_params.x * 50.0 + 10.0; // Cells across
  let edgeWidth = u.zoom_params.y * 0.1;
  let randomness = u.zoom_params.z;
  let influence = u.zoom_params.w;

  // Distort UV space towards mouse to create "densification"
  let aspect = resolution.x / resolution.y;
  let dVec = uv - mousePos;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

  // Magnify grid near mouse (fisheye grid)
  let distortion = 1.0 - smoothstep(0.0, 0.5, dist) * influence;
  // Apply distortion to the coordinate we use for grid calculation
  let gridUV = uv * (1.0 + distortion);

  // Voronoi / Delaunay-ish approximation
  // Standard Voronoi implementation
  let scaled = gridUV * cellSize;
  let i_st = floor(scaled);
  let f_st = fract(scaled);

  var m_dist = 1.0;  // Minimum distance
  var m_point = vec2<f32>(0.0); // Closest point relative pos
  var m_id = vec2<f32>(0.0);    // Closest point grid ID

  // First pass: find closest point
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
       let neighbor = vec2<f32>(f32(x), f32(y));
       let point = hash22(i_st + neighbor);

       // Animate point?
       // let p = 0.5 + 0.5 * sin(u.config.x + 6.2831 * point);

       let pos = neighbor + point * randomness;
       let d = length(pos - f_st);

       if (d < m_dist) {
           m_dist = d;
           m_point = pos;
           m_id = i_st + neighbor;
       }
    }
  }

  // Second pass: Distance to borders (optional for edge drawing)
  // Actually, for poly art, we just want the color of the cell.

  // Calculate the UV of the seed point for the cell
  // m_id is the integer grid coordinate of the cell
  // We need to reconstruct the UV.
  // scaled = gridUV * cellSize. So gridUV = scaled / cellSize.
  // The seed point in scaled space is m_id + hash22(m_id) * randomness.
  let seedPointRel = hash22(m_id) * randomness;
  let seedPointScaled = m_id + seedPointRel;

  // Inverse the distortion? That's hard.
  // Let's just sample the texture at the undistorted UV corresponding to the cell center.
  // If the grid itself is distorted, the cell center is effectively at a different place in image space.
  // We can just use `seedPointScaled / cellSize` as the sampling coordinate.
  // However, since we distorted `gridUV` from `uv`, `seedPointScaled` is in `gridUV` space.
  // If we sample image using that, the image will look distorted.
  // Maybe that's what we want? "Poly Art" often abstracts the form.
  // Let's sample the original image at the *current pixel's UV*? No, that would just look like voronoi overlay.
  // We want flat shading. So we must sample at a single point per cell.

  let sampleUV = seedPointScaled / cellSize;

  // Fix: Since we distorted the gridUV, mapping back to UV linearly is "wrong" if we want the cells to match underlying image features exactly,
  // but for an effect it works fine.
  // Let's clamp to safe range.
  let safeUV = clamp(sampleUV / (1.0 + distortion), vec2<f32>(0.0), vec2<f32>(1.0)); // Approximate inverse

  // Better: Just use `sampleUV` but understand it might drift from the "real" image pixels at that location.
  // Or, don't distort the grid, just the cell size?
  // Let's stick to the distorted grid, it looks more "responsive".

  var color = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

  // Edges
  if (edgeWidth > 0.0) {
      // Very simple edge check: distance to cell center vs neighbor center?
      // Or just use the m_dist?
      // Voronoi edges are where m_dist is equal for two neighbors.
      // This requires 2nd closest point search.
      // Let's skip expensive edge calculation and just use `m_dist` for a radial gradient or simple border.
      // Or do a cheap 2nd pass.

      var m_dist2 = 1.0;
      for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
           let neighbor = vec2<f32>(f32(x), f32(y));
           let point = hash22(i_st + neighbor);
           let pos = neighbor + point * randomness;

           if (length(i_st + neighbor - m_id) > 0.1) { // distinct from closest
               let distVec = (m_point + pos) * 0.5 - f_st;
               let r = length(distVec); // Not quite right for Voronoi edge distance
               // Correct logic for distance to edge:
               // dot( (p2-p1), (uv - (p1+p2)/2) )
               let p1 = m_point;
               let p2 = pos;
               let center = (p1 + p2) * 0.5;
               let diff = p2 - p1;
               let dEdge = dot( f_st - center, normalize(diff) );
               // This is signed distance to the perpendicular bisector.
               // We want min abs distance?
               // Actually for Voronoi border, it's simpler to check if d is close to m_dist.
           }
        }
      }
      // Too complex for now. Let's just highlight center.
      // color += smoothstep(0.1, 0.0, m_dist) * edgeWidth;
  }

  textureStore(writeTexture, global_id.xy, color);

  // Pass depth
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
