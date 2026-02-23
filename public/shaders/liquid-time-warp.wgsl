// ────────────────────────────────────────────────────────────────────────────────
//  Liquid Time Warp
//  Combines liquid distortion with temporal feedback.
//  The history is advected by a flow field influenced by the mouse.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;
@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>; // Write to history
@group(0) @binding(9) var feedbackTex: texture_2d<f32>; // Read from history

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Simple noise function
fn hash(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);
    let w = pf * pf * (3.0 - 2.0 * pf);
    return mix(mix(dot(hash(pi + vec2<f32>(0.0, 0.0)), pf - vec2<f32>(0.0, 0.0)),
                   dot(hash(pi + vec2<f32>(1.0, 0.0)), pf - vec2<f32>(1.0, 0.0)), w.x),
               mix(dot(hash(pi + vec2<f32>(0.0, 1.0)), pf - vec2<f32>(0.0, 1.0)),
                   dot(hash(pi + vec2<f32>(1.0, 1.0)), pf - vec2<f32>(1.0, 1.0)), w.x), w.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    // Adjustable Parameters
    // x: Distortion Amount (0.0 - 1.0)
    // y: Flow Speed
    // z: Noise Scale
    // w: Decay/Persistence (0.9 - 0.99)

    let distortAmt = mix(0.002, 0.02, u.zoom_params.x);
    let flowSpeed = mix(0.1, 2.0, u.zoom_params.y);
    let scale = mix(2.0, 10.0, u.zoom_params.z);
    let decay = mix(0.9, 0.995, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    // 1. Calculate Flow Field
    let n1 = noise(uv * scale + vec2<f32>(time * flowSpeed * 0.1, time * flowSpeed * 0.2));
    let n2 = noise(uv * scale - vec2<f32>(time * flowSpeed * 0.2, time * flowSpeed * 0.1));
    var flow = vec2<f32>(n1, n2);

    // 2. Mouse Interaction
    let mVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mDist = length(mVec);
    let mRadius = 0.2;

    // Create a vortex/push effect near mouse
    if (mDist < mRadius) {
        let force = (1.0 - mDist / mRadius);
        let push = normalize(mVec) * force;
        let swirl = vec2<f32>(-mVec.y, mVec.x) * force * 2.0; // Perpendicular swirl

        if (isMouseDown > 0.5) {
            // Strong push when clicking
            flow += push * 5.0;
        } else {
            // Gentle swirl when hovering
            flow += swirl * 2.0;
        }
    }

    // 3. Advect History (Sample previous frame with offset)
    let historyUV = uv - flow * distortAmt;
    let historyColor = textureSampleLevel(feedbackTex, videoSampler, historyUV, 0.0).rgba;

    // 4. Sample Current Video
    let videoColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgba;

    // 5. Combine (Feedback Loop)
    // If mouse is very close, reveal more fresh video (wipe effect)
    let wipeFactor = smoothstep(0.05, 0.0, mDist) * isMouseDown;

    // Mix current video with decayed history
    var finalColor = mix(videoColor, historyColor, decay * (1.0 - wipeFactor));

    // Prevent feedback explosion (clamp or slight darkening)
    finalColor = clamp(finalColor, vec4<f32>(0.0), vec4<f32>(1.2));

    // Write to feedback buffer for next frame
    textureStore(feedbackOut, gid.xy, finalColor);

    // Write to screen
    textureStore(outTex, gid.xy, finalColor);

    // Pass through depth
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
