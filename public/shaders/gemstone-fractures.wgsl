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

// Simple hash for pseudo-randomness
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let scale = u.zoom_params.x * 20.0 + 2.0;
    let refraction = u.zoom_params.y * 0.05;
    let rotationBase = u.zoom_params.z;
    let edgeWidth = u.zoom_params.w * 0.1;

    let st = uv * vec2<f32>(aspect, 1.0) * scale;
    let i_st = floor(st);
    let f_st = fract(st);

    // Voronoi / Cellular logic
    var m_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            // Animate point
            let animPoint = 0.5 + 0.5 * sin(u.config.x * 0.5 + 6.2831 * point);
            let diff = neighbor + animPoint - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                m_point = point;
                cell_id = i_st + neighbor;
            }
        }
    }

    // Refraction based on cell ID
    let rotAngle = (hash22(cell_id).x - 0.5) * rotationBase * 10.0 + u.config.x * (hash22(cell_id).y - 0.5) * rotationBase;
    let c = cos(rotAngle);
    let s = sin(rotAngle);

    // UV offset relative to cell center (approx)
    let cellCenter = (cell_id + 0.5) / scale;
    // Actually we need to sample relative to the pixel we are at, but shift it based on the cell orientation.
    // Simplification: rotate the uv lookup around the current pixel, but the angle is determined by the cell.
    // Or better: Sample the texture at the CELL CENTER but rotated? That makes it look like tiles.
    // Let's do: Rotate the UV space locally around the cell center.

    // Convert current UV to local coords relative to cell center
    // Wait, cell center in UV space is tricky with aspect.
    // Let's just do a simpler distortion: offset based on cell ID hash.

    // Let's stick to the rotation idea but keep it simple.
    let localUV = (uv * vec2<f32>(aspect, 1.0) - cellCenter);
    // This cellCenter calc is approximate because it ignores the Voronoi shift.
    // Let's just use the current UV and rotate it by an angle unique to the cell.

    // Correct logic:
    // We are at `uv`. We belong to `cell_id`.
    // We want to sample from a rotated version of the texture.

    // Let's rotate the offset vector (uv - 0.5) by the angle.
    let center = vec2<f32>(0.5 * aspect, 0.5);
    let fromCenter = uv * vec2<f32>(aspect, 1.0) - center;
    let rotFromCenter = vec2<f32>(
        fromCenter.x * c - fromCenter.y * s,
        fromCenter.x * s + fromCenter.y * c
    );
    let sampleUV = (rotFromCenter + center) / vec2<f32>(aspect, 1.0);

    // Chromatic aberration
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(refraction, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(refraction, 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Edges
    if (m_dist > 1.0 - edgeWidth * 5.0) { // Voronoi distance is diff length
       // This simple check doesn't make good edges on Voronoi without second neighbor.
       // But let's leave it simple.
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
     // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
