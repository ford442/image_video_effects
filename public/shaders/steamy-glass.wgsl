// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Feedback buffer for fog
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame of dataTextureA
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

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;

    // Params
    let fogDensity = u.zoom_params.x;
    let fadeSpeed = u.zoom_params.y * 0.05; // Slow fade back
    let wipeRadius = u.zoom_params.z * 0.3 + 0.05;
    let blurAmount = u.zoom_params.w;

    // Read previous fog state (from dataTextureC which should be the readable version of previous frame A)
    // Note: dataTextureC corresponds to previous frame's dataTextureA in the pipeline usually.
    // If not, we might need to check how feedback works. Assuming dataTextureC is the read texture for feedback.

    // Sample previous fog value. 1.0 = full fog, 0.0 = clear.
    let prevFog = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Calculate new fog value
    // Fog naturally increases (returns)
    var newFog = min(prevFog + fadeSpeed * 0.1, 1.0);
    // Or just fade towards 1.0?
    // Let's create noise for the fog pattern
    let fogNoise = hash12(uv * 50.0 + u.config.x * 0.01);

    // Wipe logic
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // If close to mouse, clear the fog
    // Smoothstep for soft edge brush
    let wipe = smoothstep(wipeRadius, wipeRadius - 0.1, dist);

    // Apply wipe (subtract from fog)
    // If we wipe, fog goes to 0.0
    newFog = max(0.0, newFog - wipe);

    // Write new fog state to feedback buffer
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newFog, 0.0, 0.0, 1.0));

    // Render Logic
    // Sample clear image
    let clearColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Sample blurred image (fake blur by sampling mipmap or offset)
    // Simple blur: average 4 neighbors
    let offset = blurAmount * 0.01;
    var blurColor = vec3<f32>(0.0);
    blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(offset, 0.0), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(offset, 0.0), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, offset), 0.0).rgb;
    blurColor += textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, offset), 0.0).rgb;
    blurColor *= 0.25;

    // Mix based on fog
    // Fog makes it blurry and whiter/greyer
    let fogColor = vec3<f32>(0.9, 0.95, 1.0); // Steam color

    // Mix clear and blur
    var finalColor = mix(clearColor, blurColor, newFog * blurAmount);

    // Add fog overlay (whiteness)
    finalColor = mix(finalColor, fogColor, newFog * fogDensity * 0.5);

    // Add drips? Too complex for now.

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
