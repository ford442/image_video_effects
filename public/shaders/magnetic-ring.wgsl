// ────────────────────────────────────────────────────────────────────────────────
//  Magnetic Ring
//  A distortion ring that follows the mouse, creating a lens-like pulse effect.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    // Correct distance for aspect ratio
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params
    let baseRadius = u.zoom_params.x * 0.5 + 0.1; // 0.1 to 0.6
    let strength = u.zoom_params.y * 0.2;         // 0.0 to 0.2
    let pulseSpeed = u.zoom_params.z * 5.0;

    // Ring Animation
    let pulse = sin(time * pulseSpeed) * 0.05;
    let radius = baseRadius + pulse;
    let thickness = mix(0.01, 0.3, u.zoom_params.w);

    // Calculate Ring Influence
    // We want a smooth bump function around 'radius'
    // 1.0 at radius, 0.0 at radius +/- thickness
    let distDiff = abs(dist - radius);
    let ringMask = smoothstep(thickness, 0.0, distDiff);

    // Distortion
    // Twist UVs inside the ring influence
    let angle = atan2(dVec.y, dVec.x);
    let twist = ringMask * strength * sin(dist * 20.0 - time * 2.0);

    // Radial offset
    let radialOffset = ringMask * strength * 0.5;

    var offset = vec2<f32>(cos(angle + twist), sin(angle + twist)) * (dist + radialOffset) - dVec;

    // If we are strictly correcting aspect back, we might get oval distortion if not careful.
    // Let's just apply a simple offset based on the vector.
    // Simpler approach:
    // Move UV towards/away from mouse based on ringMask

    let distortDir = normalize(dVec);
    let finalOffset = distortDir * ringMask * strength * sin(dist * 50.0);

    // Apply chromatic aberration
    let rUV = uv + finalOffset * (1.0 + ringMask * 0.5);
    let gUV = uv + finalOffset;
    let bUV = uv + finalOffset * (1.0 - ringMask * 0.5);

    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Optional: Highlight the ring itself with brightness
    let highlight = ringMask * 0.2;

    var color = vec3<f32>(r, g, b) + highlight;

    textureStore(writeTexture, gid.xy, vec4<f32>(color, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
