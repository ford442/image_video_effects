// ────────────────────────────────────────────────────────────────────────────────
//  Spectral Rain
//  Falling streaks of chromatic distortion.
//  Mouse X controls rain angle. Mouse Y controls fall speed.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Mouse Controls
    let mouse = u.zoom_config.yz;
    let angleVal = (mouse.x - 0.5) * 2.0; // -1 to 1
    let speedVal = mouse.y * 2.0 + 0.5;   // 0.5 to 2.5

    // Params
    let density = u.zoom_params.x * 20.0 + 5.0;
    let chromaticStr = u.zoom_params.y * 0.05;
    let trailLen = u.zoom_params.z * 0.5 + 0.1;

    // Rotate UV for rain direction
    let angle = angleVal * 0.5; // rads roughly
    let c = cos(angle);
    let s = sin(angle);
    let rotMat = mat2x2<f32>(c, -s, s, c);

    let rotUV = rotMat * (uv * vec2<f32>(aspect, 1.0));

    // Rain generation
    // We create grid cells
    let gridUV = rotUV * density;
    let gridID = floor(gridUV);
    let gridOffset = fract(gridUV);

    // Random speed per column
    let colSpeed = hash12(vec2<f32>(gridID.x, 0.0)) * 0.5 + 0.5;

    // Vertical movement
    let yPos = rotUV.y + time * speedVal * colSpeed;

    // Rain drop streaks
    // We use noise to determine if a drop is passing
    let dropNoise = fract(yPos * density * 0.1 + hash12(vec2<f32>(gridID.x, 10.0)) * 100.0);

    // Shape the drop: 1.0 at head, fading tail
    // Threshold it
    let drop = smoothstep(1.0 - trailLen, 1.0, dropNoise);

    // Apply displacement
    let displace = vec2<f32>(s, c) * drop * chromaticStr;

    let r = textureSampleLevel(videoTex, videoSampler, uv + displace, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, uv, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, uv - displace, 0.0).b;

    // Brighten where rain is
    let bright = drop * 0.1;

    textureStore(outTex, gid.xy, vec4<f32>(r + bright, g + bright, b + bright, 1.0));
}
