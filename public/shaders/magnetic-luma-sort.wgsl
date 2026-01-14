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

fn get_luma(color: vec3<f32>) -> f32 {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let pullStrength = u.zoom_params.x * 0.05; // Scaling for reasonable speed
    let threshold = u.zoom_params.y;
    let decay = u.zoom_params.z;
    let repel = step(0.5, u.zoom_params.w); // 0 or 1

    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Vector to mouse
    var dirToMouse = mousePos - uv;
    dirToMouse.x *= aspect;
    let dist = length(dirToMouse);

    var dir = normalize(dirToMouse);
    if (dist < 0.001) { dir = vec2(0.0, 0.0); }

    if (repel > 0.5) {
        dir = -dir;
    }

    // Read current image source
    let srcColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = get_luma(srcColor.rgb);

    // Read history (trail)
    // We want to sample the history from "upstream".
    // If pixels move towards mouse, we (at current pixel) look AWAY from mouse to see what's coming.
    // Movement speed depends on luma. Brighter = faster.

    var speed = 0.0;
    if (luma > threshold) {
        speed = pullStrength * (luma - threshold) / (1.0 - threshold + 0.001);
    }

    // Dampen speed by distance? Maybe infinite reach is better.
    // Let's dampen slightly so the edge of screen doesn't pull too hard if mouse is center.
    // speed *= smoothstep(0.0, 0.1, dist);

    let offset = -dir * speed;

    // Sample history at the upstream position
    let historyUV = uv + offset;
    var historyColor = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0);

    // Combine
    // If we are just moving the image, we should primarily see the history moving.
    // But we need to inject the new frame's content otherwise it fades out or is empty initially.
    // A common "trail" technique is max(current, history * decay).

    // Let's try a blend:
    // The "moved" content is history. The "source" is the current video frame.
    // If we only use history, the video won't update.
    // So we mix current frame into history.

    var finalColor = mix(historyColor, srcColor, 0.1); // Continually add 10% new image

    // To make it look like "sorting" or "smearing", we heavily favor the displaced history
    // but we clamp it so it doesn't blow out.
    finalColor = max(srcColor * 0.2, historyColor * decay);

    // Alternative: If the pixel is bright enough to move, it "leaves" its spot and "arrives" at the next.
    // This is hard in a gather-based shader.
    // Gather approach: I am pixel P. Who arrived here?
    // The pixel at P + offset (away from mouse) arrived here if it was moving towards mouse.

    // Let's stick to the feedback loop approach.
    // New Value = (Old Value at Upstream P) * Decay + (Current Input) * Blend

    let mixed = mix(srcColor, historyColor, decay);

    // If luma is low, we don't move history much?
    // Actually, if luma is low (speed 0), offset is 0. So we sample history at current UV.
    // This results in a standard feedback trail.

    textureStore(writeTexture, global_id.xy, mixed);
    textureStore(dataTextureA, global_id.xy, mixed); // Write to history

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
