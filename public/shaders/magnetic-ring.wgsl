// ────────────────────────────────────────────────────────────────────────────────
//  Magnetic Ring
//  A distortion ring that follows the mouse, creating a lens-like pulse effect.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
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
    let thickness = 0.1;

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

    let r = textureSampleLevel(videoTex, videoSampler, rUV, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, gUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, bUV, 0.0).b;

    // Optional: Highlight the ring itself with brightness
    let highlight = ringMask * 0.2;

    var color = vec3<f32>(r, g, b) + highlight;

    textureStore(outTex, gid.xy, vec4<f32>(color, 1.0));

    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
