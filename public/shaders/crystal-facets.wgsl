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

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    // x: Facet Count (e.g. 3 to 12)
    // y: Refraction Strength
    // z: Rotation Speed / Offset
    // w: Center Zoom / Size

    let facetCount = floor(mix(3.0, 16.0, u.zoom_params.x));
    let refraction = u.zoom_params.y * 0.1;
    let rotation = u.zoom_params.z * 6.28 + u.config.x * 0.1; // Base rotation + time
    let zoom = mix(1.0, 0.5, u.zoom_params.w);

    // Coordinate relative to mouse/center
    // Use mouse as the "cut" center
    let center = mouse;
    var dir = (uv - center);
    dir.x *= aspect;

    let dist = length(dir);
    var angle = atan2(dir.y, dir.x);

    // Apply rotation
    angle += rotation;

    // Quantize angle to create facets
    let sector = floor(angle / (6.28318 / facetCount));
    let sectorAngle = sector * (6.28318 / facetCount);

    // Each facet has a random tilt/offset based on its ID (sector)
    let facetID = sector;
    let randomTilt = (hash11(facetID) - 0.5) * 2.0; // -1 to 1

    // New UV calculation
    // We want to sample the texture as if looking through a prism face.
    // The face might be tilted, causing a shift.
    // The shift depends on the facet ID.

    // Offset vector for this facet
    let offsetDir = vec2<f32>(cos(sectorAngle), sin(sectorAngle));

    // Chromatic aberration: different offsets for R, G, B
    let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
    let gOffset = offsetDir * refraction * 0.5; // Less shift
    let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

    // Zoom effect per facet
    // Sample closer to center based on zoom
    // We modify the distance
    let distDistorted = pow(dist, zoom); // Bulge or pinch

    // Reconstruct coordinate
    // Rotate back? Or just use the original angle but quantized?
    // Let's use the original angle for continuity within the facet, but shifted

    // Actually, "Facet" means the image is discontinuous at boundaries.
    // So we should sample based on the sector center angle + local UV?
    // Or just distort the global UV.

    let baseUV = center + vec2<f32>(cos(angle - rotation), sin(angle - rotation)) * distDistorted / vec2<f32>(aspect, 1.0);

    // Sample
    let r = textureSampleLevel(readTexture, u_sampler, baseUV - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, baseUV - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, baseUV - bOffset, 0.0).b;

    // Add facet edges (lines)
    // Distance to nearest sector boundary
    let angleLocal = fract(angle / (6.28318 / facetCount)); // 0 to 1
    let edge = min(angleLocal, 1.0 - angleLocal);
    let edgeStrength = smoothstep(0.02, 0.0, edge);

    var color = vec3<f32>(r, g, b);

    // Add shine to edges
    color += vec3<f32>(edgeStrength * 0.5);

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
