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

// Function to rotate a 2D vector
fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    let mouse = u.zoom_config.yz; // Mouse coordinates
    let time = u.config.x;

    // Hex Grid Config
    let scale = 15.0; // Hex size
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    // Find Hex Center and Local Coords (Staggered Grid approach)
    // Normalized to r=1
    let s = vec2<f32>(1.7320508, 1.0);
    let u_scaled = uv_aspect * scale;

    let ga = (fract(u_scaled / s) - 0.5) * s;
    let ida = floor(u_scaled / s);

    let u_off = u_scaled - s * 0.5;
    let gb = (fract(u_off / s) - 0.5) * s;
    let idb = floor(u_off / s);

    let da = dot(ga, ga);
    let db = dot(gb, gb);

    var localUV = ga;
    var cellID = ida;
    var center = (ida + 0.5) * s;

    if (db < da) {
        localUV = gb;
        cellID = idb + 0.5;
        center = (idb + 0.5) * s + s * 0.5;
    }

    // Center in 0..1 space
    let centerUV = vec2<f32>(center.x / scale / aspect, center.y / scale);

    // Interaction
    let mouseVec = (mouse - centerUV) * vec2<f32>(aspect, 1.0);
    let dist = length(mouseVec);

    let influence = smoothstep(0.4, 0.0, dist); // 0.4 radius

    // Effects
    // 1. Rotation based on mouse distance
    let rotAngle = influence * 3.14159; // Rotate up to 180 degrees
    let rotatedLocal = rotate(localUV, rotAngle);

    // 2. Scale/Zoom inside cell
    let zoom = 1.0 - influence * 0.5;

    // Reconstruct UV
    let finalUV_scaled = center + rotatedLocal * zoom;
    let finalUV = vec2<f32>(finalUV_scaled.x / scale / aspect, finalUV_scaled.y / scale);

    // 3. Chromatic Aberration (Prism effect)
    // Split RGB based on rotation/influence
    let ca = influence * 0.02;

    // To make it look like a prism, we offset R, G, B in different directions relative to the cell center
    let rOffset = rotate(vec2<f32>(ca, 0.0), rotAngle);
    let bOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 2.094); // +120 deg
    let gOffset = rotate(vec2<f32>(ca, 0.0), rotAngle + 4.188); // +240 deg

    let r = textureSampleLevel(videoTex, videoSampler, finalUV + rOffset, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, finalUV + gOffset, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, finalUV + bOffset, 0.0).b;

    var color = vec3<f32>(r, g, b);

    // Edges (Simple distance based edge for hex approximation)
    let edge = smoothstep(0.45, 0.5, length(localUV));

    // Darken edges
    color = mix(color, vec3<f32>(0.0), edge * influence);

    // Highlight active cells
    color += vec3<f32>(0.2, 0.5, 1.0) * influence * 0.2;

    textureStore(outTex, gid.xy, vec4<f32>(color, 1.0));
}
